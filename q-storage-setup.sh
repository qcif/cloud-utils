#!/bin/bash
#
# Setup NFS mounting of QRIScloud storage for QRIScloud virtual machine
# instances.
#
# Copyright (C) 2013, 2016, 2017 Queensland Cyber Infrastructure Foundation Ltd.
#
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program.  If not, see {http://www.gnu.org/licenses/}.
#----------------------------------------------------------------

VERSION=3.4.0

DEFAULT_ADHOC_MOUNT_DIR="/mnt"
DEFAULT_AUTO_MOUNT_DIR="/data"

# Note: use NFS v3; NFS v4 does not work on tier2 NFS
MOUNT_OPTIONS="rw,nfsvers=3,hard,intr,nosuid,nodev,timeo=100,retrans=5"
MOUNT_OPTIONS_DNF_YUM=nolock
MOUNT_OPTIONS_APT=

MOUNT_AUTOFS_EXTRA=bg

NFS_SERVERS="10.255.120.200 10.255.120.226 10.255.122.70"

#----------------------------------------------------------------
# Error checking

PROG=`basename "$0"`

trap "echo $PROG: command failed: aborted; exit 3" ERR # abort if command fails
# Can't figure out which command failed? Run using "bash -x" or uncomment:
#   set -x # write each command to stderr before it is exceuted

# If using sh, use following instead (since "trap ERR" does not work in sh):
#   set -e # fail if a command fails

set -u # fail on attempts to expand undefined variables

#----------------------------------------------------------------
# Functions

# Function to determine NFS servers and export directory for an allocation
# using the showmount command.
#
# Usage: nfs_export_from_showmount Q-number IP-address
#
# Returns both the server and export path as a single string
# (e.g. "10.255.120.200:/tier2d1/Q0039/Q0039").
#
# Note: this must be done after installing the NFS utilities,
# otherwise the `showmount` command might not be installed.
#
# The allocation must be exported to the IP address for a valid result
# to be returned.
#
# The showmount command is not always reliable (e.g. due to load on the
# server), so this may return a blank result even though the mount exists.

nfs_export_from_showmount () {
  ALLOC=$1
  IP_ADDRESS=$2

  if ! which showmount >/dev/null 2>&1; then
    echo "$PROG: error: command not found: showmount" >&2
    # This function was called before showmount was installed.
    exit 1
  fi

  RESULT=
  for NFS_SERVER in ${NFS_SERVERS}; do
    # showmount will produce lines like "/tier2d1/Q0039/Q0039 10.255.120.8/32"
    # The first `grep` keeps the lines that match the allocation.
    # The second `grep` matches this host's IP address (ends in comma or "/32").
    # The `cut` command keeps the first column, which is the export path.

    MATCH=`showmount -e "$NFS_SERVER" | grep "${ALLOC}/${ALLOC}" | egrep "[ ,]${IP_ADDRESS}((,.*)|(/32.*))$" | cut -d ' ' -f 1`

    if [ -n "$MATCH" ]; then
      # Match or matches were found for the allocation

      NUM_MATCHES=`echo "$MATCH" | wc -l`

      if [ -n "$RESULT" -o "$NUM_MATCHES" -ne 1 ]; then
        # Matches from another NFS server or multiple matches were found
       echo "$PROG: error: $ALLOC has multiple NFS exports (please contact QRIScloud Support)" >&2
       exit 1
      fi

      RESULT="$NFS_SERVER:$MATCH"
    fi
  done

  echo $RESULT # could be blank if match not found
}

# Function to convert an NFS export path to an allocation Q-number.

alloc_from_nfs_path () {
  echo $1 | sed -E 's/^.+\///'
}

#----------------------------------------------------------------
# Process command line arguments

VERBOSE=
DO_AUTOFS=
DO_MOUNT=
DO_UMOUNT=
STAGE=
DIR=
FORCE=

## Define options: trailing colon means has an argument

SHORT_OPTS=hd:amuf:vV
LONG_OPTS=help,dir:,autofs,mount,umount,force:,verbose,version

ALLOC_SPEC_HELP="
allocSpec = the QRISdata Collection Storage allocation to mount/unmount.
This can either be a Q-number (e.g. \"Q0039\") or an export path.
An export path is a string that contains the NFS server and path;
it looks something like \"10.255.120.200:/tier2d1/Q0039/Q0039\".
The export path can be obtained from the QRIScloud Services Portal:
  https://services.qriscloud.org.au/"

SHORT_HELP="Usage: $PROG [options] allocSpecs...
Options:
  -a      configure and use autofs (default)
  -m      perform ad hoc mount
  -u      perform ad hoc unmount

  -d name directory containing mount points
          default for autofs: $DEFAULT_AUTO_MOUNT_DIR
          default for mount or umount: $DEFAULT_ADHOC_MOUNT_DIR
  -f pkg  set package manager type (\"apt\", \"dnf\" or \"yum\" )

  -v      show extra information
  -V      show version
  -h      show this message
$ALLOC_SPEC_HELP
"

LONG_HELP="Usage: $PROG [options] allocSpecs...
Options:
  -a | --autofs     configure and use autofs (default)
  -m | --mount      perform ad hoc mount
  -u | --umount     perform ad hoc unmount

  -d | --dir name   directory containing mount points
                    default for autofs: $DEFAULT_AUTO_MOUNT_DIR
                    default for mount or umount: $DEFAULT_ADHOC_MOUNT_DIR
  -f | --force pkg  set package manager type (\"apt\", \"dnf\" or \"yum\")

  -v | --verbose    show extra information
  -V | --version    show version
  -h | --help       show this message
$ALLOC_SPEC_HELP
"

# Detect if GNU Enhanced getopt is available

HAS_GNU_ENHANCED_GETOPT=
if getopt -T >/dev/null; then :
else
  if [ $? -eq 4 ]; then
    HAS_GNU_ENHANCED_GETOPT=yes
  fi
fi

# Run getopt (runs getopt first in `if` so `trap ERR` does not interfere)

if [ -n "$HAS_GNU_ENHANCED_GETOPT" ]; then
  # Use GNU enhanced getopt
  if ! getopt --name "$PROG" --long $LONG_OPTS --options $SHORT_OPTS -- "$@" >/dev/null; then
    echo "$PROG: usage error (use -h or --help for help)" >&2
    exit 2
  fi
  ARGS=`getopt --name "$PROG" --long $LONG_OPTS --options $SHORT_OPTS -- "$@"`
else
  # Use original getopt (no long option names, no whitespace, no sorting)
  if ! getopt $SHORT_OPTS "$@" >/dev/null; then
    echo "$PROG: usage error (use -h for help)" >&2
    exit 2
  fi
  ARGS=`getopt $SHORT_OPTS "$@"`
fi
eval set -- $ARGS

## Process parsed options (customize this: 2 of 3)

while [ $# -gt 0 ]; do
    case "$1" in
        -a | --autofs)   DO_AUTOFS=yes;;
        -m | --mount)    DO_MOUNT=yes;;
        -u | --umount)   DO_UMOUNT=yes;;
        -d | --dir)      DIR="$2"; shift;;
        -f | --force)    FORCE="$2"; shift;;
        -V | --version)  echo "$PROG $VERSION"; exit 0;;
        -v | --verbose)  VERBOSE=yes;;

        -h | --help)     if [ -n "$HAS_GNU_ENHANCED_GETOPT" ]
                         then echo "$LONG_HELP";
                         else echo "$SHORT_HELP";
                         fi;  exit 0;;
        --version)       echo "$PROG $VERSION"; exit 0;;
        --)              shift; break;; # end of options
    esac
    shift
