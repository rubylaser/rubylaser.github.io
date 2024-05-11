---
id: 153
title: 'Encrypted External Drive'
date: '2012-11-19T08:00:00-05:00'
excerpt: 'I wanted to extend my backup strategy to include rotating a couple encrypted disks offsite for another layer to backup my family videos and pictures.  Here are the steps I used to do that on Ubuntu 12.04 Server.'
layout: post
permalink: /encrypted-external-drive/
image: /wp-content/uploads/2012/11/luks-logo.png
categories: [linux, ubuntu]
tags: [encryption]
---

First, let’s grab the packages.

```bash
apt-get install cryptsetup
```

Then, let’s enable the modules.

```bash
modprobe dm-crypt
modprobe aes
```

Next, let’s use badblocks to identify bad sectors and overwrite the disk with random data at the same time (this took about 10 hours on my 640GB drive).

```bash
badblocks -c 10240 -s -w -t random -v /dev/sdg
```

When that’s done, you’ll want to add a filesystem to the drive

```bash
fdisk /dev/sdg
```

Next, let’s LUKS encrypt the drive.

```bash
cryptsetup --hash sha512 --key-size 256 --cipher aes-cbc-essiv:sha256 luksFormat /dev/sdg1
```

You’ll need to answer YES to the question in all caps to create the encrypted partition. Then, you’ll want to mount the volume.

```bash
cryptsetup luksOpen /dev/sdg1 securebackup
```

This will open the volume at /dev/mapper/securebackup. Next, we need to put a filesystem on the encrypted partition.

```bash
mkfs.ext4 -m 1 -O dir_index,filetype /dev/mapper/securebackup
```

Once that’s done, you are ready to mount the encrypted partition to write to it.

```bash
mkdir -p /media/securebackup
mount /dev/mapper/securebackup /media/securebackup/
```

When you are done working on your encrypted volume, you’ll want to unmount it, and then close the LUKS encrypted volume like this.

```bash
umount /media/securebackup/
cryptsetup luksClose /dev/mapper/securebackup
```

And, there are the simple steps to an encrypted backup disk.