q-storage-setup
===============

Setup a QRIScloud virtual machine instance to NFS mount QRIScloud storage.

Synopsis
--------

    q-storage-setup.sh
        [ -a | --autofs] [ -m | --mount ] [ -u | --umount ]
        [ -d | --dir dirname] [ -f | --force flavour]
        [ -s | --stage name]
        [ -v | --verbose ] [ -h | --help ] storageID {storageID...}

Description
-----------

This script operates in one of four modes. The mode is set by using one
of these options:

- `-a | --autofs` configure _autofs_ to automatically mount the storage.

- `-m | --mount` runs the mount command to manually mount the storage.

- `-u | --umount` runs the umount command to reverse the action of the mount command.

- `-h | --help` shows help information.

Other options are:

- `-d --dir name` sets the directory containing the mount point. The
directory must be an absolute directory (i.e. starting with a
slash). Used in autofs, mount and unmount modes only. For mount and
unmount modes, the directory must already exist; the default of `/mnt`
is used if this option is not specified. For autofs mode, the default
of `/data` is used if this option is not specified.


- `-f | --force flavour` forces use of commands for a given flavour of
operating system.  This script has been tested with particular
versions of _Red Hat Enterprise Linux_ or _Ubuntu_ based Linux
distributions. It attempts to automatically detects if it is running
on a tested Linux distribution. If the automatic detection fails or
you want to take the risk of running it on an untested distribution,
force it to use the commands for a particular distribution by using
this option with `RHEL` or `ubuntu` as the argument.

- `-s | --stage facility` sets the facility being used. The
facility must either be "stage1" or "stage2". This option is normally
not needed, since this script will try to automatically detect which
stage it is running on (by examining the localhost's IP address).  It
is only needed if that automatic detection does not work
properly. Note: both the compute (i.e. the VM instance this script is
run on) and the storage allocation must be in the same facility. You
cannot NFS mount storage allocations from a different facility.

- `-v | --verbose` show extra information.

The `storageID` must be one or more storage allocation names. These must be of
the form "Qnnnn" where _n_ is a digit (except for Q01, Q02, Q03 and
Q16, which only have two digits).

The first time this script is used, it might take a few minutes to
run. This is because it needs to download and install the dependent
packages. Use verbose mode to see an indication of progress as it is
running.

### Configure autofs mode

This mode configures _autofs_ to NFS mount the specified storage. Use
this mode to setup the storage for production use.  The mounts will be
re-established if the operating system is rebooted.

If necessary, it also installs the necessary packages and configures the
private network interface. Groups and users are also created.

It is recommended that the mounting is tested using the ad hoc mount
mode (see below) before setting up _autofs_. Errors are easier to
detect in mount mode, because _autofs_ silently fails if errors are
encountered.

### Mount mode

This mode runs an _ad hoc_ mount command to NFS mount the specified
storage. Use this mode to test whether storage can be successfully
mounted.

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

Note: the URL being downloaded is the _raw_ file from GitHub, which
can change when GitHub reorganises their service. If the URL does not
work, go to this project on GitHub and locate the raw link to the
q-storage-setup.sh file.

### Ad hoc testing

Mount storage allocation Q0039, examine its contents and unmount it. Since the
script reqires root privileges, the _sudo_ command is used.

    $ sudo ./q-storage-setup.sh --mount Q0039
    $ sudo ls /mnt/Q0039
    $ sudo ./q-storage-setup.sh --umount Q0039

Remember, the first execution of the script might take a few minutes
to run. This is because it needs to download and install the dependent
packages. Don't panic if it runs for a few minutes without printing
anything out. Add the "--verbose" option to see its progress.

### Configure autofs

Configure autofs and examine its contents.

    $ sudo ./q-storage-setup.sh Q0039
    $ sudo ls /data/Q0039


Environment
-----------

This script must be run with root privileges.

You might want to update existing packages before running this
script. In RHEL, run "yum update". In Ubuntu, run "apt-get update".

Supported distributions
-----------------------

This script has been tested on the following distributions (as
installed from the NeCTAR official images):

- CentOS 6.4 x86_64
- CentOS 6.5 x86_64
- Fedora 19 x86_64
- Fedora 20 x86_64
- Scientific Linux 6.4 x86_64
- Scientific Linux 6.5 x86_64
- Ubuntu 12.10 (Quantal) amd64
- Ubuntu 13.10 (Saucy) amd64
- Ubuntu 14.04 (Trusty) amd64
- Debian 6 x86_64 (Squeeze)
- Debian 7 x86_64 (Wheezy)

Files
-----

- `/etc/auto.qriscloud` - direct map file created with mount information.
- `/etc/auto.master` - configuration file for _autofs_.

Diagnosis
---------

### Interface eth1 not found: not running on QRIScloud?

QRIScloud storage allocations can only be NFS mounted from virtual
machine instances running in QRIScloud (i.e. either on the stage 1
"qld" or stage 2 "QRIScloud" availability zone). The current system is
not running on the Queensland node.

### Cannot access /data/Q...: no such file or directory

See "mount.nfs: access denied by server while mounting" below.

### mount.nfs: access denied by server while mounting...

The most common cause is the virtual machine instance has not been
given permission to mount that particular storage allocation. Please
contact QCIF support.

Try to manually mount the storage (using the `--mount` option) and see
if there are any error messages.

Alternatively add `OPTIONS="--debug"` to the _/etc/sysconfig/autofs_
file, restart _autofs_ (`sudo service autofs restart`), attempt to
access the mounted directory and then examine _/var/log/messages_.

If the VM instance was instantiated less than 5 minutes ago, the
permissions might not have been applied to it. Wait less than 5
minutes and try again.

### Package '...' has no installation candidate

The _apt-get_ package manager has not been properly configured.
Update it:

    sudo apt-get update

### dhclient(...) is already running - exiting

This error occurs on the Fedora images.

Just re-run the script a second time, with the same parameters, and it
should work.

### warning: DHCP did not set eth1 MTU to 9000 bytes

The network interface did not set the MTU size from the information
provided by the DHCP server. This occurs on the Fedora images.

Explicitly set it by editing the network interface configuration file
(for RHEL systems, edit _/etc/sysconfig/network-scripts/ifcfg-eth1_;
for ubuntu systems, edit _/etc/network/interfaces_) and restart the
interface (`ifdown eth1; ifup eth1`).

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

### Cannot determine stage

The automatic detection of whether the VM instance is running in
QRIScloud stage 1 or QRIScloud stage 2 failed.

Before explicitly specifying a stage, check that the VM instance is
running in QRIScloud. The automatic detection probably failed because
the VM instance is not running in QRIScloud at all, in which case NFS
mounting cannot work (even if a stage is explicitly specified).

See also
--------

QCIF knowledge base article on _NFS mounting collection storage for Linux_.

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

Contact
-------

Please send feedback and queries to Hoylen Sue at <h.sue@qcif.edu.au>.
