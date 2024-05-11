---
title: 'Automating Ubuntu 22.04 file and Docker server with Ansible'
date: '2024-03-22T10:19:42-04:00'
layout: post
permalink: /automating-the-setup-of-ubuntu-22-04-file-and-docker-server-with-ansible/
image: /wp-content/uploads/2024/03/DALL·E-2024-03-22-10.12.21-An-artistic-representation-of-a-server-setup-featuring-Docker-Ansible-and-file-serving.-The-image-should-include-symbolic-elements-of-Docker-like-t.jpg
categories: [automation, fileserver, linux, mergerfs, snapraid, ubuntu]
---

## Introduction

In the realm of IT automation, Ansible stands out as a powerful and user-friendly tool. It simplifies complex configuration tasks, manages server deployments, and orchestrates multi-tier application environments with ease. Ansible’s agentless nature, where no software needs to be installed on the managed nodes, makes it a preferred choice for system administrators and DevOps professionals.

The purpose of this guide is to introduce Ansible to macOS users looking to automate and streamline operations on remote Linux servers, specifically Ubuntu 22.04. Whether you’re managing a single server or an entire data center, Ansible can help you automate the mundane, repetitive tasks, allowing you to focus on more strategic initiatives.

By the end of this tutorial, you will have learned how to set up Ansible on a macOS machine, configure SSH access to a remote Ubuntu server, and run Ansible playbooks to automate tasks. This guide is designed to be a comprehensive starting point for macOS users new to Ansible, providing the necessary steps to get up and running with this powerful automation tool.

This introduction sets the stage for the tutorial, explaining what Ansible is, why it’s useful, and what the reader will achieve by following your guide. It’s aimed at macOS users who are beginners with Ansible, guiding them through the process of managing a remote Ubuntu server.

## Configuring Ansible on macOS

To harness the power of Ansible for automating tasks on your Ubuntu server, you first need to set up Ansible on your macOS system. This section guides you through the installation and configuration process, ensuring a seamless connection between your macOS machine and the Ubuntu server.

#### Installation

1. **Install Homebrew**: If you haven’t already installed Homebrew, the package manager for macOS, you can do so by executing the following command in your terminal:

```bash
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
```

2. **Install Ansible**: With Homebrew installed, you can easily install Ansible by running the following command:

```bash
brew install ansible
```

This command downloads and installs the latest version of Ansible, along with its dependencies.

#### Configuration

1. **Create a Project Directory**: Organize your Ansible projects by creating a dedicated directory:

```
mkdir ~/ansible-projects && cd ~/ansible-projects
```

2. **Configure SSH Access**: Ansible uses SSH to communicate with remote servers. Ensure you have an SSH key pair on your macOS machine. If you don’t have one, generate it using `ssh-keygen` and then copy the public key to your Ubuntu server:

```bash
ssh-keygen -t ed25519 -C "your_email@example.com"
ssh-copy-id user@your-ubuntu-server-ip
```

Replace `your_email@example.com` with your email and `user@your-ubuntu-server-ip` with your actual server login and IP address.

3. **Create an Inventory File**: Ansible needs to know about the servers it manages. Create an inventory file named `hosts`:

```bash
touch hosts
```

Edit this file using a text editor and add your server details under a group, for example:

```
[ubuntu_servers]
your-ubuntu-server-ip ansible_user=user ansible_ssh_private_key_file=~/.ssh/id_ed25519
```

Replace `your-ubuntu-server-ip` and `user` with your server’s IP address and username. The `ansible_ssh_private_key_file` should point to your private key file.

4. **Test the Connection**: Ensure Ansible can connect to your Ubuntu server by running the following command:

```bash
ansible -i hosts ubuntu_servers -m ping
```

If everything is set up correctly, you should receive a `SUCCESS` message.

### Configuring SSH for Ansible

To enable Ansible to manage your remote servers seamlessly, you must configure SSH properly. This ensures secure and efficient communication between your local machine and the Ubuntu server. Here’s how to set up SSH for Ansible use:

#### Generating an SSH Key Pair

1. **Open Terminal**: Launch the Terminal application on your macOS.
2. **Generate SSH Key**: Run the following command to create a new SSH key pair. If you already have an SSH key and want to use it, you can skip this step.

```bash
ssh-keygen -t ed25519 -C "your_email@example.com"
```

Replace `"your_email@example.com"` with your email address. This command generates a new SSH key, using the provided email as a label.

3. **Save the Key**: When prompted to “Enter a file in which to save the key,” press Enter to accept the default file location.

#### Copying the SSH Public Key to the Ubuntu Server

1. **Copy Public Key**: Use the `ssh-copy-id` command to copy your public SSH key to the Ubuntu server. This facilitates password-less SSH login.

```bash
ssh-copy-id user@your-ubuntu-server-ip
```

