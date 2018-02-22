#!/bin/sh
#
# Setup of X-Windows on a virtual machine instance.
#
# This script is no longer being maintained. It only works with CentOS
# 6.4, CentOS 6.9 and Scientific Linux 6.4.  It won't work with CentOS
# 7, because there has been significant changes. If you are interested in
# helping update this script, please contact QRIScloud Support.**
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
PASSWORD=
VERBOSE=
QUIET=

getopt -T > /dev/null
if [ $? -eq 4 ]; then
  # GNU enhanced getopt is available
  ARGS=`getopt --name "$PROG" --long help,password:,force,quiet,verbose --options hp:fqv -- "$@"`
else
  # Original getopt is available (no long option names nor whitespace)
  ARGS=`getopt hp:fqv "$@"`
fi
if [ $? -ne 0 ]; then
  echo "$PROG: usage error (use -h for help)" >&2
  exit 1
fi
eval set -- $ARGS

while [ $# -gt 0 ]; do
    case "$1" in
        -h | --help)     HELP=yes;;
        -p | --password) PASSWORD="$2"; shift;;
        -f | --force)    FORCE=yes;;
        -q | --quiet)    QUIET=yes;;
        -v | --verbose)  VERBOSE=yes;;
        --)              shift; break;;
    esac
    shift
done

if [ -n "$HELP" ]; then
  echo "Usage: $PROG [options] userNames..."
  echo "Options:"
  echo "  -p | --password str  use this VNC password instead of a random one"
  echo "  -f | --force         run on untested system (use with caution)"
  echo "  -q | --quiet         suppress status output"
  echo "  -v | --verbose       output extra information"
  echo "  -h | --help          show this message"
  exit 0
fi

# Process command line arguments

if [ $# -lt 1 ]; then
  echo "$PROG: usage error: missing usernames (use -h for help)" >&2
  exit 2
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

  if [ -r '/etc/system-release' ]; then
    ISSUE=`cat /etc/system-release`
  else
    ISSUE=`head -1 /etc/issue`
  fi
  if [ "$ISSUE" != 'CentOS release 6.4 (Final)' -a \
		"$ISSUE" != 'CentOS release 6.9 (Final)' -a \
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

# Check if all users exist

ERROR=
for USERNAME in "$@"
do
  id "$USERNAME" > /dev/null 2>&1
  if [ $? -ne 0 ]; then
    echo "Error: user does not exist: $USERNAME" >&2
    ERROR=1
  fi
done
if [ -n "$ERROR" ]; then
  exit 1
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

INSTALLED_VNC_SERVER=

for PACKAGE in "tigervnc-server"
do
  rpm -q "$PACKAGE" > /dev/null
  if [ $? -ne 0 ]; then
    # Package not installed: install it

    if [ -z "$QUIET" ]; then
      echo "Installing package: $PACKAGE"
    fi
    yum $YUM_QUIET_FLAG -y install "$PACKAGE" || die

    INSTALLED_VNC_SERVER=yes

  else
    # Package already installed
    if [ -n "$VERBOSE" ]; then
      echo "Package already installed: $PACKAGE"
    fi
  fi
done

if [ -n "$INSTALLED_VNC_SERVER" ]; then
  # Configure VNC server to start on boot up and run it now

  if [ -z "$QUIET" ]; then
    echo "Configuring VNC server to start at boot up"
  fi
  chkconfig vncserver on || die

else
  # Stop VNC server

  service vncserver stop || die
fi

#----------------------------------------------------------------
# Create user and configure VNC server

VNC_CONFIG='/etc/sysconfig/vncservers'

# Check that VNC server configuration file is present

if [ ! -f "$VNC_CONFIG" ]; then
  echo "$PROG: error: VNC server not installed correctly: config file missing: $VNC_CONFIG" >&2
  exit 1
fi

# Strip out existing configurations

mv "$VNC_CONFIG" "${VNC_CONFIG}.bak" || die
grep -v ^VNCSERV "${VNC_CONFIG}.bak" > "$VNC_CONFIG" || die

# Create new configurations

VNC_PARAMS="-geometry 1024x768 -nolisten tcp -localhost"
COUNT=0

if [ -z "$QUIET" ]; then
  echo
  echo "---"
fi

VALUE=

for USERNAME in "$@"
do
  if [ -z "$QUIET" ]; then
    echo "User: $USERNAME"
    echo "  VNC server $COUNT: port `expr 5900 + $COUNT`"
  fi

  # Build up list of display:user pairs
  if [ -n "$VALUE" ]; then
    VALUE="$VALUE "
  fi
  VALUE="$VALUE$COUNT:$USERNAME"

  # VNC server arguments
  echo "VNCSERVERARGS[$COUNT]=\"$VNC_PARAMS\"" >> $VNC_CONFIG

  COUNT=`expr $COUNT + 1`

  PWFILE="/home/$USERNAME/.vnc/passwd"
  if [ ! -f "$PWFILE" ]; then
    # VNC password file for user does not exist: create it

    PWDIR=`dirname "$PWFILE"`
    if [ ! -d "$PWDIR" ]; then
      # Create directory as that user so owner and group are correct
      su "$USERNAME" -c "mkdir \"$PWDIR\"" || die
      chmod g-w "$PWDIR" || die
      chmod o-w "$PWDIR" || die
    fi

    if [ -z "$PASSWORD" ]; then
      # Make up a random password
      # vncpasswd uses only the first 8 chars, so "6" binary bytes is enough
      PASSWORD=`openssl rand -base64 6`
    fi

    if [ -z "$QUIET" ]; then
      echo "  VNC password: setting with vncpasswd: $PASSWORD"
    fi

    su "$USERNAME" -c "touch \"$PWFILE\"" # create file as that user
    chmod 600 "$PWFILE" || die

    echo "$PASSWORD" | vncpasswd -f > "$PWFILE"

  else
    # VNC password file for user exists
    if [ -z "$QUIET" ]; then
      echo "  VNC password: using existing value"
    fi
  fi
done

echo "VNCSERVERS=\"$VALUE\"" >> $VNC_CONFIG

if [ -z "$QUIET" ]; then
  echo "---"
  echo
fi

rm "${VNC_CONFIG}.bak" || die

#----------------------------------------------------------------
# Starting VNC server

service vncserver start || die

#----------------------------------------------------------------

exit 0

#----------------------------------------------------------------
#EOF
