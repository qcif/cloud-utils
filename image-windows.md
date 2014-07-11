Creating an image for Windows Server 2012 R2
============================================

This document describes how to create a virtual machine instance of
Microsoft Windows Server 2012 R2 for OpenStack.

These steps may apply to other versions of Microsoft Windows with some
modification.  These instructions should also be applicable to other
deployments of OpenStack.

Requirements
------------

- OpenStack project to upload the image to.
- Local system, with a ssh client and a VNC client.
- Creation host system, with QEMU and glance (e.g. a [configured VM instance](image-init.md)).
- Installation ISO image for Microsoft Windows Server 2012 R2.
- VirtIO drivers for Windows ISO image.
- Suitable licence for Microsoft Windows Server 2012 R2.

Licensing
---------

Please consult with your Node for the latest situation about Windows
licensing, because this section is subject to change and may vary
between the different Nodes.

**Important: It is your responsibility to ensure all licensing
requirements are satisfied.**

At the time of writing, it is clear that these licenses **must not**
be used:

- OEM licenses

It is not clear whether these licenses can be used:

- Evaluation licences (even for evaluation purposes).

These licences **may** be used subject to their conditions:

- Service Provider Licensing Agreement (SPLA)

    Some NeCTAR Nodes may be SPLA licensees and are able to provide
    users with a license for Windows Server.  Please talk to you Node
    about their processes for SPLA licensed servers.

- Bring Your Own License (BYOL)

    If you or your institution has a Windows Server 2012 R2 license key
    available for use, then before using that license key you must:

     - If it is an institutional license key, you need to obtain
       permission from your institution’s IT department prior to
       use. Please talk to your IT department about internal processes
       for obtaining these keys.  You IT department will need to
       ensure that the license key they provide supports “License
       Mobility” under its product usage rights (PUR).  License
       Mobility allows you to deploy the Windows server license on the
       Microsoft Azure Cloud or on an Authorised Mobility Partner.
       More information can be found here:
  
        <http://www.microsoft.com/licensing/software-assurance/license-mobility.aspx#tab=1>

    - When deploying, you will need to ensure the NeCTAR Node is an
      Authorised Mobility Partner.  Not all NeCTAR Nodes are
      Authorised Mobility Partners, so you will need to check with the
      Node prior to use.

    - If the NeCTAR Node is an Authorised Mobility Partner, then you
      will be required to submit a “license verification form”, within
      10 days of deployment.  More information can be found here:

        <http://www.microsoft.com/licensing/software-assurance/license-mobility.aspx#tab=2>

    - Once approved by both the NeCTAR Node and your IT department,
      you can deploy the license on the set of compute Nodes that are
      licensed to support Windows servers.

    - You **must not** deploy your Windows server anywhere in the
      NeCTAR cloud as not all compute nodes are licensed to support
      Windows Server. Please work with the respective Node to ensure
      you deploy your license on the correct compute nodes.

Process
-------

### Step 1: Get installation ISO image on the creation host system

#### 1a. Get the Windows installation ISO image

Get a copy of the ISO image onto the creation host.  The example
commands copies it from the local system. Store it in the working
directory on the large ephemeral disk, and not in the home directory
on the small boot disk.

    [local]$ scp win2012r2.iso creator@creation.host.system:/mnt/creator/win2012r2.iso

#### 1b. Connect to the host system and create a SSH tunnel

From the local system, ssh into the creation host as the new user.  At
the same time, create a ssh tunnel from a local port (in this example
15900 is used) to a VNC port (5900) on the creation host:

    [local]$ ssh -L 15900:localhost:5900 creator@creation.host.system

#### 1c. Get the VirtIO drivers ISO image

Get a copy of the VirtIO drivers ISO image onto the creation host.
The example commands uses _curl_ to download it from Red Hat
<http://alt.fedoraproject.org/pub/alt/virtio-win/latest/images/bin/>. If
_curl_ is not available, try using _wget_.  Store it in the working
directory on the large ephemeral disk, and not in the home directory
on the small boot disk.

    [creator@host]$ cd /mnt/creator
    [creator@host]$ curl -L -O --progress-bar http://alt.fedoraproject.org/pub/alt/virtio-win/latest/images/bin/virtio-win-0.1-81.iso

#### 1d. Get the script

