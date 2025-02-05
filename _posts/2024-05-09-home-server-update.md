---
layout: post
title: "Evolving My Home Server: A Journey Through Hardware and Software"
date: 2024-05-08
image: /wp-content/uploads/images/rack-front-2024.jpg
categories: technology
tags: [home server, proxmox, zfs, snapraid, mergerfs, docker, hardware]
---
## Introduction
Following the spirit of my previous article years ago on my [home server upgrade](/new-home-server/), I recently gave my home server a significant performance and functionality overhaul. This machine has gone through numerous hardware iterations, reflecting both my evolving needs and the advances in technology.

## Hardware Evolution
The heart of my current setup is an AMD EPYC 7402P CPU paired with a Supermicro H12SSL-i motherboard, a robust combination that supports the extensive tasks demanded by a modern home server. Memory is no slouch either, with (8) sticks of 32GB DDR4 ECC REG RAM. The storage configuration is equally impressive: four Intel P4510 2TB PCIe NVMe SSDs in a ZFS RAID10 setup for blazing-fast data access and reliable redundancy.

![Home Server Build](/wp-content/uploads/images/rack-front-2024.jpg)


## Specialized Hardware Components
**Boot Drives:** The system boots from two 800GB Intel DC S3610 SSDs, ensuring quick startups and robust performance.
Mass Storage: For bulk storage, I've assembled 16 drives totaling 174TB useable, a mix of Seagate EXOS and HGST drives, managed with SnapRAID and mergerfs for optimal data protection and flexibility.

![Home Server Build](/wp-content/uploads/images/home-server-build-2024.jpg)

**Case(s):** The machine runs inside two Supermicro 826 cases (one with the 826BE1C4 backplane to support the 4 Intel NVME drives). The JBOD case uses a Supermicro CSE-PTJBOD-CB2 controller board for JBOD chassis along with a fan controller to scale the decibels back on the 3 PWM fans in the case.

![JBOD Case](/wp-content/uploads/images/826-jbod-2024.jpg)
![JBOD Case Racked](/wp-content/uploads/images/826-jbod-racked-2024.jpg)

**Graphics and Connectivity:** An NVIDIA 3060 GPU handles GPU encoding (I tried an Intel Arc A380, but the lack of BAR support on AMD Eypc made this not work as well as I'd hoped. **Edit: this board now supports resizeable BAR, and the ARC GPU does work, but I'm sticking with the 3060 for now.** ) for media applications like Plex, while dual HBAs (LSI 9300-8i and 9300-8e) ensure expansive connectivity and data throughput. The network is handled with an Intel X540-T2.

![Intel Arc 380](/wp-content/uploads/images/home-server-with-arc-gpu.jpg)

## Software Management
My server runs Proxmox, enabling a mix of LXC containers and VMs to coexist seamlessly. This setup allows for efficient resource management and isolation, which is crucial for hosting a variety of services from DNS to Docker containers.

## Key Applications
**Media and Backup:** The server hosts files via SnapRAID and mergerfs, supports media streaming through Plex, and manages backups with a mix of [ZFS Snapshots](https://github.com/jimsalterjrs/sanoid), [SnapRAID](https://www.snapraid.it/), [cv4pve-autosnap](https://github.com/Corsinvest/cv4pve-autosnap), [Kopia](https://ftlwebservices.com/fast-and-reliable-automated-cloud-backups-with-kopia-and-backblaze), and [Backblaze B2](https://www.backblaze.com/cloud-storage).

**Network Management:** Applications like Unifi for network device management run in isolated Docker containers, ensuring stability and security.

## Conclusion
This latest upgrade has transformed my home server into a powerhouse capable of handling virtually any task I throw at it, from intensive data processing to serving as a media hub. It's a testament to how far home server technology has come and a peek into where it's headed.

![Final Server Build](/wp-content/uploads/images/home-server-inside-2024.jpg)