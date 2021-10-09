Creating a Microsoft Windows image
==================================

This document describes how to create a virtual machine instance of
_Microsoft Windows Server 2022_ for OpenStack using a Linux host.

These steps may apply to other versions of Microsoft Windows with some
modification.

Requirements
------------

- Local machine, with a ssh client and a VNC client.
- Creation host, with QEMU and the OpenStack client (e.g. a [configured VM instance](README-init.md)).
- Installation ISO image for _Microsoft Windows Server 2022_.
- VirtIO drivers for Windows ISO image.
- Suitable licence for Microsoft Windows Server 2022 (optinal for testing).
- OpenStack project to upload the image to.

Note: the local machine can be the same machine as the creation host.

Licensing
---------

**Important: It is your responsibility to ensure all licensing
requirements are satisfied.**

Windows licensing is complicated and may change. At the time of
writing, _OEM licenses_ must not be used on OpenStack virtual
machines.  Other licenses are subject to their terms and conditions,
the organisation that purchased the license, and the particular
OpenStack environment it will be running on (even down to the
particuar hardware).

Please consult with your OpenStack provider for the latest situation
about Microsoft Windows licensing.

Process
-------

This process takes at least 2.5 hours to complete.

### Step 1: Get installation ISO image on the creation host system

#### 1a. Get the Windows installation ISO image

Copy the ISO image onto the creation host.  The example commands
copies it from the local machine to the creation host.

    [local]$ scp win-inst.iso creator@host:/mnt/creator/win-inst.iso

#### 1b. Connect to the host system and create a SSH tunnel to it

From the local machine, ssh into the creation host.  At the same time,
create a ssh tunnel from a local port (in this example 15900 is used)
to a VNC port (5900) on the creation host. That tunnel will be used to
connect to a virtual machine running on the creation host.

    [local]$ ssh -L 15900:localhost:5900 creator@creation

#### 1c. Get the VirtIO drivers ISO image

