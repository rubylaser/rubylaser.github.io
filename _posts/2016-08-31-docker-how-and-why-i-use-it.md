---
title: 'Docker &#8211; How and why I use it'
date: '2016-08-31T14:49:14-04:00'
layout: post
permalink: /docker-how-and-why-i-use-it/
image: /wp-content/uploads/2016/08/docker-part-duex-copy.jpg
categories: [docker]
tags: [popular]
---

## Docker
Docker is a fantastic way to run applications in containers separate from your host OS. But, you may ask why bother doing this or why not use VMs instead?

Docker is not a replacement for virtual machines or all local applications, but it can help you modularize your system and keep your host OS neat and tidy. I primarily use Docker for things like small applications to put everything in a nice tidy folder structure without installing a bunch of dependencies on my host OS. Here are some of the things that I run in containers at home.

Running these things in containers keeps things like the Mono libraries, Ruby dependencies (and gems), Java, etc. From being stored on my host OS. I can also easily port these containers to a new system by stopping the container, rsyncing/ZFS sending it over, and running docker create on the other end. Here’s a snippet of how I setup the folder structure for my containers and what I use to set most of them up.

All of this is running on my Ubuntu 16.04 server. The first thing I will do is setup the folder structure for all of these apps. Holy crap! That is a crazy long command you are issuing there. If you take a step back you will see that I first switch to the root user, and then make the folders for all my apps in /docker/containers and a config directory in each to house their configuration files. Then, I created a shared downloads directory and some directories for specialized containers like observium and Plex. Finally, I change the owner and group to my zack user to prevent any permissions issues between my containers. As a sidenote, the /docker path is on a pair of ZFS mirrors made up of (8) 400GB HGST SAS disks + and Intel S3700 ZIL, that makes taking snapshots of my containers’ configurations and content super easy.

```
sudo -i
mkdir -p /docker/containers/{couchpotato,crashplan,muximux,nzbget,observium,plex,plexpy,portainer,radarr,sonarr,unifi}/config
chown -R zack:zack /docker
mkdir -p /docker/downloads/{completed/Movies,completed/TV}
mkdir -p /docker/containers/observium/{config,logs,rrd}
mkdir -p /docker/containers/plex/{config,transcode}
chmod -R 777 observium
```

For future reference used in the examples below, my user zack has user id of 1000 and group of 1000.

### CAdvisor

cAdvisor is a simple Monitor for Docker containers. It’s an easy way to check utilization without needing to SSH into your host. This host will be available at http://:7070 after it starts.

```
docker run -d                                   \
  --volume=/:/rootfs:ro                         \
  --volume=/var/run:/var/run:rw                 \
  --volume=/sys:/sys:ro                         \
  --volume=/var/lib/docker/:/var/lib/docker:ro  \
  --publish=7070:8080                           \
  --detach=true                                 \
  --name=cadvisor                               \
  google/cadvisor:latest
```

### Couchpotato

Here I’m passing through the localtime from the host machine to the container. I’m also passing through the /docker/containers/couchpotato/config folder to the container mounted at /docker/containers/couchpotato/config. This also passes through a download directory /docker/downloads/completed/Movies that is shared by the NZBget container. Finally, I have my mergerfs pool shared to the container to move completed files to. I’m passing through port 5050 from the host to the container. This allows me to connect to the container from my network by going to the host ip on port 5050.

```
docker run \
--name=couchpotato \
-v /etc/localtime:/etc/localtime:ro \
-v /docker/containers/couchpotato/config:/config \
-v /docker/downloads/completed/Movies:/downloads \
-v /storage/videos:/movies \
-e PGID=1000 -e PUID=1000  \
-p 5050:5050 \
linuxserver/couchpotato
```

### Crashplan

Crashplan is receiving it’s name from the host, and also setting the timezone so that the container has accurate time. I’m again passing through a config directory to the container and my entire mergerfs pool so that I can backup specific directories to Crashplan Central. I’m passing through ports 4242 and 4243 that Crashplan needs to function. This runs Crashplan in headless mode on the server. I connect to this instance from my Macbook Air and have configured it with the server’s ip address, and ui\_info and identity files, so that I can manage it remotely. This uses Java, so I’m glad this isn’t on my OS.

```
docker run \
--name crashplan \
-h $HOSTNAME \
-e TZ=America/Detroit \
--publish 4242:4242 --publish 4243:4243 \
--volume /docker/containers/crashplan/config:/var/crashplan \
--volume /storage:/storage \
jrcs/crashplan:latest
```

### Minecraft

A Minecraft server for my son.

