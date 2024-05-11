---
title: 'Ubuntu 14.04 with 4.0.4 kernel and latest AUFS from source'
date: '2015-05-29T19:22:09-04:00'
layout: post
permalink: /ubuntu-14-04-with-4-0-4-kernel-and-latest-aufs-from-source/
image: /wp-content/uploads/2016/01/404_kernel.jpg
categories: [aufs, pooling, compile]
---

After some Googling, this looks like a common issue with most kernels shipping with distros. Here are a few links to look at.

<https://forums.sonarr.tv/t/native-mono-crashes/4985/32>  
<https://emby.media/community/index.php?/topic/19955-emby-crashing-ubuntu-server/page-5#entry207271>  
<https://bugs.launchpad.net/ubuntu/+source/linux/+bug/1450584>

Here are the steps I followed to get this working.

First, let’s become the root user and get the build dependencies…

```
sudo -i

# Build Dependencies
apt-get -y install git-core kernel-package fakeroot build-essential bc ncurses-dev -y
```

Next, let’s grab the mainline Ubuntu 4.0.4 kernel and patches, and install them.

```
mkdir -p /opt/src/4.0.4/
cd /opt/src/4.0.4/
wget https://kernel.ubuntu.com/~kernel-ppa/mainline/v4.0.4-wily/linux-headers-4.0.4-040004-generic_4.0.4-040004.201505171336_amd64.deb
wget https://kernel.ubuntu.com/~kernel-ppa/mainline/v4.0.4-wily/linux-headers-4.0.4-040004_4.0.4-040004.201505171336_all.deb
wget https://kernel.ubuntu.com/~kernel-ppa/mainline/v4.0.4-wily/linux-image-4.0.4-040004-generic_4.0.4-040004.201505171336_amd64.deb
wget https://kernel.ubuntu.com/~kernel-ppa/mainline/v4.0.4-wily/0001-base-packaging.patch
wget https://kernel.ubuntu.com/~kernel-ppa/mainline/v4.0.4-wily/0002-debian-changelog.patch
wget https://kernel.ubuntu.com/~kernel-ppa/mainline/v4.0.4-wily/0003-configs-based-on-Ubuntu-4.0.2-1.1.patch
dpkg -i linux-*4.0.4*.deb
```

Next, let’s grab the AUFS git repository and use the branch to match our 4.0.4 kernel

```
mkdir -p /opt/src/aufs
cd /opt/src/aufs/
git clone https://github.com/sfjro/aufs4-standalone.git aufs4-standalone.git
cd aufs4-standalone.git/
git checkout origin/aufs4.0
```

Next, let’s get kernel source and extract it.

```
mkdir -p /opt/src/4.0.4aufs
cd /opt/src/4.0.4aufs/
wget https://www.kernel.org/pub/linux/kernel/v4.x/linux-4.0.4.tar.gz
tar xzvf linux-4.0.4.tar.gz
```

Let’s patch this kernel with the Ubuntu configurations and then apply the AUFS patches.

```
cd linux-4.0.4/
patch -p1 < /opt/src/4.0.4/0001-base-packaging.patch
patch -p1 < /opt/src/4.0.4/0002-debian-changelog.patch
patch -p1 < /opt/src/4.0.4/0003-configs-based-on-Ubuntu-4.0.2-1.1.patch

# Apply AUFS patches
patch -p1 < /opt/src/aufs/aufs4-standalone.git/aufs4-base.patch
patch -p1 < /opt/src/aufs/aufs4-standalone.git/aufs4-standalone.patch
patch -p1 < /opt/src/aufs/aufs4-standalone.git/aufs4-mmap.patch
patch -p1 < /opt/src/aufs/aufs4-standalone.git/aufs4-kbuild.patch
```

Next, copy the AUFS files to kernel source tree.

```
cp -R /opt/src/aufs/aufs4-standalone.git/Documentation /opt/src/4.0.4aufs/linux-4.0.4
cp -R /opt/src/aufs/aufs4-standalone.git/fs /opt/src/4.0.4aufs/linux-4.0.4
cp /opt/src/aufs/aufs4-standalone.git/include/uapi/linux/aufs_type.h /opt/src/4.0.4aufs/linux-4.0.4/include/uapi/linux/.
```

Next, let’s configure kernel options to enable AUFS NFS exports.

```
cp /boot/config-4.0.4-040004-generic .config
make olddefconfig
make menuconfig
```

