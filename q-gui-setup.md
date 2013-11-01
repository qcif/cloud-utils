q-gui-setup
===========

Setup X11 and a VNC server on a Q-Cloud virtual machine instance to
run a graphical user interface.

Synopsis
--------

    q-gui-setup.sh
        [ -p | --password str ]
        [ -f | --force ]
        [ -v | --verbose] [ -q | --quiet ]
        username {username...}

Description
-----------

Installs the X Windows System and VNC and configures the
VNC server for a number of users.

This script will configure a set of user accounts to have VNC
servers. The first user's VNC server will be running on port 5900, the
second user on 5901, etc. These VNC servers will keep running after
the VNC client has disconnected from them, so you can return to the
VNC server later. There is one VNC server per user account.

The alternative method, of setting up a single VNC server with a login
screen, is not used. There are advantages and disadvantages with
either method. The VNC server per user approach was chosen because:
there will be very few users, so configuring each user and running a
separate VNC server for each is practical; users should be encouraged
to _ssh_ tunnel the unencrypted VNC traffic, so providing a graphical
login would not encourage them to do that; and it was easier to setup.

This script can be run multiple times. It only installs the packages
if they have not been installed and will not change any existing VNC
passwords. It will only create new VNC passwords for users that do not
have a VNC password.

Note: This script can take a long time to run, because it has to
download and install a number of _yum_ packages.

### Options

- `-p | --password str`  use this VNC password instead of a randomly generated
   value.

- `-f | --force` run on untested operating systems and distributions.

- `-q | --quiet` suppress normal output

- `-v | --verbose` show extra output (i.e. does not run _yum_ in quiet mode)

- `-h | --help` shows help information.

### Requirements

This script has been designed to run on RedHat Enterprise Linux (RHEL)
based distributions and has been tested on CentOS 6.4 64-bit and
Scientific Linux.

To force it to run on other RHEL-based distributions, use the `--force` option.

### Security

#### VNC password

A VNC password is required to access each VNC server. This is different from
the user account's password.

The VNC password is important, because it prevents anyone with access
to the VNC port to use the account. Even if firewalls block external
access to the ports, other users on the machine can still access the
port.

The script will generate a new random VNC password for the user, if a
VNC password does not already exist for that user. This VNC password
is printed out to _stdout_ (unless the `--quiet` option is used).  To
specify a value to use, instead of randomly generated values, use the
`--password` option.

To change the VNC password, run the `vncpasswd` program as that user
(use _sudo_ if you do not know the user account password for that
user).

    $ su jsmith -c vncpasswd
    $ sudo su jsmith -c vncpasswd

#### User login password

A user login password should be set for the user account, because it
will be required to unlock the screensaver.

Strictly speaking, a user login password is not required for access to
the VNC server. Access to the VNC server only requires the VNC
password and access to the VNC server port. If the VNC server port is
exposed to the external network, anyone can access it. If the VNC
server port is not exposed to the external network, a login to any
user account will allow a ssh tunnel to be established. That login can
be to the VNC user's account using ssh public keys or login to a
different account, so technically the user login password to the VNC
user's account is not needed -- as long as the screensaver is
disabled.

#### SSH tunnel

The VNC servers are set up to prevent remote VNC clients from
connectiong except through a secure tunnel. This setting
was chosen because VNC traffic is not encrypted.

Therefore, to connect to the VNC server an _ssh_ tunnel to any account
on the host is required (it can be, but does not have to be, the same
account as the VNC server).

The command line _ssh_ command creates ssh tunnels using the `-L`
option. Its argument is "[bind_address:]port:host:hostport" where the
bind_address is optional. This example tunnels port 15900 on the local
machine to port 5900 (the first VNC server) at example.com.

    local$ ssh -L 15900:localhost:5900 user@example.com

### VNC servers for multiple users

To run VNC servers for multiple users, specify every user as arguments:

    $ ./q-gui-setup.sh alice bob charlie

The first user's VNC server will be running on port 5900, the
second user on 5901, etc. Multiple ssh tunnels can be established
by repeating the `-L` option:

    local$ ssh -L 15900:localhost:5900 -L 15901:localhost:5901 -L 15902:localhost:5902 user@example.com

The VNC server for alice can be accessed through port 15900, bob
through port 15901 and charlie through port 15902.

Examples
--------

1. Create a VM instance running RHEL, CentOS or Scientific
   Linux. Note: the security groups must allow _ssh_ access.

2. Login to the VM instance using _ssh_ and tunnel port 5900 on the VM
   instance to a local port (using 15900 in this example).

        local$ ssh -L 15900:localhost:5900 ec2-user@130.102.xxx.xxx

3. Put a copy of the _q-gui-setup.sh_ script onto the VM instance.

        $ curl -O https://raw.github.com/qcif/cloud-utils/master/q-gui-setup.sh
        $ chmod a+x q-gui-setup.sh

4. Run the script, providing it a list of at least one user account.
   Wait until the script finishes running (which can take over an hour
   to run, depending on the processing power of your VM instance).

        $ ./q-gui-setup.sh neo

    You will be prompted to set a VNC password.

5. Set a password for the new user account. Although this is not
   strictly needed (since you can establish the _ssh_ tunnel
   to any account on the host), it will be required to unlock
   the screensaver.

        $ sudo passwd neo

6. Connect to the VNC server (via the forwarded port) using a VNC client.

    For example, on Mac OS X, you can choose _Go_ > _Connect to Server_
    in the _Finder_, or run the following command from the _Terminal_:

        local-mac$ open vnc://localhost:59000

     Enter the VNC password when prompted.

7. When finished, close the VNC client and then log out of the _ssh_
   connection.

When you close the VNC client, the next time you connect to the VNC server
it will show you the session as you left it. This is useful, because
you can leave programs running and return to them later.

Additional software can be installed via the GUI or via the command
line.  For example, install the Firefox Web browser with the command
`yum install firefox` and it will appear in the menu _Applications_ >
_Internet_. The GUI installer (available through the _System_ >
_Administration_ > _Add/Remove Software_ menu item) does not always
work properly under CentOS 6.4 64-bit.

Environment
-----------

This script must be run with root privileges.

Files
-----

- `/etc/hosts` - hosts file
- `/etc/sysconfig/vncservers` - VNC configuration file

Contact
-------

Please send feedback and queries to Hoylen Sue at <h.sue@qcif.edu.au>.
