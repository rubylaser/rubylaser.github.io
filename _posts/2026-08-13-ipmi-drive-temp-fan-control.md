---
title: "Drive-Temp Fan Control on a Supermicro H12 with a Passed-Through HBA"
date: 2026-08-13 11:00:00 -0400
categories: [Homelab, Hardware]
tags: [supermicro, ipmi, fan-control, proxmox, hba, jbod, bash, homelab]
image: /assets/images/posts/supermicro-fans/supermicro_fans.webp
---

My drives were running in the mid-40s. Not dangerous, but warmer than I wanted, and the only
way to cool them was to set the BMC fan mode to Full — which on a Supermicro 826 means all
three mid-wall fans at 7400 RPM, permanently, in a room I sit in.

The fix is a script that reads drive temperatures and sets the BMC's fan duty cycle directly.
That part is well-trodden. What made my setup awkward is that the HBA is passed through to a
VM, so the host that can talk to the BMC can't see the drives, and the guest that can see the
drives can't talk to the BMC. There's also a second 826 attached as a JBOD, whose drives must
not be allowed to influence fans that can't cool them.

And, spoiler... the real cause of my heat problem turned out to be a fan that wasn't seated
properly after I'd cleaned the case out a few days ago. I'll come back to that, because it's the most useful part of this post.

## The hardware

- Supermicro H12SSL-i, EPYC 7502, 512GB RAM, in an SC826 chassis
- Three populated mid-wall fans (FAN2, FAN3, FAN4); FAN1, FAN5, FANA, FANB empty
- LSI HBA passed through to a Ubuntu 24.04 VM running MergerFS + SnapRAID
- Second SC826 as a JBOD on a separate HBA
- 15 spinners total: 8 in the main chassis, 7 in the JBOD

The host is Proxmox. My Fileserver VM has all the drives passed through to it.

## Why the BMC's own modes don't solve this

Supermicro boards have four fan modes: Standard, Full, Optimal, and Heavy IO. Read the names
carefully, because "Full" doesn't mean what you'd think. It means *manual*. In Full mode the
BMC stops managing fans and honors whatever duty cycle you write to it. That's the mode you
want.

The problem with the automatic modes is what they're measuring. Optimal and Standard drive
the peripheral fan zone from CPU and system temperatures. Your drives aren't in that loop at
all. On my box, Optimal held the CPU comfortably while the drives climbed into the mid-40s,
because from the BMC's point of view nothing was wrong.

Check your current mode:

```bash
ipmitool raw 0x30 0x45 0x00
```

Returns `00` for Standard, `01` for Full, `02` for Optimal, `04` for Heavy IO.

And the current duty cycle per zone:

```bash
ipmitool raw 0x30 0x70 0x66 0x00 0x00
ipmitool raw 0x30 0x70 0x66 0x00 0x01
```

Zone 0 is typically FAN1–FAN4, zone 1 is FANA/FANB. On my board only zone 0 is populated, so
there's exactly one knob. Confirm which zone your drive-cage fans are on before you script
anything — the SC826 backplane and fan wiring vary by chassis revision.

To set a zone manually:

```bash
ipmitool raw 0x30 0x45 0x01 0x01              # Full (manual) mode
ipmitool raw 0x30 0x70 0x66 0x01 0x00 0x32    # zone 0 -> 0x32 (50%)
```

Full mode is a prerequisite. In Standard or Optimal the BMC accepts your duty writes and then
silently overrides them within seconds, which is a confusing way to spend twenty minutes.

## Find your floor before you write a curve

Don't guess at a minimum duty cycle. The BMC clamps below some threshold, and the point where
it stops tracking your input is a property of your board and fans, not something you can look
up.

Sweep it:

```bash
for d in 0x20 0x28 0x30 0x38 0x40; do
  ipmitool raw 0x30 0x70 0x66 0x01 0x00 $d
  sleep 45
  echo -n "duty $d: "
  ipmitool sensor list 2>/dev/null | awk '/^FAN[234]/{printf "%s ", $3}'
  echo
done
ipmitool raw 0x30 0x70 0x66 0x01 0x00 0x64
```

My first sweep came back cleanly linear at roughly 105 RPM per percent, with no sign of a
floor — so I went lower:

```
duty 0x0f: 2240 2380 2520
duty 0x14: 2660 2660 2660
duty 0x1a: 2940 2940 2940
```

Two tells that I'd hit the clamp. The curve flattened: 0x14 to 0x1a moved 280 RPM where the
linear region moved about 600 for the same span. And at 0x14 and 0x1a all three fans reported
*identical* RPM, where every other data point had 100–300 RPM of spread between physically
different fans. Identical readings across three units means you're seeing a clamped value, not
a measured one.

I took 0x14 (~2660 RPM) as the floor. 0x0f buys almost no real airflow and puts you in the
region where behavior stops being predictable.

While you're here, check your fan sensor thresholds:

```bash
ipmitool sensor list | grep -i fan
```

Mine read lower-non-recoverable at 280 RPM and lower-critical at 420. If a fan drops below
the non-recoverable threshold the BMC declares a fault and pins every fan at 100% until you
reset it. With a floor at 2660 RPM I had enormous headroom, but if yours is tighter, lower
the thresholds first:

```bash
ipmitool sensor thresh FANA lower 100 200 300
```

## The Division of access: the host owns the BMC, guest owns the drives

`ipmitool` needs to run on the Proxmox host — that's where the direct access to the BMC is.
`smartctl` needs to run in the VM, because that's where the passed-through HBA lives. You need
a bridge, and the direction matters.

I have the host pull from the guest, not the guest push to the host. If the VM is suspended,
crashed, or mid-reboot, the host notices immediately — the SSH call fails and the script
responds by going to 100%. If you inverted it, a dead VM would simply stop sending updates
and the fans would hold at whatever they were last set to, indefinitely. Loud is the correct
failure state; silent is not.

Generate a dedicated key on the host:

```bash
ssh-keygen -t ed25519 -f /root/.ssh/id_fanctl -N '' -C fanctl
ssh-copy-id -i /root/.ssh/id_fanctl.pub root@192.168.172.10
```

Then, in the VM's `/root/.ssh/authorized_keys`, prefix that key with a forced command so it
can't be used for anything else. All on one line:

```
command="/root/scripts/disktemps",restrict ssh-ed25519 AAAAC3Nza... fanctl
```

`restrict` disables port forwarding, agent forwarding, X11, and PTY allocation. The forced
command means the remote command is ignored entirely — whatever you ask for, `disktemps`
runs.

That last detail is worth knowing when you test it. `ssh -i key root@vm true` will return
successfully whether or not the restriction is in place, because `true` prints nothing either
way. Test with something that would produce different output:

```bash
ssh -i /root/.ssh/id_fanctl root@192.168.172.10 id
```

If that prints a temperature instead of user info, the restriction is working.

## Reading temperatures: SAS is not SATA

If your drives are behind an HBA presenting them as SAS devices, a lot of common advice
doesn't apply. There are no `/dev/disk/by-id/ata-*` symlinks. There's no
`Temperature_Celsius` attribute in the SMART table. The temperature comes back as:

```
Current Drive Temperature:     43 C
```

I lost a while to a script that globbed `ata-*`, matched nothing, and reported a max of 0 —
which my fan logic read as "all drives are spun down" and dutifully set the fans to minimum.
Silent, wrong, and exactly the failure mode you don't want. Use `wwn-*` identifiers, which
cover both SAS and SATA, and treat "no readable drives" as an error rather than an idle state.

## The two-enclosure problem

With a JBOD attached, `smartctl` in the VM sees all 15 drives identically. But the mid-wall
fans in the main chassis do nothing for the 7 drives in the other box. If a JBOD drive ends up
as your maximum, the script will chase a temperature it cannot affect and sit at 100% forever.

