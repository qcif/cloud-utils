Creation host on Nectar
=======================

This document describes how to create a Nectar virtual machine
instance to act as the creation host system for creating images.

Process
-------

### Step 1: Instantiate VM instance for the host system

Instantiate a virtual machine instance to use as the creation host.
And configure the security groups to allow _ssh_ acccess to the instance.

While the Nectar Melbourne Availability Zone is physically closest to
the Glance image store, the instance can be launched in any
Availability Zone.

The most critical factor is having enough disk space.  If the VM
instance does not have enough disk space, attaching Volume Storage to
it can be an option (if your project has access to it). It needs to
have enough space for the ISO files, the image file that will be
created, the operating system and software.


The second most critical factor is performance. The virtual machine
instance that will be run by QEMU will be configured to have 2 vCPUs
and 4 GiB of RAM (though this can be changed by editing the
script). Therefore, the creation host needs to be larger than that.

### Step 2: Install necessary packages

The QEMU hypervisor is needed to create the image, and the OpenStack
client (in particular the _glance_ component) is needed to upload the
image.

Login to the creation host system and install those packages.  The
following commands are for CentOS 7, different commands will be needed
for other distributions:

CentOS 7:

    [local]$ ssh ec2-user@creation.host.system

    [ec2-user@host] sudo yum update -y

    [ec2-user@host] sudo yum install -y qemu-kvm

    [ec2-user@host]$ sudo yum install -y python3
    [ec2-user@host]$ sudo pip3 install --upgrade pip

    [ec2-user@host]$ sudo pip3 install python-openstackclient

Ubuntu 20.04:

    [local]$ ssh ec2-user@creation.host.system

    [ubuntu@host]$ sudo apt-get -y update

    [ubuntu@host]$ sudo apt-get -y install -y qemu-kvm

    [ubuntu@host]$ sudo apt-get -y install python3-pip
    [ubuntu@host]$ sudo pip3 install --upgrade pip
    # Log out and log back in to use the new version

    [ubuntu@host]$ sudo pip3 install python-openstackclient

### Step 3: Create a user account on the creation host

Any user account can be used to create the image, but in this example
a separate "creator" account will be created for it.

    [ec2-user@host]$ sudo adduser creator

On Ubuntu's version of _adduser_, include the `--disabled-password`
option.

Identify a working directory to store the files. The volume it is on
must have enough available space to store the ISO and image files
(e.g. 20 GiB free).

    [ec2-user@host]$ sudo mkdir /mnt/creator
    [ec2-user@host]$ sudo chown creator:creator /mnt/creator

Finally set up access to the creator account. Normally, this can be done
by adding your SSH public key to it.

    [ec2-user@host]$ sudo mkdir /home/creator/.ssh
    [ec2-user@host]$ sudo cp ~/.ssh/authorized_keys /home/creator/.ssh/authorized_keys
    [ec2-user@host]$ sudo chown -R creator:creator /home/creator/.ssh

Log out of the creation host.

    [ec2-user@host]$ exit

See also
--------

- [Creating an image for CentOS Stream 8](image-linux.md)
- [Creating an image for Windows Server 2012 R2](image-windows.md)
