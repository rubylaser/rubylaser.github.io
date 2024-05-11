---
title: 'Home Hyper-V Server'
date: '2014-09-25T18:27:07-04:00'
layout: post
permalink: /home-hyper-v-server/
image: /wp-content/uploads/2014/09/rQ9u2dF.jpg
categories: [home, hyper-v, server, virtualization]
---

I have always used Proxmox or ESXi for virtualization, but this time I wanted to give Server 2012 R2 + Hyper-V a spin. I also wanted to virtualize my IPFire firewall, a Domain Controller, and eventually, my fileserver. I have also eliminated the need for one of my HTPC’s, because I’m able to use the Hyper-V host as a Plex Home Theater host. Here is a list of the hardware. I transplanted these parts into an old Antec case and used an older Antec PSU I had as well.

- \[CPU\] Intel i5-4590
- \[MOBO\] ASRock B85M Pro4
- \[RAM\] 32GB of Crucial DDR3-1600
- \[OS HD\] Samsung 830 64GB
- \[VM HD\] Crucial MX100 512GB (Both SSDs in an Icy Dock EZ-Fit Lite Holder).
- \[BACKUP HD\] Hitachi Deskstar 2TB
- \[NIC1\] Intel I350-T4

![](/wp-content/uploads/2014/09/tZTbJru.jpg)

I have swapped out the two Intel nics and replaced them with an Intel I350-T4 quad port gigabit adapter so that I can get an IBM M1015 attached to the board, and virtualize my fileserver as well. I’ve also used this machine to eliminate the need for my old Core2Quad Q9550 OpenELEC + Plex box that feeds my basement projector. I ran a 25′ optical audio cable and a DVI -&gt; ethernet -&gt; DVI adapter to my projector. DXVA keeps the load down on the CPU even playing back a Bluray disc. This machine uses 1/10th of the power of the old Dell machine and is MANY times more powerful. So far, this has been a really exciting experience.

As an update, I have decided to hold off on migrating my storage to this box. Although, I am able to pass through disks to a virtual machine in Hyper-V, it does not pass through the raw disk, so this prevents things the smartmontools from scanning my disks for issues or hdparm to spin my disks down.

![](/wp-content/uploads/2014/09/rQ9u2dF.jpg)