---
id: 144
title: 'Increasing the size of mdadm RAID1 disks'
date: '2012-02-21T08:00:00-05:00'
layout: post
permalink: /increasing-the-size-of-mdadm-raid1-disks/
image: /wp-content/uploads/2012/02/ct06158TBPlatten_84415-ll-jg_PR.jpg
categories: [linux, mdadm]
---

I started off with 2 existing RAID1 arrays (one for / and one for swap).

```bash
cat /proc/mdstat
Personalities : [linear] [multipath] [raid0] [raid1] [raid6] [raid5] [raid4] [raid10] 
md1 : active raid1 sda5[0] sdb5[1]
      2094068 blocks super 1.2 [2/2] [UU]
      
md0 : active raid1 sda1[0] sdb1[1]
      10483640 blocks super 1.2 [2/2] [UU]
```

```bash
fdisk -l

Disk /dev/sda: 12.9 GB, 12884901888 bytes
255 heads, 63 sectors/track, 1566 cylinders, total 25165824 sectors
Units = sectors of 1 * 512 = 512 bytes
Sector size (logical/physical): 512 bytes / 512 bytes
I/O size (minimum/optimal): 512 bytes / 512 bytes
Disk identifier: 0x000a35cd

   Device Boot      Start         End      Blocks   Id  System
/dev/sda1   *        2048    20971519    10484736   fd  Linux raid autodetect
/dev/sda2        20973566    25163775     2095105    5  Extended
/dev/sda5        20973568    25163775     2095104   fd  Linux raid autodetect

Disk /dev/sdb: 12.9 GB, 12884901888 bytes
255 heads, 63 sectors/track, 1566 cylinders, total 25165824 sectors
Units = sectors of 1 * 512 = 512 bytes
Sector size (logical/physical): 512 bytes / 512 bytes
I/O size (minimum/optimal): 512 bytes / 512 bytes
Disk identifier: 0x000b985f

   Device Boot      Start         End      Blocks   Id  System
/dev/sdb1   *        2048    20971519    10484736   fd  Linux raid autodetect
/dev/sdb2        20973566    25163775     2095105    5  Extended
/dev/sdb5        20973568    25163775     2095104   fd  Linux raid autodetect

Disk /dev/sdc: 21.5 GB, 21474836480 bytes
255 heads, 63 sectors/track, 2610 cylinders, total 41943040 sectors
Units = sectors of 1 * 512 = 512 bytes
Sector size (logical/physical): 512 bytes / 512 bytes
I/O size (minimum/optimal): 512 bytes / 512 bytes
Disk identifier: 0x00065756

   Device Boot      Start         End      Blocks   Id  System

Disk /dev/sdd: 21.5 GB, 21474836480 bytes
255 heads, 63 sectors/track, 2610 cylinders, total 41943040 sectors
Units = sectors of 1 * 512 = 512 bytes
Sector size (logical/physical): 512 bytes / 512 bytes
I/O size (minimum/optimal): 512 bytes / 512 bytes
Disk identifier: 0x00000000

Disk /dev/sdd doesn't contain a valid partition table

Disk /dev/md0: 10.7 GB, 10735247360 bytes
2 heads, 4 sectors/track, 2620910 cylinders, total 20967280 sectors
Units = sectors of 1 * 512 = 512 bytes
Sector size (logical/physical): 512 bytes / 512 bytes
I/O size (minimum/optimal): 512 bytes / 512 bytes
Disk identifier: 0x00000000

Disk /dev/md0 doesn't contain a valid partition table

Disk /dev/md1: 2144 MB, 2144325632 bytes
2 heads, 4 sectors/track, 523517 cylinders, total 4188136 sectors
Units = sectors of 1 * 512 = 512 bytes
Sector size (logical/physical): 512 bytes / 512 bytes
I/O size (minimum/optimal): 512 bytes / 512 bytes
Disk identifier: 0x00000000

Disk /dev/md1 doesn't contain a valid partition table
```

Here’s the file space

```bash
df -h
Filesystem            Size  Used Avail Use% Mounted on
/dev/md0              9.9G  2.5G  6.9G  27% /
udev                  997M  8.0K  997M   1% /dev
tmpfs                 402M  788K  401M   1% /run
none                  5.0M     0  5.0M   0% /run/lock
none                 1005M  108K 1005M   1% /run/shm
```

The next thing to do is get your partitions setup on your replacement disk. Since, I’m growing from 12GB to 20GB in the Virtualbox example, you’ll set that reflected in the partitioning.