```
docker run \
    --name minecraft-vanilla \
    -p 25565:25565 \
    -d \
    -it \
    -v /docker/containers/minecraft-vanilla/data:/data \
    -e EULA=TRUE \
    -e WHITELIST=username \
    -e OPS=username \
    -e DIFFICULTY=easy \
    -e MAX_PLAYERS=3 \
    -e ALLOW_NETHER=true \
    -e ENABLE_COMMAND_BLOCK=true \
    -e SPAWN_ANIMALS=true \
    -e SPAWN_MONSTERS=true \
    -e SPAWN_NPCS=true \
    -e MODE=creative \
    -e PVP=false \
    itzg/minecraft-server
```

### Muximux

Muximux is an nice aggregator for all of these services. It allows me to have one landing page so that I don’t have to keep 10 different tabs open for each service. I have also added things like my EdgeOS login page, and IPMI devices into this page as well. This runs on port 80.

```
docker run \
--name=muximux \
-p 80:80 \
-p 443:443 \
-v /docker/containers/muximux/config:/config \
linuxserver/muximux
```

### NZBget

NZBget runs as the zack user and group. I’m passing through port 6789 and a couple of directories for files following the same pattern as above.

```
docker run \
--name nzbget \
-p 6789:6789 \
-e PUID=1000 -e PGID=1000 \
-v /docker/containers/nzbget/config:/config \
-v /docker/downloads:/downloads \
-v /storage/videos:/movies \
-v /storage:/storage \
linuxserver/nzbget
```

### Observium

I use Observium to montior SNMP data from a few of my networking devices as well as my firewall. This has port 8668 passed through, along with the timezone from the host, and a few directories that it needs to function.

```
docker run \
--name=observium \
-p 8668:8668 \
-e TZ="America/Detroit" \
-v /docker/containers/observium/config:/config \
-v /docker/containers/observium/logs:/opt/observium/logs \
-v /docker/containers/observium/rrd:/opt/observium/rrd \
zuhkov/observium
```

### OpenVPN

OpenVPN Access Server allows me to easily connect remotely. I port forwarded port 1194 to this host to support this container.

```
docker run \
--name=openvpn-as \
-v /docker/containers/openvpn-as/config:/config \
-e PGID=1000 -e PUID=1000 \
-e TZ=America/Detroit \
-e INTERFACE=enp0s25 \
--net=host \
--privileged \
linuxserver/openvpn-as
```

### Pihole

An adblocking DNS server for my house.

```
docker run -d \
    --name pihole \
    -p 53:53/tcp -p 53:53/udp -p 8082:80 \
    -v /docker/containers/pihole/config/etc/pihole:/etc/pihole/ \
    -v /docker/containers/pihole/config/dnsmasq.d/:/etc/dnsmasq.d/ \
    -e ServerIP=192.168.172.10 \
    -e ServerIPv6=192.168.172.10 \
    -e TZ=America/Detroit \
    --restart=always \
    diginc/pi-hole:alpine
```

### Plex

Plex is a beast when you factor in all of the metadata and artwork that it sucks in. This keeps everything in one nice tidy directory structure and is easily backed up. I’m using the host option so that plex can function correctly, along with running the plexpass version instead of stable. I’m also passing through configuration/transcode directories, my mergerfs pool, as well as the underlying individual disks in the pool. This last part allows me to setup plex folders for each disk and only spins up that one disk to view a file vs. potentially having to spin up a few or the whole pool as plex “searches” for the file to playback.

```
docker create \
-d \
--name plex \
--net=host \
-e TZ="America/Detroit" \
-e PLEX_UID=1000 -e PLEX_GID=1000 \
-v /docker/containers/plex/config:/config \
-v /storage:/storage \
-v /docker/containers/plex/transcode:/transcode \
--device /dev/dri:/dev/dri \
plexinc/pms-docker:plexpass
```

NVIDIA

```

docker create \
--runtime=nvidia \
--name=plex \
--net=host \
-e NVIDIA_VISIBLE_DEVICES=all \
-e NVIDIA_DRIVER_CAPABILITIES=compute,video,utility \
-e VERSION=latest \
-e PUID=1000 -e PGID=1000 \
-e TZ=America/Detroit \
-v /docker/containers/plex/config:/config \
-v /storage:/storage \
-v /transcode:/transcode \
plexinc/pms-docker:plexpass
```

### Portainer

Portainer is a nice management GUI for Docker containers. It allows you to view running containers, and start/stop/destroy them. You can also create new containers pull from LS.IO repositories or using any Docker repo.

