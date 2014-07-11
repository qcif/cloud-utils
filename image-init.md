Creation host on NeCTAR
=======================

This document describes how to create a NeCTAR virtual machine
instance to act as the creation host system for creating images.

Process
-------

### Step 1: Instantiate VM instance for the host system

Instantiate a virtual machine instance to use as the creation host.

- A medium flavour or larger VM instance is recommended.  These
  instructions with work on a small flavour VM instance, but the small
  30 GiB ephemeral disk can be limiting, since space is required to
  store ISO images and the images being created.

- Configure the security groups to allow ssh access to the host system.

- Choose an availability zone with high performance. Although the
  NeCTAR Melbourne availability zone is physically close to the glance
  image store, the benefits of performance during the creation of the
  image is much more signficant then speed of upload the image.

### Step 2: Install necessary packages

To run the create the image, QEMU is needed. To upload the image the
glance client is needed.

Login to the creation host system and run these commands:

    [local]$ ssh ec2-user@creation.host.system

    [ec2-user@host] sudo yum update
    [ec2-user@host] sudo yum install qemu-kvm
    [ec2-user@host] sudo yum install python-glanceclient

If using a Ubuntu creation host system, use _apt-get_ instead of _yum_.

### Step 3: Create a user account on the creation host

Any user account can be used to create the image, but in this example
a separate "creator" account will be created for it.

    [ec2-user@host]$ sudo adduser creator

On Ubuntu's version of _adduser_, include the `--disabled-password`
option.

Create a working area for the user on the ephemeral disk (mounted on
_/mnt_ by default). The user's home directory is on the boot disk
(which is 10GiB in size), so it is usually not big enough to hold
necessary files.

    [ec2-user@host]$ sudo mkdir /mnt/creator
    [ec2-user@host]$ sudo chown creator:creator /mnt/creator

And set up access to the creator account. Normally, this can be done
by setting up their SSH public key.

    [ec2-user@host]$ sudo mkdir /home/creator/.ssh
    [ec2-user@host]$ sudoedit /home/creator/.ssh/authorized_keys
      # Add the ssh public key the local system will use to login
    [ec2-user@host]$ sudo chown -R creator:creator /home/creator/.ssh

Log out of the creation system.

    [ec2-user@host]$ exit

See also
--------

- [Creating an image for CentOS 6.5](image-linux.md)
- [Creating an image for Windows Server 2012 R2](image-windows.md)