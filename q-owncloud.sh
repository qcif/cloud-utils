#!/bin/sh
#
# Setup ownCloud on Ubuntu.
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

HOST=`hostname`

DATA_DIR=/mnt/data

#----------------------------------------------------------------
# Checks

# Check this is running on the expected OS and distribution

FORCE=
if [ -z "$FORCE" ]; then
  OS=`uname -s`
  if [ "$OS" != 'Linux' ]; then
    echo "$PROG: error: unsupported operating system: $OS"
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

  if [ "$DISTRO" = 'Ubuntu 13.04' -o \
       "$DISTRO" = 'Ubuntu 12.10' ]; then
    :
  else
    echo "$PROG: error: unsupported distribution: $DISTRO"
    exit 1
  fi
else
  :
fi

# Check this is running with root privileges

if [ `id -u` != '0' ]; then
  echo "$PROG: this script requires root privileges (try 'sudo $0')" >&2
  exit 1
fi

# Detect if running from a pipe. For download and running "curl ... | sudo sh"

INTERACTIVE=yes

ls -l /proc/self/fd/0 | grep \/dev\/pts\/[0-9] > /dev/null
if [ $? -ne 0 ]; then
  INTERACTIVE=
fi

# Check arguments

if [ $# -eq 0 ]; then
  INTERACTIVE=yes
elif [ $# -eq 1 ]; then
  if [ "$1" = '-y' -o "$1" = '--yes' ]; then
    INTERACTIVE=
  else
    echo "Usage: $PROG [-y | --yes]" >&2
    exit 2
  fi
else
  echo "Usage: $PROG [-y | --yes]" >&2
  exit 2
fi

#----------------------------------------------------------------
# Prompt user

if [ -n "$INTERACTIVE" ]; then
  /bin/echo -n "Install ownCloud on this machine ($HOST) [yes/NO]? "
  read ANSWER
  if [ "$ANSWER" != 'yes' ]; then
    echo "$PROG: aborted"
    exit 1
  fi
fi

echo
/bin/echo -n "When prompted, you must set a password for the MySQL root account"
sleep 3; /bin/echo -n .
sleep 1; /bin/echo -n .
sleep 1; /bin/echo -n .
sleep 1; echo; echo

#----------------------------------------------------------------
# Do install

# Put hostname in /etc/hosts so it can resolve
# This shuts up the warning when the self-signed certificate is generated
# during the installation process (as well as the warning when sudo is run).
sed -i "s/127.0.0.1\s\s*localhost/127.0.0.1 $HOST localhost/" /etc/hosts

# Install ownCloud Ubuntu packages

echo "Updating package lists..."
apt-get --quiet --quiet update

apt-get --quiet --yes install owncloud # prompts for MySQL "root" password

# Create the data directory
if [ ! -d "$DATA_DIR" ]; then
  mkdir "$DATA_DIR" || exit 1
fi
chown www-data:www-data "$DATA_DIR" || exit 1

# Additional configuration of Apache2

## Set the ServerName
echo "ServerName $HOST" > /etc/apache2/conf.d/local-servername

## Remove the ownCloud configuration from global (so it doesn't run in
## the insecure HTTP site).
rm -f /etc/apache2/conf.d/owncloud.conf

## Put the ownCloud configurations in the SSL site

DEF_SSL=/etc/apache2/sites-available/default-ssl
grep owncloud.conf ${DEF_SSL} > /dev/null
if [ $? -ne 0 ]; then
  # The owncloud.conf line has not been added: add it
  cp -a ${DEF_SSL} ${DEF_SSL}.bak || exit 1
  awk '/<\/VirtualHost>/ {print "\tInclude conf-available/owncloud.conf"}{print}' ${DEF_SSL}.bak > ${DEF_SSL} || exit 1
  rm ${DEF_SSL}.bak || exit 1
fi

# Enable the Apache2 SSL module and enable an SSL site

a2enmod ssl
a2ensite default-ssl

# Restart Apache2 so it picks up all the new configurations

service apache2 restart

#----------------------------------------------------------------
# Final message

IPADDR=`ifconfig eth0 | grep "inet addr" | sed 's/.*inet addr:\([^ ]*\).*/\1/'`

echo
echo "ownCloud installed"
echo "Visit <https://$IPADDR/owncloud> and enter the following:"
echo "  Username: (choose your own username)"
echo "  Password: (choose your own password)"
echo "  Data folder: /mnt/data"
echo "  Database user: root"
echo "  Database password: (the MySQL root password you used)"
echo "  Database name: (choose your own database name, e.g. \"owncloud\")"
echo "  Database host: localhost"

#EOF
