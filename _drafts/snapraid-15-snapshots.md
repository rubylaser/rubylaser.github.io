---
# TODO: confirm against your usual front matter
title: "SnapRAID 15.0: Filesystem Snapshots and Migrating from ext4"
date: 2026-10-16 00:00:00 -0400
categories: [Storage, SnapRAID]
tags: [snapraid, mergerfs, btrfs, zfs, ubuntu]
image:
  path: /wp-content/uploads/images/snapraid15_snapshots.webp  # TODO: create image
  alt: SnapRAID 15.0 snapshots
---

SnapRAID 15.0 is out, and for once the headline feature isn't a new command or a nicer report. It changes one of the oldest tradeoffs in SnapRAID: what happens to your recovery when files change between syncs.

If you've been following along, you've probably read my [SnapRAID + mergerfs on Ubuntu 24.04](/posts/snapraid-mergerfs-on-ubuntu-24.04/) post, my [first look at SnapRAID 14.X and the daemon](/posts/snapraid-14.0-and-new-daemon/), and the [modern SnapRAID maintenance script](/posts/modern-snapraid-maintenance-script/). This post builds on all three.

Before we get into it, one honest disclaimer. I haven't migrated my own array yet. All of my data disks are ext4, and the clean way to migrate is one disk at a time through a spare. Disks are expensive right now, so I'm going to do the first conversion when I buy my next drive. This post is the plan I'll be following. When I run it on my own hardware, I'll update this post with real output and anything that surprised me.

## What's new in 15.0

The highlights:

- **Filesystem snapshots.** A new `snapshot` option lets SnapRAID manage read-only snapshots of your data disks on its own. This works on Btrfs, Bcachefs, and ZFS on Linux, and NTFS on Windows. More on this below, because it's the whole reason for this post.
- **AVX-512BW parity.** Parity generation and recovery can now use 512-bit registers on CPUs like Intel Sapphire Rapids and AMD Zen 4/5. If you're on something older (my EPYC 7502 is Zen 2), you stay on the AVX2 code path.
- **ARM64 NEON parity.** A nice bump for people running SnapRAID on ARM boards and ARM servers.
- **Better recovery after an interrupted sync.** SnapRAID no longer skips recomputing parity when the input data matches the expected hash. The tradeoff is that the first sync *after* an interruption is slower. If you use Healthchecks or similar with a tight grace period, give it some slack.
- **SSDs and NVMe drives are skipped for spin-up and spin-down.**
- **No more 512 TiB disk size limit** with the default block size.
- **Custom smartctl info options** with an `[info: ...]` tag, for RAID controllers and USB enclosures that need special arguments.
- **SMART attribute names in `smartignore`**, instead of only numeric IDs.
- **No more libblkid dependency** when building.

## What snapshots actually do

SnapRAID has always had one limitation that's easy to forget. If a disk fails and you haven't synced recently, files that were changed or deleted since the last sync can hurt your recovery, *even if those files weren't on the failed disk*. That's because parity is computed across all of your data disks. If one disk's data has moved on from what parity remembers, that block of parity can no longer reconstruct the matching block on the failed disk.

That's why every SnapRAID guide (including mine) tells you it's best for data that rarely changes.

Snapshots fix this. With `snapshot` enabled, SnapRAID works from frozen, point-in-time copies of your data disks instead of the live filesystem:

- **sync** creates a new *pending* snapshot and computes parity from it. When the sync finishes successfully, that pending snapshot becomes the new *stable* snapshot.
- **scrub** reads from the *stable* snapshot, which matches what parity was computed from.
- **check** and **fix** use the last snapshot for the disks they're reading from.

So, if you delete a file on disk3 on Tuesday and disk5 dies on Wednesday, the old version of that file is still sitting in disk3's stable snapshot. SnapRAID can use it to rebuild disk5. Changes you make between syncs no longer weaken your protection.

It also means a long scrub or sync isn't racing against Sonarr renaming files out from under it.

### What snapshots don't do

