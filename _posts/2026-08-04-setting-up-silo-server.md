---
layout: post
title: "Setting Up Silo: A Faster Media Server for People With Too Many Files"
date: 2026-08-04 09:00:00 -0500
categories: selfhosted homelab
tags: [silo, jellyfin, plex, docker, traefik, garage, s3, nvidia, media-server]
excerpt: "I found Silo in a Reddit thread and had it running the same night. Here's the full Docker Compose setup, including the four things that broke along the way."
image: /wp-content/uploads/images/silo_landing.jpg
---

I found Silo in a Reddit comment. Not even the post itself, a comment, three replies deep, in a thread about why Jellyfin gets sluggish once your library crosses some invisible threshold. Someone said "it was the superhero we deserved" and linked a GitHub repo with nine stars and no tagged releases.

## The itch I was scratching

I've run Plex since roughly forever. I've moved through MythTV, XBMC, Windows Media Center, and finally to Plex.  It's the thing my family knows how to use, the apps are good on every screen I own, and I've made peace with the parts of it I don't love. Alongside it I run Jellyfin, mostly out of principle, partly because I like knowing there's an exit.

The problem is that the Jellyfin web ui and apps are pretty clunky. My library isn't outrageous by datahoarder standards, but it's big enough that browsing feels like waiting. Load a library, wait. Scroll, wait for posters to populate. Search, wait. None of it is broken exactly, it's just *slow* compared to Plex in a way that makes me not want to use it. And the more I read, the more it seemed like that's structural. It's not a setting I forgot to flip. Although, the upcoming v12 is supposed to address speed issues (doesn't work on the clunky UI).

So when someone in a Reddit thread described it that way, I had to check it out.  The website feels like an [AI hype page](https://siloserver.org/), but it was definitely intriguing... a media server with a Go backend built on top of a Postgres database, built from the start to be fast with large catalogs, with a Jellyfin-compatible API bolted on so existing clients keep working. I was interested 🤓 

## What Silo actually is

Silo is a self-hosted media server: Go backend, React frontend, Postgres for durable state, Redis for coordination and caching. It does direct play, remuxing, and hardware-accelerated transcoding. AND, It's AGPL.

The piece that makes it immediately usable is the compatibility layer. Silo speaks Jellyfin's API on a separate port, so Wholping and the native Jellyfin app, along withthe rest of the Jellyfin client ecosystem will talk to it. There's also an Audiobookshelf-compatible endpoint on a third port, if you're into that sort of thing (I use Bookorbit, so I don't need this part).

It's early. The official apps are in TestFlight and various states of alpha. There are no tagged releases as I write this. The setup wizard has rough edges. But the web UI is genuinely fast, it looks good in a way self-hosted software usually doesn't, and the docs are better than a nine-star project has any right to have.

Fair warning before you follow along: this is early software and I'm treating it as a second server, not a Plex replacement. My media is mounted read-only. Nothing about this setup can touch the files.

## My setup

For context, since paths matter later:

- Media on `/storage`, subdirectories for `videos`, `tv_shows`, `audiobooks`, `music`, plus `anime`, `ebooks`, and a pile of stuff that isn't media at all
- Docker containers under `/docker/containers/<name>`
- Traefik out front, everything on a shared `proxy` network
- Jellyfin already running and holding port 8096
- An NVIDIA card for transcoding

That last one and the Jellyfin port conflict both bite immediately, so let's get into it.

## Starting from the official compose file

The quickstart gives you a one-liner to pull down `docker-compose.yml` and `.env.example`. That's the right starting point, but I ended up modifying the compose file enough that I'll show you mine.

The upstream design is sensible: it bundles Postgres and Redis so a fresh install is one command, mounts your media read-only at `/mnt/media`, and exposes three ports. `MEDIA_ROOT` is the one variable most people need to change.

Here's my `.env`:

