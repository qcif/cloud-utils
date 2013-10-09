q-storage-setup
===============

Setup VM instances to NFS mount Q-cloud collection storage.

Synopsis
--------

    q-storage-setup.sh
        [ -a | --autofs] [ -m | --mount ] [ -u | --umount ]
        [ -d | --dir dirname] [ -f | --force flavour]
        [ -v | --verbose ] [ -h | --help ] storageID {storageID...}

Description
-----------

This script operates in one of four modes. The mode is set by using one
of these options:

- `-a | --autofs` configure _autofs_ to automatically mount the collection storage.

- `-m | --mount` runs the mount command to manually mount the collection storage.

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
operating system.  This script has been designed to work with both
_Red Hat Enterprise Linux_ or _Ubuntu_ based Linux distributions, and
automatically detects which distribution it is running on. If the
automatic detection fails, force it to assume a particular
distribution by using this option with `rhel` or `ubuntu` as the
argument.

- `-v | --verbose` show extra information.

The `storageID` must be one or more collection names. These must be of
the form "Qnnnn" where _n_ is a digit (except for Q01, Q02, Q03, Q04,
Q05 and Q16, which only have two digits.

The first time this script is used, it might take a few minutes to
run. This is because it needs to download and install the dependent
packages. Run it in verbose mode if you want to see an indication of
progress while you are waiting.

### Configure autofs mode

This mode configures _autofs_ to NFS mount the specified collection
storage. Use this mode to setup collection storage for production use.
The mounts will be re-established if the operating system is rebooted.

If necessary, it also installs the necessary packages and configures the
private network interface. Groups and users are also created.

It is recommended that the mounting is tested using the ad hoc mount
mode (see below) before setting up _autofs_. Errors are easier to
detect in mount mode, because _autofs_ silently fails if errors are
encountered.

### Mount mode

This mode runs an ad hoc mount command to NFS mount the specified
collection storage. Use this mode to test whether collection storage
can be successfully mounted.

If necessary, it also installs the necessary packages and configures the
private network interface. Groups and users are also created.

Undo the mounts created by the mount mode using the unmount mode (see below).

### Unmount mode

This mode unmounts ad hoc mounted collection storage. Use this mode to
reverse the actions of the mount mode (see above).

### Help mode

Prints a short help message.

Examples
--------

### Obtaining the script

The easiest way to obtain the latest copy of the script is
to download it directly from GitHub:

   $ curl -O https://raw.github.com/qcif/cloud-utils/master/q-storage-setup.sh
   $ chmod a+x q-storage-setup.sh

### Ad hoc testing

Mount collection Q0039, examine its contents and unmount it.

    # ./q-storage-setup.sh --mount Q0039
    # ls /mnt/Q0039
    # ./q-storage-setup.sh --umount Q0039

### Configure autofs

Configure autofs and examine its contents.

    # ./q-storage-setup.sh Q0039
    # ls /data/Q0039


Environment
-----------

This script must be run with root privileges.

You might want to update existing packages before running this
script. In RHEL, run "yum update". In Ubuntu, run "apt-get update".

Files
-----

- `/etc/auto.qcloud` - direct map file created with mount information.
- `/etc/auto.master` - configuration file for _autofs_.

Diagnosis
---------

### Interface eth1 not found: not running on Q-Cloud?

Collection storage can only be NFS mounted from virtual machine
instances running on the Queensland node. The current system is
not running on the Queensland node.

See also
--------

QCIF knowledge base article on _NFS mounting collection storage for Linux_.

Bugs
----

The unmount mode does not delete any of the user accounts or groups
created by the mount mode.

In mount mode, the `bg` option is specified. This causes the _mount_
command to run in the background if an error occurs.

Contact
-------

Please send feedback and queries to Hoylen Sue at <h.sue@qcif.edu.au>.
