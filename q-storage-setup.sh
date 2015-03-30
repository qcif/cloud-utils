#!/bin/sh
#
# Setup NFS mounting of QRIScloud storage for QRIScloud virtual machine
# instances.
#
# Copyright (C) 2013, Queensland Cyber Infrastructure Foundation Ltd.
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

PROG=`basename $0`

DEFAULT_ADHOC_MOUNT_DIR="/mnt"
DEFAULT_AUTO_MOUNT_DIR="/data"

MOUNT_OPTIONS="rw,nfsvers=3,hard,intr,nosuid,nodev,timeo=100,retrans=5"
MOUNT_OPTIONS_YUM=nolock
MOUNT_OPTIONS_APT=

MOUNT_AUTOFS_EXTRA=bg

NFS_SERVERS="10.255.120.223 10.255.120.200 10.255.120.226"

#----------------------------------------------------------------
# Function to check for errors and abort

check_ok () {
  if [ $? -ne 0 ]; then
    echo "$PROG: error encountered" >&2
    exit 1
  fi
}

#----------------------------------------------------------------
# Function to determine NFS servers and export directory for an allocation
#
# Returns both the server and export path as a single string
# (e.g. "10.255.120.200:/tier2d1/Q0039/Q0039").
#
# Note: this must be done after installing the NFS utilities,
# otherwise the `showmount` command might not be installed.

nfs_export () {
  ALLOC=$1

  if ! which showmount >/dev/null 2>&1; then
    echo "$PROG: error: command not found: showmount" >&2
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
	echo "$PROG: Please contact QRIScloud support to report this." >&2
	exit 1
      fi

      RESULT="$NFS_SERVER:$MATCH"
    fi
  done

  if [ -z "$RESULT" ]; then
    echo "$PROG: error: could not find NFS server and export for $ALLOC" >&2
    exit 1
  fi

  echo $RESULT
}

#----------------------------------------------------------------
# Process command line arguments

HELP=
VERBOSE=
DO_AUTOFS=
DO_MOUNT=
DO_UMOUNT=
STAGE=
DIR=
FORCE=

getopt -T > /dev/null
if [ $? -eq 4 ]; then
  # GNU enhanced getopt is available
  ARGS=`getopt --name "$PROG" --long help,dir:,autofs,mount,unmount,force:,verbose --options hd:amuf:v -- "$@"`
else
  # Original getopt is available (no long option names nor whitespace)
  ARGS=`getopt hd:amuf:v "$@"`
fi
if [ $? -ne 0 ]; then
  echo "$PROG: usage error (use -h for help)" >&2
  exit 1
fi
eval set -- $ARGS

while [ $# -gt 0 ]; do
    case "$1" in
        -a | --autofs)   DO_AUTOFS=yes;;
        -m | --mount)    DO_MOUNT=yes;;
        -u | --umount)   DO_UMOUNT=yes;;
        -d | --dir)      DIR="$2"; shift;;
        -f | --force)    FORCE="$2"; shift;;
        -v | --verbose)  VERBOSE=yes;;
        -h | --help)     HELP=yes;;
        --)              shift; break;;
    esac
    shift
done

if [ -n "$HELP" ]; then
  echo "Usage: $PROG [options] storageID..."
  echo "Options:"
  echo
  echo "  -a | --autofs     configure and use autofs (default)"
  echo "  -m | --mount      perform ad hoc mount"
  echo "  -u | --umount     perform ad hoc unmount"
  echo
  echo "  -d | --dir name   directory containing mount points"
  echo "                    default for autofs: $DEFAULT_AUTO_MOUNT_DIR"
  echo "                    default for mount or umount: $DEFAULT_ADHOC_MOUNT_DIR"
  echo "  -f | --force pkg  set package manager type (\"yum\" or \"apt\")"
  echo
  echo "  -v | --verbose    show extra information"
  echo "  -h | --help       show this message"
  exit 0
fi

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

echo $DIR | grep '^\/' > /dev/null
if [ $? -ne 0 ]; then
  echo "$PROG: error: directory must be an absolute path: $DIR" >&2
  exit 2
fi

