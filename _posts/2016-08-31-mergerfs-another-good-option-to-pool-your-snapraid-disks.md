---
title: 'Mergerfs &#8211; another good option to pool your SnapRAID disks'
date: '2016-08-31T08:41:01-04:00'
layout: post
permalink: /mergerfs-another-good-option-to-pool-your-snapraid-disks/
image: /wp-content/uploads/2016/01/merger-ahead-small.jpg
categories: [polling, snapraid, union]
---

I’m always on the hunt for better options to pool my [SnapRAID array at home](/setting-up-snapraid-on-ubuntu/). I have found a new, great companion in MergerFS. Mergerfs is another disk pooling solution (union filesystem). [Here’s what the author says about it](https://github.com/trapexit/mergerfs).

> mergerfs is similar to mhddfs, unionfs, and aufs. Like mhddfs in that it too uses FUSE. Like aufs in that it provides multiple policies for how to handle behavior. Why create mergerfs when those exist? mhddfs has not been updated in some time nor very flexible. There are also security issues when with running as root. aufs is more flexible than mhddfs but contains some hard to debug inconsistencies in behavior on account of it being a kernel driver. Neither support file attributes (chattr).

Luckily, mergerfs is super easy to install (this is on Ubuntu 22.04 64-bit Server).

```
sudo -i
wget https://github.com/trapexit/mergerfs/releases/download/2.39.0/mergerfs_2.39.0.ubuntu-jammy_amd64.deb
dpkg -i mergerfs_2.39.0.ubuntu-jammy_amd64.deb
rm mergerfs*.deb
```

**Check the [releases page](https://github.com/trapexit/mergerfs/releases) to make sure you are downloading the latest version.**

If you would like to run the latest version, you can always compile from the git repository like this.

```
sudo -i
cd
apt-get install g++ pkg-config git git-buildpackage pandoc debhelper libfuse-dev libattr1-dev -y
git clone https://github.com/trapexit/mergerfs.git 
cd mergerfs
make clean
make deb
cd ..
dpkg -i mergerfs*_amd64.deb
rm mergerfs*_amd64.deb mergerfs*_amd64.changes mergerfs*.dsc mergerfs*.tar.gz
```

That’s it. Mergerfs is ready to pool your data. A couple of nice things that it supports right out of the gate is globbing for mountpoints. This makes it very easy to add to your /etc/fstab.

The nice thing is that mergerfs provides [create modes](https://github.com/trapexit/mergerfs#policy-descriptions) like AUFS. I like the default mode of epmfs, but it’s always nice to have options. I’m also using the minfreespace option with empfs so that I don’t overfill my data disks. So, in a nutshell this has even easier setup than mhddfs, and the benefits of create modes like AUFS. If it was kernel based, this would be the best combination of all pooling solutions. So far, it seems like it may be the current winner.

Enough talk, let’s see how this works… Let’s say I have my data disks mounted in /disks/data/. To add a mergerfs mount line to my fstab, it would be as simple as this.

```
/disks/data/* /storage fuse.mergerfs cache.files=partial,dropcacheonclose=true,category.create=mfs,moveonenospc=true,minfreespace=20G,fsname=mergerfsPool,nonempty 0 0
```

This would pool all mounts in /mnt/data and present them at /storage. This defaults to using lfs (least free space) mode on created files and with the minfreespace option, so my disks won’t fill past 20GB remaining. I’m also using the fsname option so that my df -h is short and usable (otherwise, all the disks show up here and horrible wrapping occurs making the view challenging to use).

I ran a couple of tests tonight on my pooled SnapRAID array, and it appears that mergerfs is faster than mhddfs and just as fast as AUFS. Here’s the outcome of writing a 20GB file over Samba to the server and then reading a different 20GB file back. As the graphs show there is a little “breathing” on the transfers, but reading and writing have no problem saturating a gigabit connection over Samba (an impressive feat).

**WRITE SPEED**  
![z17QiLO](http://zackreed.me/wp-content/uploads/2015/10/z17QiLO.png)  
**Note:** There were times that this transfer exceeded 120MB/s, but it averaged around 105MB/s. Very impressive for a FUSE based pooling solution.  
**READ SPEED**  
![IsAVCSr](http://zackreed.me/wp-content/uploads/2015/10/IsAVCSr.png)  
**Note:** the 140MB/s shown here is faster than gigabit speeds, but it’s due to caching on my Macbook. The transfer averaged around 118MB/s.