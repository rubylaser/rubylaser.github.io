---
title: 'Unifi Controller on Docker'
date: '2016-01-15T00:09:01-05:00'
layout: post
permalink: /unifi-controller-on-docker/
image: /wp-content/uploads/2014/09/Docker-logo-011-220x162.png
categories: [docker, unifi]
---

Docker is an amazing way to run specific software stacks without installing them on your host machine. It allows the containers to be portable and run on any other Docker host. This was my maiden voyage with Docker, so I grabbed a repo that for unifi-controller. This assumes you have Docker and git configured already.

```
git clone https://github.com/rednut/docker-unifi-controller.git
cd docker-unifi-controller/
docker build -t=rednut/unifi .
mkdir -p /var/lib/unifi/data
```

I’m going to name my Docker instance **unifi**, create a local directory on the fileserver for the unifi data to reside in (/config/unifi), and run it.

```
docker run -d -p 2222:22 -p 8080:8080 -p 8443:8443 -p 27117:27117 -v /config/unifi:/usr/lib/unifi/data --name unifi rednut/unifi
```

This runs the instance in daemon mode, and maps all the ports necessary to the container. Now, starting and stopping the container is as easy as.

```
# Start Docker
docker start unifi

# Stop Docker
docker stop unifi
```

After a few minutes of starting up, you should be able to connect to the Unifi web interface via https://host\_ip:8443, in my case https://fileserver:8443.

The only trick with this is that the L2 Adoption built into Unifi doesn’t see the access points. You can either configured DHCP Option 43 or use the very simple Unifi Discover tool to adopt your access points. To get this working, I followed the directions \[here\](http://community.ubnt.com/t5/UniFi/UniFi-FAQ-the-missing-manual-and-beyond/m-p/110114#M177). I have copied the directions here incase the page ever goes away.

**Use the UniFi Discovery Utility**  
Not many environment can have a DHCP server that’s configurable, even less likely with a DNS server.  
That’s where UniFi Discovery Utility comes in. It listens to the multicast/broadcast packets from UniFi APs and allow you to tell the AP to inform any URL you’d like.  
(only APs in default state or not in contact with any controller will be displayed)  
UniFi Discovery utility is installed along with your UniFi controller.  
On Windows, it’s in Start Menu-&gt;Ubiquiti UniFi-&gt;UniFi-Discover  
On Mac, /Applications/UniFi-Discover.app (or use Spotlight to find it)  
To perform L3 adoption with the discovery utility:

1. Wait until the AP shows up
2. If the AP is not in default state. click “reset”, specify the SSH username/password and click “Apply”
3. Click on “manage”, modify the inform URL and leave the SSH username/password as ubnt/ubnt and click “Apply”
4. Open a browser to your remote UniFi controller and you should see it being “Pending Approval”
5. Click on “approve”. You’ll see it going to “Adopting” state, ignore it as it’ll eventually become “Adoption Failed” or “Disconnected”
6. Perform again (no need to wait for to finish)
7. AP is now managed by the controller

**Adopt right from the AP**  
To get the AP to show up in the controller so it can be adopted and provisioned, do the following:

1. Determine the IP the AP was leased
2. SSH to that IP
3. Login as ubnt / ubnt
4. mca-cli
5. set-inform http://address:port/inform (where address is IP of controller and port is the port you are using for inform, default is 8080)

Once you run the set inform command it should show in the controller. As soon as you click adopt you need to run the set inform command a second time on the AP.

You can view your running Docker containers like this.

```
docker ps -l
```

Here’s what the output looks like.

```
root@fileserver:~# docker ps -l
CONTAINER ID        IMAGE                 COMMAND                CREATED             STATUS              PORTS                                                                                            NAMES
853c84f562a5        rednut/unifi:latest   "/usr/bin/supervisor   33 hours ago        Up 33 hours         0.0.0.0:2222->22/tcp, 0.0.0.0:8080->8080/tcp, 0.0.0.0:8443->8443/tcp, 0.0.0.0:27117->27117/tcp   unifi
```

All-in-all, this has been a great learning experience, and I really like how Docker compartmentalizes my various programs.