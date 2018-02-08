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

VERSION=3.2.0

DEFAULT_ADHOC_MOUNT_DIR="/mnt"
DEFAULT_AUTO_MOUNT_DIR="/data"

# NFSv4 known working in Ubuntu 16.04
# change conditional if other OSes supported/wanted
if [[ $(python -mplatform | grep "Ubuntu-16.04") ]]; then 
    MOUNT_OPTIONS="rw,nfsvers=4,hard,intr,nosuid,nodev,timeo=100,retrans=5"
else
    MOUNT_OPTIONS="rw,nfsvers=3,hard,intr,nosuid,nodev,timeo=100,retrans=5"
fi
#MOUNT_OPTIONS="rw,nfsvers=3,hard,intr,nosuid,nodev,timeo=100,retrans=5"

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
# using the QRIScloud Portal API.
#
# Returns both the server and export path as a single string
# (e.g. "10.255.120.200:/tier2d1/Q0039/Q0039").

nfs_export_from_portal() {
  ALLOC=$1
  NUM=`echo $ALLOC | sed s/Q0*//`

  VALUE=`curl --silent --user-agent "q-storage-setup" -H "Accept: text/plain"  https://services.qriscloud.org.au/api/collectionStorage/allocation/${NUM}/nfs-path`
  if [ $? -ne 0 ]; then
    return  # failed: curl failed
  fi

  if ! echo "$VALUE" | grep -q -E '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+\:(\/[0-9A-Za-z]+)*\/Q[0-9]{4}\/Q[0-9]{4}$'; then
    return  # failed: value doesn't look like a mount path
  fi

  echo $VALUE # success
}

# Function to determine NFS servers and export directory for an allocation
# using the showmount command.
#
# Returns both the server and export path as a single string
# (e.g. "10.255.120.200:/tier2d1/Q0039/Q0039").
#
# Note: this must be done after installing the NFS utilities,
# otherwise the `showmount` command might not be installed.
#
# The showmount command is not always reliable (e.g. due to load on the
# server), so this may return a blank result even though the mount exists.

nfs_export_from_showmount () {
  ALLOC=$1

  if ! which showmount >/dev/null 2>&1; then
    echo "$PROG: error: command not found: showmount" >&2
    # This function was called before showmount was installed.
    exit 1
  fi

  RESULT=
  for NFS_SERVER in ${NFS_SERVERS}; do
    # showmount will produce lines like "/tier2d1/Q0039/Q0039 10.255.120.8/32"
    # The `cut` command keeps the first column and the `grep` keeps only those
    # that ends in the desired allocation number.

    MATCH=`showmount -e "$NFS_SERVER" | cut -d ' ' -f 1 | grep "${ALLOC}/${ALLOC}\$"`
    if [ -n "$MATCH" ]; then
      # Match or matches were found

      NUM_MATCHES=`echo "$MATCH" | wc -l`

      if [ -n "$RESULT" -o "$NUM_MATCHES" -ne 1 ]; then
        # Matches from another NFS server or multiple matches were found
       echo "$PROG: error: $ALLOC has multiple NFS exports" >&2
       echo "  Please contact QRIScloud Support to report this." >&2
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

SHORT_OPTS=hd:amuMf:vV
LONG_OPTS=help,dir:,autofs,mount,umount,mtu,force:,verbose,version

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
  -M      force MTU 9000

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
  -M | --mtu        force setting MTU to 9000

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
        -M | --mtu)      DO_MTU=yes;;
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

  OS=`uname -s`
  if [ "$OS" != 'Linux' ]; then
    echo "$PROG: error: unsupported OS: $OS (use --force apt|dnf|yum)"
    exit 1
  fi

  # Detect package manager

  if which dnf > /dev/null 2>&1; then
    FLAVOUR=dnf
  else
    if which yum > /dev/null 2>&1; then
      FLAVOUR=yum
    fi
  fi

  if which apt-get > /dev/null 2>&1; then
    if [ -n "$FLAVOUR" ]; then
      echo "$PROG: error: detected dnf/yum and apt-get (use --force apt|dnf|yum)" >&2
      exit 1
    fi
    FLAVOUR=apt
  fi

  if [ -z "$FLAVOUR" ]; then
    echo "$PROG: error: package manager not found (use --force apt|dnf|yum)"
    exit 1
  fi

else
  # Use package manager specifed by --force

  FLAVOUR="$FORCE"
  if [ "$FLAVOUR" != 'dnf' -a "$FLAVOUR" != 'yum' -a "$FLAVOUR" != 'apt' ]; then
    echo "$PROG: error: unsupported package manager (expecting \"apt\", \"dnf\" or \"yum\"): $FLAVOUR" >&2
    exit 2
  fi
fi

