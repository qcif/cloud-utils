q-storage-setup
===============

Setup a QRIScloud virtual machine instance to NFS mount a QRISdata Collection Storage allocation.

Synopsis
--------

    q-storage-setup.sh
        [ -a | --autofs] [ -m | --mount ] [ -u | --umount ]
        [ -r | --read-only]
        [ -d | --dir dirname]
        [ -v | --verbose ]
        [ -V | --version ]
        [ -h | --help ] allocSpec {allocSpec...}

Description
-----------

_Don't want to read all this (even though you really should)? Then jump
to the "Examples" section below._

This script simplifies the task of setting up _autofs_, or directly
mounting/unmounting, QRISdata Collection Storage allocations (both
allocations with _frequent access_ and _MeDiCI_ storage).  Allocations
can be specified by the NFS path or by the allocation's Q-number. If a
Q-number is provided, the script automatically determines the NFS path
to use.

This script operates in one of three modes. The mode is set by using one
of these options:

- `-a | --autofs` configure _autofs_ to automatically mount the storage.
  This is the default if none of the other mode options are specified.

- `-m | --mount` runs the _mount_ command to manually mount the storage.

- `-u | --umount` runs the _umount_ command to reverse the action of the _mount_ command.

Other options are:

- `-r | --read-only` mount in read-only mode, instead of the default
of read-write mode.

- `-d | --dir name` sets the directory containing the mount point. The
directory must be an absolute directory (i.e. starting with a
slash). In the mount and unmount modes, the directory must already
exist; the default of `/mnt` is used if this option is not
specified. In the autofs mode, the default of `/data` is used if this
option is not specified.

- `-h | --help` shows help information.

- `-V | --version` shows the scripts version number.

- `-v | --verbose` show extra information.

The `allocSpec` is a storage allocation Q-number or NFS path. A
Q-number is the leter "Q" followed by four digits (e.g. "Q0039").  The
NFS path for an allocation can be found on the QRIScloud Services
Portal, listed under the allocation in the "My Services" section
(e.g. "10.255.120.200:/tier2d1/Q0039/Q0039").

**Note:** The first time this script is used, it might take a few minutes to
run. This is because it needs to download and install the dependent
packages.

### Configure autofs mode

This mode configures _autofs_ to NFS mount the specified storage. Use
this mode to setup the storage for production use.  The _autofs_
mounts will be re-established if the operating system is rebooted. As
with normal _autofs_ behaviour, the mounts will be established when an
attempt is made to access it.

If necessary, it also installs the necessary packages and configures the
private network interface. Groups and users are also created.

It is recommended that the mounting is tested using the ad hoc mount
mode (see below) before setting up _autofs_. Errors are easier to
detect in mount mode, because _autofs_ silently fails if errors are
encountered.

Note: previous autofs configurations created by this script will be
deleted and replaced with a new configuration. To keep mounting
existing allocations, provide as arguments the current allocations as
well as the new ones: the script accepts multiple allocation
specification arguments.

### Mount mode

This mode runs an _ad hoc_ mount command to NFS mount the specified
storage. Use this mode to test whether storage can be successfully
mounted.

An _ad hoc_ mount does not survive reboots. Only use it for testing,
before using _autofs_ to create mounts that will survive reboots.

If necessary, it also installs the necessary packages and configures the
private network interface. Groups and users are also created.

Undo the mounts created by the mount mode using the unmount mode (see below).

### Unmount mode

This mode unmounts _ad hoc_ mounted storage. Use this mode to
reverse the actions of the mount mode (see above).

Examples
--------

### Obtaining the script

The easiest way to obtain the latest copy of the script is
to download it directly from GitHub:

    $ curl -O https://raw.githubusercontent.com/qcif/cloud-utils/master/q-storage-setup.sh
    $ chmod a+x q-storage-setup.sh

