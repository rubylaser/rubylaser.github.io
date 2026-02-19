---
title: "SnapRAID and mergerfs FAQ: Common Questions from New Linux Users"
date: 2026-02-19
categories: [self-hosting, linux, storage]
tags: [snapraid, mergerfs, ubuntu, linux, faq, troubleshooting]
description: "Answers to the most common questions I receive about setting up SnapRAID and mergerfs, especially for people making the jump from Windows to Linux."
image: /wp-content/uploads/images/faq_cover.webp
---

Since publishing my [SnapRAID and mergerfs guide](https://zackreed.me/posts/snapraid-mergerfs-on-ubuntu-24.04/), I've had some great conversations with readers who are new to Linux and working through their first media server setup. These are the questions that come up most often, and I wanted to compile them into one place to help others who might be wondering the same things.

## Table of Contents
- [Should my parity drive be part of the mergerfs pool?](#should-my-parity-drive-be-part-of-the-mergerfs-pool)
- [What's the best mergerfs create policy for keeping content organized?](#whats-the-best-mergerfs-create-policy-for-keeping-content-organized)
- [How do mount points work in Linux?](#how-do-mount-points-work-in-linux)
- [How do I fix permissions issues?](#how-do-i-fix-permissions-issues)
- [I accidentally created a recursive mergerfs mount - how do I fix it?](#i-accidentally-created-a-recursive-mergerfs-mount---how-do-i-fix-it)
- [How does mergerfs actually work?](#how-does-mergerfs-actually-work)

## Should my parity drive be part of the mergerfs pool?

**Short answer: No, absolutely not.**

This is by far the most common question I get, especially from people with traditional RAID5/RAID6 experience. In those systems, parity is calculated and distributed automatically across all drives in real-time, and you interact with a single unified pool.

SnapRAID works fundamentally differently. Your parity drives are **dedicated parity storage only** - they don't contain any of your actual files. They contain calculated parity information that's generated when you run `snapraid sync`.

**The correct approach:**
- **Data drives** (`/mnt/disk1`, `/mnt/disk2`, etc.) contain your actual files and are merged into your storage pool via mergerfs
- **Parity drives** (`/mnt/parity1`, `/mnt/parity2`) contain only parity data and are **never** mounted as part of your storage pool

If you include your parity drive in your mergerfs pool, files would be written to it as regular data, and you'd lose all parity protection. For a more detailed explanation, check out the [Understanding SnapRAID's Parity Model](https://zackreed.me/posts/snapraid-mergerfs-on-ubuntu-24.04/#understanding-snapraids-parity-model) section in my main guide.

## What's the best mergerfs create policy for keeping content organized?

If you want to keep different types of content on specific drives (like movies on one drive and TV shows on another), use **`category.create=epmfs`** (Existing Path, Most Free Space).

Here's how it works: when mergerfs needs to write a new file, it looks at which drives already have the destination folder and writes to the one with the most free space among those.

**Example:**
```
/mnt/disk1/movies/
/mnt/disk2/tvseries/
```

With `epmfs`, new movies will land on `disk1` because that's the only drive with a `movies` folder, and new shows will land on `disk2` for the same reason. Your organization is maintained automatically.

**The key requirement:** On each of your physical drives, make sure your files live inside top-level folders rather than scattered at the root of the drive. This is what gives `epmfs` the path it needs to make the right decision about where new files land.

**Setting it up in fstab:**
```
/mnt/disk1:/mnt/disk2 /mnt/storage fuse.mergerfs cache.files=off,category.create=epmfs,func.getattr=newest,dropcacheonclose=false,minfreespace=10G,defaults,allow_other,fsname=mergerfs 0 0
```

**Future-proofing:** When you add more drives later, just create the matching top-level folder on the new drive (`/mnt/disk3/movies/` for example) and mergerfs will naturally start routing the right content there without any configuration changes.

---

## How do mount points work in Linux?

This is one of those concepts that seems backwards when you're coming from Windows, but it's actually quite elegant once you understand it.

**In Windows:** Drives appear automatically as `C:`, `D:`, `E:`, etc. Windows decides the letters for you.

**In Linux:** **You** decide where drives appear in the filesystem hierarchy. Mount points are just empty directories that serve as "doors" where you attach drives.

**The process:**

1. **Create an empty directory** (the mount point):
   ```bash
   sudo mkdir -p /mnt/disk1
   ```
   Right now it's just an empty folder - nothing special about it.

2. **Mount a drive to it:**
   ```bash
   sudo mount /dev/sda1 /mnt/disk1
   ```
   Now `/mnt/disk1` shows your drive's contents.

3. **Make it permanent** by adding it to `/etc/fstab`:
   ```
   /dev/disk/by-uuid/YOUR-UUID-HERE /mnt/disk1 ext4 defaults 0 2
   ```

**Key concept:** The directory exists whether or not a drive is mounted to it - it's just empty until something is mounted there. You could mount your drive to `/home/myusername/myseconddrive/` or `/banana/` if you wanted. `/mnt/` is just a convention (the "mount" directory) where people typically put external drives.

**Why unmount before changing mount points?**

If you're moving a drive from `/mnt/movies` to `/mnt/disk1`:

1. Create the new mount point: `sudo mkdir -p /mnt/disk1`
2. Disconnect drive from old location: `sudo umount /mnt/movies`
3. Update `/etc/fstab` to point to the new location
4. Remount: `sudo mount -a`

A drive can't be mounted in two places at once (well, technically it can with bind mounts, but that's a different topic), so you need to disconnect it from the old location first.

## How do I fix permissions issues?

The cleanest approach for a home media server is to make sure everything runs as the same user.

**Step 1: Identify your user ID**
```bash
id
```
You should see something like `uid=1000(yourusername) gid=1000(yourusername)`. On a fresh Ubuntu install, your primary user is almost certainly `1000`.

**Step 2: Set ownership of your drives**
```bash
sudo chown -R 1000:1000 /mnt/disk1
sudo chown -R 1000:1000 /mnt/disk2
```

**Step 3: Set proper permissions**
```bash
sudo chmod -R 755 /mnt/disk1
sudo chmod -R 755 /mnt/disk2
```

**Step 4: Configure your applications to run as the same user**

If you're running Jellyfin/Plex and your *arr apps (Sonarr, Radarr, etc.) in Docker, set the user in your `docker-compose.yml`:

```yaml
environment:
  - PUID=1000
  - PGID=1000
```

Most media server Docker images from [linuxserver.io](https://linuxserver.io) support `PUID` and `PGID` environment variables natively.

When everything - your drives, your media server, and your *arr stack - all run as user `1000`, permissions stop being a headache entirely because they're all treated as the same owner.

## I accidentally created a recursive mergerfs mount - how do I fix it?

This happens when you try to mount mergerfs into one of its source directories. For example, mounting `/mnt/movies:/mnt/tvseries` to `/mnt/movies/merge`. This creates an infinite loop where the merged view contains itself, which contains itself, and so on.

**The good news:** mergerfs doesn't persist anything after you unmount it. It's just a virtual filesystem. Once it's unmounted, it's completely gone.

**How to fix it:**

1. **Unmount the mergerfs mount:**
   ```bash
   sudo umount /mnt/storage  # or whatever your mount point was
   ```

2. **Verify it's unmounted:**
   ```bash
   mount | grep mergerfs
   # Should return nothing
   ```

3. **Remove the leftover empty directories:**
   ```bash
   # Check if they're empty first
   ls -la /mnt/movies/merge/
   
   # If empty, remove them cautiously
   sudo rmdir /mnt/movies/merge/movies
   sudo rmdir /mnt/movies/merge/tvseries
   sudo rmdir /mnt/movies/merge
   ```
   Using `rmdir` instead of `rm -rf` is safer - it will only work if directories are truly empty.

4. **Set up your mount points correctly:**
   
   Create a **separate** directory for your merge point that's not on any of your source drives:
   ```bash
   sudo mkdir -p /mnt/storage
   ```
   
   Then in `/etc/fstab`:
   ```
   /mnt/disk1:/mnt/disk2 /mnt/storage fuse.mergerfs [options] 0 0
   ```

**The key rule:** Never merge into one of the source directories themselves. Your merge point should always be a separate, empty directory.

## How does mergerfs actually work?

mergerfs is a **union filesystem** - it presents multiple filesystems as if they were one unified directory tree.

**Think of it like this:**

- The files physically live on your individual drives (`/mnt/disk1`, `/mnt/disk2`, etc.)
- mergerfs provides a "view" layer that shows you everything from all drives combined
- There's no copying or duplication - mergerfs is just showing you a unified perspective

**Example:**

If you write a file to `/mnt/storage/movies/Inception.mkv`, it physically lands on `/mnt/disk1/movies/Inception.mkv` (assuming disk1 has the movies folder and you're using `epmfs`). 

You can access that file through **either** path:
- `/mnt/storage/movies/Inception.mkv` (through mergerfs)
- `/mnt/disk1/movies/Inception.mkv` (directly on the drive)

They're the same file, just accessed through different paths. There's only one copy.

**What happens when you read?**

mergerfs combines the directory listings from all your drives. If you have:
```
/mnt/disk1/movies/MovieA.mkv
/mnt/disk2/movies/MovieB.mkv
```

When you look at `/mnt/storage/movies/`, you'll see both `MovieA.mkv` and `MovieB.mkv` even though they're on different physical drives.

**What happens when you write?**

The `category.create` policy you set determines which drive gets the new file. With `epmfs`, it picks the drive that already has the destination folder and has the most free space.

**Important:** Files don't get duplicated. When you write through the mergerfs mount, the file goes to exactly one of your underlying drives based on the policy you've configured.

---

## Additional Resources

- [SnapRAID and mergerfs on Ubuntu 24.04](https://zackreed.me/posts/snapraid-mergerfs-on-ubuntu-24.04/) - My main setup guide
- [Modern SnapRAID Maintenance Script](https://zackreed.me/posts/modern-snapraid-maintenance-script/) - Automated SnapRAID syncing and scrubbing
- [mergerfs documentation](https://github.com/trapexit/mergerfs) - Official mergerfs docs

---

Have a question that's not covered here? Drop a comment below. I'm always happy to help people get their storage setups running smoothly!
```