q-owncloud
==========

Utility to help install _ownCloud_ on a Ubuntu Linux system running in Q-Cloud.

Synopsis
--------

    q-owncloud.sh [-y | --yes]
	
Description
-----------

This script installs _ownCloud_ on Ubuntu. It updates the package
list, installs the necessary packages and configures the for use.

The script is designed for use with Q-Cloud virtual machine instances,
because it is configured to store the _ownCloud_ files in `/mnt/data`,
which is where the large local storage disk is mounted.

The script first prompts the user to confirm the installation process.
This prompt does not occur if the `-y` option is provided, or _stdin_
is not a terminal. The later is useful if the script is piped in to
the shell (see examples below).

- `-y` | `--yes` disables the confirmation prompt.

The install process will prompt the user to create a password for the
MySQL _root_ account. A password must be provided (even though the
text says it is optional), because this password will be needed later
when setting up _ownCloud_.

This script can be rerun multiple times.

Examples
--------

The script can be downloaded from GitHub and run directly:

    $ curl https://raw.github.com/qcif/cloud-utils/master/q-owncloud.sh | sudo sh

This is usually the best way to run the script, since there is usually no reason
to keep the script after it has done its job.

If you want to save a copy of the script before running it, use these commands:

    $ curl -O https://raw.github.com/qcif/cloud-utils/master/q-owncloud.sh
    $ chmod a+x q-owncloud.sh
    $ sudo ./q-owncloud.sh


Environment
-----------

This script needs root privileges to run.

This script only runs on Ubuntu 13.04 or Ubuntu 12.10. Earlier
releases of Ubuntu do not have the _ownCloud_ package.

Diagnosis
---------

### Browser cannot contact to server

Check firewalls permit port 443 traffic.

### Not found. The requested URL ... was not found on this server

Make sure the URL starts with "https" instead of "http".

See also
--------

- [ownCloud](http://owncloud.org/)

Contact
-------

Please send feedback and queries to Hoylen Sue at <h.sue@qcif.edu.au>.
