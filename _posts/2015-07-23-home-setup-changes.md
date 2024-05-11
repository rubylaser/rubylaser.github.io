---
title: 'Home Setup Changes'
date: '2015-07-23T19:36:07-04:00'
layout: post
permalink: /home-setup-changes/
image: /wp-content/uploads/2016/01/virtualize_it.jpg
categories: [home, snapraid, virtualization]
---

I have have tried all of the popular hypervisors at home (other than Xen) and arrived back at Proxmox which I have used for years. The combination of KVM + LXC, a modern kernel, the inclusion of ZFS support in the hypervisor, a simple, lightweight web based GUI, and dead simple backup (free), sealed the deal.

I have added a Rackable Systems SE3016 to expand the storage available to my SnapRAID VM. I will probably add another SE3016 down the road as I still have a bunch of 2TB Western Digital RE drives that I could use in my SnapRAID array. I have also broken my firewall back out into a separate physical box. It was just too much of a pain to have all of this on one hypervisor. If I had to reboot the host, my internet connection would go down (not desirable).

Now, I just need to downsize the PSU for the hardware left in my HAF case (I may even go with a smaller case). I have the same i5-4590 CPU, 32GB of DDR3 RAM, (1) IBM m1015, (4) 240GB Intel 730’s, and (1) Hitachi 2TB Coolspin still in the HAF912 case.

Here’s a picture of the new setup (with the drives spun down in the 3016). Notice my UPS next to it showing the power consumption (78 watts). This number includes my cable modem (Motorola Surfboard SB6121), Celeron 847 system (IPFire firewall), and 24 port gigabit dumb switch (TRENDnet TEG-S24DG).

![2Lgx68d](/wp-content/uploads/2016/01/2Lgx68d.jpg)