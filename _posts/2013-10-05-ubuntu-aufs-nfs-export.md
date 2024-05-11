---
title: 'Ubuntu AUFS NFS Export'
date: '2013-10-05T11:33:28-04:00'
layout: post
permalink: /ubuntu-aufs-nfs-export/
image: /wp-content/uploads/2013/10/11378005-export-cars-from-usa.jpg
categories: [aufs, fileserver, linux, nfs, snapraid, ubuntu]
---

I’ve had many people ask in the comments on my original thread how to get NFS exports working with their stock kernel. The default Ubuntu kernel does not have the option for NFS exports on AUFS filesystems enabled. Rather than walk you through the process of compiling your own custom kernel, I decided to compile the current kernel and headers on my 64 bit system. If you use the 64 bit Ubuntu 12.04 server, you should be able to grab this package, untar, install, reboot, and have NFS support.

```bash
wget https://zackreed.me/wp-content/uploads/2013/10/ubuntu_12.04_64bit_kernels.zip
tar xvf ubuntu_12.04_64bit_kernels.zip
dpkg -i linux-image-3.2.51-customsds5+_3.2.51-customsds5+-10.00.Custom_amd64.deb
dpkg -i linux-headers-3.2.51-customsds5+_3.2.51-customsds5+-10.00.Custom_amd64.deb
reboot
```

Install NFS Server

```bash
apt-get install nfs-kernel-server
```

Enable some exports

```bash
nano /etc/exports
```

Paste in something like this. I added the insecure option so that the export would work with my OS X boxes.

```bash
/storage    192.168.172.0/24(rw,fsid=0,sync,insecure,no_subtree_check,crossmnt,anonuid=1000,anongid=1000)
```

```bash
exportfs -a
```

At this point NFS exports should be working on your AUFS filesystem.

**\*\*Is the wrong / old kernel booting instead of your new, fancy NFS-enabled kernel?\*\***  
One problem you may have is that this new kernel is not showing up as the default in your Grub Boot menu. It’s likely that it is showing up at the top of the previous linux versions list in Grub. If this is the case, you can easily set it as default. First make a backup of your default Grub list.

```bash
cp /etc/default/grub /etc/default/grub.bak
```

Next, edit the file.

```bash
nano /etc/default/grub
```

edit the GRUB\_DEFAULT line from GRUB\_DEFAULT=0 to this.

```bash
GRUB_DEFAULT="Previous Linux versions>0"
```

This will boot the first item in the list. Fnially, update the Grub Menu.

```bash
update-grub
```