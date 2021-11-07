QRIScloud utilities
===================

Utilities for working with the QRIScloud collection storage.

[QRIScloud](https://www.qriscloud.org.au) is a set of services
provided by the _Queensland Cyber Infrastructure Foundation_
([QCIF](https://www.qcif.edu.au)).

Scripts
-------

### NFS mounting QRISdata Collection Storage allocations

The [q-storage-setup](q-storage-setup.md) utility can be used
to setup a mount to access a QRISdata Collection Storage allocation
using NFS.

Note: the allocation must be enabled for NFS access and the
virtual machine instance must be running in Nectar's _QRIScloud_
availability zone.

Other utilities
---------------

The OpenStack image utility (previously called _q-image-maker_) has
been moved into its own
[openstack-image-maker](https://github.com/qcif/openstack-image-maker)
repository.

Licence
-------

This utility is distributed in the hope that they will be useful, but
**without any warranty**; without even the implied warranty of
**merchantability** or **fitness for a particular purpose**.  See the
GNU General Public License for more details.

Contact
-------

Please submit issues using the repository's [GitHub
issues](https://github.com/qcif/openstack-image-maker/issues)

For questions about QRIScloud storage, please contact [QRIScloud
Support](https://support.qriscloud.org.au/).