This is the question I've already been asked the most, so let me be clear:

- **You still need to run sync on a schedule.** Snapshots protect what was there at the last sync. A new file is still unprotected until the next sync, and if it was on the disk that failed, it's gone. Keep using the [helper script](/posts/modern-snapraid-maintenance-script/) or the daemon.
- **There's still no online rebuild.** This is still SnapRAID, not RAID.
- **ext4 and XFS disks don't benefit.** The option only applies to data disks on Btrfs, Bcachefs, or ZFS. Every other disk keeps reading the live filesystem. Parity disks always use the live filesystem too, so leave your parity disks on ext4 or XFS.
- **Snapshots aren't backups.** They live on the same disk as the data.

## Choosing a filesystem

If you're on ext4 or XFS today, you'll need to move your data disks to one of the supported filesystems. Here's how I think about the options:

- **Btrfs** is what I'm going with. One single-device Btrfs filesystem per disk keeps everything that makes SnapRAID + mergerfs nice. Each disk is still independent, you can still pull any disk and mount it on another machine, and it's in the mainline kernel with tooling that ships with Ubuntu.
- **ZFS** works too, and I cover it in a short sidebar below. It's a heavier fit for this use case.
- **Bcachefs** is supported, but it's too new for me to trust with my array.

Since SnapRAID is already doing the parity, use Btrfs in single-device mode. Don't build a multi-disk Btrfs RAID under this. You'd be stacking two redundancy systems that don't know about each other.

## The disk layout that matters

This is the part I'd get wrong if I hadn't read the GitHub issues first, and it matters a lot more with mergerfs than without it.

SnapRAID stores its snapshots in a hidden `.snapraid` directory at the **root of the subvolume** that contains your data. If your `data` line points directly at the disk root:

```
data d1 /mnt/disk1/
```

then `.snapraid` ends up *inside* your data directory, at `/mnt/disk1/.snapraid/`. SnapRAID knows to ignore it. Nothing else on your system does.

With mergerfs, that's a problem. Your pool would show a `.snapraid` folder on every snapshot-enabled disk, and anything that walks the pool can wander into a full frozen copy of your files. That includes Plex scans, Jellyfin scans, arr library refreshes, and backups like rsync or Kopia. One user [filled a backup drive](https://github.com/amadvance/snapraid/issues/68) this way.

The fix, and the layout Andrea recommends, is to point `data` at a regular **subdirectory** inside the filesystem:

```
/mnt/disk1/                  <- Btrfs filesystem root (what gets mounted)
├── .snapraid/               <- SnapRAID snapshots live here
├── snapraid.content         <- content file (optional, if you keep one on this disk)
└── data/                    <- your files, and the ONLY thing SnapRAID and mergerfs see
    ├── movies/
    ├── tv/
    └── music/
```

Then:

- `snapraid.conf` uses `data d1 /mnt/disk1/data/`
- your mergerfs branch uses `/mnt/disk1/data`
- your backups point at the pool or at `/mnt/diskN/data`, never at `/mnt/diskN`

Your files keep the same paths *relative to the data directory*, which is what SnapRAID cares about. Inside the pool, `/storage/movies/...` doesn't change at all.

One note on content files. If you keep a content file at the root of a data disk like I do, it sits inside the snapshotted filesystem but outside `data/`. SnapRAID won't scan it. The stable snapshot will hold onto one older copy of it, which costs about one content file's worth of space per disk. That's not worth a more complicated subvolume layout for me.

## Building SnapRAID 15.0 from source

I've always built SnapRAID from source, and 15.0 is a little easier because it no longer needs libblkid.

```
sudo apt update
sudo apt install build-essential btrfs-progs

cd /tmp
wget https://github.com/amadvance/snapraid/releases/download/v15.1/snapraid-15.1.tar.gz
tar xzf snapraid-15.1.tar.gz
cd snapraid-15.1

./configure
make -j"$(nproc)"
make check
sudo make install
```

<!-- TODO: confirm the release asset filename on the v15.0 release page before publishing. -->