```bash
# Layer the NVIDIA override in without needing -f flags
COMPOSE_FILE=docker-compose.yml:docker-compose.nvidia.yml
NVIDIA_GPU_COUNT=1

MEDIA_ROOT=/storage
MEDIA_CONTAINER_ROOT=/mnt/media

MEDIA_BOOKS_ROOT=/storage/ebooks
MEDIA_BOOKS_CONTAINER_ROOT=/mnt/books

SILO_DATA_ROOT=/docker/containers/silo/data
SILO_IMAGE=ghcr.io/silo-server/silo-server:latest
GARAGE_IMAGE=dxflrs/garage:v2.3.0

PORT=8090
JF_PORT=8097
ABS_PORT=13378

POSTGRES_USER=silo
POSTGRES_PASSWORD=something-you-actually-generated
POSTGRES_DB=silo
POSTGRES_SHM_SIZE=8gb
POSTGRES_TUNE=auto

SECRET_KEY=<openssl rand -base64 48>
SILO_PUBLIC_URL=https://silo.example.com
```

One mount covers everything because all four libraries live under `/storage`. Inside the container `/storage/videos` becomes `/mnt/media/videos`, and so on. It's read-only and Silo only scans paths you explicitly point it at, so I don't have to worry about beta software wiping out my media.

`SECRET_KEY` is required, the server won't start without it, and it encrypts every stored credential. Back it up somewhere that isn't your database dump. If you lose it you lose every encrypted secret with it.

## NVIDIA

The NVIDIA setup is really straightforward. The default repo loads nvidia via a second compose. So I used the `docker-compose.nvidia.yml` override in the repo, and `COMPOSE_FILE` in `.env` layers it in so you never type `-f` flags:

```yaml
services:
  silo:
    deploy:
      resources:
        reservations:
          devices:
            - driver: nvidia
              count: ${NVIDIA_GPU_COUNT:-1}
              capabilities: [gpu]
    environment:
      NVIDIA_VISIBLE_DEVICES: all
      NVIDIA_DRIVER_CAPABILITIES: compute,video,utility
```

Verify the runtime works before you blame Silo for not working:

```bash
docker run --rm --gpus all nvidia/cuda:12.4.0-base-ubuntu22.04 nvidia-smi
```

If that fails, install `nvidia-container-toolkit`, run `nvidia-ctk runtime configure --runtime=docker`, restart Docker.

## Traefik, and a network gotcha

My labels:

```yaml
labels:
  - "traefik.enable=true"
  - "traefik.docker.network=proxy"
  - "traefik.http.routers.silo.rule=Host(`silo.example.com`)"
  - "traefik.http.routers.silo.entrypoints=websecure"
  - "traefik.http.routers.silo.tls.certresolver=le"
  - "traefik.http.routers.silo.middlewares=lanOrVpnOnly@file"
  - "traefik.http.services.silo.loadbalancer.server.port=8080"
```

`traefik.docker.network=proxy` is the line worth mentioning. I put Postgres and Redis on a separate internal network so they're not published to the host at all, which means the Silo container sits on two networks. When a container is multi-homed, Traefik picks whichever IP it finds first, and if it lands on the internal network it can't route there. You get a gateway timeout with no useful error anywhere. Pin the network and it goes away.

Also note `server.port=8080`. That's the container's internal port, which only became correct after the fix in gotcha two. Before that Traefik was proxying to a dead port too, so I got to debug the same bug twice through two different front doors.

I keep 8090 published for direct access. When Traefik or certificates are the thing that's broken, you want a way in that doesn't involve either.

## Object storage, kept at home

Silo wants S3-compatible storage for client-facing assets: artwork, chapter thumbnails, subtitles. Not media, just generated stuff. You can leave it blank for a basic install, but chapter thumbnails are rejected at library creation without it, and I wanted chapter thumbnails.

I'm not sending my poster art to a cloud provider to serve it back to devices on my own LAN. The docs' preferred self-hosted option is Garage, which is a small S3-compatible object store built for exactly this scale. Added it to the same stack:

```yaml
garage:
  image: ${GARAGE_IMAGE:-dxflrs/garage:v2.3.0}
  restart: unless-stopped
  volumes:
    - ./garage/garage.toml:/etc/garage.toml:ro
    - ${SILO_DATA_ROOT}/garage/meta:/var/lib/garage/meta
    - ${SILO_DATA_ROOT}/garage/data:/var/lib/garage/data
  networks: [silo, proxy]
```

