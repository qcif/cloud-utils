#!/bin/bash
#
# Setup NFS mounting of QRIScloud storage for QRIScloud virtual machine
# instances.
#
# Copyright (C) 2013-2019 Queensland Cyber Infrastructure Foundation Ltd.
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

VERSION=4.1.1

DEFAULT_ADHOC_MOUNT_DIR="/mnt"
DEFAULT_AUTO_MOUNT_DIR="/data"

# Note: use NFS v3; NFS v4 does not work on tier2 NFS
MOUNT_OPTIONS_BASE="nfsvers=3,hard,intr,nosuid,nodev,timeo=100,retrans=5"
MOUNT_OPTIONS_DNF_YUM=nolock
MOUNT_OPTIONS_APT=

MOUNT_AUTOFS_EXTRA=bg

NFS_SERVERS="10.255.120.200 10.255.120.226 10.255.122.70"

#----------------------------------------------------------------
# Error checking

PROG=`basename "$0"`

# Log file where output from commands are redirected.
# This is used because apt-get is noisy, even in quiet mode!
LOG="/tmp/${PROG}-$$.log"

trap "echo $PROG: aborted \(see $LOG for details\); exit 3" ERR
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
    # The second `grep` matches host's IP address (ends in comma or "/32").
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
READ_ONLY=
STAGE=
DIR=

## Define options: trailing colon means has an argument

SHORT_OPTS=hd:amurvV
LONG_OPTS=help,dir:,autofs,mount,umount,read-only,verbose,version

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

  -r      mount in read-only mode (default: read-write)
  -d name directory containing mount points
          default for autofs: $DEFAULT_AUTO_MOUNT_DIR
          default for mount or umount: $DEFAULT_ADHOC_MOUNT_DIR

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

  -r | --read-only  mount in read-only mode (default: read-write)
  -d | --dir name   directory containing mount points
                    default for autofs: $DEFAULT_AUTO_MOUNT_DIR
                    default for mount or umount: $DEFAULT_ADHOC_MOUNT_DIR

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
    -r | --read-only) READ_ONLY=yes;;
    -d | --dir)      DIR="$2"; shift;;
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

# Determine action

if [ -z "$DO_MOUNT" -a -z "$DO_UMOUNT" -a -z "$DO_AUTOFS" ]; then
  # No action specified: default to autofs
  DO_AUTOFS=yes
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

# Set the ACTION. After this point, the script does not use the DO_* variables.

if [ -n "$DO_AUTOFS" ]; then
  ACTION=autofs
elif [ -n "$DO_MOUNT" ]; then
  ACTION=mount
elif [ -n "$DO_UMOUNT" ]; then
  ACTION=umount
else
  echo "$PROG: internal error: no action" >&2
  exit 3
fi

# Use default directories (if explicit directory not specified)

if [ $ACTION = 'mount' -o $ACTION = 'umount' ]; then
  # Mount or unmount
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
  # Automount
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
# Basic checks before it starts doing anything

#----------------
# Check OS is supported

OS=`uname -s`
if [ "$OS" != 'Linux' ]; then
  echo "$PROG: error: unsupported operating system: $OS" >&2
  exit 1
fi

#----------------
# Detect package manager

FLAVOUR=

if which dnf > /dev/null 2>&1; then
  FLAVOUR=dnf
elif which yum > /dev/null 2>&1; then
  FLAVOUR=yum
elif which apt-get > /dev/null 2>&1; then
  FLAVOUR=apt
else
  echo "$PROG: error: could not find package manager: dnf, yum or apt-get" >&2
  exit 1
fi

#----------------
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

#----------------
# Check if runing with root privileges

if [ `id -u` != '0' ]; then
  echo "$PROG: error: this script requires root privileges" >&2
  exit 1
fi

#----------------------------------------------------------------
# Start log

TIMESTAMP=`date '+%F %T %:z'`

echo "$PROG: $TIMESTAMP" >>"$LOG" 2>&1

#----------------------------------------------------------------
# Install packages (if they are not already installed)