#----------------------------------------------------------------

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

  ETH1_CFG=/etc/sysconfig/network-scripts/ifcfg-eth1

  if [ ! -f "$ETH1_CFG" ]; then
    if [ -n "$VERBOSE" ]; then
      echo "$PROG: creating config file : $ETH1_CFG"
    fi

    if [ -n "$DO_MTU" ]; then
        cat > "$ETH1_CFG" <<EOF
DEVICE="eth1"
BOOTPROTO="dhcp"
#NM_CONTROLLED="yes"
ONBOOT="yes"
DEFROUTE=no
TYPE="Ethernet"
MTU="9000"
IPV6_MTU="9000"
EOF
    else
        cat > "$ETH1_CFG" <<EOF
DEVICE="eth1"
BOOTPROTO="dhcp"
#NM_CONTROLLED="yes"
ONBOOT="yes"
DEFROUTE=no
TYPE="Ethernet"

## MTU size should have been provided by DHCP. If not, uncomment these lines:
#
# MTU="9000"
# IPV6_MTU="9000"
EOF
    fi

    # Bring up the network interface

    if [ -n "$VERBOSE" ]; then
      echo "$PROG: ifup eth1"
    fi
    ifup eth1 > /dev/null

    # Show DHCP assigned IP addresses

    if [ -n "$VERBOSE" ]; then
      ip addr show dev eth1
    fi

    I_CONFIGURED_ETH1=yes
  fi

elif [ "$FLAVOUR" = 'apt' ]; then

  IF_FILE=/etc/network/interfaces
  if [ ! -f "$IF_FILE" ]; then
    echo "$PROG: file missing: $IF_FILE" >&2
    exit 1
  fi

  if ! grep -q 'eth1' "$IF_FILE"; then
    # eth1 not yet configured
    if [ -n "$DO_MTU" ]; then
        cat >> "$IF_FILE" <<EOF

# The secondary network interface (connects to QRIScloud internal network)
auto eth1
iface eth1 inet dhcp
post-up /sbin/ifconfig eth1 mtu 9000

EOF
    else
        cat >> "$IF_FILE" <<EOF

# The secondary network interface (connects to QRIScloud internal network)
auto eth1
iface eth1 inet dhcp

## MTU size should have been provided by DHCP. If not, uncomment this line:
#
#post-up /sbin/ifconfig eth1 mtu 9000

EOF
    fi

    if [ -n "$VERBOSE" ]; then
      echo "$PROG: ifup eth1"
      ifup eth1
    else
      ifup eth1 >/dev/null 2>&1
    fi

  fi 

else
  echo "$PROG: internal error" >&2
  exit 3
fi

# Cycle eth1 if forcing MTU

if [ -n "$DO_MTU" ]; then
    #ifconfig eth1 mtu 9000
    ifdown eth1
    ifup eth1
fi

# Check MTU packet size

if ! ip link show dev eth1 | grep -q ' mtu 9000 '; then
  echo "$PROG: warning: MTU for eth1 is not 9000 bytes" >&2
fi

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
    echo "$PROG: please check $ETH1_CFG" >&2
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

# Check for NetworkManager

if [ "$FLAVOUR" = 'dnf' -o "$FLAVOUR" = 'yum' ]; then
  if [ -n "$VERBOSE" ]; then
    if rpm -q NetworkManager >/dev/null; then
      echo "$PROG: warning: NetworkManager installed, consider uninstalling it" >&2
    fi
  fi
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
    # Argument is a Q-number: lookup

    # Try using the QRIScloud Services Portal first
    VALUE=`nfs_export_from_portal $ALLOC_SPEC`

    if [ -z "$VALUE" ]; then
	# Resort to using showmount
	if [ -n "$VERBOSE" ]; then
	    echo "$PROG: warning: could not get export path from services portal"
	fi

	VALUE=`nfs_export_from_showmount $ALLOC_SPEC`

	if [ -n "$VERBOSE" -a -z "$VALUE" ]; then
	    echo "$PROG: warning: could not get export path from showmount"
	fi
    fi

    if [ -z "$VALUE" ]; then
      # Neither worked
      echo "$PROG: error: could not automatically get export path for $ALLOC_SPEC" >&2
      echo "  Instead, provide the full NFS export path (from the QRIScloud Services Portal" >&2
      echo "  at https://services.qriscloud.org.au), or contact QRIScloud support." >&2
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
  if [ -f "${DMAP}" ]; then
    echo "${PROG}: extending direct map file for autofs: ${DMAP}"
  else
    echo "$PROG: creating direct map file for autofs: $DMAP"
  fi
fi

TMP="$DMAP".tmp-$$
trap "rm -f "$TMP"; echo $PROG: command failed: aborted; exit 3" ERR

if [ -f "${DMAP}" ]; then
  # rm existing fs line if existing
  grep -v "${DIR}/${ALLOC}" ${DMAP} > ${TMP}
else
  echo "# autofs mounts for storage" > "$TMP"
fi

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
  systemctl restart autofs.service
else
  # Init.d is used
  service autofs restart
fi

# Check mounts work

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