Confirm the version:

```
root@fileserver:~/snapraid-15.1# snapraid --version
SnapRAID CLI v15.1 by Andrea Mazzoleni, https://www.snapraid.it
```

`make check` takes a more than few minutes. Don't skip it. It runs SnapRAID's own test suite against your build, and it's the cheapest insurance you'll ever get.

If you're coming from 14.X, your existing `snapraid.conf`, content files, and parity all work as-is. Upgrading the binary doesn't turn on snapshots. That only happens when you add the option, and it only matters on disks with a supported filesystem.

## Setting up a new Btrfs data disk

This is the path for a brand new disk you're adding to the array. If you're converting an existing ext4 disk, read this section anyway, then go to the migration section.

### 1. Find the right disk

Destructive warning: the next step formats a disk. Make absolutely sure you have the right one.

A disk has several `/dev/disk/by-id/` names (the WWN style and the vendor/model/serial style). Don't compare those strings by eye. Resolve the name you're about to use to a real device and check it against what's mounted:

```
ls -l /dev/disk/by-id/ | grep -v part
readlink -f /dev/disk/by-id/ata-YOUR_NEW_DISK_SERIAL
lsblk -o NAME,SIZE,MODEL,SERIAL,FSTYPE,MOUNTPOINTS
```

The new disk should show no filesystem and no mountpoint. If it shows anything else, stop.

### 2. Create the filesystem

```
sudo mkfs.btrfs -L disk14 -d single -m dup /dev/disk/by-id/ata-YOUR_NEW_DISK_SERIAL
```

`-d single` stores one copy of the data, which is what you want with SnapRAID handling parity. `-m dup` keeps two copies of the filesystem metadata on the disk, so a bad sector in the metadata doesn't take the filesystem with it. Recent btrfs-progs defaults to this already, but I like being explicit.

### 3. Mount it

Grab the UUID:

```
sudo blkid /dev/disk/by-id/ata-YOUR_NEW_DISK_SERIAL
```

Add it to `/etc/fstab`:

```
UUID=REPLACE-ME  /mnt/disk14  btrfs  defaults,noatime  0  0
```

Then mount it and create the data directory:

```
sudo mkdir -p /mnt/disk14
sudo systemctl daemon-reload
sudo mount /mnt/disk14
sudo mkdir /mnt/disk14/data
```

I leave compression off. Media files don't compress, and Btrfs would just spend CPU finding that out.

### 4. Add it to SnapRAID

In `/etc/snapraid.conf`, add the data disk pointing at the subdirectory, and turn on snapshots:

```
# Use filesystem snapshots for sync, scrub, check, and fix.
# Only affects data disks on Btrfs, Bcachefs, or ZFS.
snapshot

data d14 /mnt/disk14/data/
```

`snapshot` is a bare option with no value. You only need it once, and it's safe to enable while your other disks are still ext4. Those just keep using the live filesystem.

### 5. Add it to mergerfs

Point the branch at the `data` directory, not the mount root. If your mergerfs line uses a glob like `/mnt/disk*`, that glob now picks up the wrong path for this disk. I'll cover what to do about that in the next section.

### 6. Sync

```
sudo snapraid diff
sudo snapraid sync
```

SnapRAID needs root to create and delete snapshots. If you run sync through the helper script, the daemon, or root's crontab, you're already covered.

## Mixing ext4 and Btrfs disks in one pool

You'll be in this state for a while if you migrate one disk at a time. I'd recommend making every disk look the same from day one, ext4 included.

On an ext4 disk, you can move everything into a `data/` subdirectory and point SnapRAID at it. Because you're moving files within the same filesystem, the `mv` is instant and the inodes don't change. SnapRAID lets you change a disk's path as long as the disk's name stays the same. Relative to the new path, nothing has moved.

Stop anything that writes to the pool first, then for each ext4 disk:

```
sudo mkdir /mnt/disk1/data
cd /mnt/disk1
# Move everything except the content file, lost+found, and the new data dir itself
sudo find . -mindepth 1 -maxdepth 1 \
  ! -name data ! -name 'snapraid.content*' ! -name lost+found \
  -exec mv -t data/ {} +
```

Update the disk's line in `snapraid.conf`:

```
data d1 /mnt/disk1/data/
```

Then run `sudo snapraid diff`. You want to see zero added and zero removed. If you see a big wall of removals, stop and look at what went wrong before you sync.

[I need to fill this in when I finish migrating]

Once every disk has a `data/` directory, the mergerfs glob works for everything again:

```
/mnt/disk*/data  /storage  fuse.mergerfs  <your existing options>  0  0
```

If you'd rather not touch your ext4 disks, list your mergerfs branches explicitly instead of using a glob. Either way works. 

## Migrating an existing ext4 disk to Btrfs

This is the path I'll take when that new disk shows up. It's a rotation: format the spare as Btrfs, copy one ext4 disk onto it, swap it in, verify, and the old disk becomes the next spare.

The nice thing about doing it this way is that your array never loses parity protection. The original disk is never touched, so you always have a clean way back.

You could skip the spare by reformatting a data disk in place and rebuilding it with `snapraid fix`. Please don't. That intentionally takes a disk out of the array, so you're running with one less parity level for however long the rebuild takes. If you don't have a spare, use the [in-place `btrfs-convert` method](#alternative-converting-in-place-with-btrfs-convert) instead.

### Before you start

- You're on SnapRAID 15.0 and the array is freshly synced (`snapraid status` shows nothing pending).
- The spare is at least as large as the used space on the disk you're converting. Ideally, it's the same size or bigger.
- You have time. A 10 TB disk takes roughly 15 hours to copy at typical sequential speeds, plus a full read for verification.

For this example, I'm converting `d5` at `/mnt/disk5`, and the spare will be temporarily mounted at `/mnt/new`.

### 1. Format and mount the spare

Same destructive warning as before. Resolve the device and confirm it isn't mounted or listed in `snapraid.conf`.

```
readlink -f /dev/disk/by-id/ata-SPARE_SERIAL
lsblk -o NAME,SIZE,MODEL,SERIAL,FSTYPE,MOUNTPOINTS

sudo mkfs.btrfs -L disk5 -d single -m dup /dev/disk/by-id/ata-SPARE_SERIAL
sudo mkdir -p /mnt/new
sudo mount /dev/disk/by-id/ata-SPARE_SERIAL /mnt/new
sudo mkdir /mnt/new/data
```

### 2. Stop writes to the disk

Stop anything that writes to the pool: downloaders, the arr stack, and anything else. If you use my helper script, the `SERVICES` list in your profile is a good starting point. A file that changes mid-copy is the one thing this process can't catch for you.

### 3. Copy the data

If you already moved your ext4 data into `/mnt/disk5/data/`:

```
sudo rsync -aHAX --info=progress2 /mnt/disk5/data/ /mnt/new/data/
```

If your data is still at the disk root, exclude the content file and `lost+found`:

```
sudo rsync -aHAX --info=progress2 \
  --exclude='/snapraid.content*' \
  --exclude='/lost+found' \
  /mnt/disk5/ /mnt/new/data/
```

If this disk holds a content file, copy it to the new filesystem's root, not into `data/`:

```
sudo cp -a /mnt/disk5/snapraid.content /mnt/new/
```

Run the same rsync a second time. It should finish almost instantly and transfer nothing. If it copies files, something was still writing to the disk.

`-a` preserves timestamps, which matters here. SnapRAID matches files by name, size, and timestamp, including the sub-second part.

### 4. Swap the disks

Unmount both:

```
sudo umount /mnt/new
sudo umount /mnt/disk5
```

Label or physically mark the old disk so you don't grab it by accident. Then edit `/etc/fstab` and replace the old disk5 line with the new Btrfs UUID:

```
UUID=NEW-BTRFS-UUID  /mnt/disk5  btrfs  defaults,noatime  0  0
```