if [ $ACTION != 'umount' ]; then
  # Not doing unmount (i.e. doing mount or autofs)
  # Check and install NFS client and ifup/ifdown
  #
  # Don't do this if unmounting, since it is assumed the script has already
  # been run at least once (to mount it) and therefore these packages have
  # already been installed.
  
  #----------------
  # Install NFS client
  
  if [ "$FLAVOUR" = 'dnf' ]; then
  
    # nfs-utils
    if ! rpm -q nfs-utils > /dev/null; then
      # Package not installed: install it
      if [ -n "$VERBOSE" ]; then
	echo "$PROG: installing package: nfs-utils"
      fi
      dnf -y install "nfs-utils" >>"$LOG" 2>&1
    fi
  
  elif [ "$FLAVOUR" = 'yum' ]; then
  
    # nfs-utils
    if ! rpm -q nfs-utils > /dev/null; then
      # Package not installed: install it
      if [ -n "$VERBOSE" ]; then
	echo "$PROG: installing package: nfs-utils"
      fi
      yum -y install "nfs-utils" >>"$LOG" 2>&1
    fi
  
  elif [ "$FLAVOUR" = 'apt' ]; then
  
    # nfs-common
    if ! dpkg-query --status "nfs-common"  >/dev/null 2>&1; then
      # Package not installed: install it
      if [ -n "$VERBOSE" ]; then
	echo "$PROG: installing package: nfs-common"
      fi
      apt-get -y --no-upgrade install "nfs-common" >>"$LOG" 2>&1
    fi
  
  else
    echo "$PROG: internal error: bad install flavour: $FLAVOUR" >&2
    rm "$LOG"
    exit 3
  fi
  
  #----------------
  # Install ifup and ifdown
  
  if [ "$FLAVOUR" = 'yum' ]; then

    # Check: all supported distributions of CentOS have ifup/ifdown
    if ! which ifup >/dev/null 2>&1; then
      echo "$PROG: error: command not found: ifup" >&2
      rm "$LOG"
      exit 1
    fi
    if ! which ifdown >/dev/null 2>&1; then
      echo "$PROG: error: command not found: ifdown" >&2
      rm "$LOG"
      exit 1
    fi

  elif [ "$FLAVOUR" = 'dnf' ]; then

    # Check: some supported distributions of Fedora have ifup/ifdown some don't
    if ! which ifup >/dev/null 2>&1; then
      # Starting with Fedora 29, ifup and ifdown is a legacy network script
      if [ -n "$VERBOSE" ]; then
	echo "$PROG: installing package: network-scripts"
      fi
      dnf -y install "network-scripts" >>"$LOG" 2>&1
    fi
    if ! which ifdown >/dev/null 2>&1; then
      echo "$PROG: error: command not found: ifdown" >&2
      rm "$LOG"
      exit 1
    fi
    
  elif [ "$FLAVOUR" = 'apt' ]; then
  
    # Need ifup/ifdown

    # It is not installed by default in newer distributions
    # (e.g. Ubuntu 17.10). Need to use them because 'ip link set dev eth1 up'
    # does not read the config files.

    if ! dpkg-query --status "ifupdown"  >/dev/null 2>&1; then
      # Package not installed: install it
      if [ -n "$VERBOSE" ]; then
	echo "$PROG: installing package: ifupdown"
      fi
      apt-get -y --no-upgrade install "ifupdown" >>"$LOG" 2>&1
    fi

    if ! which ifup >/dev/null 2>&1; then
      echo "$PROG: error: ifupdown: command not found: ifup" >&2
      rm "$LOG"
      exit 1
    fi
    if ! which ifdown >/dev/null 2>&1; then
      echo "$PROG: error: ifupdown: command not found: ifdown" >&2
      rm "$LOG"
      exit 1
    fi
  
  else
    echo "$PROG: internal error: bad install flavour: $FLAVOUR" >&2
    rm "$LOG"
    exit 3
  fi
fi

#----------------
# Install autofs automounter

# yum -y $QUIET_FLAG update
# apt-get update

