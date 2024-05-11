---
title: 'MergerFS neat tricks'
date: '2016-08-31T14:54:14-04:00'
layout: post
permalink: /mergerfs-neat-tricks/
image: /wp-content/uploads/2016/08/flexible-working-spring-mergerfs.jpg
categories: [mergerfs, union]
---

Trapexit’s MergerFS is awesome. He has some [great documentation on the README](https://github.com/trapexit/mergerfs), but I just wanted to share a couple of quick examples I use all the time. Let’s say you have a MergerFS pool mounted at /storage. You can view the current setup by using xattrs to view the pseudo .mergerfs file.

```
apt-get install python-xattr
```

```
cd /storage
xattr -l .mergerfs
```

It will output something like this. Note that there are currently 5 disks shown under the srcmounts value.

```
user.mergerfs.srcmounts: /mnt/data/disk01:/mnt/data/disk02:/mnt/data/disk03:/mnt/data/disk04:/mnt/data/disk05
user.mergerfs.minfreespace: 21474836480
user.mergerfs.moveonenospc: true
user.mergerfs.policies: all,eplfs,eplus,epmfs,erofs,ff,lfs,lus,mfs,newest,rand
user.mergerfs.version: 2.13.1
user.mergerfs.pid: 91089
user.mergerfs.category.action: all
user.mergerfs.category.create: eplfs
user.mergerfs.category.search: ff
user.mergerfs.func.access: ff
user.mergerfs.func.chmod: all
user.mergerfs.func.chown: all
user.mergerfs.func.create: eplfs
user.mergerfs.func.getattr: ff
user.mergerfs.func.getxattr: ff
user.mergerfs.func.link: all
user.mergerfs.func.listxattr: ff
user.mergerfs.func.mkdir: eplfs
user.mergerfs.func.mknod: eplfs
user.mergerfs.func.open: ff
user.mergerfs.func.readlink: ff
user.mergerfs.func.removexattr: all
user.mergerfs.func.rename: all
user.mergerfs.func.rmdir: all
user.mergerfs.func.setxattr: all
user.mergerfs.func.symlink: eplfs
user.mergerfs.func.truncate: all
user.mergerfs.func.unlink: all
user.mergerfs.func.utimens: all
```

All of these options above can be set in realtime without unmounting and re-mounting the mergerfs pool via the runtime options.

**Removing Disks**  
The first example could be removing a couple of disks from the pool.

```
xattr -w user.mergerfs.srcmounts '-/mnt/data/disk04:/mnt/data/disk05' .mergerfs
```

This modifies the pool in realtime (no need to unmount, or stop services like samba/plex). It just works. Afterwards, we are left with this. Note that disk04 and disk05 have been removed from the pool.

```
user.mergerfs.srcmounts: /mnt/data/disk01:/mnt/data/disk02:/mnt/data/disk03
user.mergerfs.minfreespace: 21474836480
user.mergerfs.moveonenospc: true
user.mergerfs.policies: all,eplfs,eplus,epmfs,erofs,ff,lfs,lus,mfs,newest,rand
user.mergerfs.version: 2.13.1
user.mergerfs.pid: 91089
user.mergerfs.category.action: all
user.mergerfs.category.create: eplfs
user.mergerfs.category.search: ff
user.mergerfs.func.access: ff
user.mergerfs.func.chmod: all
user.mergerfs.func.chown: all
user.mergerfs.func.create: eplfs
user.mergerfs.func.getattr: ff
user.mergerfs.func.getxattr: ff
user.mergerfs.func.link: all
user.mergerfs.func.listxattr: ff
user.mergerfs.func.mkdir: eplfs
user.mergerfs.func.mknod: eplfs
user.mergerfs.func.open: ff
user.mergerfs.func.readlink: ff
user.mergerfs.func.removexattr: all
user.mergerfs.func.rename: all
user.mergerfs.func.rmdir: all
user.mergerfs.func.setxattr: all
user.mergerfs.func.symlink: eplfs
user.mergerfs.func.truncate: all
user.mergerfs.func.unlink: all
user.mergerfs.func.utimens: all
```

**Adding Disks**  
Now, let’s show you an example to add a couple disks. Let’s say you got some nice shiny 8TB data disks that you’d like to add to your pool. You can get them all setup and mounted via /etc/fstab (including adding them to the mergerfs line there), but you don’t want to have to offline your pool right now because your kids are watching a movie in Plex. No problem, mergerfs pseudo file to the rescue!

```
xattr -w user.mergerfs.srcmounts '+>/mnt/data/disk04:/mnt/data/disk05' .mergerfs
```

The above will append disk04 and disk05 onto the end of the current srcmounts.

```
user.mergerfs.srcmounts: /mnt/data/disk01:/mnt/data/disk02:/mnt/data/disk03:/mnt/data/disk04:/mnt/data/disk05
user.mergerfs.minfreespace: 21474836480
user.mergerfs.moveonenospc: true
user.mergerfs.policies: all,eplfs,eplus,epmfs,erofs,ff,lfs,lus,mfs,newest,rand
user.mergerfs.version: 2.13.1
user.mergerfs.pid: 91089
user.mergerfs.category.action: all
user.mergerfs.category.create: eplfs
user.mergerfs.category.search: ff
user.mergerfs.func.access: ff
user.mergerfs.func.chmod: all
user.mergerfs.func.chown: all
user.mergerfs.func.create: eplfs
user.mergerfs.func.getattr: ff
user.mergerfs.func.getxattr: ff
user.mergerfs.func.link: all
user.mergerfs.func.listxattr: ff
user.mergerfs.func.mkdir: eplfs
user.mergerfs.func.mknod: eplfs
user.mergerfs.func.open: ff
user.mergerfs.func.readlink: ff
user.mergerfs.func.removexattr: all
user.mergerfs.func.rename: all
user.mergerfs.func.rmdir: all
user.mergerfs.func.setxattr: all
user.mergerfs.func.symlink: eplfs
user.mergerfs.func.truncate: all
user.mergerfs.func.unlink: all
user.mergerfs.func.utimens: all
```

You can also do all sorts of other things like change the create mode, or the moveonenospc value, or even the minfreespace option all without remounting.