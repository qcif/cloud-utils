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

DEFAULT_DISK_SIZE=10G # for --create
DEFAULT_DISK_FORMAT=qcow2 # for --create

DEFAULT_DISK_INTERFACE=virtio
DEFAULT_VNC_DISPLAY=0

DEFAULT_PARTITION=1 # for --mount
DEFAULT_MOUNT_POINT=/mnt/partition

#DEFAULT_VOLUME_LABEL=bootdisk
DEFAULT_IMAGE_NAME_PREFIX='Test image'

RAM_SIZE=2048  # initial testing indicates more RAM does not change boot speed
NUM_CPUS=1     # initial testing indicates more CPUs decreases boot speed

#----------------------------------------------------------------

die () {
  echo "$PROG: stopped"
  exit 1
}

#----------------------------------------------------------------
# Process command line

SHORT_OPTS="cd:Df:i:rMn:o:p:s:t:uUhvx:"

getopt -T > /dev/null
if [ $? -eq 4 ]; then
  # GNU enhanced getopt is available
  ARGS=`getopt --name "$PROG" --long create,run,mount,unmount,partition:,upload,format:,disk-type:,iso:,os-type:,size:,display:,extra-opts:,name:,help,verbose,debug --options $SHORT_OPTS -- "$@"`
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
DISK_FORMAT=$DEFAULT_DISK_FORMAT
DISK_INTERFACE=$DEFAULT_DISK_INTERFACE
ISO_IMAGES=
PARTITION=$DEFAULT_PARTITION
OS_TYPE=

# EXTRA_QEMU_OPTIONS="-drive file=dummydisk.img,if=virtio"
EXTRA_QEMU_OPTIONS=

while [ $# -gt 0 ]; do
    case "$1" in
        -c | --create)   CMD=create;;
        -r | --run)      CMD=run;;
        -M | --mount)    CMD=mount;;
        -U | --unmount)  CMD=unmount;;
#        -l | --label)    CMD=label;;
        -u | --upload)   CMD=upload;;

        -s | --size)     DISK_SIZE="$2"; shift;;
        -f | --format)   DISK_FORMAT="$2"; shift;;
        -t | --disk-type) DISK_INTERFACE="$2"; shift;;
        -i | --iso)      ISO_IMAGES="$ISO_IMAGES $2"; shift;;
        -n | --name)     IMAGE_NAME="$2"; shift;;
        -o | --os-type)  OS_TYPE="$2"; shift;;
        -d | --display)  VNC_DISPLAY="$2"; shift;;
        -x | --extra-opts) EXTRA_QEMU_OPTIONS="$2"; shift;;
        -p | --partition)  PARTITION="$2"; shift;;

        -h | --help)     HELP=yes;;
        -v | --verbose)  VERBOSE=yes;;
        -D | --debug)    DEBUG=yes;;
        --)              shift; break;; # end of options
    esac
    shift
done

if [ -n "$HELP" ]; then
  echo "Usage: $PROG [options] diskImage"
  echo "Commands:"
  echo "  -c | --create          create disk image and boot off first CDROM"
  echo "  -r | --run             run guest system from disk image"
#  echo "  --label   disk.raw [volumeLabel] (default: $DEFAULT_VOLUME_LABEL)"
  echo "  -u | --upload          copy disk image up into glance repository"
  echo "  -M | --mount           mount partition from disk image"
  echo "  -U | --unmount         unmount partition from disk image"
  echo "Create options:"
  echo "  -s | --size numBytes   size of disk to create (default: $DEFAULT_DISK_SIZE)"
  echo "  -f | --format diskFmt  disk image format to save to (default: $DEFAULT_DISK_FORMAT)"
  echo "                         Note: mount/unmount only works with the raw format"
  echo "Create or run options:"
  echo "  -i | --iso isofile     attach as a CDROM (repeat for multiple ISO images)"
  echo "  -t | --disk-type intf  virtual QEMU disk interface (default: $DEFAULT_DISK_INTERFACE)"
  echo "  -x | --extra-opts str  extra QEMU options, for advanced use"
  echo "  -d | --display num     VNC server display (default: $DEFAULT_VNC_DISPLAY)"
  echo "Mount options:"
  echo "  -p | --partition num   partition to mount (default: $DEFAULT_PARTITION)"
  echo "Upload options:"
  echo "  -n | --name imageName  name of image in glance (default: \"$DEFAULT_IMAGE_NAME_PREFIX ...\")"
  echo "  -o | --os-type value   set os_type property for image (e.g. \"windows\")"
  echo "Common options:"
  echo "  -h | --help            show this help message"
  echo "  -v | --verbose         show extra information"
  exit 0