The URL being downloaded is the _raw_ file from GitHub, which can
change when GitHub reorganises their service. If the URL does not
work, go to [this project](https://github.com/qcif/cloud-utils) on
GitHub and locate the raw link to the _q-storage-setup.sh_ file.

The "-O" (capital-o) option tells _curl_ to save the response to a file
with the same name as the remote file.

**Note:** The first time this script is run, it can take a few minutes
to run. This is because it is downloading and installing the
NFS/autofs packages it requires. Please be patient.

### Ad hoc mounting and unmounting

Perform an _ad hoc_ mount before trying to setup autofs.

This step is optional, but recommended because if there is something
wrong (e.g. the allocation is not being properly exported) this should
print out an error message. The _ad hoc_ mount is different from the
_autofs_ mount, because by default _autofs_ does not print out any
error messages: so if something is wrong _autofs_ will simply not work
with no indication of why it is not working.

Mount storage allocation, examine its contents and unmount it. Since
the script reqires root privileges, the _sudo_ command is used. This
example uses Q0039: change it to your allocation (otherwise it
definitely won't work).

    $ sudo ./q-storage-setup.sh --mount Q0039
    $ sudo ls /mnt/Q0039
    $ sudo ./q-storage-setup.sh --umount Q0039

Remember, the first execution of the script might take a few minutes
to run. This is because it needs to download and install the dependent
packages. Don't panic if it runs for a few minutes without printing
anything out. Add the "--verbose" option to see its progress (or if
a blank screen makes you nervious).

The _ls_ command is to check if the mount worked. It needs to be run
with _sudo_ because the directory is owned by the user created for
that allocation (the "q39" user in this example).

Remove the _ad hoc_ mount with the `--umount` option. Note: following
Unix tradition, it is called "umount" and not "unmount".

### Configure autofs

This is how to setup autofs:

    $ sudo ./q-storage-setup.sh Q0039

Check if it is working by examining the mounted storage:

    $ sudo ls /data/Q0039

As an autofs mount, this will be available if the machine is
rebooted. It might get automatically unmounted if it has not been used
for a while, so don't be surprised if it does not appear under
"/data". But it will automatically get re-mounted when it is accessed.

If there are multiple allocations to mount, specify them all.
For example:

    $ sudo ./q-storage-setup Q0039 Q0224

Environment
-----------

This script must be run with root privileges.

You should update existing packages before running this
script. On YUM-based distributions, run "yum update". On APT-based
distributions, run "apt-get update".

Supported distributions
-----------------------

This script has been tested on the following official Nectar images
(as released on 11 May 2018):

- CentOS 6.7
- CentOS 7.0
- Debian 7 (Wheezy)
- Debian 8 (Jessie)
- Debian 9 (Stretch)
- Fedora 26
- Scientific Linux 6.8 (Carbon)
- Ubuntu 14.04 (Trusty)
- Ubuntu 16.04 (Xenial)
- Ubuntu 17.10 (Artful)
- Ubuntu 18.04 (Bionic)

The script does not work on the following Nectar official image:

- openSUSE Leap 42.3

This script is provided on an as-is basis. There is no guarantee it
will work on any platform. In the face of changes/updates, there is
also no guarantee it will continue to work on platforms where it
had previously worked.

Files
-----

- `/etc/auto.qriscloud` - direct map file created with mount information.
- `/etc/auto.master` - configuration file for _autofs_.
- `/tmp/q-storage-setup.sh-*.log` - log file, not deleted if an error occurs.

Diagnosis
---------

### Check version

If the script was downloaded a long time ago, please check (on GitHub)
whether a newer version of the script exists. Use the newer version if
one exists.

    ./q-storage-setup.sh --version

### eth1 not found: not running on a QRIScloud virtual machine?

QRISdata Collection Storage allocations can **only** be NFS mounted from
virtual machine instances running in QRIScloud (i.e. the "QRIScloud"
NeCTAR availability zone).

The virtual machine is not running in QRIScloud, so it cannot mount
any QRISdata Collection Storage allocations. Use a virtual machine
instance in "QRIScloud" and run the script from there.

### error: autofs configured, but didn't mount

The autofs was successfully configured, but the mount does not work.

This can happen if the NFS server is heavily loaded. It is a shared
resource and other users might be putting a heavy load on the server.
Try again at a later time.

If the script was invoked with the NFS mount path (instead of just the
Q-number) for the allocation, there could be a problem with the NFS
mount path. Check if the value is correct and that the virtual machine
is running in the correct Nectar project. If the script was invoked
with the Q-number, it looks up the NFS mount path so it is unlikely to
be incorrect.

### Diagnosing problems with autofs

By default, _autofs_ error message are suppressed, which makes
diagnosing problems difficult.

To see error messages, try _ad hoc_ mounting the storage (i.e. without
using autofs):

    ./q-storage-setup.sh --mount ...

Alternatively, enable the logging feature of _autofs_:

1. Add `OPTIONS="--debug"` to the _/etc/sysconfig/autofs_ file.
2. Restart _autofs_.
3. Attempt to access the mounted directory (e.g. ls /data/Q....).
4. Examine the logs.

On a system that uses _init.d_:

    sudoedit /etc/sysconfig/autofs
    sudo service autofs restart
    sudo ls /data/Q????
    less /var/log/messages

On a system that uses _systemd_:

    sudoedit /etc/sysconfig/autofs
    sudo systemctl restart autofs.service
    sudo ls /data/Q????
    sudo journalctl -u autofs

Afterwards, remove the debug option.

### Cannot access /data/Q...: no such file or directory

Encountered when trying to access the autofs mounted directory, even
though the directory appears listed under "/data".

Try ad hoc mounting the storage (i.e. without using autofs), and see
what error message appears:

    ./q-storage-setup.sh --mount Q...

The most common cause is the virtual machine instance has not been
given permission to NFS mount that particular storage allocation.  If
that is the case, see "mount.nfs: access denied by server while
mounting..." below.

### mount.nfs: access denied by server while mounting...

This error occurs when the virtual machine instance does not have
permission to mount the particular storage allocation.

First, check the allocation specification is correct; and the virtual
machine is running in the correct NeCTAR project.

Secondly, if the VM instance was instantiated less than 5 minutes ago,
the permissions might not have been applied to it. Wait up to 5
minutes and try again.

If it still doesn't work, please contact QRIScloud support.  If you
can, please identify the support ticket where you asked for NFS
mounting permissions to be setup for that NeCTAR project and storage
allocation.

### Package 'nfs-common' has no installation candidate

The _apt-get_ package manager has not been properly configured.
Update it:

    sudo apt-get update

### dhclient(...) is already running - exiting

This error occurs on the Fedora images.

Just re-run the script a second time, with the same parameters, and it
should work.

### error: eth1: MTU != 9000

The Maximum Transmission Unit (MTU) for the network interface is not
set to 9000. This reduces the performance of the NFS mount.

The MTU for eth1 can be shown using:

    ip link show dev eth1

Please contact QRIScloud support, because this problem indicates
something has changed in OpenStack or the Nectar images and the script
needs to be updated.


### Cannot ping NFS server

Cannot contact one or more of the NFS servers. This might be because
that NFS server is down or it is heavily loaded.

### NetworkManager

NetworkManager is a daemon that dynamically configures the network
interfaces.  It is useful for environments where the network
configuration changes (e.g. wi-fi networks that comes and goes), but
not so useful for staic environments (such as NeCTAR VM instances). In
the past, NetworkManager has been the cause of seemingly-random
network changes, which breaks the network connectivity of the VM.

Consider uninstalling NetworkManager, if you don't need it.

    sudo rpm -e NetworkManager

If you experience problems with the network connections, treat
NetworkManager as your primary suspect!

See also
--------

QCIF knowledge base article on [NFS mounting collection storage for
Linux](https://qriscloud.zendesk.com/hc/en-us/articles/200106199-NFS-mounting-collection-storage-in-Linux).

Bugs
----

On RHEL platforms, the "nolock" option is always set when mounting
(via autofs or the mount mode). This allows the script to run
successfully on some platforms where the support services for locking
has not been set up properly, but means those platforms where the
support services are working cannot make use of locking.

The unmount mode does not delete any of the user accounts or groups
created by the mount mode.

This script cannot remove all the mounts it creates. While it can
change the mounts to a new set of one or more storage allocation
names, that new set cannot be empty.  Removing all mounts can be done
manually: editing the _/etc/auto.master_ file, optionally deleting the
_/etc/auto.qriscloud_ file, and restarting _autofs_ (by running `service
autofs restart`).

Ad hoc mounts are created by default under _/mnt_, which is the
ephemeral disk on NeCTAR VM instances. Use the `--dir` option to
specify a different location.

Knowm limitation: if the read-only option is used and there are
multiple allocations specified, it is applied to all of them.
This is not a problem if only one allocation is specified.

Contact
-------

Please send feedback and queries to Hoylen Sue at <h.sue@qcif.edu.au>
or raise a ticket with [QRIScloud Support](https://www.qriscloud.org.au/support).