done

if [ -n "$DO_MOUNT" -a -n "$DO_UMOUNT" ]; then
  echo "$PROG: usage error: cannot use --mount and --umount together" >&2
  exit 2
fi
if [ -n "$DO_AUTOFS" -a -n "$DO_MOUNT" ]; then
  echo "$PROG: usage error: cannot use --autofs and --mount together" >&2
  exit 2
fi
if [ -n "$DO_AUTOFS" -a -n "$DO_UMOUNT" ]; then
  echo "$PROG: usage error: cannot use --autofs and --umount together" >&2
  exit 2
fi

# Use default directories (if explicit directory not specified)

if [ -n "$DO_MOUNT" -o -n "$DO_UMOUNT" ]; then
  # Mount or unmount mode
  if [ -z "$DIR" ]; then
    DIR="$DEFAULT_ADHOC_MOUNT_DIR"
  fi
  if [ ! -e "$DIR" ]; then
    echo "$PROG: error: directory does not exist: $DIR" >&2
    exit 1
  fi
  if [ ! -d "$DIR" ]; then
    echo "$PROG: error: not a directory: $DIR" >&2
    exit 1
  fi
else
  # Automount mode
  if [ -z "$DIR" ]; then
    DIR="$DEFAULT_AUTO_MOUNT_DIR"
  fi