if [ $ACTION = 'autofs' ]; then
  # Doing autofs: check and install autofs package.
  #
  # Note: don't install autofs if user only wants to use ad hoc mounting.
  # No sense installing autofs if they might not want it.

  if [ "$FLAVOUR" = 'dnf' ]; then
  
    # Install autofs
  
    if ! rpm -q autofs > /dev/null; then
      # Package not installed: install it
      if [ -n "$VERBOSE" ]; then
	echo "$PROG: installing package: autofs"
      fi
      dnf -y install "autofs" >>"$LOG" 2>&1
    fi
  
  elif [ "$FLAVOUR" = 'yum' ]; then
  
    # Install autofs
  
    if ! rpm -q autofs > /dev/null; then
      # Package not installed: install it
      if [ -n "$VERBOSE" ]; then
	echo "$PROG: installing package: autofs"
      fi
      yum -y install "autofs" >>"$LOG" 2>&1
    fi
  
  elif [ "$FLAVOUR" = 'apt' ]; then
  
    # Install autofs

    if ! dpkg-query --status "autofs"  >/dev/null 2>&1; then
      # Package not installed: install it
      if [ -n "$VERBOSE" ]; then
	echo "$PROG: installing package: autofs"
      fi
      apt-get -y --no-upgrade install "autofs" >>"$LOG" 2>&1
    fi
  
  else
    echo "$PROG: internal error: bad install flavour: $FLAVOUR" >&2
    rm "$LOG"
    exit 3
  fi
fi

#----------------------------------------------------------------
# Set the mount options to use

MOUNT_OPTIONS="$MOUNT_OPTIONS_BASE"

if [ $FLAVOUR = 'dnf' ]; then
  MOUNT_OPTIONS="$MOUNT_OPTIONS,$MOUNT_OPTIONS_DNF_YUM"
elif [ $FLAVOUR = 'yum' ]; then
  MOUNT_OPTIONS="$MOUNT_OPTIONS,$MOUNT_OPTIONS_DNF_YUM"
elif [ $FLAVOUR = 'apt' ]; then
  MOUNT_OPTIONS="$MOUNT_OPTIONS,$MOUNT_OPTIONS_APT"
else
  echo "$PROG: internal error: unknown flavour: $FLAVOUR" >&2
  rm "$LOG"
  exit 3
fi

if [ -z "$READ_ONLY" ]; then
  MOUNT_OPTIONS="rw,$MOUNT_OPTIONS"
else
  MOUNT_OPTIONS="ro,$MOUNT_OPTIONS"
fi

echo "$PROG: mount options: $MOUNT_OPTIONS" >>"$LOG"

#----------------------------------------------------------------
# Configure private network interface

I_CONFIGURED_ETH1=

if [ "$FLAVOUR" = 'dnf' -o "$FLAVOUR" = 'yum' ]; then

  # Configure eth1

  ETH1_CFG=/etc/sysconfig/network-scripts/ifcfg-eth1

  if [ ! -f "$ETH1_CFG" ]; then
    # eth1 not configured: create eth1 configuration file

    if [ -n "$VERBOSE" ]; then
      echo "$PROG: eth1: creating config file: $ETH1_CFG"
    fi

    cat > "$ETH1_CFG" <<EOF
# ifcfg-eth1: QRIScloud internal network interface
# Created by $PROG on $TIMESTAMP
#
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
# unexpectedly stop working. Unless NetworkManager is properly configured, it
# is better to disable it. NetworkManager is useful a dynamically changing
# network environment (such as a portable laptop), but less useful for a static
# server environment.

NM_CONTROLLED="no"

# MTU size
#
# The MTU size should be configured by DHCP. If not, uncomment these lines.
# There is a known problem with some releases of OpenStack that prevents
# setting the MTU size by DHCP from working. Until that is fixed, this
# configures it.

