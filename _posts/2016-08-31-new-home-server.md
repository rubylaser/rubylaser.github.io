---
title: 'New Home Server'
date: '2016-08-31T14:35:54-04:00'
layout: post
permalink: /new-home-server/
image: /wp-content/uploads/2016/08/4b6czZ3.jpg
categories: [fileserver, home]
---

Much like my other [recent article about my workstation upgrade](/home-workstation/), I decided to give my home server a big performance boost. This machine has went through many hardware iterations. Here are just the CPUs that I can think of: Athlon X64, Xeon X3000 series, Celeron 847, i3, and most recently, a Haswell i5-4590. I have also experimented and learned many different storage technologies due tothis journey. It began with mdadm+LVM, then onto ZFS in Solaris > Openindiana > OmniOS > Linux, and now, I’m back to using Ubuntu 22.04 with [SnapRAID + mergerfs](/setting-up-snapraid-on-ubuntu/) for my bulk media and ZFS for my boot pool and [Docker containers](/docker-how-and-why-i-use-it/). This has proven to be a very flexible solution for my home server media setup.

All of this is re-purposed gear or used gear. This setup works great and is a huge performance improvement over my old setup. Adding all this CPU horsepower consequently impacted the total power draw of the system over a single CPU system with new architecture. At idle, the power draw went up about 65 watts over the i5-4590 system with 1 HBA + SAS Expander. At full load, that difference is a whole lot bigger 🙂

## Home Server Parts List

**CASE:** Norco 4224  
**PSU:** EVGA Supernova 750 G2  
**MOBO:** Intel S2600CP  
**CPU:** 2x Intel Xeon e5-2670 v1 SR0KX (16 physical cores and 32 threads total)  
**RAM:** 16x Hynix 8GB DDR3 ECC RAM (128GB total)  
**CPU Heatsinks:** 2 x Supermicro SNK-P0050AP4  
**OS HD:** (2) Intel S3700 400GB in ZFS mirror (an Intel 730 is shown in the pictures below).  
**HDs**: (8)HGST He8 8TB, (8)WD Red 6TB, and (8)HGST NAS 4TB. Using SnapRAID with triple parity + mergerfs for 128TB usable  
**HBAS:** 3x Dell H310’s flashed to the latest P20 IT firmware  
**ADDON:** Mellanox X-2 Connect 10GBe over fiber to my workstation upstairs  
**ADDON:** Intel AXXRMM4(+Lite) Modules for iKVM

This server hosts my files via SnapRAID + mergerfs, and employs Docker containers for a number of things including: [Crashplan, Plex, Plexpy, Unifi, etc](/docker-how-and-why-i-use-it/).

![Home Server Overview](/wp-content/uploads/2016/08/5BTNT68.jpg)
![Home Server View from Above](/wp-content/uploads/2016/08/06YXzBB.jpg) 
![Home Server 24 bays of storage!!!](/wp-content/uploads/2016/08/QjO0wft.jpg) 
![Home Server Supermicro Heatsinks for e5-2670's](/wp-content/uploads/2016/08/4b6czZ3.jpg) 
![Home Server H310s and Intel iKVM + RAM](/wp-content/uploads/2016/08/fi96C3f.jpg) 
![Home Server EVGA Supernova G2 PSU and Intel 730 SSDs](/wp-content/uploads/2016/08/UN0lqZX.jpg) 
![Home Server H310s Binking Lights](/wp-content/uploads/2016/08/gOSM4oa.jpg)