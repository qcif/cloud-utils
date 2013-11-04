#!/bin/sh
#
# Setup NFS mounting of storage.
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

NFS_SERVER=10.255.100.50

MOUNT_OPTIONS="rw,nfsvers=3,hard,intr,nosuid,nodev,timeo=15,retrans=5"
MOUNT_OPTIONS_RHEL=nolock
MOUNT_OPTIONS_UBUNTU=

MOUNT_AUTOFS_EXTRA=bg

#----------------------------------------------------------------
# Process command line arguments

HELP=
VERBOSE=
DO_AUTOFS=
DO_MOUNT=
DO_UMOUNT=
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
  echo "  -a | --autofs     configure and use autofs mode (default)"
  echo "  -m | --mount      perform ad hoc mount mode"
  echo "  -u | --umount     perform ad hoc unmount mode"
  echo
  echo "  -d | --dir name   directory containing mount points"
  echo "                    default for autofs: $DEFAULT_AUTO_MOUNT_DIR"
  echo "                    default for mount or umount: $DEFAULT_ADHOC_MOUNT_DIR"
  echo "  -f | --force flv  use commands for given flavour of OS"
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
  if [ ! -d "$DIR" ]; then
    echo "$PROG: error: directory does not exist: $DIR" >&2
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
  echo $ALLOC | grep '^Q[0-9][0-9]*$' > /dev/null
  if [ $? -ne 0 ]; then
    echo "Usage error: bad storageID name (expecting Qnnnn or Qnn): $ALLOC" >&2
    ERROR=1
    continue
  fi
  NUM=`echo $ALLOC | sed s/Q0*//`
  echo $NUM | grep '^[0-9][0-9]*$' > /dev/null
  if [ $? -ne 0 ]; then
    echo "Usage error: bad storageID name: zero is not valid: $ALLOC" >&2
    ERROR=1
    continue
  fi
  if [ "$NUM" -le 5 ]; then
    echo $ALLOC | grep '^Q[0-9][0-9]$' > /dev/null
    if [ $? -ne 0 ]; then
      echo "Usage error: storageID name should be Qnn: $ALLOC" >&2
      ERROR=1
      continue
    fi
  elif [ "$NUM" -gt 999 ]; then
    # This will cause UID/GID to violate the 54nnn pattern and
    # the behaviour is not yet defined.
    echo "$PROG: internal error: allocations greater than 999 not supported" >&2
    exit 3
  else
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
    echo "$PROG: error: unsupported operating system: $OS (use --force?)"
    exit 1
  fi

  # Determine distribution

  which lsb_release > /dev/null 2>&1
  if [ $? -eq 0 ]; then
    DISTRO=`lsb_release -d -s`
  elif [ -f '/etc/system-release' ]; then
    DISTRO=`head -1 /etc/system-release`
  elif [ -f '/etc/issue' ]; then
    DISTRO=`head -1 /etc/issue`
  else
    DISTRO=unknown
  fi
  if [ "$DISTRO" = 'CentOS release 6.4 (Final)' -o \
       "$DISTRO" = 'Scientific Linux release 6.4 (Carbon)' ]; then
    FLAVOUR=rhel
  elif [ "$DISTRO" = 'Ubuntu 13.04' -o \
         "$DISTRO" = 'Ubuntu 12.10' ]; then
    FLAVOUR=ubuntu
  else
    echo "$PROG: error: unsupported distribution: $DISTRO (use --force?)"
    exit 1
  fi
else
  FLAVOUR="$FORCE"
  if [ "$FLAVOUR" != 'rhel' -a "$FLAVOUR" != 'ubuntu' ]; then
    echo "$PROG: error: unsupported flavour (expecting rhel or ubuntu): $FLAVOUR" >&2
    exit 2
  fi
fi

if [ `id -u` != '0' ]; then
  echo "$PROG: this script requires root privileges" >&2
  exit 1
fi

#----------------------------------------------------------------

if [ $FLAVOUR = 'rhel' ]; then
  MOUNT_OPTIONS="$MOUNT_OPTIONS,$MOUNT_OPTIONS_RHEL"
elif [ $FLAVOUR = 'ubuntu' ]; then
  MOUNT_OPTIONS="$MOUNT_OPTIONS,$MOUNT_OPTIONS_UBUNTU"
else
  echo "$PROG: internal error" >&2
  exit 3
fi

#----------------------------------------------------------------

check_ok () {
  if [ $? -ne 0 ]; then
    echo "$PROG: error encountered" >&2
    exit 1
  fi
}

#----------------------------------------------------------------
# Check for existance of private network interface

ip link show | grep ' eth1:' > /dev/null
if [ $? -ne 0 ]; then
  echo "$PROG: interface eth1 not found: not running on Q-Cloud?" >&2
  exit 1
fi

#----------------------------------------------------------------
# Configure private network interface

if [ "$FLAVOUR" = 'rhel' ]; then

  ETH1_CFG=/etc/sysconfig/network-scripts/ifcfg-eth1

  if [ ! -f "$ETH1_CFG" ]; then
    if [ -n "$VERBOSE" ]; then
      echo "$PROG: creating config file : $ETH1_CFG"
    fi

    cat > "$ETH1_CFG" <<EOF
DEVICE="eth1"
BOOTPROTO="dhcp"
MTU="9000"
IPV6_MTU="9000"
#NM_CONTROLLED="yes"
ONBOOT="yes"
TYPE="Ethernet"
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

elif [ "$FLAVOUR" = 'ubuntu' ]; then

  IF_FILE=/etc/network/interfaces
  if [ ! -f "$IF_FILE" ]; then
    echo "$PROG: file missing: $IF_FILE" >&2
    exit 1
  fi

  grep 'eth1' "$IF_FILE" > /dev/null
  if [ $? -ne 0 ]; then
    # eth1 not yet configured
    cat >> "$IF_FILE" <<EOF