Replace `user` with your username on the Ubuntu server and `your-ubuntu-server-ip` with the server’s IP address.

#### Testing the SSH Connection

1. **SSH to the Server**: Try logging into your server via SSH to ensure the key-based authentication works:

```bash
ssh user@your-ubuntu-server-ip
```

If successful, you should log in without being prompted for a password.

#### Configuring SSH for Ansible

1. **Ansible SSH Settings**: Ensure Ansible uses the correct SSH settings by editing the `ansible.cfg` file or defining necessary parameters in your inventory file, like so:

```bash
[ubuntu_servers]
your-ubuntu-server-ip ansible_user=user ansible_ssh_private_key_file=~/.ssh/id_ed25519
```

This configuration tells Ansible to use the specified user and SSH private key when connecting to the Ubuntu server.

2. **Parallelism and Performance**: Adjust the SSH settings in `ansible.cfg` to improve performance, such as increasing `forks` for parallelism and enabling `ControlPersist` to keep SSH connections open.

By configuring SSH correctly, you ensure that Ansible can securely and efficiently execute tasks on the remote server without manual password entry. This setup is essential for automating server management tasks with Ansible playbooks.

### Setting Up Ansible Inventory

An Ansible inventory is a file that details the hosts and groups of hosts upon which commands, modules, and tasks in a playbook operate. For Ansible to automate a server, it must be defined in the inventory file. Here’s how to set it up:

1. **Create the Inventory File**: An inventory file can be named anything, but by default, Ansible looks for `hosts` in the `/etc/ansible/` directory. However, on macOS, it’s common to store this file in a project-specific directory or under `~/ansible-projects/`. We’ve previously created this file, but in case you haven’t, here it is again.

```bash
cd ~/ansible-projects
touch hosts
```

2. **Define Your Servers**: In the inventory file, you can define individual servers or groups of servers under a bracketed header. For example, to define a group named `ubuntu_servers`, you might add:

```bash
[ubuntu_servers]
ubuntu1 ansible_host=192.168.1.100
ubuntu2 ansible_host=192.168.1.101
```

Replace `192.168.1.100` and `192.168.1.101` with the IP addresses of your actual Ubuntu servers.

3. **Specify Connection Details**: If your servers require specific user names or private keys to connect, you can specify these in the inventory file:

```bash
[ubuntu_servers]
ubuntu1 ansible_host=192.168.1.100 ansible_user=myuser ansible_ssh_private_key_file=/path/to/private/key
ubuntu2 ansible_host=192.168.1.101 ansible_user=myuser ansible_ssh_private_key_file=/path/to/private/key
```

Replace `myuser` and `/path/to/private/key` with the username and path to the SSH private key you use to connect to these servers.

4. **Organize with Groups**: For more complex setups, you can organize hosts into groups and even have groups of groups. This organization can be beneficial for targeting specific subsets of servers with your Ansible playbooks.

```bash
[web_servers]
ubuntu1
ubuntu2

[db_servers]
ubuntu3

[all_servers:children]
web_servers
db_servers
```

5. **Use Variables**: You can define variables within the inventory file that apply to individual hosts or groups:

```bash
[ubuntu_servers:vars]
ansible_python_interpreter=/usr/bin/python3
```

This sets the Python interpreter for all hosts in the `ubuntu_servers` group.

6. **Testing Your Inventory**: Validate your inventory setup by pinging the hosts using the `ansible` command:

```bash
ansible -i hosts ubuntu_servers -m ping
```

A successful response indicates that Ansible can connect to the specified hosts.

By setting up the inventory file correctly, you ensure Ansible knows where and how to execute the tasks defined in your playbooks, paving the way for seamless automation of your server management tasks.

### Creating Your First Ansible Playbook

A playbook in Ansible is a YAML file containing a series of procedures that the automation tool will execute on the configured servers. To illustrate, we’ll create a playbook that automates the installation and configuration of MergerFS, SnapRAID, SSMTP, Docker, and Docker-Compose on an Ubuntu 22.04 server.

1. **Create the Playbook File**: Begin by creating a new YAML file for the playbook. For instance:

```bash
cd ~/ansible-projects
touch server-setup.yml
```

2. **Define Playbook Structure**: Open `server-setup.yml` in a text editor and start defining the playbook structure with hosts, become, and tasks sections:

```bash
---
- name: Setup Ubuntu server
  hosts: ubuntu_servers
  become: true
  tasks:
```

- `name`: Descriptive name of the play.
- `hosts`: Specifies the group of hosts from the inventory file.
- `become`: Enables privilege escalation (sudo).

1. **Install and Configure MergerFS and SnapRAID**:

```bash
        - name: Install MergerFS and SnapRAID dependencies
          apt:
            name: [build-essential, git, automake, autoconf, lzop, libfuse-dev, libattr1-dev]
            state: present
            update_cache: true

        - name: Clone and compile MergerFS
          git:
            repo: 'https://github.com/trapexit/mergerfs.git'
            dest: '/tmp/mergerfs'
          command: make install
          args:
            chdir: /tmp/mergerfs

        - name: Clone and compile SnapRAID
          git:
            repo: 'https://github.com/amadvance/snapraid.git'
            dest: '/tmp/snapraid'
          command: |
            ./autogen.sh
            ./configure
            make
            make install
          args:
            chdir: /tmp/snapraid
```

2. **Install and Configure SSMTP**:

```bash
        - name: Install SSMTP
          apt:
            name: ssmtp
            state: latest

        - name: Configure SSMTP
          copy:
            dest: /etc/ssmtp/ssmtp.conf
            content: |
              root=user@gmail.com
              mailhub=smtp.gmail.com:587
              AuthUser=user@gmail.com
              AuthPass=password
              UseTLS=YES
              UseSTARTTLS=YES
```

3. **Install Docker and Docker-Compose**:

The below will set up the repository for Docker and download the latest version of docker and docker-compose. It also creates two docker networks: proxy and socket\_proxy for use with your containers.

```bash
    - name: Docker installation and configuration
      block:
        - name: Add Docker's official GPG key
          ansible.builtin.shell:
            cmd: curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg

        - name: Set up the Docker stable repository
          ansible.builtin.copy:
            dest: /etc/apt/sources.list.d/docker.list
            content: |
              deb [arch=amd64 signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/ubuntu jammy stable
            owner: root
            group: root
            mode: '0644'

        - name: Install Docker CE
          apt:
            name: docker-ce
            state: present
            update_cache: true

        - name: Install Docker Compose
          ansible.builtin.shell:
            cmd: >
              curl -s https://api.github.com/repos/docker/compose/releases/latest |
              grep browser_download_url | grep docker-compose-linux-x86_64 |
              cut -d '"' -f 4 | wget -qi -
              && chmod +x docker-compose-linux-x86_64
              && mv docker-compose-linux-x86_64 /usr/local/bin/docker-compose

    - name: Create Docker networks
      block:
        - name: Create proxy network
          community.docker.docker_network:
            name: proxy
            state: present

        - name: Create socket_proxy network
          community.docker.docker_network:
            name: socket_proxy
            state: present
```

4. **Running the Playbook**: Save the file and execute it with the `ansible-playbook` command:

```bash
ansible-playbook -i hosts server-setup.yml
```

This playbook serves as a foundational example. You can expand it with more tasks, roles, handlers, and variables to fit the complexities of your infrastructure. With Ansible, you’re empowered to automate the setup and configuration of your servers efficiently and consistently.

### Understanding Playbook Output

When you run an Ansible playbook, the console output provides detailed information about what Ansible is doing. Here’s how to understand the key parts of that output.

1. **Play and Task Names**: At the start of the output, Ansible lists the play and tasks that it will execute. Each task will show its name, providing clarity on what Ansible is currently working on.
2. **Task Status**: Each task will end with a status indicator:

- `ok`: The task completed successfully, and no changes were made to the host.
- `changed`: The task completed successfully, and some changes were made to the host.
- `failed`: The task did not complete successfully. If a task fails, Ansible will stop executing the rest of the playbook on that host.

1. **Host Summary**: At the end of the playbook run, Ansible provides a summary for each host, showing how many tasks were ok, changed, or failed.
2. **Play Recap**: This section summarizes the entire playbook execution, showing the total number of tasks that were ok, changed, failed, or skipped across all hosts.

Here’s an example of what the output might look like:

```bash
PLAY [Setup Ubuntu server] *****************************************************

TASK [Gathering Facts] *********************************************************
ok: [ubuntu_server]

TASK [Install MergerFS and SnapRAID dependencies] ******************************
changed: [ubuntu_server]

TASK [Clone and compile MergerFS] **********************************************
changed: [ubuntu_server]

TASK [Clone and compile SnapRAID] **********************************************
changed: [ubuntu_server]

TASK [Install SSMTP] ***********************************************************
changed: [ubuntu_server]

TASK [Configure SSMTP] *********************************************************
changed: [ubuntu_server]

TASK [Install Docker] **********************************************************
changed: [ubuntu_server]

TASK [Install Docker-Compose] **************************************************
changed: [ubuntu_server]

PLAY RECAP *********************************************************************
ubuntu_server              : ok=8    changed=7    unreachable=0    failed=0    skipped=0    rescued=0    ignored=0
```

- **ok=8**: Eight tasks ran successfully without needing to make any changes.
- **changed=7**: Seven tasks made changes to the system.
- **unreachable=0**: No hosts were unreachable.
- **failed=0**: No tasks failed.
- **skipped=0**: No tasks were skipped.

