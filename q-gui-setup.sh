#!/bin/sh
#----------------------------------------------------------------

PROG=`basename $0`

#----------------------------------------------------------------
# Process command line arguments

FORCE=

getopt -T > /dev/null
if [ $? -eq 4 ]; then
  # GNU enhanced getopt is available
  ARGS=`getopt --name "$PROG" --long help,output:,force,verbose --options ho:fv -- "$@"`
else
  # Original getopt is available (no long option names nor whitespace)
  ARGS=`getopt ho:fv "$@"`
fi
if [ $? -ne 0 ]; then
  echo "$PROG: usage error (use -h for help)" >&2
  exit 1
fi
echo $ARGS
exit 1
eval set -- $ARGS

while [ $# -gt 0 ]; do
    case "$1" in
        -h | --help)     HELP=yes;;
        -o | --output)   OUTFILE="$2"; shift;;
        -f | --force)    FORCE=yes;;
        -v | --verbose)  VERBOSE=yes;;
        --)              shift; break;;
    esac
    shift
done

if [ -n "$HELP" ]; then
  echo "Usage: $PROG [options] newusername..."
  exit 0
fi

# Process command line arguments

if [ $# -lt 1 ]; then
  echo "$PROG: usage error: missing username (use -h for help)" >&2
  exit 2
fi
if [ $# -gt 1 ]; then
  echo "$PROG: usage error: too many arguments" >&2
  exit 2
fi

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

NEWUSER="$1"

#----------------------------------------------------------------
# Check pre-conditions

if [ -z "$FORCE" ]; then
  OS=`uname -s`
  if [ "$OS" != 'Linux' ]; then
    echo "$PROG: error: unsupported operating system: $OS (use --force?)"
    exit 1
  fi
  ISSUE=`head -1 /etc/issue`
  if [ "$ISSUE" != 'CentOS release 6.4 (Final)' ]; then
    echo "$PROG: error: unsupported distribution: $ISSUE (use --force?)"
    exit 1
  fi
fi

if [ `id -u` != '0' ]; then
  echo "$PROG: this script requires root privileges" >&2
  exit 1
fi

if [ -f '/etc/sysconfig/vncservers' ]; then
  echo "$PROG: error: VNC server is already installed" >&2
  exit 1
fi

grep "^$NEWUSER:" /etc/passwd > /dev/null
if [ $? -eq 0 ]; then
  echo "$PROG: error: user account already exists: $NEWUSER" >&2
  exit 1
fi


function check_ok () {
  if [ $? -ne 0 ]; then
    echo "$PROG: error encountered" >&2
    exit 1
  fi
}

#----------------------------------------------------------------
# Make sure hostname resolves (otherwise vncserver will not start)

HOSTNAME=`hostname`

ping -c 1 "$HOSTNAME" > /dev/null 2>&1
if [ $? -ne 0 ]; then
  # Hostname not resolving: add entry for it in /etc/hosts file

  echo "127.0.0.1   $HOSTNAME" >> /etc/hosts

  # Check it now works
  ping -c 1 "$HOSTNAME" > /dev/null 2>&1
  if [ $? -ne 0 ]; then
    echo "$PROG: internal error: could not resolve $HOSTNAME" >&2
    exit 1
  fi
fi

# Install X11

yum -y update
check_ok

yum -y groupinstall "X Window System" "Desktop" "Fonts"
check_ok

# Install VNC server

yum -y install "tigervnc-server"
check_ok

if [ ! -f '/etc/sysconfig/vncservers' ]; then
  echo "$PROG: error: VNC server was not installed correctly" >&2
  exit 1
fi

# Create user and configure VNC server

adduser "$NEWUSER"
check_ok

echo "VNCSERVERS=\"0:$NEWUSER\"" >> /etc/sysconfig/vncservers
echo "VNCSERVERARGS[0]=\"-geometry 1024x768 -nolisten tcp -localhost\"" >> /etc/sysconfig/vncservers

echo "Please supply a password to use as the VNC password for $NEWUSER"
su "$NEWUSER" -c vncpasswd
check_ok

chkconfig vncserver on
check_ok

service vncserver start
check_ok

#----------------------------------------------------------------

echo "Success"
echo "  To use VNC, create a ssh tunnel to port 5900 of this machine and"
echo "  run a VNC client (which will prompt for the password that was entered)."
echo "  e.g. ssh -L 9999:localhost:5900 ec2-user@???.???.???.???"
exit 0

#----------------------------------------------------------------
#EOF
