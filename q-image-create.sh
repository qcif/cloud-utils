#!/bin/bash
#
# Utility to help in the creation of virtual machine images.
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

# Note: script explicitly uses "bash" instead of "sh" so that the
# "source" command is available and handles the "read -s" in the RC
# file.

PROG=`basename $0`

RAMSIZE=4096
PARTITION_MOUNT_POINT=/mnt/diskimage
DEFAULT_DISK_LABEL=bootdisk
DEFAULT_IMAGE_NAME="Test `date "+%Y-%m-%d %H:%M%:z"`"

RC_FILE="Mars-openrc.sh"

#----------------------------------------------------------------

die () {
  echo "$PROG: stopped"
  exit 1
}

#----------------------------------------------------------------
# Process command line

getopt -T > /dev/null
if [ $? -eq 4 ]; then
  # GNU enhanced getopt is available
  ARGS=`getopt --name "$PROG" --long install,run,extract,mount,unmount,upload,help,verbose --options iremuUhv -- "$@"`
else
  # Original getopt is available (no long option names, no whitespace, no sorting)
  ARGS=`getopt iremuUhv "$@"`
fi
if [ $? -ne 0 ]; then
  echo "$PROG: usage error (use -h for help)" >&2
  exit 2
fi
eval set -- $ARGS

CMD=
DISK_LABEL="$DEFAULT_DISK_LABEL"
IMAGE_NAME="$DEFAULT_IMAGE_NAME"

while [ $# -gt 0 ]; do
    case "$1" in
	-i | --install)  CMD=install;;
	-r | --run)      CMD=run;;
	-e | --extract)  CMD=extract;;
	-m | --mount)    CMD=mount;;
	-u | --unmount)  CMD=unmount;;
	-U | --upload)   CMD=upload;;
        -h | --help)     HELP=yes;;
        #-o | --output)   OUT_FILE="$2"; shift;;
        -v | --verbose)  VERBOSE=yes;;
        --)              shift; break;; # end of options
    esac
    shift
done

if [ -n "$HELP" ]; then
  echo "Usage: $PROG [options] command..."
  echo "Commands:"
  echo "  --install disc.iso disk.img"
  echo "  --run     disk.img"
  echo "  --extract disk.img partition.img"
  echo "  --mount   partition.img"
  echo "  --umount  partition.img"
  echo "  --upload  partition.img"
  echo "Options:"
  echo "  --help"
  echo "  --verbose"
  exit 0
fi

if [ -z "$CMD" ]; then
  echo "$PROG: usage error: missing a command option (use -h for help)" >&2
  exit 2
fi

#----------------------------------------------------------------
# Check dependent programs are installed

MISSING_PACKAGES=

if ! which kvm-img >/dev/null || ! which qemu-system-x86_64 >/dev/null; then
  MISSING_PACKAGES="$MISSING_PACKAGES qemu-kvm cloud-utils"
fi

if ! which glance >/dev/null; then
  MISSING_PACKAGES="$MISSING_PACKAGES glance"
fi

if ! which expect >/dev/null; then
  MISSING_PACKAGES="$MISSING_PACKAGES expect"
fi

if [ -n "$MISSING_PACKAGES" ]; then
  echo "$PROG: dependencies missing. To install them, please run" >&2
  echo "  apt-get install $MISSING_PACKAGES" >&2
  exit 3
fi

#----------------------------------------------------------------

