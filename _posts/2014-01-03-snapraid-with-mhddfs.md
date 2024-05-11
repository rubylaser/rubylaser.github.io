---
title: 'SnapRAID with mhddfs'
date: '2014-01-03T08:00:00-05:00'
layout: post
guid: 'http://zackreed.me/snapraid-with-mhddfs/'
permalink: /snapraid-with-mhddfs/
image: /wp-content/uploads/2014/01/hard-drive-220x162.jpg
categories: [fileserver, mediaserver, snapraid]
---

Some users have been experiencing issues with AUFS’s quirks in terms of moving, or deleting files. mhddfs does not have white out files and as result, works as people expect.  
[mhddfs](https://romanrm.net/mhddfs) is FUSE based, so it’s not going to saturate a gigabit ethernet connection like AUFS can, but for home users it should be fine for a media server. The other downside compared to AUFS is that it uses significantly more system resources. All that being said, mhddfs has a lot of nice features, and *“it just works”*. Even my wimpy Celeron 847 reads from the pool over NFS about 60-65MB/s and writes to it between 30-60MB/s. Faster CPUs come close to staturating gigabit over NFS. Here is a quick writeup to set it up.

```bash
apt-get install mhddfs
```

Next, create a mountpoint.

```bash
mkdir /storage
```

Make an entry in /etc/fstab

```bash
mhddfs#/media/disk1,/media/disk2,/media/disk3,/media/disk4 /storage fuse defaults,allow_other,nonempty 0 0
```

Finally, mount the pool.

```bash
mount -a
```

Here is a local Write and Read speed test…

```bash
root@fileserver:~# dd if=/dev/zero of=/storage/testfile.out bs=1M count=10000; sync
10000+0 records in 10000+0 records out 10485760000 bytes (10 GB) copied, 123.954 s, 84.6 MB/s

root@fileserver:~# dd if=/storage/testfile.out of=/dev/null bs=1M count=10000
10000+0 records in 10000+0 records out 10485760000 bytes (10 GB) copied, 76.2646 s, 137 MB/s
```