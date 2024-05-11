---
id: 149
title: 'mdadm replace smaller disks with larger ones'
date: '2012-07-30T07:00:00-04:00'
excerpt: 'I was recently asked on the Ubuntuforums how to replace (3) 1TB drives in an mdadm one at a time.  Here''s a quick writeup of the process.'
layout: post
permalink: /mdadm-replace-smaller-disks-with-larger-ones/
categories:
    - linux
    - mdadm
---

Here’s a quick example to show you. I made a (3) disk RAID5 in VBox with 1GB disks (/dev/sd\[bcd\]1). Then, I’ll replace each one with 2GB disks (/dev/sd\[efg\]1). As a sidenote, this is a risky process, and you should have a good, verified backup before you proceed.

```bash
 Disk /dev/sdb: 1073 MB, 1073741824 bytes 139 heads, 8 sectors/track, 1885 cylinders, total 2097152 sectors Units = sectors of 1 * 512 = 512 bytes Sector size (logical/physical): 512 bytes / 512 bytes I/O size (minimum/optimal): 512 bytes / 512 bytes Disk identifier: 0x4e8d3932     Device Boot      Start         End      Blocks   Id  System /dev/sdb1            2048     2097151     1047552   83  Linux  Disk /dev/sdc: 1073 MB, 1073741824 bytes 139 heads, 8 sectors/track, 1885 cylinders, total 2097152 sectors Units = sectors of 1 * 512 = 512 bytes Sector size (logical/physical): 512 bytes / 512 bytes I/O size (minimum/optimal): 512 bytes / 512 bytes Disk identifier: 0x13854649     Device Boot      Start         End      Blocks   Id  System /dev/sdc1            2048     2097151     1047552   83  Linux  Disk /dev/sdd: 1073 MB, 1073741824 bytes 139 heads, 8 sectors/track, 1885 cylinders, total 2097152 sectors Units = sectors of 1 * 512 = 512 bytes Sector size (logical/physical): 512 bytes / 512 bytes I/O size (minimum/optimal): 512 bytes / 512 bytes Disk identifier: 0xa17beaec     Device Boot      Start         End      Blocks   Id  System /dev/sdd1            2048     2097151     1047552   83  Linux  Disk /dev/sde: 2147 MB, 2147483648 bytes 22 heads, 16 sectors/track, 11915 cylinders, total 4194304 sectors Units = sectors of 1 * 512 = 512 bytes Sector size (logical/physical): 512 bytes / 512 bytes I/O size (minimum/optimal): 512 bytes / 512 bytes Disk identifier: 0x1f82774e     Device Boot      Start         End      Blocks   Id  System /dev/sde1            2048     4194303     2096128   83  Linux  Disk /dev/sdf: 2147 MB, 2147483648 bytes 22 heads, 16 sectors/track, 11915 cylinders, total 4194304 sectors Units = sectors of 1 * 512 = 512 bytes Sector size (logical/physical): 512 bytes / 512 bytes I/O size (minimum/optimal): 512 bytes / 512 bytes Disk identifier: 0x517548cf     Device Boot      Start         End      Blocks   Id  System /dev/sdf1            2048     4194303     2096128   83  Linux  Disk /dev/sdg: 2147 MB, 2147483648 bytes 22 heads, 16 sectors/track, 11915 cylinders, total 4194304 sectors Units = sectors of 1 * 512 = 512 bytes Sector size (logical/physical): 512 bytes / 512 bytes I/O size (minimum/optimal): 512 bytes / 512 bytes Disk identifier: 0x6fe6a9a8     Device Boot      Start         End      Blocks   Id  System /dev/sdg1            2048     4194303     2096128   83  Linux
```

Create the array

```bash
 mdadm --create --verbose /dev/md0 --level=5 --raid-devices=3 /dev/sd[bcd]1
```

```bash
 root@test:~# mdadm --detail /dev/md0 /dev/md0:         Version : 1.2   Creation Time : Mon Jul 30 12:38:41 2012      Raid Level : raid5      Array Size : 2094080 (2045.34 MiB 2144.34 MB)   Used Dev Size : 1047040 (1022.67 MiB 1072.17 MB)    Raid Devices : 3   Total Devices : 3     Persistence : Superblock is persistent      Update Time : Mon Jul 30 12:39:01 2012           State : clean, degraded, recovering   Active Devices : 2 Working Devices : 3  Failed Devices : 0   Spare Devices : 1           Layout : left-symmetric      Chunk Size : 512K   Rebuild Status : 11% complete             Name : test:0  (local to host test)            UUID : c678b493:e13f07fb:90a4dcf3:2fcd1191          Events : 2      Number   Major   Minor   RaidDevice State        0       8       17        0      active sync   /dev/sdb1        1       8       33        1      active sync   /dev/sdc1        3       8       49        2      spare rebuilding   /dev/sdd1
```

Add a filesystem

```bash
 mkfs.ext4 /dev/md0
```

Mount it

