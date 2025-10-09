---
layout: post
title: "Upgrading My JBOD 826 Case to a SAS3 Backplane"
date: 2025-10-09
tags:
  - homelab
  - storage
  - server
  - sas
summary: >
  I upgraded my second Supermicro 826 JBOD case from an older SAS2 backplane to a modern SAS3 model with a built-in expander, making future expansion easier and cleaner.
image: /wp-content/uploads/images/sas-826a-backplane-in-place.jpg
---

After finishing my last round of upgrades on the main storage server, I turned my attention to the second JBOD. It was running an older SAS2 826A backplane that had served me well, but it limited future growth. I wanted a cleaner path to expand storage without adding another HBA or juggling multiple breakout cables.
![826A](/wp-content/uploads/images/sas-826a-backplane.jpg)  

The upgrade centered on swapping in a **BPN-SAS3-826EL1** backplane. It fits perfectly in the same Supermicro 826 chassis but introduces a big improvement in the way of modern SAS3 and an integrated SAS expander. That means a single SFF-8644 connection from the host can handle all the drives in the enclosure. No need to run three cables from the host to address the 12 disks in the shelf.  I only need one now.
![826EL1](/wp-content/uploads/images/BPN-SAS3-826EL1.jpg)

![826EL1 Installed](/wp-content/uploads/images/sas3-826EL1-backplane.jpg)

The swap was straightforward (other than needing to pull some of the trays into the right spots to thread the backplane screws through). I removed the older 826A backplane, cleaned up the cabling, and installed the new SAS3 unit. The connectors lined up exactly, and the power distribution board didn’t need any changes. The fans and drive LEDs worked right away, which was a good sign that everything was wired correctly.

This is a great [video](https://www.youtube.com/watch?v=Ey95VDPo3Ug) for more thorough directions.

With the new backplane in place, the JBOD is ready for the next step — linking multiple shelves together. The expander makes it much easier to add another disk shelf when I need more capacity. It also improves signal quality and keeps cabling neat inside the rack.  

Performance is solid. Drive detection is instant, and the throughput on large transfers feels snappier compared to the SAS2 setup. The expander handles traffic well, even when all bays are populated.  

This was one of those small but satisfying upgrades that make the whole setup feel more professional. It sets the stage for future expansion without reworking the entire storage topology. Having both JBODs on modern SAS3 backplanes means I can grow the array confidently when the time comes.