Understanding the playbook output is crucial for diagnosing issues and verifying that your configuration changes have been applied as expected.

### Best Practices and Tips

When working with Ansible, there are several best practices and tips you can follow to ensure your automation is efficient, secure, and reliable.

#### Organizing Playbooks and Inventory

1. **Directory Structure**: Maintain a clear directory structure where playbooks, roles, inventory files, and other components are organized in a logical manner. This makes managing your Ansible project easier and more intuitive.
2. **Use of Roles**: Utilize roles to break down complex playbooks into reusable sections. Roles can be used to group related tasks, variables, files, and templates, making your playbooks more modular and manageable.
3. **Inventory Management**: Keep your inventory file(s) organized. Use groups to categorize hosts logically, such as by environment (`prod`, `dev`, `test`) or function (`web`, `db`, `cache`). This simplification aids in targeting the correct hosts during playbook runs.

#### Security Considerations

1. **Ansible Vault**: Use Ansible Vault to encrypt sensitive data, such as passwords, secret keys, and other credentials. This ensures that sensitive data is not exposed in your playbook or inventory files.
2. **Minimum Privilege**: Ensure that the user Ansible uses to connect to remote machines has the minimum required privileges for the tasks it needs to perform. Use `become` only when necessary.
3. **Secure SSH**: Use SSH keys instead of passwords for Ansible to authenticate to remote servers, and protect these keys with strong passphrases.

#### Testing and Validation of Playbooks

1. **Syntax Check**: Use `ansible-playbook --syntax-check` to validate the syntax of your playbooks before running them.
2. **Dry Run**: Perform a “dry run” using the `--check` flag. This executes the playbook without making any actual changes, allowing you to validate logic and task order.
3. **Incremental Deployment**: Test playbooks in a controlled environment before deploying to production. Consider using a staging environment that mirrors production to catch potential issues.
4. **Version Control**: Use a version control system like Git to manage your Ansible code. This allows you to track changes, collaborate with others, and revert to previous versions if something goes wrong.

By adhering to these best practices, you can create more effective and secure automation routines with Ansible, ensuring smoother deployments and operations.

## My Playbook

Here is the current monolithic version of my playbook (not broken out into smaller playbooks) to give you an example of a automatically setting up and configuring many common aspects of a fileserver with Docker.

