#!/bin/sh
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

PROG=`basename $0 .sh`

DEFAULT_DISK_SIZE=10G
DEFAULT_DISK_INTERFACE=virtio
DEFAULT_VNC_DISPLAY=0

PARTITION_MOUNT_POINT=/mnt/diskimage
DEFAULT_DISK_LABEL=bootdisk
DEFAULT_IMAGE_NAME="Test image $(date "+%F %T%:z")"

#----------------------------------------------------------------

die () {
  echo "$PROG: stopped"
  exit 1
}

#----------------------------------------------------------------
# Process command line

SHORT_OPTS="d:iremn:s:t:uUhvx:"

getopt -T > /dev/null
if [ $? -eq 4 ]; then
  # GNU enhanced getopt is available
  ARGS=`getopt --name "$PROG" --long install,run,extract,mount,unmount,upload,type:,size:,display:,extra-opts:,name:,help,verbose --options $SHORT_OPTS -- "$@"`
else
  # Original getopt is available (no long option names, no whitespace, no sorting)
  ARGS=`getopt $SHORT_OPTS "$@"`
fi
if [ $? -ne 0 ]; then
  echo "$PROG: usage error (use -h for help)" >&2
  exit 2
fi
eval set -- $ARGS

CMD=
VNC_DISPLAY=$DEFAULT_VNC_DISPLAY
DISK_SIZE=$DEFAULT_DISK_SIZE
DISK_INTERFACE=$DEFAULT_DISK_INTERFACE

# EXTRA_QEMU_OPTIONS="-drive file=dummydisk.img,if=virtio"
EXTRA_QEMU_OPTIONS=
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

        -s | --size)     DISK_SIZE="$2"; shift;;
        -t | --type)     DISK_INTERFACE="$2"; shift;;
        -d | --display)  VNC_DISPLAY="$2"; shift;;
        -x | --extra)    EXTRA_QEMU_OPTIONS="$2"; shift;;
        -n | --name)     IMAGE_NAME="$2"; shift;;

        -h | --help)     HELP=yes;;
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
  echo "  --size numBytes   disk size for install (default: $DEFAULT_DISK_SIZE)"
  echo "  --type diskType   settings for install/run (default: $DEFAULT_DISK_INTERFACE)"
  echo "  --display num     VNC server display (default: $DEFAULT_VNC_DISPLAY)"
  echo "  --extra-opts str  extra options to pass to QEMU for install/run"
  echo "  --name imageName  name for upload"
  echo "  --help"
  echo "  --verbose"
  exit 0
fi

if [ -z "$CMD" ]; then
  echo "$PROG: usage error: missing a command option (use -h for help)" >&2
  exit 2
fi

#----------------------------------------------------------------
# Check support for virtualization

