q-gui-setup
===========

Setup X11 and a VNC server on a Q-Cloud virtual machine instance to
run a graphical user interface.

Synopsis
--------

    q-gui-setup.sh
        [ -f | --force]
        [ -v | --verbose] [ -q | --quiet ]
        username {username...}

Description
-----------

Installs the X Windows System and VNC and creates user accounts
with access to X11.

This script can take a long time to run, because it has to download
and install a number of _yum_ packages.

This script will create user accounts and configure each of them with
a VNC session. The first user's VNC server will be running on port
5900, the second user on 5901, etc. These VNC servers will keep
running after the VNC client has disconnected from them, so you can
return to the VNC server later. There is one VNC server per user
account.

The alternative method, of setting up a single VNC server with a login
screen, is not used. There are advantages and disadvantages with
either method. The VNC server per user approach was chosen because:
there will be very few users, so configuring each user and running a
separate VNC server for each is practical; users should be encouraged
to _ssh_ tunnel the unencrypted VNC traffic, so providing a graphical
login would not encourage them to do that; and it was easier to setup.

### Options

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

A VNC password is required to access each VNC server. This is different from
the user account's password.

It is recommended that both a VNC password and a user account password
be set up. The VNC password prevents anyone with access to the VNC
port to use the account. Even if firewalls block external access to
the ports, other users on the machine can still access the port. The
user account password is not needed to access the VNC server, but will
be required to unlock any screensavers.

It is strongly recommended that VNC connections be made through an
_ssh_ tunnel. This is because VNC traffic is not encrypted. First,
establish a _ssh_ tunnel to any account on the host (it can be, but
does not have to be, the same account as the VNC server). Then connect
to the VNC server over the tunnel.


Examples
--------

1. Create a VM instance running RHEL, CentOS or Scientific
   Linux. Note: the security groups must allow _ssh_ access.

2. Login to the VM instance using _ssh_ and tunnel port 5900 on the VM
   instance to a local port (using 59000 in this example).

        local$ ssh -L 59000:localhost:5900 ec2-user@130.102.xxx.xxx

3. Put a copy of the _q-gui-setup.sh_ script onto the VM instance.

        vm$ curl -O https://raw.github.com/qcif/cloud-utils/master/q-gui-setup.sh
        vm$ chmod a+x q-gui-setup.sh

4. Run the script, providing it a list of at least one user account.
   Wait until the script finishes running (which can take over an hour
   to run, depending on the processing power of your VM instance).

        vm$ ./q-gui-setup.sh neo

    You will be prompted to set a VNC password.

5. Set a password for the new user account. Although this is not
   strictly needed (since you can establish the _ssh_ tunnel
   to any account on the host and from there only require the
   VNC password).

        vm$ sudo passwd neo

6. Connect to the VNC server (via the forwarded port) using a VNC client..

    For example, on Mac OS X, you can choose _Go_ > _Connect to Server_
    in the _Finder_, or run the following command from the _Terminal_:

        local-mac$ open vnc://localhost:59000

     Enter the VNC password when prompted.

7. When finished, close the VNC client and then log out of the _ssh_
   connection.

When you close the VNC client, the next time you connect to the VNC server
it will show you the session as you left it. This is useful, because
you can leave programs running and return to them later.

Additional software, such as the Firefox Web browser, can be installed
via the GUI by selecting the menu item _System_ > _Administration_ >
_Add/Remove Software_.  Firefox can also be installed from the command
line by running `yum install firefox`, and it will appear in the menu
_Applications_ > _Internet_.

Environment
-----------

This script must be run with root privileges.

Files
-----

- `/etc/hosts` - hosts file
- `/etc/sysconfig/vncservers` - VNC configuration file

Diagnosis
---------

Contact
-------

Please send feedback and queries to Hoylen Sue at <h.sue@qcif.edu.au>.
