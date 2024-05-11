---
title: 'Encrypted SnapRAID'
date: '2013-07-14T23:19:25-04:00'
layout: post
permalink: /encrypted-snapraid/
image: /wp-content/uploads/2013/07/encrypted_snapraid.jpg
categories: [mediaserver, raid, snapraid, ubuntu]
---

If you have read my [previous SnapRAID tutorial,](/setting-up-snapraid-on-ubuntu) you will see that I’m a big fan of it for home storage. I wanted to setup a SnapRAID volume made up of encrypted hard drives. We will accomplish this using dm-crypt + LUKS. The following is how I did it.

This example is going to made up of a (3) disk SnapRAID array + (1) parity disk. In this example, they are disks /dev/sd\[bcde\]. First, let’s install the tools to create encrypted filesystems and to work with our disks.

```bash
apt-get install cryptsetup parted gdisk git gcc -y
```

Next, let’s enable the modules to make the encrypted filesystems work.

```bash
modprobe dm-crypt
modprobe aes
```

With encrypted disks, it’s a good idea to start with clean verified disks. Here’s a way to zero your disk(s).

> [!WARNING]  
> Critical content demanding immediate user attention due to potential risks. WARNING! POTENTIAL DATA LOSS AHEAD

This will overwrite data on /dev/sd\[bcde\] irrevocably.

```bash
dd if=/dev/zero of=/dev/sd[bcde]
```

Next, let’s add a partition to each disk.

```bash
parted -a optimal /dev/sdb
GNU Parted 2.3
Using /dev/sdb
Welcome to GNU Parted! Type 'help' to view a list of commands.
(parted) mklabel gpt
(parted) mkpart primary 1 -1
(parted) align-check
alignment type(min/opt)  [optimal]/minimal? optimal
Partition number? 1
1 aligned
(parted) quit
```

Next, let’s make a backup of this partition table and copy it to the other disks.

```bash
sgdisk --backup=table /dev/sdb
sgdisk --load-backup=table /dev/sdc
sgdisk --load-backup=table /dev/sdd
sgdisk --load-backup=table /dev/sde
```

Then, let’s encrypt these partitions using AES-XTS, the most secure mode of full disk encryption.

```bash
cryptsetup luksFormat -c aes-xts-plain64 -s 512 -h sha512 /dev/sde1
```

Answer the questions like this

```bash
Are you sure? (Type uppercase yes): YES
Enter LUKS passphrase:
Verify passphrase:
```

Next, let’s unlock the encrypted partitions to add a filesystem to them. The names at the end, represent how the disks will be mapped to /dev/mapper (i.e. disk(1,2) or parity1).

```bash
root@snapraid-test:~# cryptsetup luksOpen /dev/sdb1 disk1
Enter passphrase for /dev/sdb1:
root@snapraid-test:~# cryptsetup luksOpen /dev/sdc1 disk2
Enter passphrase for /dev/sdc1:
root@snapraid-test:~# cryptsetup luksOpen /dev/sdd1 disk3
Enter passphrase for /dev/sdd1:
root@snapraid-test:~# cryptsetup luksOpen /dev/sde1 parity1
Enter passphrase for /dev/sde1:
```

Now that they are unlocked, adding a partition is easy.

```bash
mkfs.ext4 /dev/mapper/disk1
mkfs.ext4 /dev/mapper/disk2
mkfs.ext4 /dev/mapper/disk3
mkfs.ext4 /dev/mapper/parity1
```

Now, this encryption is nice, but I don’t want to enter a password for each of my disks to unlock them each time I boot when my / partition is unlocked, so I’ll unlock them automatically at startup. To accomplish this, we will use a keyfile. Here I’m creating a keyfile (this is a 4096 bit key).

```bash
dd if=/dev/urandom of=/root/keyfile bs=1024 count=4
```

Let’s make this file only readable by root.

```bash
chmod 0400 /root/keyfile
```

Next, let’s add this key as an unlocking method for each partition.

```bash
cryptsetup luksAddKey /dev/sdb1 /root/keyfile
cryptsetup luksAddKey /dev/sdc1 /root/keyfile
cryptsetup luksAddKey /dev/sdd1 /root/keyfile
cryptsetup luksAddKey /dev/sde1 /root/keyfile
```

Next, let’s make a mointpoint for each of these disks.

```bash
mkdir /media/{disk1,disk2,disk3,parity1}
```

To make these auto unlock, we need to make /etc/crypttab entries for each disk. They should be based off the crypto\_LUKS partitions. To find their UUIDs, try this…

```bash
blkid | grep crypto_LUKS
```

It should output something like this.

```bash
UUID=b7e810e6-7810-4dfa-893a-2f55dbf09d12
UUID=033e36fd-394c-4ed2-a323-7d596089bfb3
UUID=202e8ba6-9793-4772-a261-100ee2fdd97b
UUID=ea4687a6-875e-4f4e-8c38-eb9aa7caf817
```

Next, use those UUIDs to create the /etc/crypttab file. It should look something like this. Those names at the beginning again create the entries that map to /dev/mapper.

```bash
disk1 UUID=b7e810e6-7810-4dfa-893a-2f55dbf09d12 /root/keyfile luks
disk2 UUID=033e36fd-394c-4ed2-a323-7d596089bfb3 /root/keyfile luks
disk3 UUID=202e8ba6-9793-4772-a261-100ee2fdd97b /root/keyfile luks
parity1 UUID=ea4687a6-875e-4f4e-8c38-eb9aa7caf817 /root/keyfile luks
```

Finally, update your initramfs

```bash
update-initramfs -u
```

Now, the disks will automatically unlock at startup, but I also want them to automount too, so create /etc/fstab entries for each. They should be in this format and based off the UUID of the /dev/mapper entries. To find them quickly, try this.

```bash
blkid | grep mapper
```

Now create /etc/fstab entries for each of the ext4 partitions using the UUID’s from above.

```bash
nano /etc/fstab
```

They should be in this format.

```bash
UUID=5b022bc3-8b5d-4cc1-baf6-7ef163cc6760 /media/disk1	ext4 	defaults 0 2
```

Reboot and ensure your disks automount. Once, you have this working, you can follow along with the rest of my previous [SnapRAID tutorial](/setting-up-snapraid-on-ubuntu).