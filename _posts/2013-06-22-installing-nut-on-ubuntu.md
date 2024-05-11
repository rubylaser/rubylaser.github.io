---
layout: post
title: "Installing NUT on Ubuntu"
date: "2013-06-22T07:00:00-04:00"
permalink: /installing-nut-on-ubuntu/
image: /wp-content/uploads/2013/06/1039520-large.jpg
categories: [nut]
tags: [ups, protection, nut, linux]
---

I have been using apcupsd for years without issue. Lately, the random freezes lead me to discover that there was an issue been apcupsd and Linux 3.5.x kernels. This left me looking for an alternative. I knew about [NUT](https://www.networkupstools.org/), but I have never used it before. It’s relatively easy to configure and can work to provide shutdown scripts for remote boxes. Here’s how I set it up.

```bash
apt-get install nut
```

Next, you need to configure it for your device.

```bash
nano /etc/nut/ups.conf
```

and paste at the bottom. Mine’s an APC-1500, so I’ve set it to a recognizable name (apc-1500)

```bash
[apc-1500]
driver = usbhid-ups
port = auto
```

Start it up.

```bash
upsdrvctl start
```

I had to reboot to get this working for some reason, and still had to make the directory for it to run.

```bash
mkdir /var/run/nut
chown root:nut /var/run/nut
chmod 770 /var/run/nut
```

Try again,

```bash
upsdrvctl start
```

It should look like this when it starts up.

```bash
Network UPS Tools - UPS driver controller 2.4.3
Network UPS Tools - Generic HID driver 0.34 (2.4.3)
USB communication driver 0.31
Using subdriver: APC HID 0.95
```

Next, I set it up to listen to localhost and on my subnet.

```bash
nano /etc/nut/upsd.conf
```

add lines similar to these.

```bash
LISTEN 127.0.0.1 3493
LISTEN ::1 3493
LISTEN 192.168.172.21 3493
```

Set the mode.

```bash
MODE=netserver
```

Start the network data server

```bash
upsd
```

You can check the status like this.

```bash
upsc apc-1500@localhost ups.status
```

If all is well, it will provide output like tihs.

```bash
OL
```

OL means your system is running **O**n **L**ine power. If you want to see all the info, try this instead.

```bash
root@fileserver:/etc/nut# upsc apc-1500@localhost
battery.charge: 100
battery.charge.low: 10
battery.charge.warning: 50
battery.date: 2054/00/39
battery.mfr.date: 2008/10/20
battery.runtime: 3920
battery.runtime.low: 120
battery.type: PbAc
battery.voltage: 27.1
battery.voltage.nominal: 24.0
device.mfr: American Power Conversion
device.model: Back-UPS RS 1500 LCD
device.serial: ccccccccccccc  
device.type: ups
driver.name: usbhid-ups
driver.parameter.pollfreq: 30
driver.parameter.pollinterval: 2
driver.parameter.port: auto
driver.version: 2.6.3
driver.version.data: APC HID 0.95
driver.version.internal: 0.35
input.sensitivity: medium
input.transfer.high: 139
input.transfer.low: 88
input.voltage: 122.0
input.voltage.nominal: 120
ups.beeper.status: disabled
ups.delay.shutdown: 20
ups.firmware: 839.H7 .D
ups.firmware.aux: H7 
ups.load: 8
ups.mfr: American Power Conversion
ups.mfr.date: 2008/10/20
ups.model: Back-UPS RS 1500 LCD
ups.productid: 0002
ups.realpower.nominal: 865
ups.serial: xxxxxxxxxxxxxx  
ups.status: OL
ups.test.result: No test initiated
ups.timer.reboot: 0
ups.timer.shutdown: -1
ups.vendorid: 051d
```

Before I forget, I wanted to disable the beeper so I don’t have a heart attack if I lose power at night.

```bash
upscmd apc beeper.disable
```

Next, we need to setup some users to access the info and make changes.

```bash
nano /etc/nut/upsd.users
```

I’m building a monitor master user and a slave for remote boxes.

```bash
[monuser]
        password = PASSWORD_REPLACE
        actions = SET FSD
        instcmds = ALL
        upsmon master
        # or upsmon slave

[monuserslave]
        password = slave
        upsmon slave
```

Reload upsd

```bash
upsd -c reload
```

Then we have to setup upsmon for our device.

```bash
nano /etc/nut/upsmon.conf
```

and paste something like this.

```bash
MONITOR apc-1500@localhost 1 local_mon PASSWORD_REPLACE master
```

We need to setup NUT to run in standalone mode.

```bash
nano /etc/nut/nut.conf
```

paste

```bash
MODE=standalone
```

Now, you can start NUT

```bash
service nut start
```

You should have a working UPS Monitoring system now. Next time, I’ll show you how to connect to this with other machines to enable safely shutting them down as well.

**Setting up a Client (Slave) Computer**  
The nice thing about NUT is that it can control more than just the machine it’s hooked up to. Here’s how you configure another machine to use your master host to safely shutdown.

On your client machine, first download nut.

```bash
apt-get install nut
```

Next, configure the mode

```bash
nano /etc/nut/nut.conf
```

paste…

```bash
MODE=netclient
```

Then, set your upsmon.conf to match the setup for your monuserslave above (also, use the ip address of your master nut-server).

```bash
nano /etc/nut/upsmon.conf
```

paste… (substitue the ip address below 192.168.172.12 with your nut-server’s ip, and put your monuserslave password in from above).

```bash
MONITOR apc-1500@192.168.172.12 1 monuserslave PASSWORD_HERE slave
```

Finally, restart your nut-client

```bash
service nut-client restart
```

You can test that it’s working like this…

```bash
root@fileserver:~# upsc apc-1500@192.168.172.12
Init SSL without certificate database
battery.charge: 100
battery.charge.low: 10
battery.charge.warning: 50
battery.date: 2054/00/39
battery.mfr.date: 2008/10/20
battery.runtime: 156
battery.runtime.low: 360
battery.type: PbAc
battery.voltage: 26.7
battery.voltage.nominal: 24.0
device.mfr: American Power Conversion
device.model: Back-UPS RS 1500 LCD
device.serial: 8B0843R44379
device.type: ups
driver.name: usbhid-ups
driver.parameter.pollfreq: 30
driver.parameter.pollinterval: 2
driver.parameter.port: auto
driver.version: 2.6.4
driver.version.data: APC HID 0.95
driver.version.internal: 0.37
input.sensitivity: medium
input.transfer.high: 139
input.transfer.low: 88
input.voltage: 122.0
input.voltage.nominal: 120
ups.beeper.status: disabled
ups.delay.shutdown: 20
ups.firmware: 839.H7 .D
ups.firmware.aux: H7
ups.load: 29
ups.mfr: American Power Conversion
ups.mfr.date: 2008/10/20
ups.model: Back-UPS RS 1500 LCD
ups.productid: 0002
ups.realpower.nominal: 865
ups.serial: 8B0843R44379
ups.status: OL LB
ups.test.result: No test initiated
ups.timer.reboot: 0
ups.timer.shutdown: -1
ups.vendorid: 051d
```