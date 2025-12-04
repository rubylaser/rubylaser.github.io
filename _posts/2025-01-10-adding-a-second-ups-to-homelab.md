---
title: "Adding a Second UPS to my homelab"
date: 2025-01-10
image: /wp-content/uploads/images/UPS-setup.webp
categories: [Linux, Proxmox, UPS, Homelab]
tags: [nut, apcupsd, truenas, homelab]
---

Have you ever gone down a rabbit hole in your homelab, convinced that a small tweak would solve your problem—only to emerge with a complete overhaul? That’s exactly what happened to me when I decided to protect my expanding setup with **two different UPS units**. Here’s how it all unfolded.

---

## Why Two UPSes?

My *primary* UPS is a **2U rackmount Tripp Lite** safeguarding my main Proxmox host and file server. It’s been rock solid for years. But with more hardware creeping into my rack, I wanted to protect **network devices**, my **backup Proxmox host**, and **backup TrueNAS** on a second UPS—a **CyberPower CP1000PFCLCD**.

Initially, I tried using **apcupsd** on the backup Proxmox server, but I quickly discovered that **TrueNAS** (which I also wanted to protect) won’t natively talk to apcupsd. **TrueNAS** uses **Network UPS Tools (NUT)**, and bridging the two would require custom scripts. It was time to **switch entirely to NUT** on Proxmox.

---

## Moving Proxmox from apcupsd to NUT

Since **Proxmox** is Debian-based, installing and configuring NUT is almost the same as on Ubuntu. My steps were:

1. **Remove or disable apcupsd**  
   ```bash
   systemctl stop apcupsd
   systemctl disable apcupsd
   apt remove apcupsd
   ```

2. **Install NUT**  
   ```bash
   apt update
   apt install nut nut-client nut-server
   ```

3. **Configure NUT**  
   - `/etc/nut/nut.conf` → `MODE=netserver`  
   - `/etc/nut/ups.conf` →  
     ```ini
     [cyberpower]
       driver = usbhid-ups
       port = auto
       desc = "CyberPower CP1000PFCLCD"
     ```  
   - `/etc/nut/upsd.users` →  
     ```ini
     [monmaster]
       password = masterpass
       upsmon master

     [monslave]
       password = slavepass
       upsmon slave
     ```  
   - `/etc/nut/upsmon.conf` →  
     ```
     MONITOR cyberpower@localhost 1 monmaster masterpass master
     SHUTDOWNCMD "/sbin/shutdown -h now"
     POWERDOWNFLAG /var/run/nut/killpower
     ```

I anticipated that would be it. But then I discovered an unexpected obstacle: **USB disconnects**.

---

## The Dreaded USB Disconnect

As soon as NUT attempted to monitor the CyberPower UPS, the device kept dropping off the USB bus. Checking `dmesg` logs, I saw:

```
xhci_hcd 0000:0a:00.4: xHCI host not responding to stop endpoint command
xhci_hcd 0000:0a:00.4: xHCI host controller not responding, assume dead
usb 6-1: USB disconnect, device number 3
```

Basically, the **USB 3.x controller** in my server would die whenever the UPS was plugged in. This rendered the UPS invisible to NUT.

---

## The Magic Fix: Disabling Autosuspend (via `usbcore.conf`)

Turns out **USB autosuspend** can cause random disconnects on some xHCI controllers, especially with UPS devices. Rather than modifying my kernel parameters in GRUB, I **added a small config file** in `/etc/modprobe.d/usbcore.conf`:

```
options usbcore autosuspend=-1
```

Then I rebuilt the initramfs (on Debian/Ubuntu/Proxmox systems):

```bash
update-initramfs -u
```

After a reboot, autosuspend was disabled at the driver level. Suddenly, the UPS stayed perfectly connected—no more “xhci_hcd died” messages in `dmesg`, and `lsusb` consistently listed the CyberPower unit.

---

## TrueNAS as NUT Slave

With Proxmox hosting the UPS via NUT, **TrueNAS** could finally join the party:

1. **System Settings** → **Services** → **UPS**  
2. **UPS Mode**: `Slave`  
3. **Remote Host**: Proxmox’s IP address  
4. **Port**: `3493` (default NUT port)  
5. **Username/Password**: `monslave` / `slavepass` (from `/etc/nut/upsd.users`)  
6. **Monitor UPS**: `cyberpower` (the label in `/etc/nut/ups.conf`)

TrueNAS connected immediately, and a quick test (unplugging the UPS from AC for a few seconds) confirmed that both Proxmox and TrueNAS recognized the outage and were ready to shut down gracefully if the battery got too low.

---

## Two UPSes, Smooth Shutdown

Now, my homelab is more resilient than ever:

1. **Tripp Lite UPS** for my main Proxmox host and file server.  
2. **CyberPower UPS** for my backup Proxmox host, network devices, and backup TrueNAS server.

No more worries about storms or prolonged outages knocking out the entire network without a proper shutdown.

---

## Lessons Learned

1. **NUT vs. apcupsd**  
   - TrueNAS uses **NUT**, so if you want a direct, official integration, you’re better off running NUT on all hosts.
2. **USB 3.x Autosuspend**  
   - On some systems, disabling autosuspend via `/etc/modprobe.d/usbcore.conf` and updating initramfs can fix random disconnects.
3. **Proxmox + NUT**  
   - Setting up NUT on Proxmox is straightforward since it’s based on Debian. The same steps apply (with minor differences) on Ubuntu or other Debian derivatives.
4. **Splitting UPS Loads**  
   - Having different UPS units for different sets of equipment can keep your core services (like your main storage server) protected while offloading less critical or secondary systems onto another unit.

---

## The End

Migrating from apcupsd to NUT wasn’t exactly a walk in the park—particularly when USB autosuspend caused my CyberPower UPS to vanish repeatedly. But after tweaking **`usbcore.conf`** and **updating the initramfs**, everything stabilized.

If you’re juggling multiple UPSes or need TrueNAS integration, **NUT** is a solid choice. Just remember that hardware quirks, especially on USB 3.x, can throw a wrench in your plans. A quick config change to disable autosuspend may be all you need to get rock-solid uptime (and graceful downtime) across your homelab.

Got similar experiences or tips? Share them in the comments. Remember: homelab adventures are best enjoyed with friends—and sometimes just a dash of troubleshooting magic!