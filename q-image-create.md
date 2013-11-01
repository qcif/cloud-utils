q-image-create
==============

Utility to help create virtual machine image for NeCTAR.

**Note: This script (and this documentation) is currently under development.**

Synopsis
--------

    q-image-create.sh
	
Description
-----------



Examples
--------

This example walks through the process of creating a virtual machine
instance on a creation host that is running on a NeCTAR VM instance.
A physical machine (or a non-NeCTAR virtual machine) can also be used
as the creation host.

### Setup host and get necessary files

Create the creation host NeCTAR VM instance to run Ubuntu Linux. This
example uses the "NeCTAR Ubuntu 13.04 (Raring) amd64 UEC" image. This
creation host must have 8GiB of memory or more, since the guest
running inside the host will be allocated 4GiB of memory.

Login into the creation host and create a ssh tunnel from a local port
(in this example 6900 is used) to the VNC port (5900) on the remote machine:

    $ ssh -L 6900:localhost:5900 ubuntu@creation.host

Create a working area on the ephemeral disk. The default home
directory is on the boot disk (which is 10GiB in size), so it is not
big enough to hold the created image (which will also be 10GiB in
size) plus working files.

    $ sudo mkdir /mnt/genesis
	$ sudo chown ubuntu /mnt/genesis
	$ sudo chgrp ubuntu /mnt/genesis
	$ cd /mnt/genesis

Obtain a copy of the script.

    $ curl -O https://raw.github.com/qcif/cloud-utils/master/q-image-create.sh
	$ chmod a+x q-image-create.sh

Obtain a copy of the ISO image to install.

    $ curl -L -O http://download.fedoraproject.org/.../Fedora-19-x86_64-DVD.iso

### Phase 1: install from ISO to drive

Run a guest virtual machine by booting off the install ISO image and
create a new disk image to install onto. The following command will
start the guest virtual machine and set VNC to have an empty
password. It will stay running, with the qemu console ready to accept
a command.

    $ ./q-image-create.sh --install Fedora-19-x86_64-DVD.iso disk.img

Connect to the VNC server (through the ssh tunnel). If the local
machine is a Macintosh, a VNC client can be started by running (in a
different shell; not in the qemu console):

    localhost$ open vnc://localhost:6900

The VNC password is empty, just press return when prompted for it.

Install the operating system normally, using the entire 10GiB drive
for one partition that mounts on "/".  Select "custom disk
partitioning" or similar option to do this, because the default
automatic partition will create an unwanted swap partition.  Ignore
any warnings about not having a swap partition.

When the installation has finished (i.e. after shutting down the guest
virtual machine), close the VNC client then stop the guest virtual
machine by typing "quit" into the qemu console.

    (qemu) quit

### Phase 2: run from drive to configure

Run a guest virtual machine by booting off the disk image. The
following command will start the guest virtual machine and set VNC to
have an empty password.

    $ ./q-image-create.sh --run disk.img
	
As before, connect to the VNC server (through the ssh tunnel) with an
empty password.

    localhost$ open vnc://localhost:6900

Perform any necessary software installation and configurations necessary
to create the image. This will depend on the operating system and
purpose of the image, but the following are the recommended
minimum configurations.

#### Update the operating system

Install security patches and updates.

    guest$ sudo yum update

#### Change disk image name


#### Remove ssh server key





### Phase 3: extract partition from the disk image

    $ ./q-image-create.sh --extract disk.img part.img
	
### Phase 4: mount and umount

    $ ./q-image-create.sh --mount part.img
	
Modify files and directories on the file system as needed.

    $ ./q-image-create.sh --umount part.img
	
### Phase 5: upload

    $ ./q-image-create.sh --upload part.img

### Use the image

Log into the NecTAR Dashboard.

Environment
-----------

This script is designed to run on Ubuntu.

This script must be run with root privileges.


Files
-----


Diagnosis
---------

### MP-BIOS bug: 8254 timer not connected

The workaround is to use "noapic" option when booting.

See also
--------

Bugs
----

Contact
-------

Please send feedback and queries to Hoylen Sue at <h.sue@qcif.edu.au>.