```bash
fdisk /dev/sdc

Command (m for help): n
Command action
   e   extended
   p   primary partition (1-4)
p
Partition number (1-4, default 1): 1
First sector (2048-41943039, default 2048): 
Using default value 2048
Last sector, +sectors or +size{K,M,G} (2048-41943039, default 41943039): 37748736

Command (m for help): t
Selected partition 1
Hex code (type L to list codes): fd
Changed system type of partition 1 to fd (Linux raid autodetect)

Command (m for help): w
The partition table has been altered!

Calling ioctl() to re-read partition table.
Syncing disks.
root@mdadm-test:~# fdisk /dev/sdc

Command (m for help): n
Command action
   e   extended
   p   primary partition (1-4)
e
Partition number (1-4, default 2): 2
First sector (37748737-41943039, default 37748737): 
Using default value 37748737
Last sector, +sectors or +size{K,M,G} (37748737-41943039, default 41943039): 
Using default value 41943039

Command (m for help): w
The partition table has been altered!

Calling ioctl() to re-read partition table.
Syncing disks.
root@mdadm-test:~# fdisk /dev/sdc

Command (m for help): n
Command action
   l   logical (5 or over)
   p   primary partition (1-4)
l
First sector (37750785-41943039, default 37750785): 
Using default value 37750785
Last sector, +sectors or +size{K,M,G} (37750785-41943039, default 41943039): 
Using default value 41943039

Command (m for help): t
Partition number (1-5): 5 
Hex code (type L to list codes): fd
Changed system type of partition 5 to fd (Linux raid autodetect)

Command (m for help): w
The partition table has been altered!

Calling ioctl() to re-read partition table.
Syncing disks.

fdisk /dev/sdd
Command (m for help): n
Command action
   e   extended
   p   primary partition (1-4)
p
Partition number (1-4, default 1): 1
First sector (2048-41943039, default 2048): 
Using default value 2048
Last sector, +sectors or +size{K,M,G} (2048-41943039, default 41943039): 37748736

Command (m for help): t
Selected partition 1
Hex code (type L to list codes): fd
Changed system type of partition 1 to fd (Linux raid autodetect)

Command (m for help): n
Command action
   e   extended
   p   primary partition (1-4)
e
Partition number (1-4, default 2): 2
First sector (37748737-41943039, default 37748737): 
Using default value 37748737
Last sector, +sectors or +size{K,M,G} (37748737-41943039, default 41943039): 
Using default value 41943039

Command (m for help): n
Command action
   l   logical (5 or over)
   p   primary partition (1-4)
l
First sector (37750785-41943039, default 37750785): 
Using default value 37750785
Last sector, +sectors or +size{K,M,G} (37750785-41943039, default 41943039): 
Using default value 41943039

Command (m for help): t
Partition number (1-5): 5
Hex code (type L to list codes): fd
Changed system type of partition 5 to fd (Linux raid autodetect)

Command (m for help): w
The partition table has been altered!

Calling ioctl() to re-read partition table.
Syncing disks.
```

Here’s the new partitioning…

```bash
fdisk -l

Disk /dev/sda: 12.9 GB, 12884901888 bytes
255 heads, 63 sectors/track, 1566 cylinders, total 25165824 sectors
Units = sectors of 1 * 512 = 512 bytes
Sector size (logical/physical): 512 bytes / 512 bytes
I/O size (minimum/optimal): 512 bytes / 512 bytes
Disk identifier: 0x000a35cd

   Device Boot      Start         End      Blocks   Id  System
/dev/sda1   *        2048    20971519    10484736   fd  Linux raid autodetect
/dev/sda2        20973566    25163775     2095105    5  Extended
/dev/sda5        20973568    25163775     2095104   fd  Linux raid autodetect

Disk /dev/sdb: 12.9 GB, 12884901888 bytes
255 heads, 63 sectors/track, 1566 cylinders, total 25165824 sectors
Units = sectors of 1 * 512 = 512 bytes
Sector size (logical/physical): 512 bytes / 512 bytes
I/O size (minimum/optimal): 512 bytes / 512 bytes
Disk identifier: 0x000b985f

   Device Boot      Start         End      Blocks   Id  System
/dev/sdb1   *        2048    20971519    10484736   fd  Linux raid autodetect
/dev/sdb2        20973566    25163775     2095105    5  Extended
/dev/sdb5        20973568    25163775     2095104   fd  Linux raid autodetect

Disk /dev/sdc: 21.5 GB, 21474836480 bytes
255 heads, 63 sectors/track, 2610 cylinders, total 41943040 sectors
Units = sectors of 1 * 512 = 512 bytes
Sector size (logical/physical): 512 bytes / 512 bytes
I/O size (minimum/optimal): 512 bytes / 512 bytes
Disk identifier: 0x00065756

   Device Boot      Start         End      Blocks   Id  System
/dev/sdc1            2048    37748736    18873344+  fd  Linux raid autodetect
/dev/sdc2        37748737    41943039     2097151+   5  Extended
/dev/sdc5        37750785    41943039     2096127+  fd  Linux raid autodetect

Disk /dev/sdd: 21.5 GB, 21474836480 bytes
255 heads, 63 sectors/track, 2610 cylinders, total 41943040 sectors
Units = sectors of 1 * 512 = 512 bytes
Sector size (logical/physical): 512 bytes / 512 bytes
I/O size (minimum/optimal): 512 bytes / 512 bytes
Disk identifier: 0x36d4ebfb

   Device Boot      Start         End      Blocks   Id  System
/dev/sdd1            2048    37748736    18873344+  fd  Linux raid autodetect
/dev/sdd2        37748737    41943039     2097151+   5  Extended
/dev/sdd5        37750785    41943039     2096127+  fd  Linux raid autodetect

Disk /dev/md0: 10.7 GB, 10735247360 bytes
2 heads, 4 sectors/track, 2620910 cylinders, total 20967280 sectors
Units = sectors of 1 * 512 = 512 bytes
Sector size (logical/physical): 512 bytes / 512 bytes
I/O size (minimum/optimal): 512 bytes / 512 bytes
Disk identifier: 0x00000000

Disk /dev/md0 doesn't contain a valid partition table

Disk /dev/md1: 2144 MB, 2144325632 bytes
2 heads, 4 sectors/track, 523517 cylinders, total 4188136 sectors
Units = sectors of 1 * 512 = 512 bytes
Sector size (logical/physical): 512 bytes / 512 bytes
I/O size (minimum/optimal): 512 bytes / 512 bytes
Disk identifier: 0x00000000

Disk /dev/md1 doesn't contain a valid partition table
```