At this point, you will want to go to select AuFS under \*\*File Systems &gt; Miscellaneous filesystems\*\* Also, select the NFS export option. When you are done, it should look like this.  
![ZEuhl43](/wp-content/uploads/2015/05/ZEuhl43.png)

Then press exit a few times until you are out and save the changes.

Next, we will compile the kernel and generate dpkgs (this will take a LONG time). **NOTE: I would strongly suggest you run this via tmux or screen because an SSH session will likely disconnect before it’s done causing the compile to be half finished and future steps in this tutorial to fail.**

```
CONCURRENCY_LEVEL=4 fakeroot make-kpkg --initrd --append-to-version=-aufs kernel_image kernel_headers
```

```
Once the compile is done, we will install the new kernel and kernel headers.
cd ..
dpkg -i linux-headers-4.0.4-aufs_4.0.4-aufs-10.00.Custom_amd64.deb linux-image-4.0.4-aufs_4.0.4-aufs-10.00.Custom_amd64.deb
```

Next, let’s hold these custom packages, so that future kernel updates don’t break anything.

```
echo "linux-image-4.0.4-aufs hold"             | dpkg --set-selections
echo "linux-headers-4.0.4-aufs hold"           | dpkg --set-selections
echo "linux-image-4.0.4-040004-generic hold"    | dpkg --set-selections
echo "linux-headers-4.0.4-040004-generic hold"  | dpkg --set-selections
```

Next’s let update our GRUB menu to boot from this custom kernel.

```
sed -i.bak /etc/default/grub -e's|^GRUB_DEFAULT=.*|GRUB_DEFAULT="Advanced options for Ubuntu>Ubuntu, with Linux 4.0.4-aufs"|g'
update-grub

# and run update-grub
update-grub
```

At this point, you should have your new kernel all setup and working. Let’s reboot the machine and make sure you are on this new kernel.

```
reboot
```

After reboot, running uname -a should provide something like this (4.0.4 kernel).

```
uname -a
```

Now, let’s start working on compiling AUFS for our kerel and include the notify and NFS export options.

```
cd /opt/src/aufs/aufs4-standalone.git/
# Enable hnotify, allows direct access to branches bypassing AUFS
sed -i.bak config.mk -e's|^CONFIG_AUFS_HNOTIFY.*|CONFIG_AUFS_HNOTIFY = y|g' -e's|^CONFIG_AUFS_HFSNOTIFY.*|CONFIG_AUFS_HFSNOTIFY = y|g'
```

Next, we need to fix a missing binary that prevents AUFS from compiling properly.

```
cd /opt/src/4.0.4aufs/linux-4.0.4/scripts/
gcc unifdef.c -o unifdef
cd -
```

It’s time to start compiling…

```
make
```

If everything went well, and you don’t see errors at the end of the make, then it’s time to install and pickup this new AUFS module.

```
make install
depmod -a
```

For some reason the module didn’t install in the right location correctly with the above, I therefore had to copy it manually to the proper location.

```
cd /lib/modules/4.0.4-aufs/kernel/fs/aufs/
mv aufs.ko aufs.bak
cp /opt/src/aufs/aufs4-standalone.git/aufs.ko .
reboot
```

I created a mount point for it.

```
mkdir /storage
```

Finally, to use these options, you should mount your AUFS pool like this.

```
mount -t aufs -o br:/media/disk1=rw:/media/disk2=rw:/media/disk3=rw:/media/disk4=rw,sum,create=pmfsrr:10000000000,udba=notify none /storage
```

If the mount works correctly, I would suggest that you mount your pool via adding a line to /etc/rc.local rather than trying to mount the pool via fstab.

```
nano /etc/rc.local
```

Add a line like this just before the exit line.

```
mount -t aufs -o br:/media/disk1=rw:/media/disk2=rw:/media/disk3=rw:/media/disk4=rw,sum,create=pmfsrr:10000000000,udba=notify none /storage
```

**NOTE: I’m mounting with the pmfsrr option so that if the parent directory doesn’t have the available space for a write, AUFS will gracefully write to the next disk.**

Once everything is working, you can clean up your src directory to get back 10+ GB if you’d like to.

```
rm -rf /opt/src/*
```

You should now have AUFS running without the whiteout and opaque files, and all of it’s other benefits vs. mhddfs (less resource intensive and increased disk throughput). The whiteout files and opaque files will still show up at the data disk root. This is how AUFS works and is normal behavior.