# MTU=9000
# IPV6_MTU=9000
EOF

    # Bring up the network interface
    # Do not use "ip link set dev eth1 up" since it doesn't read ifcfg-eth1

    ifup eth1  >>"$LOG" 2>&1

    # Check MTU packet size

    if ! ip link show dev eth1 | grep -q ' mtu 9000 '; then
      # MTU is not 9000: explicitly configure it to be 9000.
      #
      # In early-2018, OpenStack has made a change so using DHCP to set the
      # MTU size does not work. This code is to work around it.
      #
      # First, try and set the MTU in the network configuration.

      if [ -n "$VERBOSE" ]; then
        echo "$PROG: eth1: MTU DHCP not working: adding MTU 9000 config"
      fi

      # Uncomment the MTU configuration lines

      sed -i 's/^# *\(.*MTU=9000\) *$/\1/' "$ETH1_CFG"

      # Restart the interface to use MTU 9000 configuration
      # Do not use "ip link set dev eth1 up" since it doesn't read ifcfg-eth1

      ifdown eth1  >>"$LOG" 2>&1
      ifup eth1  >>"$LOG" 2>&1

      # Check MTU packet size (after MTU 9000 configuration added)

      if ! ip link show dev eth1 | grep -q ' mtu 9000 '; then
	# MTU is still not 9000: add command to explicitly set it
	#
	# The configuration of MTU 9000 did not work. On some
	# distibutions, the above MTU configuration works (e.g. CentOS
	# 7 and Fedora 26), but other distributions (e.g. CentOS 6.7
	# and Scientific Linux 6.8) seem to use the (wrong) MTU value
	# from DHCP in preference to the value from the
	# configuration. On these systems, run a command to explicitly
	# set the MTU to 9000 (below).

	POST_FILE=/etc/sysconfig/network-scripts/ifup-post

	if [ -n "$VERBOSE" ]; then
          echo "$PROG: eth1: MTU config not working: adding MTU 9000 command to $POST_FILE"
	fi

	# Append extra commands just before the "exit 0" at the end of the file
	awk "
/^exit 0\s*$/ {
            print \"# Set the MTU to 9000 on eth1 (the QRIScloud private network interface)\"
            print \"# Added by $PROG on $TIMESTAMP\"
            print \"if [ \\\"\$REALDEVICE\\\" = \\\"eth1\\\" ]; then\"
            print \"  /sbin/ip link set \$REALDEVICE mtu 9000\"
            print \"fi\"
            print \"\"
          }
1 # print all other lines
" "$POST_FILE" > "${POST_FILE}.tmp$$"
	chmod 755 "${POST_FILE}.tmp$$"
	mv "${POST_FILE}.tmp$$" "$POST_FILE"

	# Restart the interface so the command in ifup-post runs
	# Do not use "ip link set dev eth1 up" since it doesn't use ifup-post

	ifdown eth1  >>"$LOG" 2>&1
	ifup eth1  >>"$LOG" 2>&1
      fi
    fi

    I_CONFIGURED_ETH1="$ETH1_CFG"
  fi

  #----------------
elif [ "$FLAVOUR" = 'apt' ]; then

  IF_FILE=/etc/network/interfaces

  if [ ! -f "$IF_FILE" ]; then
    echo "$PROG: file missing: $IF_FILE" >&2
    rm "$LOG"
    exit 1
  fi

  if ! grep -q 'eth1' "$IF_FILE"; then
    # eth1 not yet configured: append eth1 lines to the interfaces file

    cat >> "$IF_FILE" <<EOF

# The secondary network interface (QRIScloud internal network interface)
# Added by $PROG on $TIMESTAMP
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
    # Do not use "ip link set dev eth1 ...": it does not get the IPv4 address

    ifup eth1  >>"$LOG" 2>&1

    # Check MTU packet size

    if ! ip link show dev eth1 | grep -q ' mtu 9000 '; then
      # MTU is not 9000: explicitly configure it to be 9000.
      #
      # In early-2018, OpenStack has made a change so using DHCP to set the
      # MTU size does not work. This code is to work around it.

      if [ -n "$VERBOSE" ]; then
        echo "$PROG: eth1: DHCP MTU not working: configuring MTU 9000"
      fi

      # Uncomment the MTU configuration line

      sed -i 's/^# *\(post-up.*mtu 9000\) *$/\1/' "$IF_FILE"

      # Restart the interface to use MTU 9000 configuration
      # Do not use "ip link set dev eth1 ...": it does not get the IPv4 address

      ifdown eth1  >>"$LOG" 2>&1
      ifup eth1  >>"$LOG" 2>&1
    fi

    I_CONFIGURED_ETH1="$IF_FILE"
  fi