Update `snapraid.conf` if needed:

```
snapshot

data d5 /mnt/disk5/data/
```

Point the disk5 mergerfs branch at `/mnt/disk5/data` (or rely on the `/mnt/disk*/data` glob), then remount everything:

```
sudo systemctl daemon-reload
sudo mount -a
findmnt /mnt/disk5
```

If you're unsure the pool picked up the change, unmount and remount `/storage`, or reboot.

### 5. Verify the copy before you sync

This is my favorite part. SnapRAID already has a checksum for every block of every file on that disk, computed back when the data was on ext4. You can ask it to read every file on the new disk and compare:

```
sudo snapraid -d d5 -a check
```

`-d d5` limits the check to that disk. `-a` checks file data against the stored hashes without touching parity, so it's faster. This reads the whole disk and takes a while. When it finishes cleanly, you know the copy is bit-for-bit what parity was built from.

[I need to add to his when I actually run these]

Then look at the diff:

```
sudo snapraid diff
```

Every file on the new disk has a new inode, so expect them to show up as **restored** (same name, size, and timestamp, different inode). You should see zero added and zero removed. If you see a lot of **updated** files, timestamps didn't survive the copy. Stop and figure out why before syncing.

[I need to put output here...]

SnapRAID will also notice that d5's UUID changed. That's expected. With single parity, one UUID change is allowed without any force flags.

### 6. Sync

Run the first sync by hand rather than letting your scheduled job do it:

```
sudo snapraid sync
```

[YOUR OUTPUT]

### 7. Confirm the snapshot exists

After a successful sync, you should have a stable snapshot on the new disk:

```
sudo btrfs subvolume list /mnt/disk5
ls -la /mnt/disk5/.snapraid/
```