Sort them out with SES data:

```bash
apt install -y sg3-utils lsscsi
for e in /sys/class/enclosure/*; do
  echo "=== $e"
  cat "$e"/device/vendor "$e"/device/model 2>/dev/null
  for s in "$e"/*/device/block/*; do
    [[ -e $s ]] && echo "  $(basename $s)"
  done
done
```

Mine came back as two LSI SAS3x28 expanders, one with 8 drives and one with 7 — matching the
physical split. But drive count is circumstantial. Confirm which enclosure is which by
lighting a locate LED and walking over to look:

```bash
sg_ses --index=0 --set=locate /dev/sg12
sg_ses --index=0 --clear=locate /dev/sg12
```

Then whitelist the local drives by WWN. I keep them in a file rather than deriving the split
at runtime, because enclosure paths can shift if you re-cable, and a silent misclassification
here means a cage full of drives cooling on assumptions.

`/root/scripts/local-wwns` on the VM:

```
# Enclosure 1:0:8:0 (LSI SAS3x28) — main chassis, IPMI-cooled.
# JBOD drives (enclosure 8:0:7:0) deliberately excluded.
wwn-0x5000c500a74282db   # sdb  IBM ST14000NM0288
wwn-0x5000cca264c4eb64   # sdc  WDC W7214A520ORA014T
wwn-0x5000cca267f7d600   # sdd  WD100EMAZ
wwn-0x5000c500a7a0456f   # sde  IBM ST14000NM0288
wwn-0x5000cca2b00e4870   # sdf  HGST HUH721212AL4201
wwn-0x5000c500c79306da   # sdg  ST8000VN004
wwn-0x5000c500ada6b183   # sdh  IBM ST14000NM0288
wwn-0x5000c500a7a06ee3   # sdi  IBM ST14000NM0288
```

## The temperature reader

`/root/scripts/disktemps` on the VM:

```bash
#!/usr/bin/env bash
# Max temperature across drives in the IPMI-controlled chassis only.
# stdout: single integer (C). Non-zero exit = caller must fail safe.
set -uo pipefail

WWNS=/root/scripts/local-wwns
max=0
found=0

[[ -r $WWNS ]] || { echo "ERR_NO_WWN_LIST" >&2; exit 2; }

while read -r w _; do
  [[ -z $w || $w == \#* ]] && continue
  d="/dev/disk/by-id/$w"
  [[ -b $d ]] || { echo "ERR_MISSING:$w" >&2; exit 2; }
  found=$((found+1))
  t=$(smartctl -A -n standby "$d" 2>/dev/null \
      | awk '/Current Drive Temperature/{print $4}
             /Temperature_Celsius/{print $10}
             /^Current Temperature:/{print $3}' | head -1)
  [[ -n ${t:-} && $t =~ ^[0-9]+$ ]] && (( t > max )) && max=$t
done < "$WWNS"

(( found == 0 )) && { echo "ERR_NO_DEVICES" >&2; exit 2; }
(( max == 0 ))   && { echo "ERR_NO_TEMPS" >&2; exit 2; }
echo "$max"
```

Every failure path exits non-zero. A missing drive, an empty whitelist, an unreadable
temperature — all of them are faults, not quiet zeros. The caller turns any of them into
maximum fan speed.

## The controller

`/root/scripts/fanctl.sh` on the Proxmox host:

```bash
#!/usr/bin/env bash
# Drive-temp-driven IPMI fan control for the local 826 chassis.
# Fails loud: any error pins fans at 100%.
set -uo pipefail

VM=192.168.172.10
KEY=/root/.ssh/id_fanctl
STATE=/run/fanctl.duty
LOG=/var/log/fanctl.log
HC_URL="https://healthchecks.example.com/ping/YOUR-UUID-HERE"

FLOOR=20           # measured: below ~0x14 the BMC clamps and stops tracking
STEP=8             # max ramp-down per run; ramp-up is immediate

set_duty() { ipmitool raw 0x30 0x70 0x66 0x01 0x00 "$(printf '0x%02x' "$1")" >/dev/null 2>&1; }

panic() {
  set_duty 100
  echo 100 > "$STATE"
  echo "$(date -Is) FAIL: $* — fans forced to 100%" | tee -a "$LOG" >&2
  [[ -n $HC_URL ]] && curl -fsS -m 10 "${HC_URL}/fail" -d "$*" >/dev/null 2>&1
  exit 1
}

# Ensure Full (manual) mode — a BMC reset silently reverts this to Optimal,
# after which duty writes are accepted but immediately overridden.
mode=$(ipmitool raw 0x30 0x45 0x00 2>/dev/null | tr -d ' ')
[[ $mode == 01 ]] || ipmitool raw 0x30 0x45 0x01 0x01 >/dev/null 2>&1

max=$(timeout 30 ssh -i "$KEY" -o BatchMode=yes -o ConnectTimeout=10 \
        root@"$VM" true 2>/dev/null) || panic "ssh to $VM failed"
[[ $max =~ ^[0-9]+$ ]] || panic "bad temp value: ${max:-empty}"
(( max < 10 || max > 90 )) && panic "implausible temp: $max"

if   (( max >= 44 )); then duty=100
elif (( max >= 41 )); then duty=78
elif (( max >= 40 )); then duty=58
elif (( max >= 38 )); then duty=38
else                       duty=$FLOOR
fi

prev=$(cat "$STATE" 2>/dev/null || echo 100)
[[ $prev =~ ^[0-9]+$ ]] || prev=100

# Ramp down gradually, up immediately. The gaps between bands provide the
# hysteresis; no additional deadband is needed.
(( duty < prev - STEP )) && duty=$(( prev - STEP ))
(( duty < FLOOR )) && duty=$FLOOR

set_duty "$duty" || panic "ipmitool set_duty $duty failed"
echo "$duty" > "$STATE"

# Fan health: flag if one fan is significantly slower than its siblings.
# The BMC's own thresholds won't catch a fan running at half speed.
sleep 5
rpms=$(ipmitool sensor list 2>/dev/null | awk '/^FAN[234]/{print $3}' | cut -d. -f1)
hi=$(echo "$rpms" | sort -n | tail -1)
lo=$(echo "$rpms" | sort -n | head -1)
if [[ -n ${hi:-} && -n ${lo:-} ]] && (( hi > 0 && (hi - lo) * 100 / hi > 25 )); then
  echo "$(date -Is) WARN: fan spread ${lo}-${hi} RPM" | tee -a "$LOG" >&2
fi

echo "$(date -Is) max=${max}C duty=${duty}%" | tee -a "$LOG"
[[ -n $HC_URL ]] && curl -fsS -m 10 "$HC_URL" >/dev/null 2>&1
exit 0
```

A few decisions worth explaining.

Ramp-up is immediate; ramp-down is capped at 8 points per run. Spinning hard drive temperatures have a
long cool down after a load finishes, and dropping straight to the floor puts you right back into
a ramp. With a 2-minute timer, walking from 100% to 20% takes about 20 minutes.

The mode is restarted every run. A BMC reset or firmware event drops you back to Optimal,
and without this check your duty writes would be silently overridden while the script
cheerfully logged success.

## systemd

```ini
# /etc/systemd/system/fanctl.service
[Unit]
Description=IPMI drive-temp fan control
After=network-online.target
Wants=network-online.target

[Service]
Type=oneshot
ExecStart=/root/scripts/fanctl.sh
SyslogIdentifier=fanctl
```

```ini
# /etc/systemd/system/fanctl.timer
[Unit]
Description=Run IPMI fan control every 2 minutes

[Timer]
OnBootSec=3min
OnUnitActiveSec=2min
AccuracySec=10s

[Install]
WantedBy=timers.target
```

