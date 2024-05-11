---
layout: post
title: "Send System Email with Gmail and sSMTP"
date: 2020-12-20
permalink: /send-system-email-with-gmail-and-ssmtp
image: /wp-content/uploads/2011/11/New_Logo_Gmail.svg.png
categories: technology
tags: [linux, ssmtp, email, system administration, gmail]
---

### Introduction

In this post, I'll guide you through setting up your system to send emails using Gmail and sSMTP, a simple tool for those who need to send emails from their local machine. This is particularly useful for system alerts, SnapRAID sync scripts, hard drive space usage notifications, and more.

### Prerequisites

#### Installing Mutt

First, we need to ensure that Mutt, the email client, is installed:

```bash
sudo -i
apt install mutt
```

Next, ensure the root user has an email directory:

```bash
touch /var/mail/root
```

#### Installing sSMTP

Installing sSMTP on Debian/Ubuntu is straightforward:

```bash
apt-get install ssmtp
```

### Configuration

Edit the `ssmtp.conf` file to set up Gmail for sending emails:

```bash
nano /etc/ssmtp/ssmtp.conf
```

Insert the following configuration, replacing `GmailUsername` and `GmailPassword` with your Gmail username and a one-time password if you have two-factor authentication enabled:

```
root=GmailUsername@gmail.com
mailhub=smtp.gmail.com:587
rewriteDomain=gmail.com
hostname=fileserver.local
TLS_CA_FILE=/etc/ssl/certs/ca-certificates.crt
UseTLS=YES
UseSTARTTLS=YES
AuthUser=GmailUsername
AuthPass=GmailPassword
AuthMethod=LOGIN
FromLineOverride=YES
```

Save and exit (`Ctrl+X`, then `Y`).

#### Setting Up User Aliases

You also need to define user aliases:

```bash
nano /etc/ssmtp/revaliases
```

Add the following, replacing `youruser` with your Ubuntu username:

```
root:GmailUsername@gmail.com:smtp.gmail.com:587
youruser:GmailUsername@gmail.com:smtp.gmail.com:587
```

### Sending a Test Email

Now, try sending a test email using Mutt:

```bash
mutt
```

Follow these steps in Mutt:
- Press `m` to compose a new email.
- Enter the recipient's email address, subject as "TEST EMAIL FROM MUTT", and type your message.
- To send the email, press `Ctrl+X`, then `Y`.

If everything is configured correctly, you'll see "sending Message" followed by "Mail sent."

### Conclusion

You've now set up your system to send emails using Gmail and sSMTP. This setup is ideal for sending system alerts and monitoring messages from your Linux machine.

---

Make sure to replace `/path/to/your/image.jpg` with the actual path to an image that visually complements the content of your post. This post provides a detailed guide on setting up sSMTP with Gmail to handle system emails, a valuable tool for system administrators and home users alike.