else
  echo "$PROG: internal error" >&2
  rm "$LOG"
  exit 3
fi

# Check MTU packet size

if ! ip link show dev eth1 | grep -q ' mtu 9000 '; then
  echo "$PROG: error: eth1: MTU != 9000 (please contact QRIScloud Support)" >&2
  rm "$LOG"
  exit 1
fi

# Get the eth1 IPv4 address (it will be needed to lookup the NFS export path)

MYIP=`ip addr show dev eth1 scope global | grep 'inet ' | sed 's/^ *inet \(.*\)\/.*/\1/'`
if [ -z "$MYIP" ]; then
  echo "$PROG: error: eth1: no IPv4 address (please contact QRIScloud Support)" >&2
  rm "$LOG"
  exit 1
fi

#----------------------------------------------------------------
# Check NFS servers are accessible

echo "$PROG: pinging NFS servers to see if they are contactable" >>"$LOG"

PING_GOOD=
PING_ERROR=
for NFS_SERVER in ${NFS_SERVERS}; do
  if ! ping -q -c 4 $NFS_SERVER >>"$LOG" 2>&1; then
    PING_ERROR="$PING_ERROR $NFS_SERVER"
  else
    PING_GOOD="$PING_GOOD $NFS_SERVER"
  fi
done

if [ -z "$PING_GOOD" ]; then
  # None of the NFS servers were pingable: probably a network problem?
  echo "$PROG: error: none of the NFS server can be pinged:$PING_ERROR" >&2
  echo "$PROG: error: none of the NFS server can be pinged:$PING_ERROR" >>"$LOG"
  if [ -z "$I_CONFIGURED_ETH1" ]; then
    echo "$PROG: please check $I_CONFIGURED_ETH1" >&2
  fi
  rm "$LOG"
  exit 1
elif [ -n "$PING_ERROR" ]; then
  # Some good, some bad
  if [ -n "$VERBOSE" ]; then
    echo "$PROG: warning: cannot ping some NFS servers:$PING_ERROR" >>"$LOG"
    echo "$PROG: mount might be ok if your allocation is not on them." >>"$LOG"
    echo "$PROG: mount will fail if it is." >>"$LOG"
  fi
else
  # All good
  :
fi

