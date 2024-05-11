---
title: 'Spindown SAS disks'
date: '2017-10-05T00:19:04-04:00'
layout: post
permalink: /spindown-sas-disks/
image: /wp-content/uploads/2017/10/spin1.jpg
categories: [linux, spindown]
---

So, in my [previous article](/hgst-7k6000-not-spinning-not-working/), I was struggling to get a new SAS disk to spin up. Now that I have that working, I want to get it to go into standby (spindown) when it’s idle for a while. Although hdparm works with SATA disks, SAS disks are a different beast. To work with them you need to use sdparm.

```bash
sudo -i
apt-get install sdparm -y
```

Once it is installed, you can use this code to view the current spindown parameters (my disk is /dev/sdp or use /dev/disk/by-id/).

```bash
sdparm --flexible -6 -l --get SCT /dev/sdp
sdparm --flexible -6 -l --get STANDBY /dev/sdp
```

You may get output that looks like this…

```bash
STANDBY     0  [cha: y, def:  1, sav:  1]
SCT       4294967286  [cha: y, def:9000, sav:9000]
```

I this case, STANDBY = 0 means that the disk will never spindown. So, let’s change that…

```bash
sdparm --flexible -6 -l --set SCT=18000 /dev/sdp
sdparm --flexible -6 -l --set STANDBY=1 /dev/sdp
```

The first option enables standby (spindown), and the second sets the timer. The SCT number is equal to 100ms. So, 18000 = 30 minutes.

And, that’s it. These values should be saved to your disk and even be portable between systems. If you do run across a funky disk that doesn’t retain these values through a reboot, you can always add a line like this to /etc/rc.local

```bash
sdparm --flexible -6 -l --set SCT=18000 --set STANDBY=1 /dev/sdp
```