Now, we’ll remove one disk at a time, and replace with a new disk. We’re removing both partitions of each disk from each array.

```bash
mdadm --manage /dev/md0 --fail /dev/sdb1
mdadm --manage /dev/md0 --remove /dev/sdb1
```

```bash
mdadm --manage /dev/md1 --fail /dev/sdb5
mdadm --manage /dev/md1 --remove /dev/sdb5
```

Here’s what it will look like after doing that.

```bash
cat /proc/mdstat
Personalities : [linear] [multipath] [raid0] [raid1] [raid6] [raid5] [raid4] [raid10] 
md1 : active raid1 sda5[0]
      2094068 blocks super 1.2 [2/1] [U_]
      
md0 : active raid1 sda1[0]
      10483640 blocks super 1.2 [2/1] [U_]
```

Next, let’s add in the 2 new partitions.

```bash
mdadm --manage /dev/md0 --add /dev/sdd1
mdadm --manage /dev/md1 --add /dev/sdd5
```

Wait for both arrays to finish syncing

```bash
watch cat /proc/mdstat
```

Finally, install grub to the new disk

```bash
grub-install /dev/sdd
```

Okay, you’re on the final stretch! Let’s do that with the other disk.

```bash
mdadm --manage /dev/md0 --fail /dev/sda1
mdadm --manage /dev/md0 --remove /dev/sda1
mdadm --manage /dev/md1 --fail /dev/sda5
mdadm --manage /dev/md1 --remove /dev/sda5
```

And add in the replacement

```bash
mdadm --manage /dev/md0 --add /dev/sdc1
mdadm --manage /dev/md1 --add /dev/sdc5
```

Wait for it to finish syncing…

```bash
watch cat /proc/mdstat
```

Install grub on this disk

```bash
grub-install /dev/sdc
```

Next, we need to resize the mdadm array to take advantage of the new space.

```bash
mdadm -G /dev/md0 -z max
```

Here’s the new array’s size.

```bash
mdadm --detail /dev/md0
/dev/md0:
        Version : 1.2
  Creation Time : Tue Feb 21 07:29:02 2012
     Raid Level : raid1
     Array Size : 18872320 (18.00 GiB 19.33 GB)
  Used Dev Size : 18872320 (18.00 GiB 19.33 GB)
   Raid Devices : 2
  Total Devices : 2
    Persistence : Superblock is persistent

    Update Time : Tue Feb 21 10:05:40 2012
          State : clean
 Active Devices : 2
Working Devices : 2
 Failed Devices : 0
  Spare Devices : 0

           Name : mdadm-test:0  (local to host mdadm-test)
           UUID : be0e3084:b6d1245a:893001ba:3dbfb1f1
         Events : 119

    Number   Major   Minor   RaidDevice State
       3       8       33        0      active sync   /dev/sdc1
       2       8       49        1      active sync   /dev/sdd1
```

And finally, resize the filesystem.

```bash
resize2fs /dev/md0
```

Now, reboot and enjoy all of your newfound storage space 🙂

```bash
df -h
Filesystem            Size  Used Avail Use% Mounted on
/dev/md0               18G  2.6G   15G  15% /
udev                  997M  8.0K  997M   1% /dev
tmpfs                 402M  816K  401M   1% /run
none                  5.0M     0  5.0M   0% /run/lock
none                 1005M  1.1M 1004M   1% /run/shm
```