---
layout: post
title: "Wireguard fails to work on one host"
date: 2026-06-04
categories: [homelab, vpn]
tags: [wireguard, vpn, homelab, linux]
image: /wp-content/uploads/images/wireguard/wireguard_cover_image2.webp
---

# When Docker Breaks WireGuard: A Sneaky UniFi VPN Routing Conflict

Last night I decided to move my remote access VPN from a Docker hosted WireGuard instance (wg-easy) in a VM that is hosted on my Proxmox host. This VM has the bulk of my Docker containers, and it felt like it was a better idea to push the VPN access to the edge on my UniFi Fiber gateway.

The migration appeared to go perfectly. The Unifi GUI was simple a few clicks. I got the QR code scanned in the Wireguard app on my iPhone and the VPN connected immediately. My phone showed my home's public IP address when browsing. I could browse the internet through the VPN connection. 

But... I couldn't hit any of the services on that same busy Docker container host. 

## The Symptoms

The behavior was incredibly confusing.

From my phone connected through the UniFi WireGuard VPN:

* I could access the UniFi gateway itself.
* I could SSH into my Proxmox hosts.
* I could every other computer in the house.
* I could not access my primary Docker host.
* I could not SSH into that host.
* I could not access any of the applications running on it.

At first, I thought it was probably an iptables or Crowdsec issue on that host.

## The Rabbit Hole

I first circled back to the firewall rules on my router. Was there anything that could be preventing this. I added explicit rules allowing VPN traffic to reach internal networks. There was no change.

Next, I dove into CrowdSec. That Docker host runs CrowdSec with the firewall bouncer enabled, so it seemed entirely possible that VPN traffic was being blocked. I checked the CrowdSec blocklists. I created allowlists. I killed CrowdSec altogther. Still no luck.

Next came iptables and nftables. Maybe it was just the firewall? So, I added temporary ACCEPT rules.Nothing changed.

The VPN connected successfully, but connections to the Docker host would simply hang.

## The Breakthrough

The breakthrough came from a simple packet capture.

On the Docker host, I ran (192.168.2.2 was the ip address of the VPN client):

```bash
tcpdump -ni any net 192.168.2.0/24
```

and attempted to connect from the VPN. The packets were arriving at the Docker host. Well... that rules out the firewall and Wireguard, because the host was receiving the traffic.

The question became:

> Why wasn't it responding?

The answer appeared after running:

```bash
ip route get 192.168.2.2
```

Instead of routing the traffic through my LAN interface and default gateway, Linux reported:

```text
192.168.2.2 dev br-9798460af619 src 192.168.0.1
```

What?! That's not right.

## The Actual Problem

Sometimes the trickiest problems are the easiest and most obvious. The UniFi WireGuard server had automatically assigned itself 192.168.2.0/24 for the Wireguard VPN subnet. Meanwhile, Docker had created one of its bridge networks as:

```text
192.168.0.0/20
```

If you're not used to thinking of networking in CIDR ranges, that Docker network covers:

```text
192.168.0.0 - 192.168.15.255
```

See the problem yet?... This means the VPN subnet was falling inside the Docker network... I'm so stupid ;)

```text
192.168.2.0/24
```

The VM host therefore believed the VPN subnet was locally attached to the Docker network. So, when applications on the Docker host attempted to reply to VPN clients, their responses disappeared into the Docker network instead of being sent back through the UniFi gateway.

The packets weren't being dropped. They were being routed into the wrong network void.

## The Fix

The simplest solution was changing the WireGuard subnet. So, instead of using the automatically assigned network, I had to spend an additional 15 seconds and manually set the subnet for the VPN connections.

I changed the VPN network to:

```text
10.8.0.0/24
```

After importing a new WireGuard profile to my phone and Macbook, everything immediately started working.

SSH to the host worked. I could access my web apps. All was well again.  I think there's a good lesson here when troubleshooting to take a step back and think for a few minutes before trying to fix something.