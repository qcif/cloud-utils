QRIScloud utilities
===================

Utilities for working with the QRIScloud virtual machine instances and
data storage.

[QRIScloud](https://www.qriscloud.org.au) is a set of services
provided by the _Queensland Cyber Infrastructure Foundation_
([QCIF](http://www.qcif.edu.au)).

Scripts
-------

### NFS mounting QRISdata Collection Storage allocations

The [q-storage-setup](q-storage-setup.md) script can be used
to setup a mount to access a QRISdata Collection Storage allocation
using NFS.

Note: the allocation must be enabled for NFS access and the
virtual machine instance must be running in Nectar's _QRIScloud_
availability zone.

### Creating OpenStack images for Nectar

The [q-image-maker](openstack-images/q-image-maker.md) script can
assist with the process of creating a virtual machine images
for Nectar.

For example, if you want to instantiate a virtual machine instance
with a different operating system: one that someone else has not
created a Nectar image for you to use.

It has been used to create Linux and Windows images.

See the [openstack-images](../../tree/master/openstack-images) folder
for details.

Licence
-------

These scripts are distributed in the hope that they will be useful,
but **without any warranty**; without even the implied warranty of
**merchantability** or **fitness for a particular purpose**.  See the
GNU General Public License for more details.

Contact
-------

Please send feedback and queries to QRIScloud Support
<https://support.qriscloud.org.au/>.
