q-image-create
==============

Utility to help create virtual machine image for NeCTAR.

Synopsis
--------

    q-image-create.sh

Description
-----------

This script runs the qemu-kvm emmulator and glance client program with
parameters for creating virtual machine images for use on the
[NeCTAR](http://www.nectar.org.au) deployment of OpenStack.



Usage: q-image-create [options] commandArguments
Commands:

 -c | --create disc.iso disk.img

Create a new disk image and boot off the ISO.

  -r | --run disk.img

Run the disk image.

  -u | --upload disk.img [imageName] (default name: "Test image ...")

Upload a disk image to OpenStack glance.

Create options:
  -s | --size numBytes   size of disk to create (default: 10G)
  -f | --format fmt      disk image format to save to (default: qcow2)

Create or run options:
  -d | --display num     VNC server display (default: 0)
  -D | --disk-type intf  virtual QEMU disk interface (default: virtio)
  -e | --extra-opts str  extra options to pass to QEMU

Upload options:
  -O | --os-type value   set os_type property for image (e.g. "windows")

Common options:
  -h | --help            show this help message
  -v | --verbose         show extra information




Examples
--------

Guides are available to show the use of this script for creating
images for:

- [CentOS 6.5](image-centos.md)
- [Windows Server 2012 R2](image-win2012r2.md)

Requirements
------------

Creation host system requires QEMU KVM and the OpenStack glance client.

On systems using YUM:

    # yum install qemu-kvm
    # yum install python-glanceclient

On systems using apt-get:

    # apt-get install qemu-kvm cloud-utils
    # apt-get install glance


Examples
--------

- [Creating an image for CentOS 6.5](image-centos.md)
- [Creating an image for Windows Server 2012 R25](image-win2012r2.md)

Environment
-----------

This script is has been tested on CentOS 6.5 and Ubuntu.

Some commands of this script must be run with root privileges.


Files
-----


Diagnosis
---------

### Program not found: glance

The OpenStack glance client has not been installed. Install it.

### MP-BIOS bug: 8254 timer not connected

The guest operating system does not support APIC.  Inform QEMU to use
"noapic" option when booting.  Add `--extra-opts "--noapic"` when
using the create or run commands.

#####  Cannot set up guest memory 'pc.ram': Cannot allocate memory

The RAM size for the guest is too large for the host. Use a creation
host system with more memory. Alternatively, edit the script and
reduce the RAM_SIZE variable.

See also
--------

- [OpenStack Virtual Machine Image Guide](http://docs.openstack.org/image-guide/content/ch_preface.html)

Bugs
----

Contact
-------

Please send feedback and queries to Hoylen Sue at <h.sue@qcif.edu.au>.