Get a copy of the _q-image-create.sh_ script onto the creation
host. This can be done by uploading it or downloading it. The example
below downloads it from the GitHub respository. Note: if GitHub
changes the raw download URL, find out its new value from the [project
in GitHub](https://github.com/qcif/cloud-utils).

    [creator@host]$ cd /mnt/creator
    [creator@host]$ curl -O https://raw.githubusercontent.com/qcif/cloud-utils/master/q-image-create.sh
    [creator@host]$ chmod a+x q-image-create.sh

### Step 2: Install the guest system from the ISO

#### 2a. Create the disk image and boot from the ISO

Create an disk image and boot off the ISO image. By default, a 10 GiB
disk image, which is the maximum size of the standard boot disk
supported by NeCTAR.  It is stored in the QEMU Copy-On-Write version 2
(QCOW2) format, and the VNC server is listening on display 0 (port
5900). If needed, these defaults can be changed using command line
options.

Both the installation ISO and the VirtIO drivers ISO are attached
to the guest.

    [creator@host]$ ./q-image-create.sh --verbose --iso win2012r2.iso --iso virtio-win-0.1-81.iso --create disk.qcow2

A 10 GiB disk image is sufficient to install Windows and it can be
expanded when it is used.  A larger disk image can be created by
specifying the `--size` option. Larger images can only be used on
volume storage drives and are slower to transfer, but might be needed
if you want to pre-install additional software on the image (as
opposed to installing the software after instantiating the image onto
a larger volume storage drive after uploading to OpenStack).  For
example: add the `--size 40G` option to create a 40 GiB image.

The script runs _qemu-kvm_ in the background with _nohup_. So you can
log out of the creation host and it will continue running.

#### 2b. Use VNC to access the guest system

Connect to the VNC server (e.g. in this example to local port 15900
which is port forwarded to port 5900 on the creation host).  There is
no VNC password: press return if prompted for one. Note: a VNC
password can be set using the "change vnc password" command in the
QEMU console.

The QEMU console can be accessed by typing Ctrl-Alt-2 in the VNC
client; and Ctrl-Alt-1 to return to the main display. The QEMU console
can be used to list and change the virtual CD-ROM (using the commands
"info block" and "change ide1-cd0 filenameOfISOImage"). The
"system_reset" command can be used to reboot the guest system.  The
"quit" command can be used to stop the guest system and the emulator.

Note:If the local machine is an Apple Macintosh do not use the _Screen
Sharing_ client that comes with OS X, because it is incompatible with
the VNC implementation provided by QEMU/KVM: use a third party VNC
client.

#### 2c. Install the guest system

Install the guest operating system as normal, except pay special
attention to how the disk is partitioned.

1. Change the "Time and currency format" to "English
   (Australia)". Press the "Next" button.

2. Press the "Install Now" button.

3. Select the operating system to install. Press the "Next" button.

    These steps apply to "Windows Server 2013 R2 Standard Edition
    (Server with GUI)" or "Windows Server 2013 R2 Datacentre Edition
    (Server with GUI)". They do not apply to the server core editions.

4. Read the licence terms and, if you accept them, check the "I accept
   the licence terms" checkbox and press the "Next" button.

5. Choose "Custom: install Windows only (advanced)", since this is
   not an upgrade.

#### 2d. Use the VirtIO disk drivers

No drives will appear before the VirtIO drivers are loaded.

1. Press the "Load Driver" button.

2. Press the "Browse" button.

3. Select the second CD drive, the "E:\WNET\AMD64" directory, and
   press the "OK" button. (Windows Server .NET was an old name before
   it was renamed Windows Server 2003.)

4. The "Select the driver to install" dialog should detect the "Red
   Hat VirtIO SCSI controller" driver. Press the "Next" button.
   
     A "Drive 0 unallocated space" will be detected. If a 10 GiB disk
     image is being used, there will be a message claiming more space
     is recommended: ignore it.

5. Press "Next". Wait about 20 minutes for the installation process
    to finish.

#### 2e. Complete the installation

1. Set add administrator password and press the "Finish" button.

This administrator password is for your use when creating the
image. When the image is instantiated, the user will be prompted to
create a new administrator password for that instance.

#### 2f. VirtIO network drivers

Install the VirtIO network drivers to use the virtual network
interfaces.

1. Type Ctrl-Alt-Delete into the VNC session to sign in.

2. Open the Device Manager. Launch the Control Panel and select System
    and Security > Hardware > Device Manager.

    Under "Other Devices" there should be an "Ethernet Controller"
    whose driver could not be found.

3. View the properties of the Ethernet Controller. By double clicking 
   on it, or right clicking on it and selecting Properties.

4. Click the "Update Driver" button.

5. Choose "Browse my computer for driver software".

6. Click the "Browse..." button.

7. Select the second CD Drive (E:) (not the WNET subdirectory) and
   press the "OK" button.

8. Press the "Next" button.

     It should find the "Red Hat VirtIO Ethernet Adapter" driver.

9. Press the "Install" button.

10. When prompted to find PCs, devices and content on this network,
    press the "No" button.

11. Press the "Close" to close the driver update dialog.

12. Press "Close" to close the Ethernet Adapter Properties dialog.

13. Close the Device Manager window.

14. Close the Control Panel Hardware window.

#### 2g. Configure Windows Update

Turn on automatic updates and install the current updates.

#### 2h. Time zone

When the image is instantiated, it will have a system clock in
the local time of the availability zone. Set the time zone
to match (e.g. Brisbane +10:00 for QRIScloud).

1. Open the Date and Time settings. Launch the Control Panel and
   select Clock, Language, and Region > Change the time zone.

2. Press the "Change time zone..." button.

3. Select the time zone and press the "OK" button.

    Note: the time showing might not be correct (even if the creation
    host's time and timezone are correct). This is because the system
    clock is currently in UTC, but Windows assumes it is in the local
    time zone. A system clock in local time will be presented when the
    image is running on OpenStack.

4. Press the "OK" button to close the Time and Date dialog.

5. Close the Control Panel Clock, Language, and Region window.

#### 2i. Disable display blanking

1. Open the Control Panel Power Options. Launch the Control Panel and select
   Hardware > Change power-saving settings.

2. Click the "Change plan settings" next to the preferred plan.

3. Change the Turn off the display to "Never".

4. Press the "Save changes" button.

5. Close the Control Panel Power Settings window.

#### 2j. Other configurations

Install software and make other configurations that need to be
included in the image.

#### 2k. cloud-init

Consider installing cloud-init for Windows if more integration with
OpenStack is required.

1. Open Internet Explorer.

2. Visit <http://www.cloudbase.it/cloud-init-for-windows-instances/>
   and add www.cloudbase.it as a trusted domains. The other
   domains can remain blocked.

3. Download and save the installer (the x64 version).

4. Run the installer accepting the defaults, except also:

    - Select the Network adapter to configure: Red Hat VirtIO Ethernet Adapter
    - Select the Serial port for logging: COM1
    - Check both "Run Sysprep to create a generalized image" and
      "Shutdown when Sysprep terminates".

#### 2l. Sysprep

If cloud-init was not installed or sysprep not run as a part of
cloud-init's installation, run sysprep.

The Microsoft Sysprep utility removes system specific data and to
enable the out-of-box-experience when Windows is first started.

This must be performed as the last step before uploading the image.

1. Start Windows PowerShell.

2. Type the following commands to run sysprep:

         C:\Windows\System32\Sysprep\sysprep /generalize /oobe 

3. Wait for sysprep to finish running and close the VNC client.
   Sysprep will shutdown the Windows system when it is finished.

### Step 3: Optionally run the guest system to configure it

If additional configuration needs to be performed, restart the guest
virtual machine by booting off the disk image.

    $ ./q-image-create.sh --run disk.qcow2
	
As before, connect to the VNC server (through the ssh tunnel) with an
empty password.

### Step 4: Upload the image to OpenStack glance image server

#### 4a. Obtain your NeCTAR password

Obtain the password for your user account. From the NeCTAR OpenStack
dashboard, click on the Settings link (top right), choose "Reset
Password" (left side), press the "Reset Password" button.

#### 4b. Source RC file

Obtain the RC file from the NeCTAR OpenStack dashboard: via Access &
Security > API Access > Download OpenStack RC File.

Set up the environment variables that the glance client needs to run
by sourcing the RC file and entering your password:

    [creator@host]$ . projectName-openrc.sh

#### 4c. Upload image

Upload the disk image, optionally giving it a name:

    [creator@host]$ ./q-image-create.sh --upload --os-type windows disk.qcow2 --name "My Win2012R2 image"

The `--os-type` option sets the property on the image in glance. As a
Windows image, instances launched from it will have a system clock in
local time (instead of UTC) and format the ephemeral disk as NTFS
(instead of ext3).

### Step 5: Use the image to instantiate virtual machine instances

Log into the [NeCTAR Dashboard](https://dashboard.rc.nectar.org.au)
and instantiate a virtual machine instance from the image.

When testing images, launch them in the Melbourne availability zone.
The glance image server is in Melbourne, so that avoids sending the
test images over the network to a different availability zone.

Note: the image is uploaded into a specific project/tenant. If the
image is not visible, check the project/tenant is the one it was
uploaded to (i.e. the one corresponding to the RC file used to set the
environment variables).

If it is intended to use RDP to access the VM instance, configure the
security groups to allow RDP network traffic through (TCP port 3389,
and optionally UDP port 3389).

There are two options for instantiating a VM image from the image:

- Run Windows from the 10 GiB boot disk; or
- Run Windows from a volume storage disk

#### Option 1: Run Windows from the 10 GiB boot disk

This option can be used if the image is 10 GiB or smaller.  If the
image is larger than 10 GB, this option cannot be used.

The boot disk is fixed at 10 GiB and cannot be increased.  The
ephemeral disk and additional volume storage disks can be used as
additional storage.

1. Instantiate an new VM and select "Boot from image" as the instance
   boot source and select the image.

#### Option 2: Run Windows from a volume storage disk

This option is available to any image, regardless of size.

The boot volume storage disk can be made any size (as long as it is
larger than the image size). The ephemeral disk and additional volume
storage disks can be used as additional storage.

1. In the Images & Snapshots list, under the "More" menu for the
   image, select "Create Volume".

2. Type in a name and optional description for the new volume.

3. Type in a size for the new volume. The size should be larger than
   the image size and it can be expanded to use the extra space (as
   described below).

4. Choose an Availability Zone. This will dictate where the VM
   instance can be launched.

5. Press the "Create Volume" button and wait for the volume to be
   created.

6. Launch a new VM and select "Boot from volume" as the instance boot
   source and select the volume that was created.

Note: use the advanced option to set the availability zone to where
the volume is located. It is not possible to have the VM instance in a
different availability zone from the volume.

#### Connect to the VM instance for the first time

1. Go to the console for the VM instance in the NeCTAR dashboard.

2. Click on the gray area at the top or sides of the console, so
   keystrokes are sent to the console.

3. If necessary, set the country or region, language and keyboard
   layout. Press the "Next" button.

4. Read and licence terms and, if you accept them, press
   the "I accept" button.

5. Enter a new password for the administrator account and press
   the "Finish" button.

6. Press the "Send CtrlAltDel" button and sign into Windows
   using the Administrator password that was just created.

7. When prompted, "do you want to find PCs, devices, and content on
   this network, and automatically connect to devices like printers
   and TVs?", press the "No" button.

#### Expanding the volume boot disk (only with option 2)

If using a volume storage disk as the boot disk, expand the size of
the boot disk to use the entire volume storage disk.

1. Start the "Administrative Tools".

2. Open "Computer Mangement".

3. Select Storage > Disk Management.

    The volume boot disk (Disk 0) should have a system reserved
    partition, the boot partition and unallocated space.

4. Right click on the boot partition (C:) and select "Extend Volume...".

5. Press the "Next" button.

6. Disk 0 should be selected and the "Select the amount of
   space in MB" should default to the same as the "Maximum available
   space in MB". That is, it will expand to use the entire unused
   space. Press the "Next" button.

7. Press the "Finish" button.

8. Optionally, enable the ephemeral disk. It should be offline.  Right
   click on the disk (on "Disk 1" itself and not on its partition) and
   select "Online".

9. Close the Computer Management window.

10. Close the Administrative Tools window.


#### Enable remote access

**Important: It is your responsibility to ensure the virtual machine
instances are secure.**

1. Open the System Properties window. Launch the Control Panel and
   select System and Security > Allow remote access

2. Select the "Allow remote connections to this computer" radio button.

3. Press the "OK" button to close the dialog that appears.
   The message in this dialog box is misleading and the Firewall
   may need further manual configuration.

4. Leave the "Allow connections only from computers running Remote
   Desktop with Network Level Authentication (recommended)" checkbox
   checked.

5. Press the "OK" button.

6. Open the Firewall window. From the Control Panel System and
   Security section, choose "Allow an app through Windows Firewall".

7. Check the "Public" checkbox for "Remote Desktop".

8. Press the "OK" button.

9. Close the Control Panel System and Security window.

For more fine-grain control of the firewall, use the Windows Firewall
Advanced settings. Select "Inbound Rules" in the list on the left hand
side of the window. Scroll down to and select "Remote Desktop - User
Mode (TCP-In)" for the "Public" profile and "Enable Rule".  Optionally
also enable the public "Remote Desktop - User Mode (UDP-In)" rule.
Note: the TCP rule is mandatory, UDP by itself is not sufficient.

Note: By default, Echo requests are disabled on Windows Server
2012. If you want to _ping_ the machine, you will need to enable the
inbound firewall rules to allow it. This can only be done through the
firewall advanced settings.

If connecting from OS X, use the newer _Microsoft Remote Desktop_
appplication from the Mac App Store. The older _Remote Desktop
Connection_ application (installed with Microsoft Office 2011) does not
[recognise](http://blog.mikejmcguire.com/2013/10/15/r2-d2-you-know-better-than-to-trust-a-strange-computer-why-doesnt-the-mac-os-x-rdp-client-trust-windows-server-2012-r2-2/)
the self-signed certificate installed by default.

See also
--------

- [OpenStack Virtual Machine Image Guide](http://docs.openstack.org/image-guide/content/ch_preface.html) especially the [Windows image example](http://docs.openstack.org/image-guide/content/windows-image.html)
- [Sysprep Technical Reference](http://technet.microsoft.com/en-us/library/cc766049.aspx), Microsoft.
- [Cloud-init for Windows](http://www.cloudbase.it/cloud-init-for-windows-instances/)

Contact
-------

Please send feedback and queries to Hoylen Sue at <h.sue@qcif.edu.au>.