fi

if [ -z "$CMD" ]; then
  echo "$PROG: usage error: missing a command option (use -h for help)" >&2
  exit 2
fi

# Check argument is the diskImage

if [ $# -lt 1 ]; then
  echo "$PROG: usage error: missing diskImage filename" >&2
  exit 2
elif [ $# -gt 1 ]; then
  echo "$PROG: too many arguments (use -h for help)" >&2
  exit 2
fi

IMAGE="$1"

if [ "$CMD" = 'create' ]; then
  # Disk image MUST NOT exist
  if [ -f "$IMAGE" ]; then
      echo "$PROG: error: image file exists (use --run, or delete it to use --create): $IMAGE" >&2
      exit 1
    fi
else
  # Disk image MUST exist
  if [ ! -e "$IMAGE" ]; then
    echo "$PROG: error: file not found: $IMAGE" >&2
    exit 1
  fi
  if [ ! -f "$IMAGE" ]; then
    echo "$PROG: error: disk image is not a file: $IMAGE" >&2
    exit 1
  fi
  if [ ! -r "$IMAGE" ]; then
    echo "$PROG: error: cannot read disk image: $IMAGE" >&2
    exit 1
  fi
fi

# Convert ISO image options into qemu-kvm option to mount them
# Drive index 0 is the hard disk. The ISO images are CDROM index 1, 2, 3, etc.

if [ -n "$ISO_IMAGES" -a \( "$CMD" != 'create' -a "$CMD" != 'run' \) ]; then
  echo "$PROG: usage error: --iso is only used with --create or --run" >&2
  exit 2
fi

INDEX=0
CDROM_OPTIONS=
for IMG in $ISO_IMAGES; do
  if [ ! -r "$IMG" ]; then
    echo "$PROG: error: cannot read ISO file: $IMG" >&2
    exit 1
  fi
  INDEX=$(($INDEX + 1))
  CDROM_OPTIONS="$CDROM_OPTIONS -drive file=$IMG,index=$INDEX,media=cdrom"
done

#----------------------------------------------------------------
# Check support for virtualization

run_vm () {
  MODE=$1

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
    echo "$PROG: unsupported disk interface type: $DISK_INTERFACE (expecting: 'virtio' or 'ide')" >&2
    exit 1
  fi

  QEMU_OPTIONS="-m $RAM_SIZE -smp $NUM_CPUS -net nic,model=virtio -net user -usbdevice tablet"

  # Additional mode-based options

  if [ "$MODE" = 'create' ]; then
    # First boot off ISO and subsequently boot off the disk drive
    BOOT_ORDER_OPTIONS="-boot order=cd,once=d"

  elif [ "$MODE" = 'run' ]; then
    # Boot off the disk drive
    BOOT_ORDER_OPTIONS="-boot order=c"

  else
    echo "$PROG: internal error: unknown mode: $MODE" >&2
    exit 1
  fi

  # Run QEMU

  COMMAND="$QEMU_EXEC $QEMU_OPTIONS \
    -drive file=$IMAGE,if=$DISK_INTERFACE,index=0 \
    $CDROM_OPTIONS \
    $BOOT_ORDER_OPTIONS \
    $EXTRA_QEMU_OPTIONS \
    -vnc 127.0.0.1:$VNC_DISPLAY"

  if [ -n "$DEBUG" ]; then
    echo "$PROG: running: $COMMAND"
  fi

  # -monitor stdio

  # Run QEMU in background (nohup so user can log out without stopping it)

  BASE=$(basename "$IMAGE" .raw)
  BASE=$(basename "$BASE" .qcow2)
  BASE=$(basename "$BASE" .img)
  LOGFILE="$(dirname "$IMAGE")/${BASE}.log"

  nohup $COMMAND >> $LOGFILE 2>&1 &
  QEMU_PID=$!

  # Detect early termination errors
  sleep 2
  if ! ps $QEMU_PID > /dev/null; then
    # QEMU process no longer running
    echo "$PROG: QEMU error (see log file: $LOGFILE)" 2>&1
    exit 1
  fi
  echo "$PROG: $(date "+%F %T%:z"): QEMU PID: $QEMU_PID" >> $LOGFILE

  if [ -n "$VERBOSE" ]; then
    PORT=$((5900 + $VNC_DISPLAY))
    echo "Guest system on VNC display $VNC_DISPLAY = port $PORT (no password required)"
    echo "  When finished, shutdown guest or enter 'quit' in QEMU console (Ctrl-Alt-2)"
  fi

  if [ -n "$DEBUG" ]; then
    echo "PID: $QEMU_PID"
  fi
}

#----------------------------------------------------------------

if [ "$CMD" = 'create' ]; then
  # Create

  # Check create parameters

  if [ "$DISK_FORMAT" != 'raw' -a "$DISK_FORMAT" != 'qcow2' ]; then
    echo "$PROG: unknown format (expecting 'raw' or 'qcow2'): $DISK_FORMAT" >&2
    exit 1
  fi

  if [ -z "$CDROM_OPTIONS" ]; then
    echo "$PROG: usage error: --create requires at least one --iso image" >&2
    exit 1
  fi

  # Check for executable

  if ! which qemu-img >/dev/null 2>&1; then
    echo "$PROG: error: program not found: qemu-img" >&2
  fi

  # Create disk image

  QEMU_IMG_OUTPUT=`qemu-img create -f $DISK_FORMAT "$IMAGE" $DISK_SIZE`
  if [ $? -ne 0 ]; then
    echo "$QEMU_IMG_OUTPUT"
    echo "$PROG: qemu-image could not create disk image: $IMAGE"
    exit 1
  fi

  if [ -n "$VERBOSE" ]; then
    echo "Creating disk image: $QEMU_IMG_OUTPUT"
  fi

  # Run virtualization

  run_vm $CMD


elif [ "$CMD" = 'run' ]; then
  #----------------------------------------------------------------
  # Run

  run_vm $CMD

elif [ "$CMD" = 'mount' ]; then
  #----------------------------------------------------------------
  # Mount

  # Note: alternatively run "kpartx -av diskImage" and mount manually

  if [ `id -u` -ne 0 ]; then
    echo "$PROG: error: must be run with root privileges for --mount" >&2
    exit 1
  fi

  if [ -z "$MOUNT_POUNT" ]; then
    MOUNT_POINT="$DEFAULT_MOUNT_POINT"
  fi

  qemu-img info "$IMAGE" | grep 'file format: raw' >/dev/null
  if [ $? -ne 0 ]; then
    echo "$PROG: mount can only be used with raw format disk images" >&2
    exit 1
  fi

  if [ -e "$MOUNT_POINT" ]; then
    # Mount point already exists: check if it is a directory

    if [ ! -d "$MOUNT_POINT" ]; then
      echo "$PROG: error: mount point is not a directory: $MOUNT_POINT" >&2
      exit 1
    fi
  else
    # Mount point does not exist
    if [ -n "$VERBOSE" ]; then
      echo "$PROG: error: mount point does not exist: $MOUNT_POINT" >&2
      exit 1
    fi
  fi

  # Associate loopback device with disk image to determine offset of partition

  D_DEVICE=`losetup -f "$IMAGE" --show`
  if [ $? -ne 0 ]; then
    echo "$PROG: error: loopback mounting of disk failed" >&2
    exit 1
  fi

  # fdisk:
  #   -l = list partitions for device
  #   -u = results in 512 byte sectors

  NUM_PARTITIONS=$(fdisk -l -u $D_DEVICE | grep -c ^/dev/)
  if [ $NUM_PARTITIONS -eq 0 ]; then
    fdisk -l -u $D_DEVICE # display partitions to user
    sleep 1 # else disconnect fails because device is busy
    losetup -d "$D_DEVICE"
    echo "$PROG: no partitions on disk: $IMAGE" >&2
    exit 1
  fi

  if [ $PARTITION -gt $NUM_PARTITIONS ]; then
    fdisk -l -u $D_DEVICE # display partitions to user
    sleep 1 # else disconnect fails because device is busy
    losetup -d "$D_DEVICE"
    echo "$PROG: no partition $PARTITION: $IMAGE only has $NUM_PARTITIONS partitions" >&2
    exit 1
  fi

  OFFSET=$(fdisk -l -u $D_DEVICE | grep ^/dev/ | awk "{ N++; if (N==$PARTITION){print \$3 * 512} }")
  if [ $? -ne 0  -o  -z "$OFFSET" ]; then
    fdisk -l -u $D_DEVICE # display partitions to user
    sleep 1 # else disconnect fails because device is busy
    losetup -d "$D_DEVICE"
    echo "$PROG: could not work out partititon offset" >&2
    exit 1
  fi

  sleep 1 # else disconnect fails because device is busy
  losetup -d "$D_DEVICE"  # disconnect loopback mounted disk
  if [ $? -ne 0 ]; then
    echo "$PROG: error: disconnect error: $D_DEVICE" >&2
    exit 1
  fi

#  # Associate loopback device with the partition
#
#  P_DEVICE=$(losetup -o $OFFSET -f "$IMAGE" --show)
#  if [ $? -ne 0 ]; then
#    echo "$PROG: error: loopback mounting of partition failed" >&2
#    exit 1
#  fi

  # Mount it

  mount -o "loop,offset=$OFFSET" "$IMAGE" "$MOUNT_POINT" || die
  # Edit /etc/fstab and rc.local

  if [ -n "$VERBOSE" ]; then
    echo "Partition $PARTITION of $IMAGE mounted on $MOUNT_POINT"
  fi

elif [ "$CMD" = 'unmount' ]; then
  #----------------------------------------------------------------
  # Unmount

  if [ `id -u` -ne 0 ]; then
    echo "$PROG: error: must be run with root privileges for --unmount" >&2
    exit 1
  fi

  if [ -z "$MOUNT_POINT" ]; then
    MOUNT_POINT="$DEFAULT_MOUNT_POINT"
  fi

  if [ ! -d "$MOUNT_POINT" ]; then
    echo "$PROG: error: mount point not found: $MOUNT_POINT" >&2
    exit 1
  fi

  umount "$MOUNT_POINT" || die

#elif [ "$CMD" = 'label' ]; then
#  #----------------------------------------------------------------
#  # Label
#
#  if [ $# -lt 1 ]; then
#    echo "$PROG: usage error: --label expects partitionImage and optional name" >&2
#    exit 2
#  elif [ $# -gt 2 ]; then
#    echo "$PROG: too many arguments (use -h for help)" >&2
#    exit 2
#  fi
#  PARTITION="$1"
#  VOLUME_LABEL="$2"
#  if [ ! -f "$PARTITION" ]; then
#    echo "$PROG: error: file not found: $PARTITION" >&2
#    exit 1
#  fi
#  if [ -z "$VOLUME_LABEL" ]; then
#    VOLUME_LABEL="$DEFAULT_VOLUME_LABEL"
#    exit 1
#  fi
#
#  # Change label of image to value in /etc/fstab
#
#  echo "Setting volume label to \"$VOLUME_LABEL\""
#  tune2fs -L "$VOLUME_LABEL" "$PARTITION" || die

elif [ "$CMD" = "upload" ]; then
  #----------------------------------------------------------------
  # Upload

  if [ -z "$IMAGE_NAME" ]; then
    IMAGE_NAME="$DEFAULT_IMAGE_NAME_PREFIX $(date "+%F %H:%M%:z")"
  fi

  # Check for glance program

  if ! which glance >/dev/null 2>&1; then
    echo "$PROG: error: program not found: glance" >&2
    exit 1
  fi

  # Check RC environment variables have been set

  if [ -z "$OS_AUTH_URL" -o -z "$OS_TENANT_ID" -o -z "$OS_TENANT_NAME" -o \
       -z "$OS_USERNAME" -o -z "$OS_PASSWORD" ]; then
    echo "$PROG: error: environment variables not set, source OpenStack RC file" >&2
    exit 1
  fi

  # Detect disk image format

  UPLOAD_DISK_FORMAT=$( qemu-img info "$IMAGE" | awk -F ': ' "/file format/ { print \$2 }" )
  if [ -z "$UPLOAD_DISK_FORMAT" ]; then
    echo "$PROG: error: could not detect image format: $IMAGE" >&2
    exit 1
  fi

  echo "$IMAGE" | grep '\.iso$' > /dev/null
  if [ $? -eq 0  -a  "$UPLOAD_DISK_FORMAT" = 'raw' ]; then
    # Filename suggests it is an ISO image and qemu-img claims is raw, since
    # qemu-img cannot tell the difference between ISO and raw: upload as ISO
    # since Glance does care about the difference.
    UPLOAD_DISK_FORMAT=iso
  fi

  # Upload
  
  if [ -n "$VERBOSE" ]; then
    echo "Uploading \"$IMAGE\" to \"$OS_TENANT_NAME\" as \"$IMAGE_NAME\""
    echo "Upload started: $(date "+%F %T%:z")"
  fi

  GLANCE_PROPERTIES=
  if [ -n "$OS_TYPE" ]; then
    GLANCE_PROPERTIES="--property os_type=windows"
  fi

  glance \
          --insecure \
          image-create \
          --name "$IMAGE_NAME" \
          --container-format bare --disk-format $UPLOAD_DISK_FORMAT \
          --is-public false \
          --min-disk 10 \
          --min-ram 1024 \
          $GLANCE_PROPERTIES \
          --owner "$OS_TENANT_ID" \
          --file "$IMAGE" || die

  if [ -n "$VERBOSE" ]; then
    echo "Upload finished: $(date "+%F %T%:z")"
  fi

else
  #----------------------------------------------------------------
  # Error
  echo "$PROG: error: unknown command: $CMD" >&2
  exit 3
fi

exit 0

#EOF
