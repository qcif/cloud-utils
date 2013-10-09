q-image-create
==============

Utility to help create virtual machine image for NeCTAR.

**Note: This script (and this documentation) is currently under development.**

Synopsis
--------

    q-image-create.sh
	
Description
-----------



Examples
--------

Create a medium size (or larger) NeCTAR VM instance. By default, this
script will run a guest virtual machine with 4GiB of memory, so the
creation VM needs to be larget than that (the medium size VM instance has
8GiB of memory).

Login into the creation VM and create a ssh tunnel to the VNC port:

    ssh -L 6900:localhost:5900 ubuntu@creation.vm.hostname

Change to the ephemeral disk

    ./q-image-create.sh --install ~/Downloads/Mandriva.2011.x86_64.1.iso m.img

VNC connect (no password)

Install, custom partition.

Close VNC and type "quit"





Environment
-----------

This script is designed to run on Ubuntu.

This script must be run with root privileges.


Files
-----


Diagnosis
---------

See also
--------

Bugs
----

Contact
-------

Please send feedback and queries to Hoylen Sue at <h.sue@qcif.edu.au>.