fi

if ! echo "$DIR" | grep -q '^\/'; then
  echo "$PROG: error: directory must be an absolute path: $DIR" >&2
  exit 2
fi

if [ $# -lt 1 ]; then
  echo "$PROG: usage error: missing allocSpec(s) (use -h for help)" >&2
  exit 2
fi

# Check syntax of allocation specifiers

ERROR=
for ALLOC_SPEC in "$@"; do
  if echo $ALLOC_SPEC | grep -q '^Q[0-9][0-9]*$'; then
    # Q-number

    QNUM=$ALLOC_SPEC

  elif echo "$ALLOC_SPEC" | grep -q -E '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+\:\/[0-9A-Za-z]+\/Q[0-9]{4}\/Q[0-9]{4}$'; then
    # Export path (nnn.nnn.nnn.nnn:/xxx/Qnnn/Qnnn)

    SERVER=`echo "$ALLOC_SPEC" | sed -E s/:.*//`
    SERVER_KNOWN=
    for NFS_SERVER in ${NFS_SERVERS}; do
      if [ "$NFS_SERVER" = "$SERVER" ]; then
        SERVER_KNOWN=1
      fi
    done
    if [ -z "$SERVER_KNOWN" ]; then
      echo "$PROG: error: unsupported server IP address: $SERVER" >&2
      echo "  Please check NFS export path is correct: $ALLOC_SPEC" >&2
      ERROR=1
      continue
    fi

    QNUM=`alloc_from_nfs_path $ALLOC_SPEC`

  else
    # Neither Q-number or export path
    echo "Usage error: bad allocation (expecting Qnnnn or n.n.n.n://.../Qnnnn/Qnnnn): $ALLOC_SPEC" >&2
    ERROR=1
    continue
  fi

  # Common checks on QNUM

  # Check correct number of leading zeros
  if ! echo "$QNUM" | grep -q '^Q[0-9][0-9][0-9][0-9]$'; then
    echo "Usage error: Q-number must have exactly four digits: $ALLOC_SPEC" >&2
    ERROR=1
    continue
  fi

  # Extract NUM as the number part (without leading zeros)
  NUM=`echo $QNUM | sed s/Q0*//`

  # Special check for Q0, Q00, Q000, etc. which slips through the above check
  if ! echo $NUM | grep -q '^[0-9][0-9]*$'; then
    echo "Usage error: bad Q-number: zero is not valid: $ALLOC_SPEC" >&2
    ERROR=1
    continue
  fi
 
  if [ "$NUM" -gt 999 ]; then
    # This will cause UID/GID to violate the 54nnn pattern and
    # the behaviour is not yet defined.
    echo "$PROG: error: allocations over 999 not supported: $ALLOC_SPEC" >&2
    ERROR=1
    continue
  fi

done
if [ -n "$ERROR" ]; then
  # At least one of the allocation specifications was wrong: abort
  exit 2
fi

#----------------------------------------------------------------
# Check pre-conditions

FLAVOUR=

if [ -z "$FORCE" ]; then
  # Try to automatically detect packet manager flavour

  OS=`uname -s`
  if [ "$OS" != 'Linux' ]; then
    echo "$PROG: error: unsupported OS: $OS (use --force apt|dnf|yum)"
    exit 1
  fi

  # Detect package manager

  if which dnf > /dev/null 2>&1; then
    FLAVOUR=dnf
  elif which yum > /dev/null 2>&1; then
    FLAVOUR=yum
  elif which apt-get > /dev/null 2>&1; then
    FLAVOUR=apt
  else
    echo "$PROG: error: could not detect package manager (use --force apt|dnf|yum)" >&2
    exit 1
  fi

else
  # Use package manager flavour specifed by --force

  if [ "$FORCE" != 'dnf' -a "$FORCE" != 'yum' -a "$FORCE" != 'apt' ]; then
    echo $PROG': bad --force (expecting "apt", "dnf" or "yum"):' $FORCE >&2
    exit 2
  fi
  FLAVOUR="$FORCE"
fi

#----------------------------------------------------------------
# Set the mount options to use

if [ $FLAVOUR = 'dnf' ]; then
  MOUNT_OPTIONS="$MOUNT_OPTIONS,$MOUNT_OPTIONS_DNF_YUM"
elif [ $FLAVOUR = 'yum' ]; then
  MOUNT_OPTIONS="$MOUNT_OPTIONS,$MOUNT_OPTIONS_DNF_YUM"
elif [ $FLAVOUR = 'apt' ]; then
  MOUNT_OPTIONS="$MOUNT_OPTIONS,$MOUNT_OPTIONS_APT"
else
  echo "$PROG: internal error: unknown flavour: $FLAVOUR" >&2
  exit 3
fi

#----------------------------------------------------------------
# Check for existance of private network interface

# Note: it is assumed that all supported distributions have the "ip" command
# even though some don't have ifconfig/ifup/ifdown.

if ! which ip >/dev/null 2>&1; then
  echo "$PROG: error: command not found: ip" >&2
  exit 1
fi

if ! ip link show dev eth1 >/dev/null; then
  echo "$PROG: eth1 not found: not running on a QRIScloud virtual machine?" >&2
  exit 1
fi

#----------------------------------------------------------------
# Check if runing with root privileges

if [ `id -u` != '0' ]; then
  echo "$PROG: error: this script requires root privileges" >&2
  exit 1
fi

#----------------------------------------------------------------
# Configure private network interface

I_CONFIGURED_ETH1=

if [ "$FLAVOUR" = 'dnf' -o "$FLAVOUR" = 'yum' ]; then

  # The "net-tools" package has been deprecated by some distributions
  # (e.g. Ubuntu 17.10) so the ifconfig/ifup/ifdown commands are not
  # installed by default. But (so far) CentOS still has them installed.

  if ! which ifup >/dev/null 2>&1; then
    echo "$PROG: error: command not found: ifup" >&2
    exit 1
  fi
  if ! which ifdown >/dev/null 2>&1; then
    echo "$PROG: error: command not found: ifdown" >&2
    exit 1
  fi

  ETH1_CFG=/etc/sysconfig/network-scripts/ifcfg-eth1

  if [ ! -f "$ETH1_CFG" ]; then
    # eth1 not configured: create eth1 configuration file

    if [ -n "$VERBOSE" ]; then
      echo "$PROG: creating config file : $ETH1_CFG"
    fi

    cat > "$ETH1_CFG" <<EOF
# ifcfg-eth1: QRIScloud internal network interface
# Created by $PROG on `date '+%F %T %:z'`
# See <https://github.com/qcif/cloud-utils/blob/master/q-storage-setup.md>

DEVICE="eth1"
BOOTPROTO="dhcp"
ONBOOT="yes"
DEFROUTE="no"
TYPE="Ethernet"

# NetworkManager
#
# NetworkManager is disabled (by NM_CONTROLLED="no") because it has been known
# to dynamically change the interface's configuration and cause it to
# unexpectedly break. Unless NetworkManager is properly configured, it is better
# to disable it.

NM_CONTROLLED="no"

# MTU size
#
# The MTU size should be configured by DHCP. If not, uncomment these lines.
# There is a known problem with some releases of OpenStack that prevents setting
# the MTU size by DHCP from working. Until that is fixed, this configures it.

# MTU=9000
# IPV6_MTU=9000
EOF

    # Bring up the network interface
    # Do not use "ip link set dev eth1 up" since it doesn't read ifcfg-eth1

    if [ -n "$VERBOSE" ]; then
	ifup eth1
    else
	ifup eth1  >/dev/null 2>&1
    fi

    # Check MTU packet size

    if ! ip link show dev eth1 | grep -q ' mtu 9000 '; then
	# MTU is not 9000: explicitly configure it to be 9000.
	#
	# In early-2018, OpenStack has made a change so using DHCP to set the
	# MTU size does not work. This code is to work around it.

	if [ -n "$VERBOSE" ]; then
	    echo "$PROG: DHCP MTU not working: configuring eth1 MTU 9000" >&2
	fi

	# Uncomment the MTU configuration lines

	sed -i 's/^# *\(.*MTU=9000\) *$/\1/' "$ETH1_CFG"

	# Restart the interface to use MTU 9000 configuration
	# Do not use "ip link set dev eth1 up" since it doesn't read ifcfg-eth1

	if [ -n "$VERBOSE" ]; then
            ifdown eth1
	    ifup eth1
	else
            ifdown eth1  >/dev/null 2>&1
	    ifup eth1  >/dev/null 2>&1
	fi
    fi

    I_CONFIGURED_ETH1="$ETH1_CFG"
  fi

elif [ "$FLAVOUR" = 'apt' ]; then

  IF_FILE=/etc/network/interfaces

  if [ ! -f "$IF_FILE" ]; then
    echo "$PROG: file missing: $IF_FILE" >&2
    exit 1
  fi

  if ! grep -q 'eth1' "$IF_FILE"; then
    # eth1 not yet configured: append eth1 lines to the interfaces file

    cat >> "$IF_FILE" <<EOF

# The secondary network interface (QRIScloud internal network interface)
# Added by $PROG on `date '+%F %T %:z'`
# See <https://github.com/qcif/cloud-utils/blob/master/q-storage-setup.md>

auto eth1
iface eth1 inet dhcp

# The MTU size on the secondary network interface should be configured by DHCP.
# If not, uncomment the following line.
# There is a known problem with some releases of OpenStack that prevents setting
# the MTU size by DHCP from working. Until that is fixed, this configures it.
#     post-up /sbin/ip link set dev eth1 mtu 9000

EOF

    # Bring up the interface

    if [ -n "$VERBOSE" ]; then
	ip link set dev eth1 up
    else
	ip link set dev eth1 up  >/dev/null 2>&1
    fi

    # Check MTU packet size

    if ! ip link show dev eth1 | grep -q ' mtu 9000 '; then
	# MTU is not 9000: explicitly configure it to be 9000.
	#
	# In early-2018, OpenStack has made a change so using DHCP to set the
	# MTU size does not work. This code is to work around it.

	if [ -n "$VERBOSE" ]; then
	    echo "$PROG: DHCP MTP not working: configuring eth1 MTU 9000" >&2
	fi

	# Uncomment the MTU configuration line
	
	sed -i 's/^# *\(post-up.*mtu 9000\) *$/\1/' "$IF_FILE"

	# Restart the interface to use MTU 9000 configuration

	if [ -n "$VERBOSE" ]; then
	    ip link set dev eth1 down
	    ip link set dev eth1 up
	else
	    ip link set dev eth1 down  >/dev/null 2>&1
	    ip link set dev eth1 up  >/dev/null 2>&1
	fi
    fi

    I_CONFIGURED_ETH1="$IF_FILE"
  fi

else
  echo "$PROG: internal error" >&2
  exit 3
fi

# Show the DHCP assigned IP address

if [ -n "$VERBOSE" ]; then
  ip addr show dev eth1
fi

# Get the eth1 IPv4 address

MYIP=`ip addr show dev eth1 scope global | grep 'inet ' | sed 's/^ *inet \(.*\)\/.*/\1/'`
if [ -z "$MYIP" ]; then
    echo "$PROG: error: eth1: no IPv4 address (please contact QRIScloud Support)" >&2
    exit 1
fi
if [ -n "$VERBOSE" ]; then
    echo "$PROG: eth1 IPv4 address: $MYIP"
fi

# Check MTU packet size

if ! ip link show dev eth1 | grep -q ' mtu 9000 '; then
    echo "$PROG: warning: eth1: MTU != 9000 (please contact QRIScloud Support)" >&2
    # exit 1
fi

#----------------------------------------------------------------
# Check NFS servers are accessible

PING_GOOD=
PING_ERROR=
for NFS_SERVER in ${NFS_SERVERS}; do
  if ! ping -c 1 $NFS_SERVER > /dev/null 2>&1; then
    PING_ERROR="$PING_ERROR $NFS_SERVER"
  else
    PING_GOOD="$PING_GOOD $NFS_SERVER"
  fi
done

if [ -z "$PING_GOOD" ]; then
  # None of the NFS servers were pingable: probably a network problem?
  echo "$PROG: error: none of the NFS server can be pinged:$PING_ERROR" >&2
  if [ -z "$I_CONFIGURED_ETH1" ]; then
    echo "$PROG: please check $I_CONFIGURED_ETH1" >&2
  fi
  exit 1
elif [ -n "$PING_ERROR" ]; then
  # Some good, some bad
 if [ -n "$VERBOSE" ]; then
    echo "$PROG: warning: cannot ping some NFS servers:$PING_ERROR" >&2
    echo "$PROG: mount might be ok if your allocation is not on them." >&2
    echo "$PROG: mount will fail if it is." >&2
  fi
else
  # All good
  :
fi

#----------------------------------------------------------------
# Install NFS client

if [ "$FLAVOUR" = 'dnf' ]; then

  # nfs-utils
  if ! rpm -q nfs-utils > /dev/null; then
    # Package not installed: install it
    if [ -n "$VERBOSE" ]; then QUIET_FLAG=; else QUIET_FLAG="-q"; fi
    dnf -y $QUIET_FLAG install "nfs-utils"
  fi

elif [ "$FLAVOUR" = 'yum' ]; then

  # nfs-utils
  if ! rpm -q nfs-utils > /dev/null; then
    # Package not installed: install it
    if [ -n "$VERBOSE" ]; then QUIET_FLAG=; else QUIET_FLAG="-q"; fi
    yum -y $QUIET_FLAG install "nfs-utils"
  fi

elif [ "$FLAVOUR" = 'apt' ]; then

  # nfs-common
  if [ -n "$VERBOSE" ]; then QUIET_FLAG=; else QUIET_FLAG="-qq"; fi
  apt-get -y --no-upgrade $QUIET_FLAG install "nfs-common"

else
  echo "$PROG: internal error" >&2
  exit 3
fi

#----------------------------------------------------------------
# Convert allocation specifier arguments into export paths

EXPORT_PATHS=
for ALLOC_SPEC in "$@"; do
  VALUE=

  if echo $ALLOC_SPEC | grep -q '^Q[0-9][0-9]*$'; then
    # Argument is a Q-number: detect the export path advertised using showmount

    VALUE=`nfs_export_from_showmount $ALLOC_SPEC $MYIP`

    if [ -z "$VALUE" ]; then
      cat >&2 <<EOF
$PROG: error: no NFS export for $ALLOC_SPEC to this machine ($MYIP)
  Please wait and try again. If this machine was recently launched, it can take
  up to 5 minutes before the NFS export is available. Also the NFS export might
  not be found if the NFS server is highly loaded.  If it does not work after a
  few retries, either specify an explicit NFS export path instead of a Q-number
  or contact QRIScloud support.
EOF
      exit 1
    fi

  else
    # Argument is already an export path
    VALUE="$ALLOC_SPEC"
  fi

  # Double check value ends in Qnnnn, because rest of script expects it

  if ! echo "$VALUE" | grep -q -E '\/Q[0-9]{4}$'; then
    echo "$PROG: internal error: unexpected export path syntax: $VALUE" >&2
    echo "  Please report this to QRIScloud Support." >&2
    # The portal API or showmount returned an unexpected value.
    exit 1
  fi

  if [ -n "$VERBOSE" ]; then
      echo "$PROG: mount path: $VALUE"
  fi

  # Append to list

  EXPORT_PATHS="${EXPORT_PATHS} ${VALUE}"
done

#----------------------------------------------------------------
# Perform desired action. Overview of the remaining code:
#
# if (umount) {
#    ad hoc unmounting
#    exit 0
# }
# create users and groups
# if (mount) {
#    ad hoc mounting
#    exit 0
# }
# configure autofs mounting
# exit 0

#----------------------------------------------------------------
# Ad hoc unmounting

if [ -n "$DO_UMOUNT" ]; then
  ERROR=
  for NFS_EXPORT in $EXPORT_PATHS; do

    ALLOC=`alloc_from_nfs_path $NFS_EXPORT`

    if [ -d "$DIR/$ALLOC" ]; then

      # Attempt to unmount it

      if [ -n "$VERBOSE" ]; then
        echo "umount \"$DIR/$ALLOC\""
      fi
      if umount "$DIR/$ALLOC"; then
        ERROR=yes
      fi

      # Attempt to remove the individual mount directory

      if rmdir "$DIR/$ALLOC"; then
        ERROR=yes
      fi

    else
      if [ -n "$VERBOSE" ]; then
        echo "$PROG: warning: mount directory does not exist: $DIR/$ALLOC"
      fi
    fi
  done 
  # Note: we do NOT attempt to remove the directory containing the mounts

  if [ -n "$ERROR" ]; then
    exit 1
  fi
  exit 0 # done for this mode
fi

#----------------------------------------------------------------
# Create group and users (needed for both ad hoc mounting and autofs)

if [ "$FLAVOUR" = 'dnf' -o "$FLAVOUR" = 'yum' ]; then

  if ! grep -q "^[^:]*:[^:]*:48:" /etc/group; then
    # Group 48 does not exist: create it
    groupadd --gid 48 apache
  fi

  if ! grep -q "^[^:]*:[^:]*:48:" /etc/passwd; then
    # User 48 does not exist: create it
    adduser --uid 48 --gid 48 --comment "Apache" \
            --no-create-home --shell /sbin/nologin apache
  fi

  for NFS_EXPORT in $EXPORT_PATHS; do
    ALLOC=`alloc_from_nfs_path $NFS_EXPORT`

    NUM=`echo $ALLOC | sed s/Q0*//`

    # Note: admin user was 55931, but users now changed to 540xx
    ID_NUMBER=`expr 54000 + $NUM`

    if ! grep -q "^[^:]*:[^:]*:$ID_NUMBER:" /etc/passwd; then
      # User does not exist: create it
      adduser --uid "$ID_NUMBER" --comment "Allocation $ALLOC" "q$NUM"
    fi
  done

elif [ "$FLAVOUR" = 'apt' ]; then

  if ! grep -q "^[^:]*:[^:]*:48:" /etc/group; then
    # Group 48 does not exist: create it
    addgroup --gid 48 --gecos "Apache" --quiet apache
  fi

  if ! grep -q "^[^:]*:[^:]*:48:" /etc/passwd; then
    # User 48 does not exist: create it
    adduser --uid 48 --gid 48 --gecos "Apache" --quiet \
            --no-create-home \
            --shell /sbin/nologin --disabled-login \
            "apache"
  fi

  for NFS_EXPORT in $EXPORT_PATHS; do
    ALLOC=`alloc_from_nfs_path $NFS_EXPORT`

    NUM=`echo $ALLOC | sed s/Q0*//`
    ID_NUMBER=`expr 54000 + $NUM`

    if ! grep -q "^[^:]*:[^:]*:$ID_NUMBER:" /etc/passwd; then
      # User does not exist: create it
      adduser --uid "$ID_NUMBER" --gecos "Allocation $ALLOC" --quiet \
              --disabled-password \
              "q$NUM"
    fi
  done

else
  echo "$PROG: internal error" >&2
  exit 3
fi

#----------------------------------------------------------------
# Ad hoc mounting

if [ -n "$DO_MOUNT" ]; then

  ERROR=

  for NFS_EXPORT in $EXPORT_PATHS; do
    ALLOC=`alloc_from_nfs_path $NFS_EXPORT`

    # Create individual mount directory

    I_CREATED_DIRECTORY=
    if [ ! -e "$DIR/$ALLOC" ]; then
      if ! mkdir "$DIR/$ALLOC"; then
        echo "$PROG: error: could not create mount point: $DIR/$ALLOC" >&2
        ERROR=yes
        continue
      fi
      I_CREATED_DIRECTORY=yes
    else
      if [ ! -d "$DIR/$ALLOC" ]; then
        echo "$PROG: error: mount point is not a directory: $DIR/$ALLOC" >&2
        ERROR=yes
        continue
      fi
    fi

    # Perform the mount operation

    if [ -n "$VERBOSE" ]; then
      echo "mount -t nfs -o \"$MOUNT_OPTIONS\" \"$NFS_EXPORT\" \"$DIR/$ALLOC\""
    fi

    if ! mount -t nfs -o "$MOUNT_OPTIONS" "$NFS_EXPORT" "$DIR/$ALLOC"; then
      # Mount failed
      if [ -n "$I_CREATED_DIRECTORY" ]; then
        rmdir "$DIR/$ALLOC" # clean up
      fi
      echo "$PROG: mount failed for $ALLOC" >&2
      ERROR=yes
      continue
    else
      echo "$PROG: ad hoc mount created: $DIR/$ALLOC"
    fi
  done 

  if [ -n "$ERROR" ]; then
    exit 1
  fi

  exit 0 # done for this mode
fi

#----------------------------------------------------------------
# Install autofs automounter

# yum -y $QUIET_FLAG update
# apt-get update

if [ "$FLAVOUR" = 'dnf' ]; then

  # Install autofs

  if ! rpm -q autofs > /dev/null; then
    # Package not installed: install it
    if [ -n "$VERBOSE" ]; then QUIET_FLAG=; else QUIET_FLAG="-q"; fi
    dnf -y $QUIET_FLAG install "autofs"
  fi

elif [ "$FLAVOUR" = 'yum' ]; then

  # Install autofs

  if ! rpm -q autofs > /dev/null; then
    # Package not installed: install it
    if [ -n "$VERBOSE" ]; then QUIET_FLAG=; else QUIET_FLAG="-q"; fi
    yum -y $QUIET_FLAG install "autofs"
  fi

elif [ "$FLAVOUR" = 'apt' ]; then

  # TODO: check if already installed?

  if [ -n "$VERBOSE" ]; then QUIET_FLAG=; else QUIET_FLAG="-qq"; fi
  apt-get -y --no-upgrade $QUIET_FLAG install "autofs"

else
  echo "$PROG: internal error" >&2
  exit 3
fi

#----------------------------------------------------------------
# Configure autofs automounter

# Create direct map file

DMAP=/etc/auto.qriscloud

if [ -n "$VERBOSE" ]; then
  echo "$PROG: creating direct map file for autofs: $DMAP"
fi

TMP="$DMAP".tmp-$$
trap "rm -f "$TMP"; echo $PROG: command failed: aborted; exit 3" ERR

echo "# autofs mounts for storage" > "$TMP"

for NFS_EXPORT in $EXPORT_PATHS; do
  ALLOC=`alloc_from_nfs_path $NFS_EXPORT`

  echo "$DIR/$ALLOC -$MOUNT_OPTIONS,$MOUNT_AUTOFS_EXTRA $NFS_EXPORT" >> "$TMP"
done

mv "$TMP" "$DMAP"
trap "echo $PROG: command failed: aborted; exit 3" ERR # abort if command fails

# Modify master map file

if ! grep -q "^/- file:$DMAP\$" /etc/auto.master; then
  # Add entry to the master map, because it is not yet in there

  if [ -n "$VERBOSE" ]; then
    echo "Modifying /etc/auto.master"
  fi
  echo "/- file:$DMAP" >> /etc/auto.master
fi

# Restart autofs service (so it uses the new configuration)

if which systemctl >/dev/null 2>&1; then
  # Systemd is used
  systemctl enable autofs.service >/dev/null
  systemctl restart autofs.service >/dev/null
else
  # Init.d is used
    service autofs restart >/dev/null
    echo "$PROG: warning: using init.d instead of systemd"
fi

#----------------------------------------------------------------
# Check mounts work

sleep 1  # needed, otherwise sometimes the mounts fail the test below

ERROR=
for NFS_EXPORT in $EXPORT_PATHS; do
  ALLOC=`alloc_from_nfs_path $NFS_EXPORT`

  if ! ls "$DIR/$ALLOC" >/dev/null 2>&1; then
    echo "$PROG: error: autofs configured, but failed to mount: $DIR/$ALLOC" >&2
    echo "  This could be because this VM does not have permission to" >&2
    echo "  NFS mount $ALLOC. Please check it is running in the correct" >&2
    echo "  Nectar project that was nominated for NFS access." >&2
    echo "  If problems persist, please contact QRIScloud Support." >&2
    ERROR=yes
  else
    echo "$PROG: autofs mount successfully configured: $DIR/$ALLOC"
  fi
done

if [ -n "$ERROR" ]; then
    exit 1
fi

#----------------------------------------------------------------
# Success

exit 0

#----------------------------------------------------------------
#EOF