function run_vm () {
  MODE=$1

  # Check for executable

  if ! which qemu-img >/dev/null 2>&1; then
    echo "$PROG: error: program not found: qemu-img" >&2
  fi

  # Determine virtualization executable

  QEMU_EXEC_1=/usr/libexec/qemu-kvm  # CentOS (not in PATH)
  QEMU_EXEC_2=qemu-system-x86_64  # Ubuntu

  if which $QEMU_EXEC_1 >/dev/null 2>&1; then
    QEMU_EXEC="$QEMU_EXEC_1"

  elif which $QEMU_EXEC_2 >/dev/null 2>&1; then
    QEMU_EXEC="$QEMU_EXEC_2"

  else
    echo "$PROG: error: program not found: $QEMU_EXEC_1 or $QEMU_EXEC_2" >&2
    echo "$PROG: error: check if the \"qemu-kvm\" package has been installed" >&2
    exit 3
  fi

  # Check if virtualization extensions are being used

  VIRT_SUPPORT=yes

  egrep "(vmx|svm)" /proc/cpuinfo >/dev/null 2>&1
  if [ $? -ne 0 ]; then
    # No Intel VT-x or AMD AMD-V extensions
    echo "$PROG: warning: CPU has no virtualization extension support" >&2
    VIRT_SUPPORT=
  else
    if [ ! -c '/dev/kvm' ]; then
      echo "$PROG: warning: KVM not installed and/or supported by kernel" >&2
      VIRT_SUPPORT=
    fi
  fi

  if [ -z "$VIRT_SUPPORT" ]; then
    echo "$PROG: warning: using emulation: performance will be poor" >&2
  fi

  # Set disk type options

  if [ "$DISK_INTERFACE" != 'virtio' -a "$DISK_INTERFACE" != 'ide' ]; then
    echo "$PROG: unsupported disk interface type: $DISK_INTERFACE (expecting: virtio or ide)" >&2
    exit 1
  fi

  RAM_SIZE=2048  # initial testing indicates more RAM does not change boot speed
  NUM_CPUS=1     # initial testing indicates more CPUs decreases boot speed
  QEMU_OPTIONS="-m $RAM_SIZE -smp $NUM_CPUS -net nic -net user -usbdevice tablet"

  # Additional mode-based options

  if [ "$MODE" = 'Installation' ]; then
    CDROM_OPTIONS="-cdrom $ISO_FILE -boot order=cd,once=d"

    STEP_2="Install on custom layout on entire disk (i.e. no swap partition)."
    STEP_NEXT="Next step: --run diskImage"

  elif [ "$MODE" = 'Configuration' ]; then
    CDROM_OPTIONS="-boot order=c"

    STEP_2="Configure the operating system ready for imaging."
    STEP_NEXT="Next step: --run diskImage (again) OR --extract diskImage partition"

  else
    echo "$PROG: internal error: unknown mode: $MODE" >&2
    exit 1
  fi

  # Run QEMU

  COMMAND="$QEMU_EXEC $QEMU_OPTIONS \
    -drive file=$IMAGE,if=$DISK_INTERFACE,index=0 \
    $CDROM_OPTIONS \
    $EXTRA_QEMU_OPTIONS \
    -vnc 127.0.0.1:$VNC_DISPLAY"

  if [ -n "$VERBOSE" ]; then
    echo $COMMAND
    echo
  fi

  # -monitor stdio

  # Run QEMU in background (nohup so user can log out without stopping it)

  LOGFILE="q-image-create-$$.log"
  nohup $COMMAND > $LOGFILE 2>&1 &
  QEMU_PID=$!

  # Detect early termination errors
  sleep 2
  if ! ps $QEMU_PID > /dev/null; then
    cat $LOGFILE
    rm $LOGFILE
    echo "$PROG: QEMU returned an error" 2>&1
    exit 1
  fi
  echo "$PROG: `date "+%F %T%:z"`: QEMU PID: $QEMU_PID" >> $LOGFILE

  echo "$MODE"
  echo "------------"
  echo "1. Connect to VNC display $VNC_DISPLAY (no password required)"
  echo "   QEMU monitor: type Ctrl-Alt-2 into VNC"
  echo "   Log file: $LOGFILE"
  echo "   PID: $QEMU_PID"
  echo "2. $STEP_2"
  echo "3. $STEP_NEXT"
}

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

  # Create disk image

  QEMU_IMG_OUTPUT=`qemu-img create -f raw "$IMAGE" $DISK_SIZE`
  if [ $? -ne 0 ]; then
    echo "$QEMU_IMG_OUTPUT"
    echo "$PROG: qemu-image could not create disk image: $IMAGE"
    exit 1
  fi

  if [ -n "$VERBOSE" ]; then
    echo "Creating disk image file: $QEMU_IMG_OUTPUT"
    echo
  fi

  # Run virtualization

  run_vm Installation


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

  run_vm Configuration


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

  # Determine parameters from disk needed to extract partition

  D_DEVICE=`losetup -f "$IMAGE" --show`
  if [ $? -ne 0 ]; then
    echo "$PROG: error: loopback mounting of disk failed" >&2
    exit 1
  fi

  if [ $(fdisk -l -u $D_DEVICE | grep ^/dev/ | wc -l) -ne 1 ]; then
    fdisk -l -u $D_DEVICE # display partitions to user
    sleep 1 # else disconnect fails because device is busy
    losetup -d "$D_DEVICE"
    echo
    echo "$PROG: error: disk image contains multiple partitions" >&2
    exit 1
  fi

  # fdisk:
  #   -l = list partitions for device
  #   -u = results in 512 byte sectors
  # egrep: make sure Start sector is the expected value of 2048
  #        must be 2048 to match the 1048576 (=2048 x 512) hardwired below

  fdisk -l -u $D_DEVICE | egrep '^/dev/[^ ]+ +[^ ]+ +2048 +' > /dev/null
  if [ $? -ne 0 ]; then
    fdisk -l -u $D_DEVICE # display partitions to user
    losetup -d "$D_DEVICE"
    echo
    echo "$PROG: error: partition does not start at expected offset" >&2
    exit 1
  fi

  sleep 1 # else disconnect fails because device is busy
  losetup -d "$D_DEVICE"  # disconnect loopback mounted disk
  if [ $? -ne 0 ]; then
    echo "$PROG: error: could not disconnect disk loopback device: $D_DEVICE" >&2
    exit 1
  fi

  # Loopback mount the partition and extract it

  P_DEVICE=$(losetup -o 1048576 -f "$IMAGE" --show)
  if [ $? -ne 0 ]; then
    echo "$PROG: error: loopback mounting of partition failed" >&2
    exit 1
  fi

  dd if="$P_DEVICE" of="$PARTITION"
  if [ $? -ne 0 ]; then
    sleep 1 # else disconnect fails because device is busy
    losetup -d "$P_DEVICE"
    echo "$PROG: error: could not copy partition from $P_DEVICE" >&2
    exit 1
  fi

  sleep 1 # else disconnect fails because device is busy
  losetup -d "$P_DEVICE"  # disconnect loopback mounted partition
  if [ $? -ne 0 ]; then
    echo "$PROG: error: could not disconnect partition loopback device: $P_DEVICE" >&2
    exit 1
  fi

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

  # Check for glance program

  if ! which glance >/dev/null 2>&1; then
    echo "$PROG: error: program not found: glance" >&2
    exit 1
  fi

  if [ -z "$OS_AUTH_URL" -o -z "$OS_TENANT_ID" -o -z "$OS_TENANT_NAME" -o \
       -z "$OS_USERNAME" -o -z "$OS_PASSWORD" ]; then
    echo "$PROG: error: environment variables not set, source OpenStack RC file" >&2
    exit 1
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