```
docker run -d -p 9000:9000 --name=portainer -v /docker/containers/portainer/config:/data -v /var/run/docker.sock:/var/run/docker.sock portainer/portainer
```

### Radarr

Radarr is a fork of Sonarr that provides downloading similar to Couchpotato. This runs on port 7878.

```
docker create \
  --name=radarr \
    -v /docker/containers/radarr/config:/config \
    -v /storage/videos:/storage/videos \
    -v /docker/downloads/completed/RadarrMovies:/downloads/completed/RadarrMovies \
    -e PGID=1000 -e PUID=1000  \
    -e TZ="America/Detriot" \
    -p 7878:7878 \
    -p 9899:9899 \
  linuxserver/radarr
```

### Sonarr

This is getting repetitive 🙂 Sonarr runs on port 8989 and as my user and group again. I pass through a few specific directories from my mergerfs pool as well as a shared folder from NZBget. This has a bunch of Mono dependencies, so I’m glad this isn’t crufting up my OS.

```
docker create \
--name sonarr \
-p 8989:8989 \
-p 9898:9898 \
-e PUID=1000 -e PGID=1000 \
-v /etc/localtime:/etc/localtime:ro \
-v /docker/containers/sonarr/config:/config \
-v /storage/tv_shows:/storage/tv_shows \
-v /storage/anime:/storage/anime \
-v /docker/downloads/completed/TV:/downloads/completed/TV \
linuxserver/sonarr
```

### Unifi

Finally Unifi. This uses Java again and requires a bunch of open ports, so this is a great thing to containerize. You can read about connecting your AP to the Unifi Controller in my [older article](/unifi-controller-on-docker/).

```
docker create \
--name=unifi-controller \
-e PGID=1000 \
-e PUID=1000  \
-p 3478:3478/udp \
-p 10001:10001/udp \
-p 8080:8080 \
-p 8081:8081 \
-p 8443:8443 \
-p 8843:8843 \
-p 8880:8880 \
-v /etc/localtime:/etc/localtime:ro \
-v /docker/containers/unifi/config:/config \
--restart unless-stopped \
linuxserver/unifi-controller:latest
```

### Tautulli

Tautulli is a great way to gather stats from the Plex host. This runs on port 8181 and again runs as my user and group (1000).

```
docker create \
  --name=tautulli \
  -e PUID=1000 \
  -e PGID=1000 \
  -e TZ=America/Detroit \
  -p 8181:8181 \
  -v /docker/containers/tautulli/config:/config \
  -v /docker/containers/plex/config/Library/Application040Support/Plex040Media040Server/Logs:/logs \
  --restart unless-stopped \
  linuxserver/tautulli:latest
```

### Watchtower

Updating Docker container images is a bit weird when you first learn about it. First, you must stop your container, then remove the current image, then re-create the image with the same options. Also, you need to keep track of when the maintainer updates the images. Sure, you could write a script to do this, but luckily, there is another Docker container that does this for you. It’s called Watchtower. Here’s how you set it up.

```
docker run -d \
  --name watchtower \
  -v /var/run/docker.sock:/var/run/docker.sock \
  containrrr/watchtower --cleanup
```

That’s it. It will periodically check for updates to your Docker container images, and if there is a newer version, it will pull the image, and re-create the container. All without you lifting a finger.

**Managing Containers**  
This is super easy. You can view your containers like this. It will show you what containers are running and for how long.

```
docker ps -a
```

You can start and stop them like this.

```
docker start unifi
docker stop unifi
```

If you need to make a change to a container, (add/remove a volume add a port, etc.) you can easily remove the current container and re-run your docker create line again.

```
# Stop the running container
docker stop nzbget

# Remove the container
docker rm nzbget

# Re-Run the create line here...
docker run --name nzbget ... the rest
```

If you ever need/want to completely remove a container image, you just stop the container, remove it, and then remove the image.

```
docker stop nzbget
docker rm nzbget
docker rmi linuxserver/nzbget
```

You can view the log files of a container like this.

```
docker logs -f plexpy
```

Or, you can even enter the container if you’d like to.

```
docker exec -it crashplan /bin/bash
```

This only scratches the surface of what you can do with Docker. It’s an awesome technology and I encourage you to check it out. Also, the people over at [linuxserver.io](https://www.linuxserver.io/) have a [huge list of awesome containers](https://tools.linuxserver.io/dockers) and are happy to assist with any issues you might have via their forums or IRC.

**Permission denied on Docker**

If you have all of your users and permissions set correctly, you may want to check if SELinux is causing the issue. You can read more about a possible solution [here](https://nanxiao.me/en/selinux-cause-permission-denied-issue-in-using-docker/).