```bash
root@test:~# df -h Filesystem      Size  Used Avail Use% Mounted on /dev/sda1       7.5G  1.1G  6.1G  16% / udev            238M  4.0K  238M   1% /dev tmpfs            99M  348K   98M   1% /run none            5.0M     0  5.0M   0% /run/lock none            246M     0  246M   0% /run/shm /dev/md0        2.0G   64M  1.9G   4% /storage
```

Let’s make a testfile to ensure consistency.

```bash
 root@test:~# echo "Hello, I'm a testfile" > /storage/testfile.out root@test:~# md5sum /storage/testfile.out  8823d4f33a26dbdb1a05e8836b93ba43  /storage/testfile.out
```

Remove the first disk

```bash
 mdadm --manage /dev/md0 --fail /dev/sdb1 mdadm --manage /dev/md0 --remove /dev/sdb1
```

Add the replacement disk

```bash
 mdadm --manage /dev/md0 --add /dev/sde1
```

View the detail (notice the array size is the same).

```bash
 root@test:~# mdadm --detail /dev/md0 /dev/md0:         Version : 1.2   Creation Time : Mon Jul 30 12:38:41 2012      Raid Level : raid5      Array Size : 2094080 (2045.34 MiB 2144.34 MB)   Used Dev Size : 1047040 (1022.67 MiB 1072.17 MB)    Raid Devices : 3   Total Devices : 3     Persistence : Superblock is persistent      Update Time : Mon Jul 30 12:44:54 2012           State : clean, degraded, recovering   Active Devices : 2 Working Devices : 3  Failed Devices : 0   Spare Devices : 1           Layout : left-symmetric      Chunk Size : 512K   Rebuild Status : 6% complete             Name : test:0            UUID : c678b493:e13f07fb:90a4dcf3:2fcd1191          Events : 72      Number   Major   Minor   RaidDevice State        4       8       65        0      spare rebuilding   /dev/sde1        1       8       33        1      active sync   /dev/sdc1        3       8       49        2      active sync   /dev/sdd1
```

Complete for the rest of the disks. Here’s with all the disks replaced (you’ll notice the size remains the same).

```bash
 root@test:~# mdadm --detail /dev/md0 /dev/md0:         Version : 1.2   Creation Time : Mon Jul 30 12:38:41 2012      Raid Level : raid5      Array Size : 2094080 (2045.34 MiB 2144.34 MB)   Used Dev Size : 1047040 (1022.67 MiB 1072.17 MB)    Raid Devices : 3   Total Devices : 3     Persistence : Superblock is persistent      Update Time : Mon Jul 30 13:01:27 2012           State : clean   Active Devices : 3 Working Devices : 3  Failed Devices : 0   Spare Devices : 0           Layout : left-symmetric      Chunk Size : 512K             Name : test:0            UUID : c678b493:e13f07fb:90a4dcf3:2fcd1191          Events : 137      Number   Major   Minor   RaidDevice State        4       8       65        0      active sync   /dev/sde1        5       8       81        1      active sync   /dev/sdf1        3       8       97        2      active sync   /dev/sdg1
```

Now, set the size of the array to the max available space.

```bash
 mdadm --grow /dev/md0 --size=max
```

```bash
 root@test:~# mdadm --detail /dev/md0 /dev/md0:         Version : 1.2   Creation Time : Mon Jul 30 12:38:41 2012      Raid Level : raid5      Array Size : 4190208 (4.00 GiB 4.29 GB)   Used Dev Size : 2095104 (2046.34 MiB 2145.39 MB)    Raid Devices : 3   Total Devices : 3     Persistence : Superblock is persistent      Update Time : Mon Jul 30 13:02:56 2012           State : clean, resyncing   Active Devices : 3 Working Devices : 3  Failed Devices : 0   Spare Devices : 0           Layout : left-symmetric      Chunk Size : 512K    Resync Status : 56% complete             Name : test:0            UUID : c678b493:e13f07fb:90a4dcf3:2fcd1191          Events : 139      Number   Major   Minor   RaidDevice State        4       8       65        0      active sync   /dev/sde1        5       8       81        1      active sync   /dev/sdf1        3       8       97        2      active sync   /dev/sdg1
```

Unmount the array, and resize the filesystem.

```bash
 umount /storage fsck.ext4 -f /dev/md0 resize2fs /dev/md0
```

And check that size now.

```bash
 root@test:~# df -h Filesystem      Size  Used Avail Use% Mounted on /dev/sda1       7.5G  1.1G  6.1G  16% / udev            238M  4.0K  238M   1% /dev tmpfs            99M  348K   98M   1% /run none            5.0M     0  5.0M   0% /run/lock none            246M     0  246M   0% /run/shm /dev/md0        4.0G   94M  3.9G   3% /storage
```

And, let’s check the consistency of our original file.

```bash
 root@test:~# cat /storage/testfile.out  Hello, I'm a testfile root@test:~# md5sum /storage/testfile.out  8823d4f33a26dbdb1a05e8836b93ba43  /storage/testfile.out
```

You’re now all set to start adding more files 🙂