{% raw %}
```bash
---
- name: Setup Ubuntu server
  hosts: loki_fileserver
  become: true
  vars:
    user_name: zack
    data_disks:
      - { id: 'scsi-hard_disk_id_here-part1', mount: '/disks/data/disk01', options: 'defaults,noatime,errors=remount-ro' }
      - { id: 'scsi-hard_disk_id_here-part1', mount: '/disks/data/disk02', options: 'defaults,noatime,errors=remount-ro' }
      - { id: 'scsi-hard_disk_id_here-part1', mount: '/disks/data/disk03', options: 'defaults,noatime,errors=remount-ro' }
      - { id: 'scsi-hard_disk_id_here-part1', mount: '/disks/data/disk04', options: 'defaults,noatime,errors=remount-ro' }
      - { id: 'scsi-hard_disk_id_here-part1', mount: '/disks/data/disk05', options: 'defaults,noatime,errors=remount-ro' }
      - { id: 'scsi-hard_disk_id_here-part1', mount: '/disks/data/disk06', options: 'defaults,noatime,errors=remount-ro' }
      - { id: 'scsi-hard_disk_id_here-part1', mount: '/disks/data/disk07', options: 'defaults,noatime,errors=remount-ro' }
      - { id: 'scsi-hard_disk_id_here-part1', mount: '/disks/data/disk08', options: 'defaults,noatime,errors=remount-ro' }
      - { id: 'scsi-hard_disk_id_here-part1', mount: '/disks/data/disk09', options: 'defaults,noatime,errors=remount-ro' }
      - { id: 'scsi-hard_disk_id_here-part1', mount: '/disks/data/disk10', options: 'defaults,noatime,errors=remount-ro' }
      - { id: 'scsi-hard_disk_id_here-part1', mount: '/disks/data/disk11', options: 'defaults,noatime,errors=remount-ro' }
      - { id: 'scsi-hard_disk_id_here-part1', mount: '/disks/data/disk12', options: 'defaults,noatime,errors=remount-ro' }
      - { id: 'scsi-hard_disk_id_here-part1', mount: '/disks/data/disk13', options: 'defaults,noatime,errors=remount-ro' }
      - { id: 'scsi-hard_disk_id_here-part1', mount: '/disks/data/disk14', options: 'defaults,noatime,errors=remount-ro' }
      - { id: 'scsi-hard_disk_id_here-part1', mount: '/disks/data/disk15', options: 'defaults,noatime,errors=remount-ro' }
      - { id: 'scsi-hard_disk_id_here-part1', mount: '/disks/data/disk16', options: 'defaults,noatime,errors=remount-ro' }
      - { id: 'scsi-hard_disk_id_here-part1', mount: '/disks/data/disk17', options: 'defaults,noatime,errors=remount-ro' }
      - { id: 'scsi-hard_disk_id_here-part1', mount: '/disks/data/disk18', options: 'defaults,noatime,errors=remount-ro' }
      - { id: 'scsi-hard_disk_id_here-part1', mount: '/disks/data/disk19', options: 'defaults,noatime,errors=remount-ro' }
      - { id: 'scsi-hard_disk_id_here-part1', mount: '/disks/data/disk20', options: 'defaults,noatime,errors=remount-ro' }
      - { id: 'scsi-hard_disk_id_here-part1', mount: '/disks/data/disk21', options: 'defaults,noatime,errors=remount-ro' }
    parity_disks:
      - { id: 'scsi-hard_disk_id_here-part1', mount: '/disks/parity/parity1', options: 'defaults,noatime,errors=remount-ro' }
      - { id: 'scsi-hard_disk_id_here-part1', mount: '/disks/parity/parity2', options: 'defaults,noatime,errors=remount-ro' }
      - { id: 'scsi-hard_disk_id_here-part1', mount: '/disks/parity/parity3', options: 'defaults,noatime,errors=remount-ro' }
    mergerfs_mount: '/storage'

  tasks:
    - name: Include secrets
      include_vars:
        file: secrets.yml
        name: secrets

    - name: Update and install dependencies
      apt:
        name:
          - git
          - tmux
          - htop
          - nmon
          - build-essential
          - samba
          - powertop
          - mutt
          - ssmtp
          - python3-pip
          - libssl-dev
          - libffi-dev
          - python3-dev
          - ca-certificates
          - curl
          - gnupg
          - lsb-release
          - fzf
          - apt-transport-https
          - software-properties-common
          - qemu-guest-agent
          - linux-image-generic-hwe-22.04
          - ocl-icd-libopencl1
          - intel-gpu-tools
        state: latest
        update_cache: true

    - name: Update and upgrade system packages
      become: true  # Ensure you have root privileges
      apt:
        update_cache: yes  # equivalent to running `apt update`
        upgrade: dist  # equivalent to running `apt upgrade`


    - name: Reduce GRUB timeout
      block:
        - name: Set GRUB timeout to 5 seconds
          ansible.builtin.lineinfile:
            path: /etc/default/grub
            regexp: '^GRUB_TIMEOUT='
            line: 'GRUB_TIMEOUT=5'
            backrefs: true

        - name: Update GRUB
          ansible.builtin.shell:
            cmd: update-grub


    - name: Install the GPG signing key for Kopia
      ansible.builtin.shell:
        cmd: curl -s https://kopia.io/signing-key | gpg --dearmor -o /etc/apt/keyrings/kopia-keyring.gpg

    - name: Register APT source for Kopia
      ansible.builtin.lineinfile:
        path: /etc/apt/sources.list.d/kopia.list
        line: 'deb [signed-by=/etc/apt/keyrings/kopia-keyring.gpg] http://packages.kopia.io/apt/ stable main'
        create: true

    - name: Update APT package index
      ansible.builtin.apt:
        update_cache: true

    - name: Install Kopia
      ansible.builtin.apt:
        name: kopia
        state: latest

    - name: Docker installation and configuration
      block:
        - name: Add Docker's official GPG key
          ansible.builtin.shell:
            cmd: curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg

        - name: Set up the Docker stable repository
          ansible.builtin.copy:
            dest: /etc/apt/sources.list.d/docker.list
            content: |
              deb [arch=amd64 signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/ubuntu jammy stable
            owner: root
            group: root
            mode: '0644'

        - name: Install Docker CE
          apt:
            name: docker-ce
            state: present
            update_cache: true

        - name: Install Docker Compose
          ansible.builtin.shell:
            cmd: >
              curl -s https://api.github.com/repos/docker/compose/releases/latest |
              grep browser_download_url | grep docker-compose-linux-x86_64 |
              cut -d '"' -f 4 | wget -qi -
              && chmod +x docker-compose-linux-x86_64
              && mv docker-compose-linux-x86_64 /usr/local/bin/docker-compose

    - name: Create Docker networks
      block:
        - name: Create proxy network
          community.docker.docker_network:
            name: proxy
            state: present

        - name: Create socket_proxy network
          community.docker.docker_network:
            name: socket_proxy
            state: present

      become: true

    - name: Ensure /etc/apt/keyrings directory exists
      file:
        path: /etc/apt/keyrings
        state: directory
        mode: '0755'

    - name: Add the GPG key for eza
      ansible.builtin.shell:
        cmd: wget -qO- https://raw.githubusercontent.com/eza-community/eza/main/deb.asc | gpg --dearmor -o /etc/apt/keyrings/gierens.gpg

    - name: Add eza repository
      ansible.builtin.lineinfile:
        path: /etc/apt/sources.list.d/gierens.list
        line: 'deb [signed-by=/etc/apt/keyrings/gierens.gpg] http://deb.gierens.de stable main'
        create: yes

    - name: Set correct permissions for eza repository files
      file:
        path: "{{ item }}"
        mode: '0644'
      loop:
        - /etc/apt/keyrings/gierens.gpg
        - /etc/apt/sources.list.d/gierens.list

    - name: Update apt cache
      ansible.builtin.apt:
        update_cache: yes

    - name: Install eza
      apt:
        name: eza
        state: present

    - name: Install Intel Compute Runtime
      block:
        - name: Create temporary directory for downloading Intel packages
          ansible.builtin.file:
            path: /tmp/neo
            state: directory

        - name: Download Intel Compute Runtime packages
          get_url:
            url: "{{ item }}"
            dest: /tmp/neo/
          loop:
            - https://github.com/intel/intel-graphics-compiler/releases/download/igc-1.0.15985.7/intel-igc-core_1.0.15985.7_amd64.deb
            - https://github.com/intel/intel-graphics-compiler/releases/download/igc-1.0.15985.7/intel-igc-opencl_1.0.15985.7_amd64.deb
            - https://github.com/intel/compute-runtime/releases/download/24.05.28454.6/intel-level-zero-gpu-dbgsym_1.3.28454.6_amd64.ddeb
            - https://github.com/intel/compute-runtime/releases/download/24.05.28454.6/intel-level-zero-gpu_1.3.28454.6_amd64.deb
            - https://github.com/intel/compute-runtime/releases/download/24.05.28454.6/intel-opencl-icd-dbgsym_24.05.28454.6_amd64.ddeb
            - https://github.com/intel/compute-runtime/releases/download/24.05.28454.6/intel-opencl-icd_24.05.28454.6_amd64.deb
            - https://github.com/intel/compute-runtime/releases/download/24.05.28454.6/libigdgmm12_22.3.11_amd64.deb

    - name: Install downloaded Intel packages
      ansible.builtin.shell:
        cmd: dpkg -i /tmp/neo/*.deb /tmp/neo/*.ddeb

    - name: Remove the temporary directory
      ansible.builtin.file:
        path: /tmp/neo
        state: absent

    - name: User and authentication setup
      block:
        - name: Set up passwordless SSH for root
          blockinfile:
            path: "/root/.ssh/authorized_keys"
            block: "{{ secrets.ssh_public_key }}"
            create: true

    - name: User and authentication setup
      block:
        - name: Ensure Docker group exists
          ansible.builtin.group:
            name: docker
            state: present

        - name: Add user user_name
          ansible.builtin.user:
            name: "{{ user_name }}"
            shell: /bin/bash
            createhome: true

        - name: Add user_name to the docker group
          ansible.builtin.user:
            name: "{{ user_name }}"
            groups: docker
            append: true

    - name: SnapRAID and MergerFS setup
      block:
        - name: Download SnapRAID
          get_url:
            url: https://github.com/amadvance/snapraid/releases/download/v12.3/snapraid-12.3.tar.gz
            dest: /tmp/snapraid-12.3.tar.gz

        - name: Extract SnapRAID archive
          unarchive:
            src: /tmp/snapraid-12.3.tar.gz
            dest: /tmp/
            remote_src: true

        - name: Compile and install SnapRAID
          command: "{{ item }}"
          loop:
            - './configure'
            - 'make'
            - 'make install'
          args:
            chdir: "/tmp/snapraid-12.3/"

        - name: Download MergerFS package
          get_url:
            url: https://github.com/trapexit/mergerfs/releases/download/2.40.2/mergerfs_2.40.2.ubuntu-jammy_amd64.deb
            dest: "/tmp/mergerfs.deb"
            mode: '0755'

        - name: Install MergerFS
          apt:
            deb: "/tmp/mergerfs.deb"

    - name: Filesystem and storage configuration
      block:
        - name: Create mount points for data and parity
          file:
            path: "{{ item.mount }}"
            state: directory
            mode: '0755'
          loop: "{{ data_disks + parity_disks }}"

        - name: Update /etc/fstab with data disks
          ansible.builtin.lineinfile:
            path: /etc/fstab
            line: "#UUID={{ item.id }} {{ item.mount }} ext4 {{ item.options }} 0 2"
            state: present
          loop: "{{ data_disks }}"

        - name: Update /etc/fstab with parity disks
          ansible.builtin.lineinfile:
            path: /etc/fstab
            line: "#UUID={{ item.id }} {{ item.mount }} ext4 {{ item.options }} 0 2"
            state: present
          loop: "{{ parity_disks }}"

        - name: Configure mergerfs in fstab
          blockinfile:
            path: /etc/fstab
            marker: "# {mark} ANSIBLE MANAGED BLOCK mergerfs"
            block: |
              # /disks/data/* /storage fuse.mergerfs cache.files=partial,dropcacheonclose=true,category.create=mfs,moveonenospc=true,minfreespace=20G,fsname=mergerfsPool,nonempty 0 0

    - name: Copy SnapRAID configuration
      template:
        src: snapraid.conf.j2
        dest: /etc/snapraid.conf
        owner: root
        group: root
        mode: '0644'

    - name: Create mail spool file
      file:
        path: /var/mail/root
        state: touch
        owner: root
        group: mail
        mode: '0660'

    - name: Create /root/Mail directory
      become: true
      file:
        path: /root/Mail
        state: directory
        owner: root
        group: root
        mode: '0700'

    - name: Ensure /etc/ssmtp directory exists
      file:
        path: /etc/ssmtp
        state: directory
        mode: '0755'    

    - name: Configure ssmtp
      blockinfile:
        path: /etc/ssmtp/ssmtp.conf
        create: true
        block: |
          root={{ secrets.email_user }}@gmail.com
          mailhub=smtp.gmail.com:587
          rewriteDomain=gmail.com
          hostname=fileserver.local
          TLS_CA_FILE=/etc/ssl/certs/ca-certificates.crt
          UseTLS=YES
          UseSTARTTLS=YES
          AuthUser={{ secrets.email_user }}
          AuthPass={{ secrets.email_password }}
          AuthMethod=LOGIN
          FromLineOverride=YES

    - name: Set up sSMTP aliases
      copy:
        dest: /etc/ssmtp/revaliases
        content: |
          # sSMTP aliases
          # Format: local_account:outgoing_address:mailhub
          #
          # Example: root:your_login@your.domain:mailhub.your.domain[:port]
          # where [:port] is an optional port number that defaults to 25.
          root:{{ secrets.email_user }}@gmail.com:smtp.gmail.com:587
          user_name:{{ secrets.email_user }}@gmail.com:smtp.gmail.com:587
        force: yes
        mode: '0644'  

    - name: Samba configuration
      block:
        - name: Set samba password for user user_name
          shell: "(echo '{{ secrets.samba_password }}'; echo '{{ secrets.samba_password }}') | smbpasswd -a {{ user_name }}"
          args:
            executable: "/bin/bash"

        - name: Deploy Samba configuration
          template:
            src: "smb.conf.j2"
            dest: "/etc/samba/smb.conf"
            owner: "root"
            group: "root"
            mode: "0644"
          notify:
            - restart samba

    - name: Configure system utilities
      block:
        - name: Set up PowerTOP for auto-tuning
          block:
            - name: Enable PowerTOP auto-tune service
              copy:
                content: |
                  [Unit]
                  Description=PowerTOP tunings

                  [Service]
                  Type=oneshot
                  ExecStart=/usr/sbin/powertop --auto-tune

                  [Install]
                  WantedBy=multi-user.target
                dest: "/etc/systemd/system/powertop.service"

            - name: Start and enable PowerTOP service
              systemd:
                name: "powertop"
                enabled: true
                state: started

    - name: Install and configure unattended-upgrades
      become: true
      tasks:
        - name: Install unattended-upgrades package
          apt:
            name: unattended-upgrades
            state: latest
            update_cache: yes

        - name: Enable automatic updates
          copy:
            dest: /etc/apt/apt.conf.d/20auto-upgrades
            content: |
              APT::Periodic::Update-Package-Lists "1";
              APT::Periodic::Download-Upgradeable-Packages "1";
              APT::Periodic::AutocleanInterval "7";
              APT::Periodic::Unattended-Upgrade "1";

        - name: Configure unattended-upgrades
          copy:
            dest: /etc/apt/apt.conf.d/50unattended-upgrades
            content: |
              Unattended-Upgrade::Allowed-Origins {
                  "${distro_id}:${distro_codename}";
                  "${distro_id}:${distro_codename}-security";
                  "${distro_id}ESMApps:${distro_codename}-apps-security";
                  "${distro_id}ESM:${distro_codename}-infra-security";
              };
              Unattended-Upgrade::Package-Blacklist {
              };
              Unattended-Upgrade::Automatic-Reboot "true";
              Unattended-Upgrade::Automatic-Reboot-Time "02:00";

        - name: Add cscli alias for CrowdSec to root's .bashrc
          lineinfile:
            path: "/root/.bashrc"
            line: 'alias cscli="docker exec -t crowdsec cscli"'
            create: true

    - name: CrowdSec setup
      block:
        - name: Download and execute the installation script for CrowdSec
          ansible.builtin.shell: |
            curl -s https://packagecloud.io/install/repositories/crowdsec/crowdsec/script.deb.sh | bash

        - name: Install CrowdSec Firewall Bouncer
          apt:
            name: "crowdsec-firewall-bouncer-iptables"
            state: latest
            update_cache: true

        - name: Configure CrowdSec Firewall Bouncer
          template:
            src: "crowdsec-firewall-bouncer.yaml.j2"
            dest: "/etc/crowdsec/bouncers/crowdsec-firewall-bouncer.yaml"

        # - name: Ensure CrowdSec service is running
        #  systemd:
        #    name: "crowdsec-firewall-bouncer"
        #    state: started
        #    enabled: yes

    - name: CrowdSec service management
      block:
        - name: Create CrowdSec Firewall Bouncer systemd service file
          copy:
            dest: /etc/systemd/system/crowdsec-firewall-bouncer.service
            content: |
              [Unit]
              Description=The firewall bouncer for CrowdSec
              After=syslog.target network.target remote-fs.target nss-lookup.target crowdsec.service docker.service
              Before=netfilter-persistent.service
              ReloadPropagatedFrom=docker.service
              StartLimitIntervalSec=20

              [Service]
              Type=notify
              RemainAfterExit=no
              Restart=always
              RestartSec=20
              ExecStart=/usr/local/bin/crowdsec-firewall-bouncer -c /etc/crowdsec/bouncers/crowdsec-firewall-bouncer.yaml
              ExecStartPre=/usr/local/bin/crowdsec-firewall-bouncer -c /etc/crowdsec/bouncers/crowdsec-firewall-bouncer.yaml -t
              ExecStartPost=/bin/sleep 0.1

              [Install]
              WantedBy=multi-user.target

        - name: Reload systemd daemon to recognize new service
          ansible.builtin.systemd:
            daemon_reload: true

        # - name: Start and enable Crowdsec Firewall Bouncer service
        #  ansible.builtin.systemd:
        #    name: crowdsec-firewall-bouncer.service
        #    state: started
        #    enabled: yes

    - name: Configure iptables for CrowdSec
      block:
        - name: Ensure /etc/rc.local exists and is executable
          file:
            path: /etc/rc.local
            state: touch
            mode: '0755'

    - name: Ensure rc.local exists and has correct content
      block:
        - name: Ensure rc.local exists and is executable
          file:
            path: /etc/rc.local
            state: touch
            mode: '0755'

        - name: Set content in rc.local
          copy:
            dest: /etc/rc.local
            content: |
              #!/bin/sh -e
              #
              # rc.local
              #
              # This script is executed at the end of each multiuser runlevel.
              # value on error.
              #
              # In order to enable or disable this script just change the execution
              # bits.
              #
              # By default this script does nothing.
              iptables -I INPUT 1 -m set --match-set crowdsec-blacklists src -j DROP
              ip6tables -I INPUT 1 -m set --match-set crowdsec6-blacklists src -j DROP
            owner: root
            group: root
            mode: '0755'

    - name: Copy SSH public key for Git
      copy:
        content: "{{ secrets.public_ssh_key }}"  # Your public SSH key here
        dest: "/root/.ssh/id_ed25519.pub"
        mode: '0644'
        owner: root
        group: root

    - name: Copy SSH private key for Git
      copy:
        content: "{{ secrets.private_ssh_key }}"  # Your private SSH key here
        dest: "/root/.ssh/id_ed25519"
        mode: '0600'
        owner: root
        group: root

    - name: Clone private repository
      ansible.builtin.git:
        repo: 'git@github.com:your_user_name/scripts.git'
        dest: "/root/scripts"
        version: main  # or whatever branch you want
        key_file: "/root/.ssh/id_ed25519"
        accept_hostkey: true

    - name: Setup Kopia repository
      block:
        - name: Connect to Kopia repository
          shell: |
            kopia repository connect b2 --bucket={{ secrets.kopia_bucket_name }} --key-id={{ secrets.kopia_key_id }} --key={{ secrets.kopia_key }} --password={{ secrets.kopia_password }}
          environment:
            KOPIA_PASSWORD: "{{ secrets.kopia_password }}"
          args:
            executable: /bin/bash

        - name: Create Kopia snapshot policies
          shell: kopia policy set --global --keep-latest=10 --compression=zstd
          environment:
            KOPIA_PASSWORD: "{{ secrets.kopia_password }}"    

    - name: Copy root's crontab template
      become: true
      template:
        src: root_crontab.j2
        dest: /tmp/root_crontab
        owner: root
        group: root
        mode: '0600'

    - name: Apply the new crontab file for root
      become: true
      command: crontab -u root /tmp/root_crontab

  handlers:
  - name: restart samba
    ansible.builtin.service:
      name: smbd
      state: restarted       
```
{% endraw %}