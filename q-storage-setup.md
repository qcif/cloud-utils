q-storage-setup
===============

Setup a QRIScloud virtual machine instance to NFS mount a QRISdata Collection Storage allocation.

Synopsis
--------

    q-storage-setup.sh
        [ -a | --autofs] [ -m | --mount ] [ -u | --umount ]
        [ -d | --dir dirname]
        [ -f | --force yum|apt]
        [ -v | --verbose ] [ -h | --help ] storageID {storageID...}

Description
-----------

_Don't want to read all this (even though you really should)? Then jump
straight to the "Examples" section below._

This script simplifies the task of setting up _autofs_, or directly
mounting/unmounting, QRISdata Collection Storage allocations.  It
also automatically detects which NFS server the particular storageID
allocation is exported from, so the user does not need to be concerned
about those details. All the user needs to know is the storageID
(Qnnnn) of the allocation, and to have the permission to mount that
allocation.

This script operates in one of four modes. The mode is set by using one
of these options:

- `-a | --autofs` configure _autofs_ to automatically mount the storage.
  This is the default if none of the other mode options are specified.

- `-m | --mount` runs the _mount_ command to manually mount the storage.

- `-u | --umount` runs the _umount_ command to reverse the action of the _mount_ command.

- `-h | --help` shows help information.

Other options are:

- `-d --dir name` sets the directory containing the mount point. The
directory must be an absolute directory (i.e. starting with a
slash). Used in autofs, mount and unmount modes only. For mount and
unmount modes, the directory must already exist; the default of `/mnt`
is used if this option is not specified. For autofs mode, the default
of `/data` is used if this option is not specified.


- `-f | --force pkg` forces use of commands for the given package
manager type. This script has been tested with particular Linux
distributions that use the "apt" (e.g. Ubuntu and Debian), "dnf" or
"yum" package managers (e.g. CentOS and Fedora). It attempts to
automatically detect which package manager is being used.  If the
automatic detection fails and/or you want to take the risk of running
it on an untested distribution, force it to use the commands for a
particular package manager by using this option with `apt`, `dnf` or
`yum` as the argument.

- `-v | --verbose` show extra information.

The `storageID` must be one or more storage allocation names. These must be of
the form "Qnnnn" where _n_ is a digit (except for Q01, Q02, Q03 and
Q16, which only have two digits... for historical reasons).

**Note:** The first time this script is used, it might take a few minutes to
run. This is because it needs to download and install the dependent
packages. Use verbose mode to see an indication of progress as it is
running.

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
deleted and replaced with a new configuration. To keep existing
storageIDs, provide as arguments the current storageIDs as well as the
new ones: the script accepts multiple storageID arguments.

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

### Help mode

Prints a short help message.

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

**Note:** The first time this script is run, it can take a few minutes
to run. This is because it is downloading and installing the
NFS/autofs packages it requires. Please be patient.

### Ad hoc mounting and unmounting

Perform an _ad hoc_ mount before trying to setup autofs.

This step is optional, but recommended because if there is something
wrong (e.g. the allocation is not being properly exported) this should
print out an error message. The _autofs_ does not print out any error
messages, so if something is wrong _autofs_ will simply not work with
no indication of why it is not working.

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

Environment
-----------

This script must be run with root privileges.

You might want to update existing packages before running this
script. On YUM-based distributions, run "yum update". On APT-based
distributions, run "apt-get update".

Supported distributions
-----------------------

This script has been tested on the following distributions (as
installed from the NeCTAR official images):

- CentOS 6.7 x86_64
- CentOS 7.0 x86_64
- Debian 8 x86_64 (Jessie)
- Fedora 22 x86_64
- Fedora 23 x86_64
- Scientific Linux 6.7 x86_64 (Carbon)
- Ubuntu 15.10 (Wily) amd64
- Ubuntu 16.04 (Xenial) amd64

It should also work with NeCTAR images for previous versions of these
distributions too.

Files
-----

- `/etc/auto.qriscloud` - direct map file created with mount information.
- `/etc/auto.master` - configuration file for _autofs_.

Diagnosis
---------

### eth1 not found: not running on a QRIScloud virtual machine?

QRISdata Collection Storage allocations can only be NFS mounted from
virtual machine instances running in QRIScloud (i.e. the "QRIScloud"
NeCTAR availability zone).

The virtual machine is not running in QRIScloud, so it cannot mount
any QRISdata Collection Storage allocations. Use a virtual machine
instance in "QRIScloud" and run the script from there.

### error: autofs mount failed

The autofs was configured, but the mount does not work.

Try _ad hoc_ mounting the storage (i.e. without using autofs), and see
what error message appears:

    ./q-storage-setup.sh --mount Q...

The most common cause is the virtual machine instance has not been
given permission to mount that particular storage allocation. If that
is the case, see "mount.nfs: access denied by server while
mounting..." below.

Alternatively, use the logging feature of _autofs_:

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

This error is printed out when performing an _ad hoc_ mount and the
virtual machine instance does not have permission to mount the
particular storage allocation.

First, check the allocation storageID is correct; and the virtual
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

### warning: MTU for eth1 is not 9000 bytes

The Maximum Transmission Unit (MTU) for the network interface is not
set to 9000.  This problem usually occurs on Fedora images, which
don't seem to be setup to use the MTU information provided by DHCP.

The NFS mount will still work, but it will not work as fast as it could
if the MTU was set to 9000 (a.k.a. "jombo frames").

Explicitly set it by editing the network interface configuration file
(for RHEL systems, edit _/etc/sysconfig/network-scripts/ifcfg-eth1_;
for ubuntu systems, edit _/etc/network/interfaces_) and then restart
the interface for the changes to take effect (`ifdown eth1; ifup
eth1`).

Show the MTU for eth1:

    ip link show dev eth1

### Cannot ping NFS server

Check the second network interface (usually eth1) on the virtual
machine instance has been activated and has been assigned a 10.255.x.x
IP address.

    ip -f inet addr

If it does not have an IP address, check the network interface
configuration files or run the DHCP client:

    sudo dhclient eth1

This script should have automatically set up the second network
interface, but obviously that failed: please report this as a bug.

### warning: NetworkManager installed, consider uninstalling it

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

Contact
-------

Please send feedback and queries to Hoylen Sue at <h.sue@qcif.edu.au>.