if [ "$CMD" = 'install' ]; then
  # Install

  if [ $# -lt 2 ]; then
    echo "$PROG: usage error: --install expects ISOfile and diskImage" >&2
    exit 2
  elif [ $# -gt 2 ]; then
    echo "$PROG: too many arguments (use -h for help)" >&2
    exit 2
  fi
  ISO_FILE="$1"
  IMAGE="$2"
  if [ ! -f "$ISO_FILE" ]; then
    echo "$PROG: error: ISO disc file not found: $ISO_FILE" >&2
    exit 1
  fi
  if [ -f "$IMAGE" ]; then
    echo "$PROG: error: image file exists (delete it first): $IMAGE" >&2
    exit 1
  fi

  echo
  echo "Installation"
  echo "------------"
  echo "1. Connect using VNC."
  echo "2. Install on custom layout on entire disk (i.e. no swap partition)."
  echo "3. Type \"quit\" when installation is finished."
  echo

  # Create disk image
  kvm-img create -f raw "$IMAGE" 10G
  if [ $? -ne 0 ]; then
    echo "$PROG: error"
    exit 1
  fi

  # Run emmulator to install the OS
  expect -c "
set timeout 30;
spawn qemu-system-x86_64 \
  -m $RAMSIZE \
  -drive \"file=$IMAGE,if=scsi,index=0\" \
  -cdrom \"$ISO_FILE\" -boot order=d \
  -net nic -net user -usbdevice tablet \
  -no-acpi \
  -vnc 127.0.0.1:0 \
  -monitor stdio;
expect \"(qemu)\";
send \"change vnc password\r\";
expect \"Password:\";
send \"\r\";
expect \"(qemu)\";
interact;
"
  if [ $? -ne 0 ]; then
    echo "$PROG: error"
    exit 1
  fi

  echo "Next step: --run diskImage"

elif [ "$CMD" = 'run' ]; then
  #----------------------------------------------------------------
  # Run
  if [ $# -lt 1 ]; then
    echo "$PROG: usage error: --run expects diskImage" >&2
    exit 2
  elif [ $# -gt 1 ]; then
    echo "$PROG: too many arguments (use -h for help)" >&2
    exit 2
  fi
  IMAGE="$1"
  if [ ! -f "$IMAGE" ]; then
    echo "$PROG: error: file not found: $IMAGE" >&2
    exit 1
  fi

  echo
  echo "Configuration"
  echo "-------------"
  echo "1. Connect using VNC."
  echo "2. Setup the operating system ready for imaging."
  echo "3. Type \"quit\" when setup is finished."
  echo

  # Run emmulator to configure OS
  expect -c "
set timeout 30;
spawn qemu-system-x86_64 \
  -m $RAMSIZE \
  -drive \"file=$IMAGE,if=scsi,index=0\" -boot order=c \
  -net nic -net user -usbdevice tablet \
  -no-acpi \
  -vnc 127.0.0.1:0 \
  -monitor stdio;
expect \"(qemu)\";
send \"change vnc password\r\";
expect \"Password:\";
send \"\r\";
expect \"(qemu)\";
interact;
"
  if [ $? -ne 0 ]; then
    echo "$PROG: error"
    exit 1
  fi

  echo "Next step: --run diskImage (again) OR --extract diskImage partition"

elif [ "$CMD" = 'extract' ]; then
  #----------------------------------------------------------------
  # Extract

  if [ `id -u` -ne 0 ]; then
    echo "$PROG: error: must be run with root privileges for --extract" >&2
    exit 1
  fi

  if [ $# -lt 2 ]; then
    echo "$PROG: usage error: --extract expects diskImage and partitionImg" >&2
    exit 2
  elif [ $# -gt 2 ]; then
    echo "$PROG: too many arguments (use -h for help)" >&2
    exit 2
  fi
  IMAGE="$1"
  PARTITION="$2"
  if [ ! -f "$IMAGE" ]; then
    echo "$PROG: error: file not found: $IMAGE" >&2
    exit 1
  fi
  if [ -f "$PARTITION" ]; then
    echo "$PROG: error: file already exists (delete it first): $PARTITION" >&2
    exit 1
  fi

  losetup -f "$IMAGE" || die
  losetup -a || die
  fdisk -l /dev/loop0 || die
  losetup -d /dev/loop0 || die	# unmount
   
  losetup -f -o 1048576 "$IMAGE" || die
  losetup -a || die

  dd if=/dev/loop0 of="$PARTITION" || die

  losetup -d /dev/loop0 || die	# unmount

  echo "Next step: --mount partitionImage"

elif [ "$CMD" = 'mount' ]; then
  #----------------------------------------------------------------
  # Mount

  if [ `id -u` -ne 0 ]; then
    echo "$PROG: error: must be run with root privileges for --mount" >&2
    exit 1
  fi

  if [ $# -lt 1 ]; then
    echo "$PROG: usage error: --run expects partitionImage" >&2
    exit 2
  elif [ $# -gt 1 ]; then
    echo "$PROG: too many arguments (use -h for help)" >&2
    exit 2
  fi
  PARTITION="$1"
  if [ ! -f "$PARTITION" ]; then
    echo "$PROG: error: file not found: $PARTITION" >&2
    exit 1
  fi

  if [ ! -d "$PARTITION_MOUNT_POINT" ]; then
    echo "$PROG: error: partition mount point directory does not exist: $PARTITION_MOUNT_POINT" >&2
    exit 1
  fi

  mkdir -p "$PARTITION_MOUNT_POINT" || die
  mount -o loop "$PARTITION" "$PARTITION_MOUNT_POINT" || die

  # Edit /etc/fstab and rc.local

  echo "Next step: --unmount partitionImage"

elif [ "$CMD" = 'unmount' ]; then
  #----------------------------------------------------------------
  # Unmount

  if [ `id -u` -ne 0 ]; then
    echo "$PROG: error: must be run with root privileges for --unmount" >&2
    exit 1
  fi

  if [ $# -lt 1 ]; then
    echo "$PROG: usage error: --unmount expects partitionImage" >&2
    exit 2
  elif [ $# -gt 1 ]; then
    echo "$PROG: too many arguments (use -h for help)" >&2
    exit 2
  fi
  PARTITION="$1"
  if [ ! -f "$PARTITION" ]; then
    echo "$PROG: error: file not found: $PARTITION" >&2
    exit 1
  fi

  if [ -z "$DISK_LABEL" ]; then
    echo "$PROG: error: --partiton required to name partition" >&2
    exit 2
  fi

  umount "$PARTITION_MOUNT_POINT" || die

  # Change label of image to value in /etc/fstab

  tune2fs -L "$DISK_LABEL" "$PARTITION" || die

  echo "Next step: --upload partitionImage"

elif [ "$CMD" = "upload" ]; then
  #----------------------------------------------------------------
  # Upload

  if [ $# -lt 1 ]; then
    echo "$PROG: usage error: --upload expects partitionImage" >&2
    exit 2
  elif [ $# -gt 1 ]; then
    echo "$PROG: too many arguments (use -h for help)" >&2
    exit 2
  fi
  PARTITION="$1"
  if [ ! -f "$PARTITION" ]; then
    echo "$PROG: error: file not found: $PARTITION" >&2
    exit 1
  fi

  if [ ! -f "$RC_FILE" ]; then
    echo "$PROG: error: missing RC file: $RC_FILE" >&2
    exit 1
  fi

  if [ -z "$OS_AUTH_URL" -o -z "$OS_TENANT_ID" -o -z "$OS_TENANT_NAME" -o \
       -z "$OS_USERNAME" -o -z "$OS_PASSWORD" ]; then
    # source is a Bash command (this is a bash script, not just a sh script)
    source `dirname "$RC_FILE"`/`basename "$RC_FILE"` || die
    if [ -z "$OS_PASSWORD" ]; then
      die
    fi
  fi

  echo "Uploading to OpenStack"
  echo "   Project: $OS_TENANT_NAME"
  echo "      User: $OS_USERNAME"
  echo "Image name: $IMAGE_NAME"
  echo "Uploading..."

  glance image-create --name "$IMAGE_NAME" \
          --disk-format raw --container-format bare --is-public false \
          --owner "$OS_TENANT_ID" --file "$PARTITION" || die

  echo "Done"

else
  #----------------------------------------------------------------
  # Error
  echo "$PROG: error: unknown command: $CMD" >&2
  exit 1
fi

exit 0

#EOF
