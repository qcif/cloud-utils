Creating a Linux image
======================

This document describes how to create a virtual machine instance of
CentOS Stream 8 for the
[Nectar Research Cloud](http://nectar.org.au/research-cloud)
deployment of [OpenStack](https://www.openstack.org).

These instructions should apply to other Linux distributions, if the
steps to install and configure the guest system are modified. These
instructions should also be applicable to other deployments of
OpenStack.

Requirements
------------

- OpenStack project to upload the image to.
- Local system, with a ssh client and a VNC client.
- Creation host system, with QEMU and glance (e.g. a [configured VM instance](README-init.md)).
- Installation ISO image for the CentOS Stream 8.

Process
-------

### Step 1: Get installation ISO image on the creation host system

#### 1a. Connect to the host system and create a SSH tunnel for VNC

From the local system, ssh into the creation host as the user that
will be creating the images.  At the same time, create a ssh tunnel
from a local port (in this example 15900 is used) to a VNC port (5900)
on the creation host:

    [local]$ ssh -L 15900:localhost:5900 creator@creation.host.system

#### 1b. Get the installation ISO image

Get a copy of the ISO image onto the creation host.

This example uses _curl_ to download it from one of the CentOS mirror
sites. If _curl_ is not available, try using _wget_.  Store it in the
working directory.

    [creator@host]$ cd /mnt/creator
    [creator@host]$ curl -L -O --progress-bar http://mirror.aarnet.edu.au/pub/centos/8-stream/isos/x86_64/CentOS-Stream-8-x86_64-20210416-dvd1.iso

#### 1c. Get the script

Get a copy of the _q-image-maker.sh_ script onto the creation
host. This can be done by uploading it or downloading it. The example
below downloads it from the GitHub respository. Note: if GitHub
changes the raw download URL, find out its new value from the [project
in GitHub](https://github.com/qcif/cloud-utils).

    [creator@host]$ cd /mnt/creator
    [creator@host]$ curl -O https://raw.githubusercontent.com/qcif/cloud-utils/master/q-image-maker.sh
    [creator@host]$ chmod a+x q-image-maker.sh

The _q-image-maker.sh_ script is just a convenient way to invoke the
_qemu-kvm_ and _glance_ commands.

### Step 2: Install the guest system from the ISO

#### 2a. Create the disk image and boot from the ISO

Create an disk image and boot off the ISO image. By default, a 10 GiB
disk image, which is the maximum size of the standard boot disk
supported by NeCTAR's deployment of OpenStack.  It is stored in the
QEMU Copy-On-Write version 2 (QCOW2) format, and the VNC server is
listening on display 0 (port 5900). If needed, these defaults can be
changed using command line options.

    [creator@host]$ ./q-image-maker.sh create \
                    --iso CentOS-6.5-x86_64-minimal.iso \
                    disk.qcow2

The script runs _qemu-kvm_ in the background with _nohup_. So you can
log out of the creation host and it will continue running.

If you intend to install the QEMU Guest Agent, include the `--agent`
option to simulate the VirtIO Serial device it uses to communicate
with the host.

#### 2b. Use VNC to access the guest system

Connect to the VNC server (e.g. in this example to local port 15900
which is port forwarded to port 5900 on the creation host).

Warning: If the local machine is an Apple Macintosh do not use the
_Screen Sharing_ client that comes with macOS, because it is
incompatible with the VNC implementation provided by QEMU/KVM: use a
third party VNC client.

There is no VNC password.  On some VNC clients, simply press return if
prompted for it. On other VNC clients (e.g. Screens on macOS)
configure the client to not use any authentication.  Note: the VNC
password can be set using the QEMU console.

The QEMU console is accessed by typing Ctrl-Alt-2 into the VNC
session. Type Ctrl-Alt-1 to return to the main display. Some commands
supported the by the QEMU console are:

- `change vnc password` to set the VNC password.
- `info block` list devices.
- `change ide1-cd0 filenameOfIsoImage` to swap the virtual CD-ROM.
- `system_reset` to reboot the guest system.
- `help` show available commands.
- `quit` to stop the guest system and the emulator.

#### 2c. Install the guest system

Install the guest operating system as normal, except pay special
attention to how the disk is partitioned.

CentOS does not enable the network adapter by default, so manually
make sure it is enabled.  Press the "Configure Network" button and
edit the "System eth0" and check the "Connect automatically"
checkbox. If you forget to do this during installation, you can edit
the /etc/sysconfig/network-scripts/ifcfg-eth0 configuration file to
set it.

For the disk partitions, choose **"Create Custom Layout"** for the
type of installation. Create a single standard partition on the free
space of /dev/vda.  Set its mount point to "/" and "fill to maximum
allowable size" for its size. The _ext4_ format can be used. Ignore
the warning about a swap partition not been specified.

#### 2d. Configure the guest system

Perform any necessary software installation and configurations
necessary to create the image. This will depend on the operating
system and purpose of the image, but the following are highly
recommended:

- Update the installed packages.

        [root@guest]# yum -y update

- Install the man package.

    For some reason, the useful _man_ command is not installed by default.

        [root@guest]# yum -y install man

- Remove hardcoded network interface MAC addresses.

    By default, the operating system saves the MAC address of the
    network interface so it can always assign the same device name
    (e.g. eth0) to it. But when the image is run on a different
    virtual machine instance, its network interface will have a
    different MAC address and the operating system will assign a
    different device to it (e.g. eth1). To prevent that from
    happening, clear out the MAC address.

    Firstly, prevent _udev_ from re-creating persistent network
    rules. If the rules file is simply deleted or replaced with an
    empty file, it will get recreated (with new hardcoded MAC
    addresses) upon reboot. Instead, create a symbolic link to
    /dev/null for it.

        [root@guest]# rm /etc/udev/rules.d/70-persistent-net.rules
        [root@guest]# ln -s /dev/null /etc/udev/rules.d/70-persistent-net.rules

    Secondly, remove references to the MAC address in the network
    device's configuration script.

        [root@guest] vi /etc/sysconfig/network-scripts/ifcfg-eth0
          # Delete the UUID and HWADDR entries (and check ONBOOT=yes and BOOTPROTO=dhcp)

     Thirdly, create a network device configuration script for a
     second network interface. This will allow any second network
     interface (when available on the VM instance, such as in
     QRIScloud) to be automatically configured.

        [root@guest]# cp /etc/sysconfig/network-scripts/ifcfg-eth0 /etc/sysconfig/network-scripts/ifcfg-eth1
        [root@guest]# vi /etc/sysconfig/network-scripts/ifcfg-eth1
          # Change the DEVICE and NAME entries from eth0 to eth1

- Disable console screen blanking

    It can be confusing to come back to a session and find the screen
    is blank. Turn off the console screen blanking feature by adding
    `consoleblank=0` to the kernel boot parameters.

         [root@guest]# vi /boot/grub/grub.conf
           # Append to the lines starting with "kernel /boot/..." the following: consoleblank=0

    After rebooting, running `cat
    /sys/module/kernel/parameters/consoleblank` should show the
    value to be zero (seconds).

    Note: yum update can create additional entries in the grub config
    file.  So after running "yum update", check this parameter is
    still set correctly.

- Disable the firewall from starting

    The guest's firewall is not needed because the OpenStack security
    groups can be used instead.

        [root@guest]# chkconfig --list
        [root@guest]# chkconfig iptables off
        [root@guest]# chkconfig ip6tables off

- Improve the security of ssh by using public keys instead of passwords

    Passwords are less secure than using ssh public keys. Disable
    password logins via ssh:

        [root@guest]# vi /etc/ssh/sshd_config
          # - Change the password authentication setting to explicitly say:
          #     PasswordAuthentication no
          # There should be an existing entry: change its value to "no".
          # Note: the default value is yes, so do NOT simply comment it out.

     Note: if _cloud-init_ is not installed, OpenStack Nova will
     inject any ssh public key chosen during VM instantiation into the
     root account. Therefore, it is possible to use ssh public keys
     without needing to install _cloud-init_ -- though allowing direct
     root ssh login is not recommended.

- Remove the generated ssh private keys

    Public key pairs have been generated for the ssh server to use.

    If this image is shared, others will also have the SSH private key
    and could impersonate each other.  To prevent this, delete the
    generated SSH key pairs. A new set of private keys will be
    generated (by the /etc/init.d/sshd script) when the ssh server is
    next started.

        [root@guest]# service sshd stop
        [root@guest]# rm /etc/ssh/ssh_host_*key*

    Note: this step has to be performed after the *last* time the
    guest system is started before the image is uploaded.  If the
    guest system is restarted, they keys will be generated and will
    have to be deleted again.


The following configurations are also recommended:

- Install cloud-init

        [root@guest]# rpm -Uvh http://download.fedoraproject.org/pub/epel/6/x86_64/epel-release-6-8.noarch.rpm
        [root@guest]# yum -y install cloud-init

- Include the QEMU Guest Agent.

- Configure users and cloud-init

    After installing cloud-init, there will be a user called "cloud-user".

    By default, when the image is instantiated any public key chosen
    during VM installation will be added to that user's
    .ssh/authorized_keys file. With the corresponding ssh private key,
    you would be able to login as "cloud-user".  For it to function as
    a substitute for root access, the simplest approach is to add the
    _cloud-user_ user to the _wheel_ group.

    But it is preferable to create another non-root user account. Add
    that user to the _wheel_ group and configure cloud-init to add the
    ssh public key to that account's .ssh/authorized_keys file.

        [root@guest]# adduser foobar
        [root@guest]# usermod -a -G wheel foobar

        [root@guest]# vi /etc/cloud/cloud.cfg
          # Change the `default_user` from `name: cloud-user` to `name: foobar`

    Proper configuration of cloud-init is outside the scope of this
    guide. For more information, see the [cloud-init
    documentation](http://cloudinit.readthedocs.org/en/latest/).

- Allow all users in the _wheel_ group to have sudo privledges.

        [root@guest]# visudo
          # Uncomment the entry that permit users in the "wheel" group to run all commands without a password.

- Disable ssh logins by root

        [root@guest]# vi /etc/ssh/sshd_config
          # - Disable root logins by adding the setting:
          #     PermitRootLogin no
          #   There should be a commented out entry: uncomment it and change the value to "no"

- Delete the root password

    Delete the root password. This will prevent anyone who knows the
    root password from logging in at the console (or via ssh if
    _PermitRootLogin_ was accidently enabled). If this is not done,
    the same root password will exist in the image and all instances
    created from the image.

        [root@guest] passwd --delete root

    **Warning:** do this only after _all_ configurations have been
    done. Unless other arrangements have been made, it will be
    _impossible_ to login to the guest system to configure it. The
    user can login after the image is instantiated and an ssh public
    key injected into the account.

- Optionally disable login to the root account

  This will prevent `sudo su -` from working:

        [root@guest] usermod -s /sbin/nologin root


Note: Don't forget to delete the generated ssh server private keys, if
you have rebooted the guest system since they were deleted.

Alternatively, the
[virt-sysprep](http://libguestfs.org/virt-sysprep.1.html) utility can
perform some of these configurations.


#### 2e. Shutdown the guest system

When finished, shutdown the guest virtual machine and immediately
close the VNC client.

    [root@guest]# shutdown -h now

Alternatively, if a problem occurs, the guest virtual machine can be
stopped with the "quit" command in the QEMU console (which can be
accessed by typing Ctrl-Alt-2 into the VNC client).

### Step 3: Optionally run the guest system to configure it

If additional configuration needs to be performed, restart the guest
virtual machine by booting off the disk image.

    $ ./q-image-maker.sh run disk.qcow2

As before, connect to the VNC server (through the ssh tunnel) with an
empty password.

### Step 5: Upload the image to OpenStack glance image server

#### 5a. Obtain your OpenStack password

Obtain the password for your user account. From the OpenStack
dashboard, click on the Settings link (top right), choose "Reset
Password" (left side), press the "Reset Password" button.

#### 5b. Source RC file

Obtain the RC file from the OpenStack dashboard: via Access & Security
> API Access > Download OpenStack RC File.

Set up the environment variables that the glance client needs to run
by sourcing the RC file and entering your password:

    [creator@host]$ . projectName-openrc.sh

#### 5c. Upload image

If a raw format disk image was used, it is recommended to convert it
to a QCOW2 format image for uploading (qemu-image covert), because
usually the QCOW2 format image will be smaller and therefore quicker
to upload.

Upload the disk image, optionally giving it a name:

    [creator@host]$ ./q-image-maker.sh upload --linux --name "My CentOS image" --min-disk 10 disk.qcow2

If the QEMU Guest Agent has been installed, include the `--agent`
option to set the metadata on the uploaded image. Do not use that
option, if the agent has not been installed.  Otherwise, OpenStack
will attempt to use it and it will not work properly.

### Step 6: Use the image to instantiate virtual machine instances

Log into the [OpenStack Dashboard](https://dashboard.rc.nectar.org.au)
and instantiate a virtual machine instance from the image.

Configure the security groups to allow ssh access, and you should be
able to ssh to the VM instance: as the user that was created,
cloud-user, or root -- depending on how the image was configured.

When testing images, launch them in the NeCTAR Melbourne availability
zone.  The NeCTAR glance image server is in Melbourne, so that avoids
sending the test images over the network to a different availability
zone.

Note: the image is uploaded into a specific project/tenant. If the
image is not visible, check the project/tenant is the one it was
uploaded to (i.e. the one corresponding to the RC file used to set the
environment variables).

See also
--------

- [OpenStack Virtual Machine Image Guide](http://docs.openstack.org/image-guide/content/ch_preface.html) especially the [CentOS image example](http://docs.openstack.org/image-guide/content/centos-image.html)
- [cloud-init](http://cloudinit.readthedocs.org/en/latest/)
- [virt-sysprep](http://libguestfs.org/virt-sysprep.1.html)

Future work
-----------

- Use _virt-sysprep_ instead of manual configuration.
- Configure _cloud-init_ properly.

Contact
-------

Please send feedback and queries to Hoylen Sue at <hoylen.sue@qcif.edu.au>.