[What's this look like?]

And confirm it's *not* visible in the pool:

```
ls -la /storage | grep snapraid
```

That should print nothing (or only your content files, if you've chosen to expose them).

### 8. Keep the old disk for a while

Don't wipe the old ext4 disk right away. Give it a week of normal syncs and scrubs. If anything is off, rolling back is just your old fstab line, your old `data` line, and a `snapraid diff`. Once you're happy, that disk becomes the spare for the next conversion.

## Alternative: converting in place with btrfs-convert

The spare rotation is my preferred method, but it needs a spare disk, and right now those aren't cheap. If you don't have one, `btrfs-convert` (part of btrfs-progs) can convert an ext4 filesystem to Btrfs in place.

Normally, I'd be nervous about an in-place filesystem conversion anywhere near my media. SnapRAID changes the math, because you get three layers of safety that a typical conversion doesn't have:

1. **A rollback image.** `btrfs-convert` keeps the original ext4 filesystem as an image file inside a subvolume named `ext2_saved`. Until you delete it, `btrfs-convert -r` can [roll the disk back to ext4](https://btrfs.readthedocs.io/en/latest/Convert.html).
2. **Proof the conversion worked.** SnapRAID already has a hash for every block of every file. `snapraid check` can read every file on the converted disk and prove it's bit-for-bit what parity was built from.
3. **Parity as the last resort.** If the conversion goes badly *and* the rollback fails, you can still rebuild the disk from parity.

### Before you start

- **Sync first.** The array should be freshly synced, with `snapraid status` showing nothing pending.
- **Check your free space.** The conversion builds Btrfs metadata in the ext4 filesystem's free space. The btrfs docs note that metadata can take several gigabytes even on a few-hundred-gigabyte filesystem, so on a 10–18 TB disk, plan on tens of GB. If you have a choice, pilot on the disk with the most free space.

  ```
  df -h /mnt/disk5
  ```

- **Move your data into `data/` first.** Do the [mixed ext4 and Btrfs step](#mixing-ext4-and-btrfs-disks-in-one-pool) on this disk *before* converting. `ext2_saved` gets created at the filesystem root, and so does SnapRAID's `.snapraid` snapshot directory. With your files already in `data/`, neither of them ever shows up in your pool or in SnapRAID's scan.
- **Know your parity level.** The worst case is rebuilding this disk from parity. With dual parity, that's a comfortable fallback. With single parity, a second disk failure during that rebuild means real data loss.

### 1. Unmount and check the filesystem

Destructive warning: this rewrites the filesystem metadata on an array member. Resolve the device name and make sure it's the disk you think it is:

```
readlink -f /dev/disk/by-id/ata-DISK5_SERIAL
lsblk -o NAME,SIZE,MODEL,SERIAL,FSTYPE,MOUNTPOINTS
```

Stop anything that writes to the pool. The disk is also a mergerfs branch, so unmount the pool first, or unmounting the disk will fail with "target is busy":

```
sudo umount /storage
sudo umount /mnt/disk5
sudo fsck.ext4 -f /dev/disk/by-id/ata-DISK5_SERIAL
```

Don't convert a filesystem with errors. If `fsck` finds and fixes anything, run it again until it comes back clean.

### 2. Convert

```
sudo btrfs-convert /dev/disk/by-id/ata-DISK5_SERIAL
```

[The output here...]

### 3. Update fstab and mount

The filesystem type changed, and the UUID most likely did too:

```
sudo blkid /dev/disk/by-id/ata-DISK5_SERIAL
```

Update the disk5 line in `/etc/fstab`:

```
UUID=NEW-BTRFS-UUID  /mnt/disk5  btrfs  defaults,noatime  0  0
```

Mount it and look at the root:

```
sudo systemctl daemon-reload
sudo mount /mnt/disk5
ls -la /mnt/disk5
```

You should see `data/`, `ext2_saved/`, and your content file if you keep one there.

[OUTPUT]

Then remount the pool:

```
sudo mount /storage
```

### 4. Verify before you sync

Same as the spare method: read every file and compare it to the hashes SnapRAID already has.

```
sudo snapraid -d d5 -a check
sudo snapraid diff
```

You want zero added, zero removed, and zero updated. SnapRAID will also notice that d5's UUID changed, which is expected.

<!-- TODO: record whether files show as "equal" or "restored" after conversion (i.e., whether btrfs-convert preserved inode numbers). -->

[OUTPUT]

### 5. Enable snapshots and sync

Add `snapshot` to `snapraid.conf` if it isn't there yet, then run the first sync by hand:

```
sudo snapraid sync
sudo btrfs subvolume list /mnt/disk5
```

[OUTPUT]

### If something goes wrong

If `check` reports errors or the disk won't mount, roll back to ext4:

```
sudo umount /storage
sudo umount /mnt/disk5
sudo btrfs-convert -r /dev/disk/by-id/ata-DISK5_SERIAL
```

Put the old ext4 line back in fstab, remount, and run `snapraid diff` to confirm you're back where you started.

The rollback only works as long as `ext2_saved` still exists and you haven't run `btrfs balance` on the disk. Both of those make rolling back impossible, which is why cleanup waits until the end.

If the rollback also fails, you're down to rebuilding the disk from parity. Format it fresh, mount it at the same path, and run the normal [SnapRAID recovery steps](https://www.snapraid.it/manual) with `snapraid -d d5 -l fix.log fix`. This is the scenario where your parity level matters.

### 6. Clean up once you trust it

Give the disk a week or two of normal syncs and scrubs. Until you clean up, `ext2_saved` pins every block you delete or overwrite on that disk, on top of SnapRAID's own snapshot. Keep writes to it light in the meantime.

When you're confident, delete the rollback image and compact the metadata:

```
sudo btrfs subvolume delete /mnt/disk5/ext2_saved
sudo btrfs balance start -m /mnt/disk5
```

After this, there's no going back to ext4.

The btrfs docs also suggest a full recursive defrag after a conversion. **I'm skipping that, and I'd recommend you do too.** It rewrites every file on the disk, large media files don't gain much from it, and once SnapRAID's stable snapshot exists, a defrag breaks the space sharing between your live files and the snapshot. You could end up with close to double the disk usage until the next sync.

### Which method should you use?

- **Spare rotation** gives you a clean, native Btrfs filesystem, and the original disk stays untouched as your rollback. Use it when you're buying a disk anyway.
- **btrfs-convert** costs nothing and takes hours instead of a full-disk copy. You get an inherited layout instead of a clean one (the metadata balance takes care of most of that), and you need enough free space for the conversion.

## Snapshots and free space

There's one new thing to keep an eye on. To preserve files that changed or were deleted since the last sync, the stable snapshot has to hold onto their old blocks. Deleting a file on a Btrfs data disk won't give you that space back until the next successful sync replaces the stable snapshot.

For a media array, this is usually a non-event. Where it bites:

- **Disks that are almost full.** Delete 200 GB to make room, copy 200 GB in, and you can run out of space before the next sync.
- **Blocked syncs.** If my helper script blocks a sync because it crossed a deletion threshold, the old stable snapshot stays in place, and so does all the space it's holding. That's the right behavior. It protects your recovery while you figure out why so much was deleted. But remember that the space won't come back until you sync.

To see how full a Btrfs disk really is:

```
sudo btrfs filesystem usage /mnt/disk5
```

If you use mergerfs's `minfreespace` option, now is a good time to make sure it's set to something sensible.

## Do you still need the helper script or the daemon?

Yes. Snapshots change *what* SnapRAID reads, not *when* it runs. You still need something to run diff, sync, and scrub on a schedule, check thresholds, and tell you when something is wrong. That's what the [helper script](/posts/modern-snapraid-maintenance-script/) and the [daemon](/posts/snapraid-14.0-and-new-daemon/) do.

A few things to check after you enable `snapshot`:

- **Run as root.** Creating and deleting snapshots needs root.
- **`REQUIRED_MOUNTS` stays on the mount roots.** You still want to validate `/mnt/disk5`, not `/mnt/disk5/data`. The mount is what can fail.
- **Exclude `.snapraid/` from anything that backs up whole disks.** If your backups point at the pool and your branches point at `data/`, you're already fine. If anything backs up `/mnt/diskN` directly, add an exclude.
- **The first sync after an interrupted one will be slower** on 15.0. Make sure your monitoring grace period can absorb that.

## Sidebar: ZFS instead of Btrfs

ZFS is supported too. The equivalent of the layout above is one pool per disk:

```
sudo zpool create -o ashift=12 -O atime=off -O compression=off \
  -m /mnt/disk14 disk14 /dev/disk/by-id/ata-YOUR_NEW_DISK_SERIAL
sudo mkdir /mnt/disk14/data
```

```
data d14 /mnt/disk14/data/
```

On ZFS, SnapRAID uses ZFS's native snapshots, exposed under `.zfs/snapshot/` instead of a `.snapraid/` directory. With the default `snapdir=hidden`, that directory doesn't show up in listings, so backup tools won't trip over it.

Why I'm not using ZFS for this:

- **Mounting works differently.** ZFS mounts pools through its own services, not fstab. If you rely on `x-systemd.requires-mounts-for` to keep mergerfs from mounting before your disks are ready, you'll need to rework that ordering for ZFS.
- **It's more moving parts than than a one disk pool probably needs.** ZFS shines when it manages redundancy itself. Here, SnapRAID is doing that job.

If you already run ZFS everywhere and know it well, it's a perfectly good choice.

## Final thoughts

This is the most significant SnapRAID release in years. Snapshots remove the biggest asterisk on SnapRAID's recovery story, and they do it without changing how you use the array day to day. You still get independent disks, mixed sizes, single-disk reads, and no lock-in.

It does mean reformatting, though, and that's not something I'm going to rush. My plan is to convert one disk when the next drive arrives, live with it for a month, and only then work through the rest of the array a disk at a time. I'll update this post with real numbers and anything that surprised me along the way.

As always, if you find something wrong or run into a problem, let me know. I'd much rather fix this post than have someone learn it the hard way.