And a unit that hands control back to the BMC when the host shuts down, so a powered-but-idle
machine never sits at 20% with nothing managing it:

```ini
# /etc/systemd/system/fanctl-restore.service
[Unit]
Description=Restore BMC fan control on shutdown
DefaultDependencies=no
Before=shutdown.target

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=/bin/true
ExecStop=/usr/bin/ipmitool raw 0x30 0x45 0x01 0x04

[Install]
WantedBy=multi-user.target
```

```bash
systemctl daemon-reload
systemctl enable --now fanctl-restore.service
systemctl enable --now fanctl.timer
```

`0x04` is Heavy IO, which runs the peripheral zone at full and leaves the CPU zone to the BMC.
It's the right unattended default. Note that this unit must stay *active* for its entire life
— stopping it is what triggers the restore.

## Log to a file, not the journal

I wrote this to `logger` initially and spent an embarrassing amount of time wondering why
nothing appeared. Two separate causes: `logger` failing silently under `set -uo pipefail`
without `-e`, and a journald `SystemMaxUse=64M` cap that had been full for a while, the host
had been quietly losing all journal history, not just mine. So... I'm compounding my errors now ;)

A plain file is better for this anyway. When you're tuning, you want a clean timestamped
series you can `tail -f`, not something interleaved with everything else a Proxmox host says.

```
/var/log/fanctl.log {
    weekly
    rotate 4
    compress
    missingok
    notifempty
}
```

## Verify it fails loud

This is the step that separates a fan controller from a liability. It's worth investigating that that if the host goes away, things don't overheat. Noise is better than dead hardware. Suspend the VM and confirm the fans actually ramp up:

```bash
qm suspend <VMID>
# wait ~2 minutes — fans should audibly ramp, log should show FAIL,
# and your monitoring should alert
qm resume <VMID>
```

Check that the alert reaches you, not just that the ping fires. The entire safety argument for
taking manual control of your cooling rests on this thing working.

## What the numbers actually looked like

After tuning, at idle:

```
2026-08-13T09:22:22-04:00 max=36C duty=20%
2026-08-13T09:24:32-04:00 max=36C duty=20%
2026-08-13T09:26:43-04:00 max=36C duty=20%
```

Flat at the floor, ~2660 RPM, drives at 35–37 °C.

Under a load like a SnapRAID sync from 02:03 to 02:39 running straight into a scrub from 02:39 to
04:14, 130 minutes continuous, the peak was 36 °C and duty never exceeded 38%. My bands above
38 °C have never fired. I've left them in as insurance, but I'm not going to pretend they're
tuned, because they've never been exercised.

Your numbers will differ based on drive count, drive models, cage design, and
room ambient. Mine are from mid-August; January will read lower and next summer may push into
bands that have never fired. Who knows?!

## The part that actually mattered

Partway through tuning, I opened the case and found one of the three mid-wall fans wasn't
seated properly.

Reseating it changed everything. Idle went from 40 °C at 38% duty to 32 °C at 70%, and the 20%
floor, which had been thermally useless, suddenly held the mid-30s comfortably. Every
measurement I'd taken before that point was of a chassis running on two-thirds of its
airflow, and I'd been building a fan curve to compensate for it.

Nothing in my monitoring would have caught it other than Scrutiny saying that a drive temp had gotten over 42 °C. Uptime Kuma doesn't watch fan RPM. SMART monitoring watches drives, not chassis fans. And the BMC's own lower-critical threshold is
420 RPM, so a fan spinning at half speed reads as perfectly healthy. That's why the script
now logs a warning when the spread between fans exceeds 25%.


The long and the short is that I didn't really need this tuning. I just needed to hook up the missing fan. But, I like that this will now cover proactively for failures or temp spikes in the future, so this should never happen again... hopefully.