# The secondary network interface (connects to internal network)
auto eth1
iface eth1 inet dhcp
pre-up /sbin/ifconfig eth1 mtu 9000

EOF
    check_ok

    service networking restart
    check_ok
  fi 

else
  echo "$PROG: internal error" >&2
  exit 3
fi

# Check MTU packet size

ip link show | grep ' eth1:' | grep ' mtu 9000 ' > /dev/null
if [ $? -ne 0 ]; then
  echo "$PROG: warning: eth1 MTU size is not set to 9000 bytes" >&2
fi

#----------------------------------------------------------------
# Check NFS server is accessible

ping -c 1 $NFS_SERVER > /dev/null
if [ $? -ne 0 ]; then
  echo "$PROG: error: cannot contact server: $NFS_SERVER" >&2
  if [ -z "$I_CONFIGURED_ETH1" ]; then
    echo "$PROG: please check $ETH1_CFG" >&2
  fi
  exit 1
fi

#----------------------------------------------------------------
# Install NFS client

if [ "$FLAVOUR" = 'rhel' ]; then

  # nfs-utils
  rpm -q nfs-utils > /dev/null
  if [ $? -ne 0 ]; then
    # Package not installed: install it
    if [ -n "$VERBOSE" ]; then QUIET_FLAG=; else QUIET_FLAG="-q"; fi
    yum -y $QUIET_FLAG install "nfs-utils"
    check_ok 
  fi

elif [ "$FLAVOUR" = 'ubuntu' ]; then

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
      # Attempt to unmount
      if [ -n "$VERBOSE" ]; then
        echo "umount \"$DIR/$ALLOC\""
      fi
      umount "$DIR/$ALLOC"
      if [ $? -ne 0 ]; then
        ERROR=yes
      fi
      # Attempt to remote the individual mount directory
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

if [ "$FLAVOUR" = 'rhel' ]; then

  grep "^[^:]*:[^:]*:48:" /etc/group > /dev/null
  if [ $? -ne 0 ]; then
    # Group 48 does not exist: create it
    groupadd --gid 48 apache
    check_ok
  fi

  grep "^[^:]*:[^:]*:[^:]*:48:" /etc/passwd > /dev/null
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

    grep "^[^:]*:[^:]*:[^:]*:$ID_NUMBER:" /etc/passwd > /dev/null
    if [ $? -ne 0 ]; then
      # User does not exist: create it
      adduser --uid "$ID_NUMBER" --comment "Allocation $ALLOC" "q$NUM"
      check_ok
    fi
  done

elif [ "$FLAVOUR" = 'ubuntu' ]; then

  grep "^[^:]*:[^:]*:48:" /etc/group > /dev/null
  if [ $? -ne 0 ]; then
    # Group 48 does not exist: create it
    addgroup --gid 48 --gecos "Apache" --quiet apache
    check_ok
  fi

  grep "^[^:]*:[^:]*:[^:]*:48:" /etc/passwd > /dev/null
  if [ $? -ne 0 ]; then
    # User 48 does not exist: create it
    adduser --uid 48 --gid 48 --gecos "Apache" --quiet \
            --no-create-home \
            --shell /sbin/nologin --disabled-login apache
    check_ok
  fi

  for ALLOC in "$@"
  do
    NUM=`echo $ALLOC | sed s/Q0*//`
    ID_NUMBER=`expr 54000 + $NUM`

    grep "^[^:]*:[^:]*:[^:]*:$ID_NUMBER:" /etc/passwd > /dev/null
    if [ $? -ne 0 ]; then
      # User does not exist: create it
      adduser --uid "$ID_NUMBER" --gecos "Allocation $ALLOC" --quiet "q$NUM"
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
  # Create directory containing mounts (if it does not exist)
  if [ ! -e "$DIR" ]; then
    mkdir "$DIR"
    check_ok
  fi
  for ALLOC in "$@"
  do
    # Create individual mount directory
    if [ ! -e "$DIR/$ALLOC" ]; then
      mkdir "$DIR/$ALLOC"
      check_ok
    fi
    # Perform the mount operation
    if [ -n "$VERBOSE" ]; then
      echo "mount -t nfs -o \"$MOUNT_OPTIONS\" \"$NFS_SERVER:/collection/$ALLOC/$ALLOC\" \"$DIR/$ALLOC\""
    fi
    mount -t nfs -o "$MOUNT_OPTIONS" \
       "$NFS_SERVER:/collection/$ALLOC/$ALLOC" "$DIR/$ALLOC"
    check_ok
  done 
  exit 0 # done for this mode
fi

#----------------------------------------------------------------
# Install autofs automounter

# yum -y $QUIET_FLAG update
# apt-get update

if [ "$FLAVOUR" = 'rhel' ]; then

  # Install autofs

  rpm -q autofs > /dev/null
  if [ $? -ne 0 ]; then
    # Package not installed: install it
    if [ -n "$VERBOSE" ]; then QUIET_FLAG=; else QUIET_FLAG="-q"; fi
    yum -y $QUIET_FLAG install "autofs"
    check_ok
  fi

elif [ "$FLAVOUR" = 'ubuntu' ]; then

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

DMAP=/etc/auto.qcloud

if [ -n "$VERBOSE" ]; then
  echo "$PROG: creating direct map file for autofs: $DMAP"
fi

echo "# autofs mounts for storage" > "$DMAP"
check_ok

for ALLOC in "$@"
do
  echo "$DIR/$ALLOC -$MOUNT_OPTIONS,$MOUNT_AUTOFS_EXTRA $NFS_SERVER:/collection/$ALLOC/$ALLOC" >> "$DMAP"
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
