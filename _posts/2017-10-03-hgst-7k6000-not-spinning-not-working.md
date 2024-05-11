---
title: 'HGST 7K6000 Not Spinning Up (Not Working)'
date: '2017-10-03T21:21:29-04:00'
author: Zack
layout: post
permalink: /hgst-7k6000-not-spinning-not-working/
image: /wp-content/uploads/2017/10/20171003_165219.jpg
categories: [linux, fileserver]
---

I bought a used HGST 7K6000 SAS disk to add to one of my Norco 4224 cases at home. I have (3) H310s in this case flashed to IT mode to connect all of the disks to. When I installed the disk, the power LED came on but the disk never powered up or showed up in Linux. Weird?!?!

Other SAS disks in this same slot, or on the same backplane all work fine (I tried other slots on different backplanes with the same effect). So, I assuned the disk was just DOA…

But, before RMAing it, I tried one more thing. I disconnected one of the 8087 -&gt; 8087 cables from my H310 to the backplane and instead hooked up an 8087 -&gt; 4x SAS cable. I supplied power from my PSU with a 4-pin molex to SATA power plugged into the back of the SAS plug. Now the disk spins up and is visible in Ubuntu?!?!

I thought this disk might have the new [power disable feature](https://www.hgst.com/sites/default/files/resources/HGST-Power-Disable-Pin-TB.pdf), but then I remembered my backplanes all use molex plugs, so I thought that shouldn’t be the issue. The article seems to imply that SAS disks don’t suffer from this because SAS backplanes don’t use Pin 3 for anything. But, it turns out this is an issue on backplanes that support SAS/SATA drives like those in my Norco. So, the answer was to disable pin 3 on my backplane to this disk. So, I could try to figure out how the backplane powers pin 3 with 3.3 volts, or I could tape over it… I went with the tape method.

Now, normal electrical tape won’t do. It’s too thick and will come off in the backplane. So, I used [Kapton tape](https://www.amazon.com/dp/B00J8PN7J4/ref=asc_df_B00J8PN7J45199011). This stuff is 1 millimeter thick, super sticky, and is a great electrical insulator. All of the things I needed.

So, I carefully cut the tape and applied it to pin 3 on the SAS disk. You can see it installed here on pin 3. It’s difficult to see since the Kapton tape is transparent and an amber color, so it’s barely visible on the gold pin. After doing that, it works like a charm. And, with the Kapton tape, I can safely remove/reseat the hard drive without the trouble of the tape coming off in the backplane.

![](https://zackreed.me/wp-content/uploads/2017/10/20171003_165219-768x1024.jpg)