> Two things you need to know for this to work!

**Garage rejects writes until you assign a cluster layout.** A fresh node has none. This is not an error state, it's just how it works, but if you skip it Silo throws S3 errors that look like a credentials problem:

```bash
docker compose exec garage /garage status          # get node ID
docker compose exec garage /garage layout assign <ID> -z dc1 -c 100G
docker compose exec garage /garage layout show     # prints the apply command
docker compose exec garage /garage layout apply --version 1

docker compose exec garage /garage bucket create silo-assets
docker compose exec garage /garage key create silo-key
docker compose exec garage /garage bucket allow --read --write --owner silo-assets --key silo-key
```

Copy the secret from `key create` immediately. It's not shown again...ever!

**The S3 endpoint can't be the internal Docker hostname.** Silo hands clients presigned URLs, and the signature covers the hostname. Whatever you set as the endpoint is what browsers will try to fetch. Set it to `http://garage:3900` and every poster 404s, because that name only resolves inside the Docker network. So Garage gets its own Traefik route and the endpoint becomes `https://s3.example.com`. The bucket stays private, presigned URLs handle auth, and nothing is actually exposed to the internet.

One more from Garage's own best-practices page, which I nearly missed: LMDB metadata has a habit of corrupting after unclean shutdowns. On a home server that means a power blip. Set `metadata_auto_snapshot_interval = "6h"` in `garage.toml`, or switch `db_engine` to `sqlite` if you'd rather trade a little speed for durability. At poster-art volume you won't notice the difference.

## The wizard

Open port 8090, make an admin account, make a profile. When you get to libraries, use container paths, not host paths:

| Library | On disk | In Silo |
| --- | --- | --- |
| Movies | `/storage/videos` | `/mnt/media/videos` |
| TV | `/storage/tv_shows` | `/mnt/media/tv_shows` |
| Audiobooks | `/storage/audiobooks` | `/mnt/media/audiobooks` |
| Music | `/storage/music` | `/mnt/media/music` |
| Ebooks | `/storage/ebooks` | `/mnt/books` |

You'll also see a warning in the logs on first boot about Postgres needing a restart to finish applying auto-tuned settings. Silo applies pgtune-style settings via `ALTER SYSTEM`, and a few of them (`shared_buffers`, `max_connections`, `huge_pages`) only take effect on restart. `docker compose restart postgres` and it's done.

## So is it fast?

Yes! It's really quick, given how much less mature it is than the thing it's replacing. Browsing is immediate. Search returns while I'm still typing. The scroll-and-wait-for-posters thing that pushed me into this whole project doesn't happen. Whether that holds as I throw more at it, I don't know yet, but the architecture is at least pointed at the right problem.

Direct play works. Transcoding hands off to NVENC properly. Jellyfin clients connect to port 8097 and behave. The only thing that blows up every time for me is trying to play a video with burned in bitmap subtitles. [That doesn't work at all!](https://github.com/Silo-Server/silo-server/issues/541)

## What I'm hoping it turns into

The apps, mostly. That's the whole thing. Jellyfin's server is cool and I love open source. But, what keeps me on Plex for anything my family touches is the apps. Silo's compatibility layer is a clever bridge, and third-party Jellyfin clients are better than they get credit for, but a first-party app that's actually as good as the server is looking like it will be would let me move over for real.

Beyond that, I want to see it stay boring in the right places. Postgres and Redis as dependencies is a real commitment for a self-hosted project, and it's the reason it's fast, but it also means backups and upgrades need to keep being straightforward. So far they are.

I'd also like a tagged release. Running `:latest` against a project with no versioning is a choice I'm making with full awareness that it's a bad one. And, I'd love to be able to move this over into my [Komodo/Forgejo setup](https://zackreed.me/posts/automated-docker-updates-renovate-komodo-forgejo/).

For now: Plex still serves the family, Jellyfin is still there, and Silo is the one I'm excited to checkout. That's a stronger endorsement than I expected to be writing about something I found in a Reddit comment a couple of days ago.

Good luck if you try it out!