---
title: 'Why I Moved from Hyper-V to ESXi at home'
date: '2015-03-02T18:32:12-05:00'
layout: post
guid: 'http://zackreed.me/?p=227'
permalink: /why-i-moved-from-hyper-v-to-esxi-at-home/
image: /wp-content/uploads/2015/03/4RXzcD0.jpg
categories: [home, esxi, virtualization]
---

**Build’s Name:** Totoro  
**Operating System/ Storage Platform:** ESXi  
**CPU:** Core i5-4590  
**Motherboard:** ASRock B85M Pro4  
**Chassis:** Coolermaster HAF 912 + 5-in-3 bay.  
**Drives:** 4x Hitachi 4TB drives, 4x Seagate 4TB drives, 2x HGST 4TB drives, and 1x Toshiba 4TB, 4x Intel 730 240GB, 2x Kingston Digital 60GB SSDNow V300, and SanDisk Ultra Fit CZ43 16GB (ESXi boot).  
**RAM:** 32GB of Crucial DDR3-1600  
**Add-in Cards:** 2x IBM m1015 passed through, Intel RES2SV240 (connected to one of the m1015’s)  
**Power Supply:** Coolermaster 600W Silent Pro  
**Other Stuff:** 2x StarTech.com USB 3.0 to Gigabit Ethernet NIC Network Adapter

**Usage Profile:** Firewall, OpenVPN, OmniOS host, Ubuntu fileserver, Windows 8.1, Windows 7, Crashplan, Gitlab.

Other information…  
I used to maintain a whole stable of machines around the house, but I have tried to consolidate everything down into one, always on box, and I can always turn on another machine if I need to.

1. The OmniOS box as an NFS share for the vm storage. It boots off a mirror of the two 60GB Kingston SSDs. It has one of the m1015’s passed through to it and has the (4) Intel 730’s in ZFS RAID10.
2. This box uses IPFire for the firewall (pass through the two Startech gigabit nics for the network interfaces). It provides OpenVPN Access, Snort, Squid Proxy (and URL filtering), DHCP, and DNS for my home LAN.
3. The bulk of the storage comes from the Ubuntu fileserver VM. It has the other m1015 and the Intel SAS exapander passed through to it. It has the (11) 4TB disks in a SnapRAID double parity volume (leaves 36TB usable) pooled with AUFS with the notify option and NFS export enabled. This box also has the APC Back UPS 1500 RS hooked up to manage shutdown of the vms via apcupsd, certificate based SSH with the ESXi host, and a simple ESXi shutdown script that gets nohup’d to the ESXi when apcupsd timer triggers. This box also runs my Plex Media Server, and hosts AFP, SMB, and NFS shares for bulk storage. (All important data is backed up locally to encrypted external USB disks, also to my colocated backup server, and via Crashplan to both Crashplan Central and my friend’s Crashplan box).
4. The other hosts are some Windows boxes, and a Unifi controller for the APs in the house.

This is my first foray into ESXi at home, and would welcome any questions or comments.

![4RXzcD0](/wp-content/uploads/2015/03/4RXzcD0.jpg)