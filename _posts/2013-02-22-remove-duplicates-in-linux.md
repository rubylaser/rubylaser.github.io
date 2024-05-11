---
id: 154
title: 'Remove Duplicates in Linux'
date: '2013-02-22T08:00:00-05:00'
excerpt: 'I had run fdupes on our Marketing server at work and realized we had about 200GB of duplicates on a 700GB volume.  Here is how I fixed it.'
layout: post
permalink: /remove-duplicates-in-linux/
image: /wp-content/uploads/2013/02/2348299637_a6b93cedfc.jpg
categories:
    - ubuntu
tags:
    - duplicates
---

## Introduction to fdupes
I knew I could use fdupes to identify the dupes, but I wanted to replace them with hardlinks. I’ve seen many bash scripts that pipe the output from fdupes -r to view them. On newer distros, Ubuntu 12.04, fdupes has a -L option that will replace the duplicates with hardlinks.

```bash
 apt-get install fdupes 
```

```bash
 fdupes -r -L /marketing 
```

On older versions of Ubuntu 10.04 the -L option does not exist. I grabbed and compiled a newer version of fdupes from [this repository](https://github.com/tobiasschulz/fdupes) to support the -L option.