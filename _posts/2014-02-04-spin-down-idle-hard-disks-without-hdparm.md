---
title: 'Spin Down Idle Hard Disks Without /etc/hdparm.conf'
date: '2014-02-04T08:00:00-05:00'
layout: post
permalink: /spin-down-idle-hard-disks-without-hdparm/
image: /wp-content/uploads/2014/02/hard-drive-stop.jpg
categories: [disk, idle, ubuntu]
---

I’ve had a few people ask me over the years about spinning down disk that don’t have Advanced Power Management or otherwise can’t be spun down by hdparm. The following is a way to spindown disks without using hdparm’s config file.  
Here is a brief shell script to spindown idle hard drives.

```bash
 nano /root/scripts/disk_spindown.sh
```

and paste this in…

```bash
#! /bin/bash

# Specify any drives you want to ignore; separate multiple drives by spaces; e.g. "sda sdb"
IGNORE_DRIVES=""


PATH='/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin'

now=$(date +"%m_%d_%Y-%H-%M")

# Check for idle disks and spin them down unless smartd is running tests

# Create a file on the ramdisk and cycle it to test for disk activity
( if [ ! -f /dev/shm/diskstats_1 ] ; then touch /dev/shm/diskstats_1 /dev/shm/diskstats_2; fi ; mv /dev/shm/diskstats_1 /dev/shm/diskstats_2; cat /proc/diskstats > /dev/shm/diskstats_1 ) >/dev/null 2>&1

# Create tempfile for managing spun down disks
TMP_OUTPUT="/tmp/spundown-disks_"$now"_temp"

# Find all removable USB drives, so we can ignore them later,
# see http://superuser.com/a/465953
REMOVABLE_DRIVES=""
for _device in /sys/block/*/device; do
 if echo $(readlink -f "$_device")|egrep -q "usb"; then
 _disk=$(echo "$_device" | cut -f4 -d/)
 REMOVABLE_DRIVES="$REMOVABLE_DRIVES $_disk"
 fi
done

# Append detected removable drives to manually ignored drives
IGNORE_DRIVES="$IGNORE_DRIVES $REMOVABLE_DRIVES"

# Loop through all the array disks and spin down the idle disks. Will find all drives sda -> sdz AND sdaa -> sdaz...
for disk in `find /dev/ -regex '/dev/sd[a-z]+' | cut -d/ -f3`
do

 # Skip removable USB drives and those the user wants to ignore
 if [[ $IGNORE_DRIVES =~ $disk ]]; then
 continue
 fi

 # Skip SSDs
 if [[ $(cat /sys/block/$disk/queue/rotational) -eq 0 ]]; then
 continue
 fi

 # Check if drive exists
 if [ -e /dev/$disk ]; then

 # Check if drive is currently spinning
 if [ "$(hdparm -C /dev/$disk | grep state)" = " drive state is: active/idle" ]; then

 # Check if smartctl is currently not running a self test
 if [ $(smartctl -a /dev/$disk | grep -c "Self-test routine in progress") = 0 ]; then

 # Check if drive has been non idle since last run
 if [ "$(diff /dev/shm/diskstats_1 /dev/shm/diskstats_2 | grep $disk )" = "" ]; then
 echo "/dev/$disk `df -h | grep /dev/$disk | rev | cut -d ' ' -f 1 | rev`" >> $TMP_OUTPUT
 hdparm -y /dev/$disk
 fi
 else
 echo "/dev/$disk is running Self-test routine"
 fi
 fi
 fi
done
```

What this script does it writes the output of /proc/diskstats to the ramdisk via cronjob. When it runs the next time, it will use the diff command to identify disks that haven’t been read from or written to in that time period, and then will spindown those disks.

Some users have reported that using hdparm -C wakes up their disks. If you are in that boat, replace this line…

```bash
# Check if drive is currently spinning
if [ "$(hdparm -C /dev/$disk | grep state)" = " drive state is:  active/idle" ]; then
```

with this…

```bash
# Check if drive is currently spinning
if [ "$(smartctl -i -n standby /dev/$disk | grep "ACTIVE or IDLE")" ]; then
```

You will want to create a cronjob to run this periodically, here is an example.

```bash
 crontab -e
```

and paste…

```bash
 */30 * * * * /root/scripts/disk_spindown.sh
```

This will check your disks every 30 minutes and will spin them down if they are idle.

**Note**

You will want to verify that smartmontools is setup to not wakeup idle disks, or every 30 minutes, it will be spinning you disks back up to check them.