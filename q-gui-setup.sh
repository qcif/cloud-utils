#!/bin/sh
#
# Setup of X-Windows on a virtual machine instance.
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

#----------------------------------------------------------------
# Process command line arguments

FORCE=
VERBOSE=
QUIET=

getopt -T > /dev/null
if [ $? -eq 4 ]; then
  # GNU enhanced getopt is available
  ARGS=`getopt --name "$PROG" --long help,output:,force,quiet,verbose --options ho:fqv -- "$@"`
else
  # Original getopt is available (no long option names nor whitespace)
  ARGS=`getopt ho:fqv "$@"`
fi
if [ $? -ne 0 ]; then
  echo "$PROG: usage error (use -h for help)" >&2
  exit 1
fi
eval set -- $ARGS

while [ $# -gt 0 ]; do
    case "$1" in
        -h | --help)     HELP=yes;;
        -f | --force)    FORCE=yes;;
        -q | --quiet)    QUIET=yes;;
        -v | --verbose)  VERBOSE=yes;;
        --)              shift; break;;
    esac
    shift
done

if [ -n "$HELP" ]; then
  echo "Usage: $PROG [options] newUserNames..."
  echo "Options:"
  echo "  -f | --force    run on untested operating system (use with caution)"
  echo "  -q | --quiet    suppress status output"
  echo "  -v | --verbose  output extra information"
  echo "  -h | --help     show this message"
  exit 0
fi

# Process command line arguments

if [ $# -lt 1 ]; then
  echo "$PROG: usage error: missing usernames (use -h for help)" >&2
  exit 2
fi

# Check if all usernames are syntatically correct

ERROR=
for USERNAME in "$@"
do
  echo "$USERNAME" | grep '^[A-Za-z_][0-9A-Za-z_-]*$' > /dev/null
  if [ $? -ne 0 ]; then
    echo "Usage error: format not valid for a username: $USERNAME" >&2
    ERROR=1 
  fi
done
if [ -n "$ERROR" ]; then
  exit 2
fi

if [ $# -gt 1 ]; then
  echo "$PROG: warning: current implementation only uses first username" >&2
fi

#----------------------------------------------------------------
# Check pre-conditions

# Check if running on expected operating system and distribution

if [ -z "$FORCE" ]; then
  OS=`uname -s`
  if [ "$OS" != 'Linux' ]; then
    echo "$PROG: error: unsupported operating system: $OS (use --force?)"
    exit 1
  fi
  ISSUE=`head -1 /etc/issue`
  if [ "$ISSUE" != 'CentOS release 6.4 (Final)' -a \
       "$ISSUE" != 'Scientific Linux release 6.4 (Carbon)' ]; then
    echo "$PROG: error: unsupported distribution: $ISSUE (use --force?)"
    exit 1
  fi
fi

# Check if run with necessary privileges

if [ `id -u` != '0' ]; then
  echo "$PROG: this script requires root privileges" >&2
  exit 1
fi

# Check if user accounts already exist

ERROR=
for USERNAME in "$@"
do
  grep "^$USERNAME:" /etc/passwd > /dev/null
  if [ $? -eq 0 ]; then
    echo "$PROG: error: user account already exists: $USERNAME" >&2
    exit 1
  fi
done
if [ -n "$ERROR" ]; then
  exit 2
fi

#----------------------------------------------------------------

function die () {
  echo "$PROG: error encountered" >&2
  exit 1
}

#----------------------------------------------------------------
# Make sure hostname resolves (otherwise vncserver will not start)

HOSTNAME=`hostname`

ping -c 1 "$HOSTNAME" > /dev/null 2>&1
if [ $? -ne 0 ]; then
  # Hostname not resolving: add entry for it in /etc/hosts file

  if [ -z "$QUIET" ]; then
    echo "Adding hostname to /etc/hosts: $HOSTNAME"
  fi

  echo "127.0.0.1   $HOSTNAME" >> /etc/hosts

  # Check it now works
  ping -c 1 "$HOSTNAME" > /dev/null 2>&1
  if [ $? -ne 0 ]; then
    echo "$PROG: internal error: could not resolve $HOSTNAME" >&2
    exit 1
  fi
fi

#----------------------------------------------------------------
# Installing packages

if [ -n "$VERBOSE" ]; then
  YUM_QUIET_FLAG=
else
  YUM_QUIET_FLAG="-q"
fi

# yum $YUM_QUIET_FLAG -y update || die

for GROUP in "X Window System" "Desktop" "Fonts"
do
  yum grouplist "$GROUP" | grep 'Installed Groups' > /dev/null
  if [ $? -ne 0 ]; then
    # Group not installed: install it
    if [ -z "$QUIET" ]; then
      echo "Installing group: $GROUP"
    fi
    yum $YUM_QUIET_FLAG -y groupinstall "$GROUP" || die

  else
    # Group already installed
    if [ -n "$VERBOSE" ]; then
      echo "Group already installed: $GROUP"
    fi
  fi
done

# Install VNC server

for PACKAGE in "tigervnc-server"
do
  rpm -q "$PACKAGE" > /dev/null
  if [ $? -ne 0 ]; then
    # Package not installed: install it

    if [ -z "$QUIET" ]; then
      echo "Installing package: $PACKAGE"
    fi
    yum $YUM_QUIET_FLAG -y install "$PACKAGE" || die

  else
    # Package already installed
    if [ -n "$VERBOSE" ]; then
      echo "Package already installed: $PACKAGE"
    fi
  fi
done

# Extra check that VNC server configuration file is present

if [ ! -f '/etc/sysconfig/vncservers' ]; then
  echo "$PROG: error: VNC server not installed correctly: config file missing" >&2
  exit 1
fi

#----------------------------------------------------------------
# Create user and configure VNC server

for USERNAME in "$@"
do
  if [ -z "$QUIET" ]; then
    echo "Creating user account: $USERNAME"
  fi
  adduser "$USERNAME" || die

  echo "VNCSERVERS=\"0:$USERNAME\"" >> /etc/sysconfig/vncservers
  echo "VNCSERVERARGS[0]=\"-geometry 1024x768 -nolisten tcp -localhost\"" >> /etc/sysconfig/vncservers

  echo "Please supply a password to use as the VNC password for $USERNAME"
  su "$USERNAME" -c vncpasswd || die
done


#----------------------------------------------------------------
# Configure VNC server to start on boot up and run it now

chkconfig vncserver on || die

if [ -z "$QUIET" ]; then
  echo "Starting VNC server"
fi
service vncserver start || die

#----------------------------------------------------------------

echo "Success"
echo "  To use VNC, create a ssh tunnel to port 5900 of this machine and"
echo "  run a VNC client (which will prompt for the password that was entered)."
echo "  e.g. ssh -L 9999:localhost:5900 ec2-user@???.???.???.???"
echo
echo "  It is recommended that passwords be set on the new user accounts,"
echo "  to unlock any screensavers that might run."
for USERNAME in "$@"
do
  echo "      passwd $USERNAME"
done
exit 0

#----------------------------------------------------------------
#EOF