Get a copy of the [VirtIO drivers](https://docs.fedoraproject.org/en-US/quick-docs/creating-windows-virtual-machines-using-virtio-drivers/index.html) ISO image onto the creation host.

From the information on the GitHub [virtio-win-pkg-scripts](https://github.com/virtio-win/virtio-win-pkg-scripts/blob/master/README.md) repository,
The _stable_ release of the virtio-win ISO image can be downloaded
using _curl_ or _wget_:

    [creator@host]$ curl -L -O --progress-bar \
      https://fedorapeople.org/groups/virt/virtio-win/direct-downloads/stable-virtio/virtio-win.iso

#### 1d. Get the script

Get a copy of the _q-image-maker.sh_ script onto the creation
host. This can be done by uploading it or downloading it. The example
below downloads it from the GitHub respository. Note: if GitHub
changes the raw download URL, find out its new value from the [project
in GitHub](https://github.com/qcif/cloud-utils).

    [creator@host]$ cd /mnt/creator
    [creator@host]$ curl -O https://raw.githubusercontent.com/qcif/cloud-utils/master/q-image-maker.sh
    [creator@host]$ chmod a+x q-image-maker.sh

### Step 2: Install the guest system from the ISO

#### 2a. Create the disk image and boot from the ISO

Create an disk image, and run a virtual machine with it and the two
ISO images:

    [creator@host]$ ./q-image-maker.sh create \
                                       --iso windows.iso --iso virtio-win.iso \
                                       --agent \
                                       --size 30  image.qcow2

The disk image **must** be large enough to hold the operating system
and any extra software installed on the image. Set the target disk size in
GiB using the `--size` option.

The default of 10 GiB disk is usually too small for most versions of
Windows Server.  For example, Windows Server 2019 R2 needs more than
17 GiB, and Windows 10 Pro 20H2 needs more than 19 GiB (they will
install less, but there is then insufficient space to install the
updates)!

Images cannot be used with VM flavours where the size of the boot
volume is smaller than the image's target size.  If the intention is
for the image to be expanded to use the available boot volume, try to
create images with a smaller target size, since they can be used with
both small and large volumes. This is possible with operating systems
like Windows 2019 R2 and older.

**Important:** Images cannot be expanded to use the available boot
volume for operating systems like Windows Server 2022 and Windows 10.
Those operating systems have a second recovery partition after the
main partition, which prevents the main partition to be expanded
(either using Cloudbase-Init or manually). For these operating
systems, the target size of the image should match exactly the boot
volume it will be used with. If the target size is larger, the image
cannot be launched. If the target size is smaller, the extra storage
on the boot volume cannot be used.

Currently, September 2021, a workaround is to make the disk image the
same size as the disk on the virtual machine that will be
instantiated. Maybe a future release of Cloudbase-Init will address
this problem, but we do not know if expanding the main partition is
even possible.

The agent option adds a VirtIO Serial interface to the VM. This will
be needed to prepare the image for use withthe QEUM Guest Agent.

The disk image will be in the default QEMU Copy-On-Write version 2
"qcow2" format, which is required for it to be used as the boot
disk. If the image will be used on volume storage, the "raw" format
needs to be used. Use the `--format` option to set the format; use the
`--help` option or read the [q-image-maker
manual](https://github.com/qcif/cloud-utils/blob/master/openstack-images/q-image-maker.md)
(a Markdown file from the GitHub repository) for details.

The VNC server is listening by default on display 0 (port 5900). Use a
different display if there is already a VNC server running on that
display. Use the `--display` option to change the display number.

The script runs _qemu-kvm_ in the background with _nohup_. So you can
log out of the creation host and it will continue running.

#### 2b. Use VNC to access the guest system

Connect to the VNC server (e.g. in this example to local port 15900
which is port forwarded to port 5900 on the creation host).  There is
no VNC password: press return if prompted for one. On some VNC
clients, the type of authentication must be set to "none", which is
different from having a VNC password which is empty.  Note: a VNC
password can be set using the "change vnc password" command in the
QEMU console, but that is usually not necessary.

The QEMU console can be accessed by typing Ctrl-Alt-2 in the VNC
client; and Ctrl-Alt-1 to return to the main display. The QEMU console
can be used to list and change the virtual CD-ROM (using the commands
"info block" and "change ide1-cd0 filenameOfISOImage"). The
"system_reset" command can be used to reboot the guest system.  The
"quit" command can be used to stop the guest system and the emulator.

#### 2c. Install the guest system

Install the guest operating system as normal, except pay special
attention to how the disk is partitioned.

1. Windows Setup: set the install language (if possible), and change
   the "Time and currency format" to "English (Australia)" or the
   preferred format, and press the "Next" button.

2. Press the "Install Now" button.

3. If prompted to Activate Windows, select "I don't have a product key".

4. Select the operating system to install, and then press the "Next" button.

    The steps below might be slightly different for different versions
    of Windows.  These steps are for "Windows Server 2022 Standard
    (Desktop Experience)" or "Windows Server 2022 Datacentre (Desktop
    Experience)". They do not apply to the non-desktop editions
    (previously called "server core editions") that do not have a
    Windows graphical environment. The non-desktop editions are for
    use with remote management tools and/or the command line.

5. Read the licence terms and, if you accept them, check the "I accept
   the Microsoft Software Licence Terms" checkbox and press the "Next" button.

6. Choose "Custom: Install Microsoft Server Operating System only
   (advanced)", since this is not an upgrade.

Initially, there won't be any drives to install Windows on, because
Windows does not come with drivers for the VirtIO virtual disk drives.

#### 2d. Use the VirtIO disk drivers

No drives will be available until the VirtIO disk drivers are loaded.

1. Press the "Load Driver" button.

2. Press the "Browse" button.

3. Browse the second CD drive, and navigate to and select the
   directory that is most suitable for the version of Windows being
   installed.  For example, the "E:\AMD64\2k19" directory.  Press the
   "OK" button.

4. The "Select the driver to install" dialog should detect the "Red
   Hat VirtIO SCSI controller" driver, and have selected it. Press the
   "Next" button.

     A "Drive 0 Unallocated Space" will be detected. If a small disk
     image is being used, there may be a message claiming more space
     is recommended. This may or may not be a problem, depending on
     the purpose of the image. That is, depending on exactly how much
     space is available, a successful installation might still be
     possible. But it is possible for it to Windows to be installed,
     but there will not be enough space to install updates and/or
     additional applications.

5. Press "Next" and Wait for the installation to finish. (About 10
   minutes.)

6. Set the administrator password and press the "Finish" button.

     This administrator password is only needed for temporary use. It
     will be removed by the final step of preparing the image (when
     _sysprep_ is run).  It can be forgotten after the image has been
     created.

     Passwords must contain at least one character from at least three
     of these character classes: lowercase letters, uppercase letters,
     numbers or symbols.

7. Sign in as the Administrator.

    Type Ctrl-Alt-Delete into the VNC session to sign in.  The VNC
    client should have a special feature to do this (e.g.  in the
    macOS _Screens_ application, use the _Command_ > _Ctrl-Alt-Del_
    menu item), since typing those keys would affect your local
    computer rather than the guest system.

#### 2e. Server Manager

Prevent the _Server Manager_ application from automatically starting.

It starts up by default. Disabling it is less important for this
temporary Administrator account. But it is useful to know how to do it
for long-lived accounts.

1. In _Server Manager_ application, open the "Manage" menu (top right).

2. Select "Server Manager Properties".

3. Check the "Do not start Server Manager automatically at logon" checkbox.

4. Press the "OK" button.

5. Close the _Server Manager_ application.

#### 2f. VirtIO network drivers

Note: some versions of Windows may strongly suggest that connecting to
the Internet is desirable during the installation process.  But it
should be possible to say there is no Internet connection, and to
proceed with the installation without it. The VirtIO network driver
(unlike the VirtIO disk driver) is installed _after_ the Windows
installation process has been fully completed.

Install the VirtIO network drivers to use the virtual network
interfaces.

1. Open the _Device Manager_. This can be done by right clicking on
   the Start button and selecting "Device Manager".

    Under "Other Devices" the Ethernet controller should appear as one
    of the devices without a driver. In some versions of Windows, it
    will be helpfully identified as an "Ethernet Controller". But in
    other versions it might simply be called an "Unknown device".

2. View the properties of the Ethernet Controller, by double clicking
   on it or right clicking on it and selecting Properties.

3. Press the "Update Driver" button.

4. Choose "Browse my computer for drivers".

5. Press the "Browse..." button.

6. Select the top level of the second CD Drive (E:) (unlike for the
   VirtIO disk driver, a specific subdirectory and file does not need
       to be chosen for the VirtIO network driver) and press the "OK"
   button.

7. Ensure the "Include subfolders" checkbox is checked and press the
   "Next" button.

     It should find the "Red Hat VirtIO Ethernet Adapter" driver
     and automatically install it.

8. When asked, "Do you want to allow your PC to be discoverable by
   other PCs and devices on this network?", press the "No" button.  It
   is more secure to not allow discovery, which is used for network
   features such as file and printer sharing. Choosing "No" will also
   set the network connection as "Public" (instead of "Private") and
   that affects the behaviour of the _Windows Firewall_ and other
   aspects of Windows.

9. Press the "Close" to close the driver update success window.

10. Press the "Close" button to close the Ethernet Adapter Properties dialog.

On some versions of Windows, a restart might be required for the
network driver to work.

#### 2g. Other VirtIO drivers

Under the "Other devices" section of the Device Manager, there should
be other interfaces without drivers:

- "PCI Device" for the VirtIO Balloon Driver;
- "PCI Device" for the VirtIO RNG Device; and
- "PCI Simple Communications Controller" for the VirtIO Serial Driver
  (if the `--agent` options was used).

Install the drivers:

1. View the properties of the device: double clicking on it or right
   clicking on it and selecting Properties.

2. Press the "Update Driver" button.

3. Choose "Browse my computer for drivers".

4. Press the "Next" button, since the location is the same as
   previously used and the "Include subfolders" checkbox is already
   checked.

5. Press the "Close" button on the update drivers window.

5. Press the "Close" button on the driver/device properties window.

6. Repeat for the other devices without drivers.


#### 2h. QEMU Guest Agent

Install the _QEMU Guest Agent_. It is a helper daemon that runs inside
the Windows guest, and is used to exchange information between the
host and the guest. For example, it can help properly shutdown the
Windows guest and assist when snapshots are being made.

First, check the VirtIO Serial Driver was one of the drivers installed
in the previous step. The QEMU Guest Agent uses it to communicate with
the host. If the VirtIO Serial Driver driver was not installed, the
agent will not work (even though it installs without any errors).  The
serial interface is present only if the VM was started with the
`--agent` option.

Install the QEMU Guest Agent:

1. Open the file explorer and browse to the second CD Drive (E:).

2. Double-click on the "virtio-win-guest-tools.exe" program (though
   the _.exe_ extension will be hidden.)

3. Follow the wizard to install it.

    a. Check the "I agree to the license terms and conditions"
    checkbox and then press the "Install" button.

    b. Press the "Next" button for the Virtio-win-driver-installer.

    c. Check the "I accept the terms in the License Agreement"
    checkbox and press the "Next" button.

    d. Press the "Next" button to install the drivers.

    e. Press the "Install" button.

    f. When it has finished, press the "Close" button.

The agent can be checked by opening the _Services_ manager (run
“services.mgr”, search for “services" or right click on Start and
choose "Computer Management" > Services and Applications > Services).
It should be running and started automatically.  The name of the
service is “QEMU Guest Agent”.

There is also a “QEMU Guest Agent VSS Provider” that is not running
and startup is manual. Applications need to have support for
Microsoft's Volume Shadow Copy Service (VSS), for it to have an effect
on those applications.

Note: when preparing the image, there is nothing on the host for the
QEUM Guest Agent to communicate with.  But the VirtIO Serial Driver
must be installed so the interface will work when the image is
launched in OpenStack.

#### 2i. Time zone

When the image is instantiated, it will have a (virtual) hardware
clock will be in the local time of the availability zone. Set the time
zone in Windows to match (e.g. Brisbane +10:00 for QRIScloud).
Unfortunately, if the image will be launched in multiple Availability
Zones, the Windows timezone may be wrong for some of them.

1. Open the _Date and Time settings_. Launch the _Control Panel_ and
   select _Clock and Region > Change the time zone_.

2. Press the "Change time zone..." button.

3. Select the time zone and press the "OK" button.

    Note: the time showing might not be correct (even if the creation
    host's time and timezone are correct). This is because the
    (virtual) hardware clock is currently in UTC, but Windows assumes
    it is in the local time zone. A system clock in local time will be
    presented when the image is running on OpenStack.

4. Press the "OK" button to close the Time and Date dialog.

5. Close the Control Panel Clock, Language, and Region window.

#### 2j. Disable display blanking

When running as a virtual machine instance, there is no point in
turning off the display to save power and it is more likely to cause
confusion when trying to use it.

1. Open the Control Panel Power Options. Launch the Control Panel and select
   _Hardware > Change power-saving settings_.

2. Select the radio button for the "High performance" power plan.

3. Click the "Change plan settings" next to that plan.

4. Change the Turn off the display to "Never".

5. Press the "Save changes" button.

6. Close the Control Panel Power Settings window.

#### 2k. Configure Windows Update

By default, Windows Server 2022 has a Local Group Policy that prevents
Windows Updates from being automatically downloaded and installed.
They are automatically downloaded but _not_ installed---and the
user is prevented from enabling automatical installation without
changing the Local Group Policy.

Automatic download _and install_ is strongly recommended, unless users
are expected to manually install the updates on a regular basis.

To disable that Local Group Policy:

1. Open the _Local Group Policy Editor_.

    In the Windows search, type "gpe" or "group policy" and select the
    "Edit Group Policy" that is found.

2. Expand "Computer Configuration" > "Administrative Templates" >
   "Windows Components" and select "Windows Update" from it.

3. Select the "Configure Automatic Updates" setting for help about
   that setting.

4. Double click on "Configure Automatic Updates" and configure it:

     a. Select the "Enabled" radio button".

     b. In the options, change _configure automatic updating_ to
          "4 - Auto download and schedule the install".

     c. Leave the "Install during automatic maintenance"
        checkbox unchecked. This allows the updates to be
        installed as soon as possible.
        All the other settings can be left unchanged.

     d. Press the "OK" button.

5. Close the _Local Group Policy Editor_.


Note: according to the help text, the default (where "Configure
Automatic Updates" is "not configured") should allow an administrator
to "still configure Automatic Updates through Control Panel." But we
have found that is not true, since the administrator is prevented from
enabling automatic installation of updates. By default, updates are
automatically download updates and not installed. The user is supposed
to be notified about them, though we have not seen any notifications
appear.

#### 2l. Apply current Windows Updates

To avoid every VM instances using the image from having to download
and install the updates that are currently available, install them in
the image.

To install the currently available updates.

1. Open the Windows Start Menu.

2. Choose _Settings_ (the gears icon in the Start menu).

3. Choose _Update & Security_ (the window may need to be scrolled up
   to see it).

4. Press the "Check for updates" button, if needed.

5. Wait for the update check to finish and for all the updates to download.
   Note: some VNC clients do not refresh unless their window has focus,
   so the progress indicators might not always change.

6. Press the "Install now" button, if it appears.

7. Wait for _all_ the installs to finish.

8. Press the "Restart now" button, if it appears.

9. Sign back into the Administrator account.

**Important:** some updates are installed when Windows is shutdown or
restarted. And also some updates won't appear until other updates have
been installed.  Restart Windows and check for updates a few times,
before finalising the image.

### Step 3: Optionally install additional software

If additional configuration needs to be performed, run a guest
virtual machine by booting off the disk image.

    $ ./q-image-maker.sh run image.qcow2

As before, connect to the VNC server (through the ssh tunnel) without
using a VNC password.

The `--iso` option can be used to attach ISO images to install
software from.

### Step 4: cloud-init and sysprep

It is optional to install _Cloudbase-Init_ (previously called
_cloud-init for Windows_).

If configured properly, it allows the Windows virtual machine to
integrate with OpenStack. It is beyond the scope of this document to
describe how to configure it.

Either install _Cloudbase-Init_, or use _sysprep_ without it.

#### 4a. Option 1: Cloudbase-Init (and running sysprep with it)

To intall _Cloudbase_Init_:

1. Inside Windows, open a Web browser.

2. Visit <https://cloudbase.it/cloudbase-init>
   (If needed, add www.cloudbase.it as a trusted domain.)

3. Download and save the setup file (the Stable _Cloudbase-Init x64_ version).

4. Run the setup MSI. The defaults can be used.

   Do not change the guest startup username to "Administrator",
   because Windows will not work with that.

5. After the installing step, for the _Network adapter to configure_
   select the _Red Hat VirtIO Ethernet Adapter_.

6. If there is no more customisation of the image, at the last step of
   the setup check both the "Run Sysprep to create a generalized
   image" and "Shutdown when Sysprep terminates" checkboxes and press
   the "Finish" button.

7. Close the VNC client after the guest shutdown has finished.

Don't worry about the installer file in the downloads directory:
_sysprep_ will remove it as a part of resetting the Administrator
account.

Cloudbase-Init will create a new "Admin" account. Its password can be
obtained using the "Retrieve Password" action from the dashboard and
decrypted it with:

    $ echo $RETRIEVED_PASSWORD \
    | openssl base64 -d \
    | openssl rsautl -decrypt -inkey ~/.ssh/privkey.private -keyform PEM

or with this _nova_ command (unfortunately, as of April 2021, there is
not an equivalent command in the OpenStack client):

    $ nova get-password <instance> <SSH_private_key>

#### 4b. Option 2: sysprep (without CloudBase-Init)

Always run _sysprep_ as the last step of preparing the disk image.

The Microsoft Sysprep utility removes system specific data and to
enable the out-of-box-experience when Windows is first started.  For
example, it removes the administrator's password.

If _sysprep_ was not run as the last stage of setting up
Cloudbase-Init, or Cloudbase-Init is not installed, _sysprep_ will
have to be run manually.

1. Start _Windows PowerShell_ or a Windows command line.

2. Enter the following command:

         C:\Windows\System32\Sysprep\sysprep /generalize /oobe

3. Wait for _sysprep_ to finish running, and for it to shutdown the
   guest. (About 3 minutes.)

4. Close the VNC client.

**Important:** do not start Windows from the image again, otherwise
Sysprep must be rerun on it.

### Step 5: Upload the image to OpenStack glance image server

#### 5a. Obtain the password for your OpenStack account

1. Open the OpenStack Dashboard in a Web browser.

2. From the account menu (email address at the top right corner) chose
   "Settings".

3. Choose "Reset Password" from the left navigation area.

4. Press the "Reset Password" button.

5. Copy the generated password and keep it secure.

#### 5b. Obtain an RC file for the OpenStack project

1. Open the OpenStack Dashboard in a Web browser.

2. Make sure the desired OpenStack project is selected (top left).

3. Select "Project" > "API Access" from the left navigation area.

4. Press the "Download OpenStack RC File" button and
   choose "OpenStack RC File".

5. Upload the RC file from where it was downloaded to the creation host.

#### 5c. Setup credentials to connect to OpenStack

1. On the creation host, source the RC file for the OpenStack project.

        [creator@host]$ . projectname-openrc.sh

2. Enter your OpenStack account password, when promoted.


#### 5d. Upload image

Upload the disk image, optionally giving it a name:

    [creator@host]$ ./q-image-maker.sh upload --windows --agent --name "My new image" image.qcow2

The `--windows` option sets the "os_type" property on the image.  It
controls the behaviour when the image is used. For example, instances
launched from it will have a virtual hardware clock in local time
(instead of UTC for Linux images). If there are ephemeral disks, it
formats them as NTFS (instead of ext3 for Linux).

The `--agent` option sets the metadata on the uploaded image, to
indicate there will be a QEMU Guest Agent running inside the VM
instance. It sets the _hw_qemu_guest_agent_ property to "yes".

**Important:** do not use the `--agent` option, if the QEMU Guest
Agent and the VirtIO Serial Driver both have not been installed inside
the image. Otherwise, OpenStack will try to contact the agent and will
not be able to.

### Step 6: Use the image to instantiate virtual machine instances

Log into the OpenStack Dashboard and instantiate a virtual machine
instance from the image.

Note: the image is uploaded into a specific OpenStack project. If the
image is not visible, check the OpenStackproject is the one it was
uploaded to (i.e. the one corresponding to the RC file used to set the
environment variables).

If it is intended to use RDP to access the VM instance, configure the
security groups to allow RDP network traffic through (TCP port 3389,
and optionally UDP port 3389). Do **not** open up RDP to the wider
Internet, because the protocol has known security vulnerbilities.

There are two options for instantiating a VM image from the image:

- Run Windows from the boot disk; or
- Run Windows from a volume storage disk.

#### Option 1: Run Windows from the boot disk

This option is the easiest, but can only be used if the image is not
larger than the boot disk size of the virtual machine instance.  If
the image is larger, this option cannot be used.

1. Instantiate an new VM and select "Boot from image" as the instance
   boot source and select the image.

#### Option 2: Run Windows from a volume storage disk

This option is available to any image, regardless of size.

The volume storage disk can be made any size (as long as it is larger
than the image size). Ephemeral disk (if any) and other volume storage
disks can be used for additional storage.

1. In the Images & Snapshots list, under the "More" menu for the
   image, select "Create Volume".

2. Type in a name and optional description for the new volume.

3. Type in a size for the new volume. The size must be at least the
   image size. If it is larger, it can be expanded to use the extra
   space (as described below).

4. Choose an Availability Zone. This will dictate where the VM
   instance can be launched.

5. Press the "Create Volume" button and wait for the volume to be
   created (check its status in the Volumes section of the dashboard).

6. Launch a new VM instance.

    - Set the availability zone to where the volume is located, since
      it is not possible to have the VM instance in a different
      availability zone to the volume.

    - For the source, select "Volume" as the boot source and the
      volume that was created.

#### Connect to the VM instance for the first time

1. Go to the console for the VM instance in the OpenStack dashboard.

    From the page showing a list of instances (Compute > Instances),
    select "Console" from the action drop-down menu at the right of
    the instance. Or on the page showing the details of the instance,
    choose the "Console" tab from the top of the page.

2. Click on the gray area at the top or sides of the console, so
   keystrokes are sent to the console.

3. If necessary, set the country or region, language and keyboard
   layout. Press the "Next" button.

4. Read and licence terms and, if you accept them, press
   the "I accept" button.

5. Enter a new password for the administrator account and press
   the "Finish" button.

6. Press the "Send CtrlAltDel" button (top right) and sign into Windows
   using the Administrator password that was just created.

7. When prompted, "Do you want to allow your PC to be discoverable by
   other PCs and devices on this network?", press the "No" button
   unless there is a reason the feature is required.

#### Expanding the boot disk

**Note: this is not possible with newer versions of Windows that has an
extra recovery partition. For example, it cannot be done with Windows
Server 2022, Windows 10.**

If using a disk or volume that is larger than the image size, it needs
to be expanded to make use of the the entire space.

This is only be needed if Cloudbase-Init was not installed, since it
should automatically expand the disk image.

1. Open "Computer Mangement", by right-clicking on the start button
   and choosing it from the menu. Alternatively, it is under the
   Administrative Tools of the control panel.

2. Select Storage > Disk Management.

    The volume boot disk (Disk 0) should have a system reserved
    partition, the boot partition and unallocated space.

3. Right click on the boot partition (C:) and select "Extend Volume...".

4. Press the "Next" button.

5. Disk 0 should be selected and the "Select the amount of
   space in MB" should default to the same as the "Maximum available
   space in MB". That is, it will expand to use the entire unused
   space. Press the "Next" button.

6. Press the "Finish" button.

7. Optionally, enable the ephemeral disk. It should be offline.  Right
   click on the disk (on "Disk 1" itself and not on its partition) and
   select "Online".

8. Close the Computer Management window.

10. Close the Administrative Tools window.

Note: unlike instances created from an image, if the instance is
deleted the volume still remains.

#### Enable remote access

One option for remote access is to enable the built in Remote Desktop
Protocol service.

**Important: It is your responsibility to ensure the virtual machine
instances are secure.**

**Do not expose the Remote Desktop protocol to the wider Internet,
because it has known security vulnerbilities. Use the OpenStack
security group rules and other mechanisms to prevent untrusted hosts
to connect to the VM instance.**

1. Open the System Properties window. Launch the _Control Panel_ and
   select _System and Security_ > _Allow remote access_.

2. Select the "Allow remote connections to this computer" radio button.

3. Press the "OK" button to close the dialog that appears.  On some
   versions of Windows Server, this message is incorrect and the
   Firewall does need additional configuration (see steps below).

4. Leave the "Allow connections only from computers running Remote
   Desktop with Network Level Authentication (recommended)" checkbox
   checked.

5. Press the "OK" button.

6. Open the Firewall window. From the Control Panel's _System and
   Security_ section, choose "Allow an app through Windows Firewall"
   (under the "Windows Defender Firewall" section).

7. Ensure the "Public" checkbox for "Remote Desktop" is checked.

8. Press the "OK" button.

9. Close the Control Panel System and Security window.

For more fine-grain control of the firewall, use the Windows Firewall
Advanced settings. Select "Inbound Rules" in the list on the left hand
side of the window. Scroll down to and select "Remote Desktop - User
Mode (TCP-In)" for the "Public" profile and "Enable Rule".  Optionally
also enable the public "Remote Desktop - User Mode (UDP-In)" rule.
Note: the TCP rule is mandatory, UDP by itself is not sufficient.

Note: By default, Echo requests are disabled on Windows Server. If you
want to _ping_ the machine, you will need to enable the inbound
firewall rules to allow it. This can only be done through the firewall
advanced settings: under _inbound rules_, enable all the "Core
Networking Diagnostics - ICMP Echo Request" rules.

See also
--------

- [OpenStack Virtual Machine Image Guide](http://docs.openstack.org/image-guide/) especially the Microsoft Windows [example](https://docs.openstack.org/image-guide/windows-image.html).

- [Sysprep](https://docs.microsoft.com/en-us/windows-hardware/manufacture/desktop/sysprep--system-preparation--overview)

- [Cloudbase-Init](https://cloudbase.it/cloudbase-init) main Website.

- [Cloudbase-Init documentation](https://cloudbase-init.readthedocs.io/en/latest/)

- [Windows Openstack imaging tools](https://github.com/cloudbase/windows-openstack-imaging-tools/) for use on a host running Windows.

Contact
-------

Please send feedback and queries to Hoylen Sue at <hoylen.sue@qcif.edu.au>.
