q-image-maker
=============

Utility to help make virtual machine image for use on Openstack.

Synopsis
--------

    q-image-maker.sh command [options] diskImage

Description
-----------

This script runs the qemu-kvm emmulator to allow an operating system
and other software to be installed onto a disk image file.  Then it
can be used to upload that disk image file into OpenStack as an image.

While the QEMU and OpenStack can be used directly, this script makes
the image creation and uploading process easier, by invoking them with
the necessary options.

Usage: q-image-maker.sh [create|run|upload] [options] diskImage

Available commands:

- `create` to create a new disk image file and run the QEMU emulator on it,
  booting off an ISO image so an operating system can be installed onto the
  disk image.

- `run` to run the QEMU emulator on an existing disk image file. Used
  to perform further changes on the disk image, if they were not done
  when the image was created.

- `upload` to upload a disk image file to Openstack as an image.

Create options:
  -s | --size numBytes   size of disk to create (default: 10G)
  -f | --format fmt      disk image format to save to (default: qcow2)

Create or run options:
  -d | --display num     VNC server display (default: 0)
  -D | --disk-type intf  virtual QEMU disk interface (default: virtio)
  -e | --extra-opts str  extra options to pass to QEMU
  -a | --agent           include interface for a VirtIO Serial Driver

Upload options:
  -l | --linux           set os_type property for uploaded image to linux
  -w | --windows         set os_type property for uploaded image to windows
  -a | --agent           set metadata for QEMU Guest Agent

Common options:
  -v | --verbose         output extra information when running
  -V | --version         display version information and exit
  -h | --help            display this help and exit


Note: when uploading, it is mandatory to specified either --linux or --windows.

Examples
--------

Guides are available to show the use of this script for creating
images for:

- [Linux](README-linux.md)
- [Windows](README-windows.md)

Requirements
------------

Creation host system requires QEMU KVM and the OpenStack client.

On CentOS 7:

    # yum install -y qemu-kvm

    # yum install -y python3
    # pip3 install --upgrade pip

    # pip3 install python-openstackclient

On systems using _apt-get_:

    # apt-get -y install -y qemu-kvm

    # apt-get -y install python3-pip
    # pip3 install --upgrade pip
    # Log out and log back in to use the new version

    # pip3 install python-openstackclient


Environment
-----------

This script has been tested on CentOS 7 and Ubuntu 20.04.

Diagnosis
---------

### qemu-kvm: Failed to start VNC server on ...: Failed to bind to socket: Address already in use

Another guest virtual machine is already running. Its VNC is alrady
using the port.

One solution is to run the new guest virtual machine on a different
port, using the `--display` option to change the VNC server display
number.

But it is better to stop the other guest virtual machine. Since
performance is likely to be reduced by having multiple guest virtual
machines running at the same time.

### MP-BIOS bug: 8254 timer not connected

The guest operating system does not support APIC.  Inform QEMU to use
"noapic" option when booting.  Add `--extra-opts "--noapic"` when
using the create or run commands.

#####  Cannot set up guest memory 'pc.ram': Cannot allocate memory

The RAM size for the guest is too large for the host.

1. Check if there is not another guest virtual machine running. Stop
   that other virtual machine before trying to run a new one.

2. Decrease the amount of memory assigned to the guest virtual machine
   using the `--ram` option. Use the help option to see the default
   amount.

3. Use a different creation host that has more memory.

### qemu-img: Unable to initialize gcrypt

An older version of _libcrypt_ is installed. Usually seen on CentOS 8.

Update it. For example, run `yum update`.

### warning: virtual machine will be slow

> Warning: virtual machine will be slow: no virtualization, using
> emulation: CPU has no virtualization extension support

The host system does not have virtualization support, or it has not
been enabled.

See also
--------

- [OpenStack Virtual Machine Image Guide](http://docs.openstack.org/image-guide/content/ch_preface.html)

Bugs
----

Contact
-------

Please send feedback and queries to Hoylen Sue at <hoylen.sue@qcif.edu.au>.