if [ $# -lt 1 ]; then
  echo "$PROG: usage error: missing storageID(s) (use -h for help)" >&2
  exit 2
fi

# Check storageID names are correctly formatted

ERROR=
for ALLOC in "$@"
do
  # Check syntax: is it "Q" followed by one or more digits
  echo $ALLOC | grep '^Q[0-9][0-9]*$' > /dev/null
  if [ $? -ne 0 ]; then
    echo "Usage error: bad storageID name (expecting Qnnnn or Qnn): $ALLOC" >&2
    ERROR=1
    continue
  fi
  # Extract NUM as the number part (without leading zeros)
  NUM=`echo $ALLOC | sed s/Q0*//`
  # Special check for Q0, Q00, Q000, etc. which slips through the above check
  echo $NUM | grep '^[0-9][0-9]*$' > /dev/null
  if [ $? -ne 0 ]; then
    echo "Usage error: bad storageID name: zero is not valid: $ALLOC" >&2
    ERROR=1
    continue
  fi
  # Check correct number of leading zeros
  if [ "$NUM" -eq 1 -o \
       "$NUM" -eq 2 -o \
       "$NUM" -eq 3 -o \
       "$NUM" -eq 16 ]; then
    # These numbers are the exception and needs to be Qnn
    echo $ALLOC | grep '^Q[0-9][0-9]$' > /dev/null
    if [ $? -ne 0 ]; then
      echo "Usage error: storageID name should be Qnn: $ALLOC" >&2
      ERROR=1
      continue
    fi
  elif [ "$NUM" -gt 999 ]; then
    # This will cause UID/GID to violate the 54nnn pattern and
    # the behaviour is not yet defined.
    echo "$PROG: internal error: allocations over 999 not supported" >&2
    exit 3
  else
    # These numbers follow the standard pattern of Qnnnn
    echo $ALLOC | grep '^Q[0-9][0-9][0-9][0-9]$' > /dev/null
    if [ $? -ne 0 ]; then
      echo "Usage error: storageID name should be Qnnnn: $ALLOC" >&2
      ERROR=1
    fi
  fi
done
if [ -n "$ERROR" ]; then
  exit 2
fi

#----------------------------------------------------------------
# Check pre-conditions

if [ -z "$FORCE" ]; then

  OS=`uname -s`
  if [ "$OS" != 'Linux' ]; then
    echo "$PROG: error: unsupported OS: $OS (use --force yum|apt)"
    exit 1
  fi

  # Detect package manager

  if which yum > /dev/null 2>&1; then
    FLAVOUR=yum
  fi

  if which apt-get > /dev/null 2>&1; then
    if [ -n "$FLAVOUR" ]; then
      echo "$PROG: error: detected yum and apt-get (use --force yum|apt)" >&2
      exit 1
    fi
    FLAVOUR=apt
  fi

  if [ -z "$FLAVOUR" ]; then
    echo "$PROG: error: package manager not found (use --force yum|apt)"
    exit 1
  fi

else
  # Use package manager specifed by --force

  FLAVOUR="$FORCE"
  if [ "$FLAVOUR" != 'yum' -a "$FLAVOUR" != 'apt' ]; then
    echo "$PROG: error: unsupported package manager (expecting \"yum\" or \"apt\"): $FLAVOUR" >&2
    exit 2
  fi
fi

#----------------------------------------------------------------

if [ $FLAVOUR = 'yum' ]; then
  MOUNT_OPTIONS="$MOUNT_OPTIONS,$MOUNT_OPTIONS_YUM"
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

if [ "$FLAVOUR" = 'yum' ]; then

  ETH1_CFG=/etc/sysconfig/network-scripts/ifcfg-eth1

  if [ ! -f "$ETH1_CFG" ]; then
    if [ -n "$VERBOSE" ]; then
      echo "$PROG: creating config file : $ETH1_CFG"
    fi

    cat > "$ETH1_CFG" <<EOF
DEVICE="eth1"
BOOTPROTO="dhcp"
#NM_CONTROLLED="yes"
ONBOOT="yes"
DEFROUTE=no
TYPE="Ethernet"
#
## MTU size is provided by DHCP. If not, uncomment the following lines.
#
# MTU="9000"
# IPV6_MTU="9000"
EOF

    # Bring up the network interface

    if [ -n "$VERBOSE" ]; then
      echo "$PROG: ifup eth1"
    fi
    ifup eth1 > /dev/null
    check_ok

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

  grep 'eth1' "$IF_FILE" > /dev/null
  if [ $? -ne 0 ]; then
    # eth1 not yet configured
    cat >> "$IF_FILE" <<EOF

# The secondary network interface (connects to QRIScloud internal network)
auto eth1
iface eth1 inet dhcp

## MTU size is provided by DHCP. If not, uncomment the following line.
# pre-up /sbin/ifconfig eth1 mtu 9000

EOF
    check_ok

    if [ -n "$VERBOSE" ]; then
      echo "$PROG: ifup eth1"
      ifup eth1
      check_ok
    else
      ifup eth1 >/dev/null 2>&1
      check_ok
    fi

  fi 

else
  echo "$PROG: internal error" >&2
  exit 3
fi

# Check MTU packet size

ip link show dev eth1 | grep ' mtu 9000 ' > /dev/null
if [ $? -ne 0 ]; then
  echo "$PROG: warning: DHCP did not set eth1 MTU to 9000 bytes" >&2
fi

# Check NFS servers are accessible

PING_ERROR=
for NFS_SERVER in ${NFS_SERVERS}
do
  ping -c 1 $NFS_SERVER > /dev/null
  if [ $? -ne 0 ]; then
    echo "$PROG: warning: cannot ping NFS server: $NFS_SERVER" >&2
    PING_ERROR=yes
  fi
done

if [ -n "$PING_ERROR" ]; then
  if [ -z "$I_CONFIGURED_ETH1" ]; then
    echo "$PROG: please check $ETH1_CFG" >&2
  fi
  exit 1
fi

#----------------------------------------------------------------
# Install NFS client

if [ "$FLAVOUR" = 'yum' ]; then

  # nfs-utils
  rpm -q nfs-utils > /dev/null
  if [ $? -ne 0 ]; then
    # Package not installed: install it
    if [ -n "$VERBOSE" ]; then QUIET_FLAG=; else QUIET_FLAG="-q"; fi
    yum -y $QUIET_FLAG install "nfs-utils"
    check_ok 
  fi

elif [ "$FLAVOUR" = 'apt' ]; then

  # nfs-common
  if [ -n "$VERBOSE" ]; then QUIET_FLAG=; else QUIET_FLAG="-qq"; fi
  apt-get -y --no-upgrade $QUIET_FLAG install "nfs-common"
  check_ok

else
  echo "$PROG: internal error" >&2
  exit 3
fi

#----------------------------------------------------------------
# Ad hoc unmounting

if [ -n "$DO_UMOUNT" ]; then
  ERROR=
  for ALLOC in "$@"
  do
    if [ -d "$DIR/$ALLOC" ]; then

      # Attempt to unmount it

      if [ -n "$VERBOSE" ]; then
        echo "umount \"$DIR/$ALLOC\""
      fi
      umount "$DIR/$ALLOC"
      if [ $? -ne 0 ]; then
        ERROR=yes
      fi

      # Attempt to remove the individual mount directory

      rmdir "$DIR/$ALLOC"
      if [ $? -ne 0 ]; then
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

if [ "$FLAVOUR" = 'yum' ]; then

  grep "^[^:]*:[^:]*:48:" /etc/group > /dev/null
  if [ $? -ne 0 ]; then
    # Group 48 does not exist: create it
    groupadd --gid 48 apache
    check_ok
  fi

  grep "^[^:]*:[^:]*:48:" /etc/passwd > /dev/null
  if [ $? -ne 0 ]; then
    # User 48 does not exist: create it
    adduser --uid 48 --gid 48 --comment "Apache" \
            --no-create-home --shell /sbin/nologin apache
    check_ok
  fi

  for ALLOC in "$@"
  do
    NUM=`echo $ALLOC | sed s/Q0*//`
    # Note: admin user was 55931, but users now changed to 540xx
    ID_NUMBER=`expr 54000 + $NUM`

    grep "^[^:]*:[^:]*:$ID_NUMBER:" /etc/passwd > /dev/null
    if [ $? -ne 0 ]; then
      # User does not exist: create it
      adduser --uid "$ID_NUMBER" --comment "Allocation $ALLOC" "q$NUM"
      check_ok
    fi
  done

elif [ "$FLAVOUR" = 'apt' ]; then

  grep "^[^:]*:[^:]*:48:" /etc/group > /dev/null
  if [ $? -ne 0 ]; then
    # Group 48 does not exist: create it
    addgroup --gid 48 --gecos "Apache" --quiet apache
    check_ok
  fi

  grep "^[^:]*:[^:]*:48:" /etc/passwd > /dev/null
  if [ $? -ne 0 ]; then
    # User 48 does not exist: create it
    adduser --uid 48 --gid 48 --gecos "Apache" --quiet \
            --no-create-home \
            --shell /sbin/nologin --disabled-login \
            "apache"
    check_ok
  fi

  for ALLOC in "$@"
  do
    NUM=`echo $ALLOC | sed s/Q0*//`
    ID_NUMBER=`expr 54000 + $NUM`

    grep "^[^:]*:[^:]*:$ID_NUMBER:" /etc/passwd > /dev/null
    if [ $? -ne 0 ]; then
      # User does not exist: create it
      adduser --uid "$ID_NUMBER" --gecos "Allocation $ALLOC" --quiet \
              --disabled-password \
              "q$NUM"
      check_ok
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

  for ALLOC in "$@"
  do
    # Create individual mount directory

    I_CREATED_DIRECTORY=
    if [ ! -e "$DIR/$ALLOC" ]; then
      mkdir "$DIR/$ALLOC"
      if [ $? -ne 0 ]; then
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

    NFS_EXPORT=`nfs_export $ALLOC`
    check_ok

    if [ -n "$VERBOSE" ]; then
      echo "mount -t nfs -o \"$MOUNT_OPTIONS\" \"$NFS_EXPORT\" \"$DIR/$ALLOC\""
    fi

    mount -t nfs -o "$MOUNT_OPTIONS" "$NFS_EXPORT" "$DIR/$ALLOC"
    if [ $? -ne 0 ]; then
      if [ -n "$I_CREATED_DIRECTORY" ]; then
        rmdir "$DIR/$ALLOC" # clean up
      fi
      echo "$PROG: mount failed for $ALLOC" >&2
      ERROR=yes
      continue
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

if [ "$FLAVOUR" = 'yum' ]; then

  # Install autofs

  rpm -q autofs > /dev/null
  if [ $? -ne 0 ]; then
    # Package not installed: install it
    if [ -n "$VERBOSE" ]; then QUIET_FLAG=; else QUIET_FLAG="-q"; fi
    yum -y $QUIET_FLAG install "autofs"
    check_ok
  fi

elif [ "$FLAVOUR" = 'apt' ]; then

  # TODO: check if already installed?

  if [ -n "$VERBOSE" ]; then QUIET_FLAG=; else QUIET_FLAG="-qq"; fi
  apt-get -y --no-upgrade $QUIET_FLAG install "autofs"
  check_ok

else
  echo "$PROG: internal error" >&2
  exit 3
fi

#----------------------------------------------------------------
# Configure autofs automounter

# Stopping autofs service

service autofs stop
check_ok

# Create direct map file

DMAP=/etc/auto.qriscloud

if [ -n "$VERBOSE" ]; then
  echo "$PROG: creating direct map file for autofs: $DMAP"
fi

echo "# autofs mounts for storage" > "$DMAP"
check_ok

for ALLOC in "$@"
do
  NFS_EXPORT=`nfs_export $ALLOC`
  check_ok

  echo "$DIR/$ALLOC -$MOUNT_OPTIONS,$MOUNT_AUTOFS_EXTRA $NFS_EXPORT" >> "$DMAP"
  check_ok
done

# Modify master map file

grep "^/- file:$DMAP\$" /etc/auto.master > /dev/null
if [ $? -ne 0 ]; then
  # Add entry to the master map, because it is not yet in there

  if [ -n "$VERBOSE" ]; then
    echo "Modifying /etc/auto.master"
  fi
  echo "/- file:$DMAP" >> /etc/auto.master
  check_ok
fi

# Starting autofs service (so it picks up the new configuration)

service autofs start
check_ok

#----------------------------------------------------------------
# Success

exit 0

#----------------------------------------------------------------
#EOF