echo "$PROG: ping done" >>"$LOG"
echo >>"$LOG"

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
$PROG: error: no export for $ALLOC_SPEC to this machine ($MYIP)

  CHECK this machine is running in the Nectar project nominated for NFS access.

  If it is, PLEASE WAIT AND TRY AGAIN. Looking up the NFS export path
  does not always work if the NFS server is highly loaded.  Also, it
  can take up to 5 minutes after launching for the NFS export to be
  available.

  If it does not work after a few retries, either specify the NFS export path
  (which can be found on https://services.qriscloud.org.au) instead of just
  "${ALLOC_SPEC}", or contact QRIScloud support.

EOF
      rm "$LOG"
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
    rm "$LOG"
    exit 1
  fi

  if [ -n "$VERBOSE" ]; then
    echo "$PROG: mount: $VALUE"
  fi

  # Append to list

  EXPORT_PATHS="${EXPORT_PATHS} ${VALUE}"
done

echo "$PROG: export paths: $EXPORT_PATHS" >>"$LOG"

#----------------------------------------------------------------
# Perform desired action. Overview of the remaining code:
#
# if (autofs or mount) {
#   create users and groups
# }
#
# if (mount) {
#    ad hoc mounting
# }
# else if (umount) {
#    ad hoc unmounting
# }
# else if (autofs) {
#   configure autofs
# }
#
# exit 0

#----------------------------------------------------------------
# Create group and users (if needed)

if [ $ACTION = 'autofs' -o $ACTION = 'mount' ]; then
  # Create group and users (needed for both autofs and ad hoc mounting)

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
    rm "$LOG"
    exit 3
  fi
fi
    
#----------------------------------------------------------------
# Ad hoc mounting

if [ $ACTION = 'mount' ]; then

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
    rm "$LOG"
    exit 1
  fi

#----------------------------------------------------------------
# Ad hoc unmounting

elif [ $ACTION = 'umount' ]; then
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
    rm "$LOG"
    exit 1
  fi

#----------------------------------------------------------------

elif [ $ACTION = 'autofs' ]; then
  # Configure autofs automounter
  
  # Create direct map file
  
  DMAP=/etc/auto.qriscloud
  
  if [ -n "$VERBOSE" ]; then
    echo "$PROG: configuring autofs: creating direct map: $DMAP"
  fi
  
  TMP="$DMAP".tmp-$$
  
  echo "# autofs mounts for storage" > "$TMP"
  
  for NFS_EXPORT in $EXPORT_PATHS; do
    ALLOC=`alloc_from_nfs_path $NFS_EXPORT`
  
    echo "$DIR/$ALLOC -$MOUNT_OPTIONS,$MOUNT_AUTOFS_EXTRA $NFS_EXPORT" >> "$TMP"
  done
  
  mv "$TMP" "$DMAP"
  
  # Modify master map file
  
  if ! grep -q "^/- file:$DMAP\$" /etc/auto.master; then
    # Add entry to the master map, because it is not yet in there
  
    if [ -n "$VERBOSE" ]; then
      echo "$PROG: configuring autofs: modifying master: /etc/auto.master"
    fi
    echo "/- file:$DMAP" >> /etc/auto.master
  fi
  
  # Restart autofs service (so it uses the new configuration)
  
  if [ -n "$VERBOSE" ]; then
    echo "$PROG: configuring autofs: autofs service: restarting..."
  fi
  echo >>"$LOG"
  echo "$PROG: Restarting autofs service..." >>"$LOG"
  
  if which systemctl >/dev/null 2>&1; then
    # Systemd is used (e.g. CentOS 7)
    systemctl enable autofs.service  >>"$LOG" 2>&1
    systemctl restart autofs.service  >>"$LOG" 2>&1
  else
    # Init.d is used (e.g. CentOS 6)
    service autofs restart  >>"$LOG" 2>&1
  fi
  
  if [ -n "$VERBOSE" ]; then
    echo "$PROG: configuring autofs: autofs service: restarted"
  fi
  
  # Check mounts work
  
  sleep 1  # needed, otherwise sometimes the mounts fail the test below
  
  ERROR=
  for NFS_EXPORT in $EXPORT_PATHS; do
    ALLOC=`alloc_from_nfs_path $NFS_EXPORT`
  
    if ! ls "$DIR/$ALLOC" >/dev/null 2>&1; then
      echo "$PROG: failed to mount: $DIR/$ALLOC" >>"$LOG"
      echo "$PROG: error: autofs configured, but didn't mount: $DIR/$ALLOC" >&2
      ERROR=yes
    else
      echo "$PROG: autofs mount successful: $DIR/$ALLOC" >>"$LOG"
      echo "$PROG: autofs mount successful: $DIR/$ALLOC"
    fi
  done
  
  if [ -n "$ERROR" ]; then
    # Unsuccessful: leave log file
  
    cat >&2 <<EOF
    Failures to mount could be because the NFS server is highly loaded.
    If the problem persists, please contact QRIScloud Support.
EOF
  
    echo "$PROG: error \(see $LOG for details\)" >&2
    exit 1
  fi

else

#----------------------------------------------------------------
# Bad ACTION  

  echo "$PROG: internal error: bad action: $ACTION" >&2
  rm "$LOG"
  exit 3
fi

#----------------------------------------------------------------
# Success: clean up and exit

rm "$LOG"

exit 0

#----------------------------------------------------------------
#EOF
