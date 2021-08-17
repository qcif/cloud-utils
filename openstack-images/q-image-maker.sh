#!/bin/sh
#
# Utility to help make virtual machine images for use with OpenStack.
#
# To create a disk image:
#
#     q-image-maker.sh create --iso install-disc.iso example.qcow2
#
# To upload an disk image to Openstack:
#
#     q-image-maker.sh upload example.qcow2
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
#
# Copyright (C) 2013-2021, Queensland Cyber Infrastructure Foundation Ltd.
#----------------------------------------------------------------

PROGRAM='q-image-maker'
VERSION='2.1.0'

EXE=$(basename "$0" .sh)
EXE_EXT=$(basename "$0")

#----------------------------------------------------------------
# Constants

#----------------
# Defaults for disk image creation

DEFAULT_DISK_SIZE_GIB=10

DEFAULT_CREATE_DISK_FORMAT=qcow2

#----------------
# Configuration of the QEMU virtual machine instance.

RAM_SIZE=4096
NUM_CPUS=2

# The host must have more RAM and CPU cores than the above!
# More RAM/CPU doesn't really change how long it takes to install the OS,
# but it can affect how fast it runs after being installed.

DEFAULT_DISK_INTERFACE=virtio

DEFAULT_VNC_DISPLAY=0

#----------------
# Defaults for the image to be uploaded into OpenStack glance.

# To make it easy to test multiple images, without having to think of new
# names, this script will generate names like "Test <diskImage> (<time>)",
# if a name is not provided.

DEFAULT_IMAGE_NAME_PREFIX='Test'

# Properties for the uploaded image

DEFAULT_INSTANCE_MIN_RAM_MIB=1024

#----------------------------------------------------------------
# Process command line

SHORT_OPTS=cd:Df:hi:ln:s:t:uVvwx:

LONG_OPTS=create,run,upload,format:,disk-type:,iso:,linux,size:,display:,extra-opts:,name:,min-disk:,min-ram:,help,linux,version,verbose,windows,debug

#----------------
# Detect if GNU Enhanced getopt is available

HAS_GNU_ENHANCED_GETOPT=
if getopt -T >/dev/null; then :
else
  if [ $? -eq 4 ]; then
    HAS_GNU_ENHANCED_GETOPT=yes
  fi
fi

# Run getopt (runs getopt first in `if` so `trap ERR` does not interfere)

if [ -n "$HAS_GNU_ENHANCED_GETOPT" ]; then
  # Use GNU enhanced getopt
  if ! getopt --name "$EXE" --long $LONG_OPTS --options $SHORT_OPTS -- "$@" >/dev/null; then
    echo "$EXE: usage error (use -h or --help for help)" >&2
    exit 2
  fi
  ARGS=$(getopt --name "$EXE" --long $LONG_OPTS --options $SHORT_OPTS -- "$@")
else
  # Use original getopt (no long option names, no whitespace, no sorting)
  if ! getopt $SHORT_OPTS "$@" >/dev/null; then
    echo "$EXE: usage error (use -h for help)" >&2
    exit 2
  fi
  ARGS=$(getopt $SHORT_OPTS "$@")
fi
eval set -- $ARGS

#----------------
# Process parsed options

CMD=
VNC_DISPLAY=$DEFAULT_VNC_DISPLAY
DISK_SIZE_GIB=$DEFAULT_DISK_SIZE_GIB
CREATE_DISK_FORMAT=$DEFAULT_CREATE_DISK_FORMAT
DISK_INTERFACE=$DEFAULT_DISK_INTERFACE
ISO_IMAGES=
OS_TYPE=
INSTANCE_MIN_RAM_MIB=$DEFAULT_INSTANCE_MIN_RAM_MIB
INSTANCE_MIN_DISK_GIB=
SHOW_VERSION=
SHOW_HELP=

EXTRA_QEMU_OPTIONS=

while [ $# -gt 0 ]; do
  case "$1" in
    -s | --size)     DISK_SIZE_GIB="$2"; shift;;
    -f | --format)   CREATE_DISK_FORMAT="$2"; shift;;
    -t | --disk-type) DISK_INTERFACE="$2"; shift;;
    -i | --iso)      ISO_IMAGES="$ISO_IMAGES $2"; shift;;
    -d | --display)  VNC_DISPLAY="$2"; shift;;
    -x | --extra-opts) EXTRA_QEMU_OPTIONS="$2"; shift;;

    -l | --linux)    OS_TYPE=linux;;
    -w | --windows)  OS_TYPE=windows;;
    
    -n | --name)     IMAGE_NAME="$2"; shift;;
         --min-ram)  INSTANCE_MIN_RAM_MIB="$2"; shift;;
         --min-disk) INSTANCE_MIN_DISK_GIB="$2"; shift;;

    -h | --help)     SHOW_HELP=yes;;
    -V | --version)  SHOW_VERSION=yes;;
    -v | --verbose)  VERBOSE=yes;;
    --)              shift; break;; # end of options
  esac
  shift
done

if [ -n "$SHOW_HELP" ]; then
  cat <<EOF
Usage: $EXE_EXT (create|run|upload) [options] diskImage

Options for create:
  -s | --size size       size of disk to create in GiB (default: $DEFAULT_DISK_SIZE_GIB GiB)
  -f | --format diskFmt  format of image: raw or qcow2 (default: $DEFAULT_CREATE_DISK_FORMAT)
                         Note: mount/unmount only works with the raw format
Options create and run:
  -i | --iso isoFile     attach as a CDROM (repeat for multiple ISO images)
  -t | --disk-type inter QEMU disk interface: virtio or ide (default: $DEFAULT_DISK_INTERFACE)
  -x | --extra-opts str  extra QEMU options, for advanced use
  -d | --display num     VNC server display (default: $DEFAULT_VNC_DISPLAY)

Options for upload:
  -n | --name imageName  name of glance image (default: "$DEFAULT_IMAGE_NAME_PREFIX <name> <time>")
  -l | --linux           set os_type property to linux
  -w | --windows         set os_type property to windows
       --min-ram size    minimum RAM size in MiB (default: $DEFAULT_INSTANCE_MIN_RAM_MIB)
       --min-disk size   minimum disk size in GiB (default: from image file)

Common options:
  -v | --verbose         output extra information when running
       --version         display version information and exit
  -h | --help            display this help and exit
EOF
  exit 0
fi

if [ -n "$SHOW_VERSION" ]; then
  echo "$PROGRAM $VERSION"
  exit 0
fi

#----------------
# Remaining arguments (for the command and diskImage)

if [ $# -eq 0 ]; then
  echo "$EXE: usage error: missing command and imageFile (-h for help)" >&2
  exit 2
elif [ $# -eq 1 ]; then
  CMD="$1"
  IMAGE=
elif [ $# -eq 2 ]; then
  CMD="$1"
  IMAGE="$2"
elif [ $# -gt 2 ]; then
  echo "$EXE: too many arguments (-h for help)" >&2
  exit 2
fi

#----------------
# Check the command is one of the known commands

if [ "$CMD" != 'create' ] && [ "$CMD" !=  'run' ] && [ "$CMD" != 'upload' ];
then
  echo "$EXE: error: unknown command: $CMD (expecting create, run, upload)" >&2
  exit 2
fi

#----------------
# Check disk image filename that was provided

if [ -z "$IMAGE" ]; then
  echo "$EXE: usage error: missing imageFile (-h for help)" >&2
  exit 2
fi

if [ "$CMD" = 'create' ]; then
  # Creating a disk image: it MUST NOT already exist

  if [ -e "$IMAGE" ]; then
    echo "$EXE: error: image file exists (use \"run\" instead?): $IMAGE" >&2
    exit 1
  fi
else
  # Using an existing disk image: file MUST already exist and can be read

  if [ ! -e "$IMAGE" ]; then
    echo "$EXE: error: file not found: $IMAGE" >&2
    exit 1
  fi
  if [ ! -f "$IMAGE" ]; then
    echo "$EXE: error: disk image is not a file: $IMAGE" >&2
    exit 1
  fi
  if [ ! -r "$IMAGE" ]; then
    echo "$EXE: error: cannot read disk image: $IMAGE" >&2
    exit 1
  fi
fi

#----------------
# Check disk size

if ! echo "$DISK_SIZE_GIB" | grep -E '^[0-9]+$' >/dev/null; then
  echo "$EXE: usage error: bad disk size (expecting a number): $DISK_SIZE_GIB" >&2
  exit 2
fi

#----------------
# Check disk format

if [ "$CREATE_DISK_FORMAT" != 'raw' ] && [ "$CREATE_DISK_FORMAT" != 'qcow2' ]; then
  echo "$EXE: usage error: unknown format ('raw' or 'qcow2'): $CREATE_DISK_FORMAT" >&2
  exit 2
fi

#----------------
# Check disk interface is one of the supported values

if [ "$DISK_INTERFACE" != 'virtio' ] && [ "$DISK_INTERFACE" != 'ide' ]; then
  echo "$EXE: usage error: unsupported disk interface type: $DISK_INTERFACE (expecting: \"virtio\" or \"ide\")" >&2
  exit 2
fi

#----------------
# Convert ISO image options into qemu-kvm option to mount them
# Drive index 0 is the hard disk. The ISO images are CDROM index 1, 2, 3, etc.

if [ -n "$ISO_IMAGES" ]; then
  if [ "$CMD" != 'create' ] && [ "$CMD" != 'run' ]; then
    echo "$EXE: usage error: --iso is only used with create or run" >&2
    exit 2
  fi
fi

INDEX=0
CDROM_OPTIONS=
for IMG in $ISO_IMAGES; do
  if [ ! -r "$IMG" ]; then
    echo "$EXE: error: cannot read ISO file: $IMG" >&2
    exit 1
  fi
  INDEX=$((INDEX + 1))
  CDROM_OPTIONS="$CDROM_OPTIONS -drive file=$IMG,index=$INDEX,media=cdrom"
done

#----------------
# Check VNC display number is a non-negative integer

if ! echo "$VNC_DISPLAY" | grep -E '^[0-9]+$' >/dev/null ; then
  echo "$EXE: usage error: VNC display is not a +ve integer: $VNC_DISPLAY" >&2
  exit 2
fi

#----------------
# Check minimum RAM size

if ! echo "$INSTANCE_MIN_RAM_MIB" | grep -E '^[0-9]+$' >/dev/null; then
  echo "$EXE: usage error: minimum RAM size: bad number: $INSTANCE_MIN_RAM_MIB" >&2
  exit 2
fi
if [ "$INSTANCE_MIN_RAM_MIB" -lt 64 ]; then
  echo "$EXE: usage error: minimum RAM size: too small: $INSTANCE_MIN_RAM_MIB (minimum allowed: 128 MiB)" >&2
  exit 2
fi

#----------------
# Check minimum disk size

if [ -n "$INSTANCE_MIN_DISK_GIB" ]; then
  if ! echo "$INSTANCE_MIN_DISK_GIB" | grep -E '^[0-9]+$' >/dev/null; then
    echo "$EXE: usage error: minimum disk size: bad number: $INSTANCE_MIN_DISK_GIB" >&2
    exit 2
  fi
  if [ "$INSTANCE_MIN_DISK_GIB" -lt 4 ]; then
    echo "$EXE: usage error: minimum disk size: too small: $INSTANCE_MIN_DISK_GIB (minimum allowed: 4 GiB)" >&2
    exit 2
  fi
fi

#----------------

if [ "$CMD" = 'upload' ]; then
  # Uploading

  # Make sure either --linux or --windows is specified

  if [ -z "$OS_TYPE" ]; then
    echo "$EXE: usage error: --linux or --windows is required to upload">&2
    exit 2
  fi
fi
#----------------------------------------------------------------
# Run the image in a virtual machine

run_vm () {
  # invoke with "--boot-iso" or "--boot-disk"
  MODE=$1

  # Determine virtualization executable

  QEMU_EXEC_1=/usr/libexec/qemu-kvm  # CentOS (not in PATH)
  QEMU_EXEC_2=qemu-system-x86_64  # Ubuntu

  if which $QEMU_EXEC_1 >/dev/null 2>&1; then
    QEMU_EXEC="$QEMU_EXEC_1"

  elif which $QEMU_EXEC_2 >/dev/null 2>&1; then
    QEMU_EXEC="$QEMU_EXEC_2"

  else
    echo "$EXE: error: program not found: $QEMU_EXEC_1 or $QEMU_EXEC_2" >&2
    echo "$EXE: error: check if the \"qemu-kvm\" package is installed" >&2
    exit 3
  fi

  # Check if virtualization extensions are available

  NO_VERT='virtual machine will be slow: no virtualization, using emulation'

  if ! grep -E '(vmx|svm)' /proc/cpuinfo >/dev/null 2>&1; then
    # No Intel VT-x or AMD AMD-V extensions
    echo "$EXE: warning: $NO_VERT: CPU has no virtualization extension support" >&2
  elif [ ! -c '/dev/kvm' ]; then
    # No /dev/kvm
    echo "$EXE: warning: $NO_VERT: /dev/kvm not installed and/or supported by kernel" >&2
  else
    # Has virtualization support
    :
  fi

  # Set disk type options

  QEMU_OPTIONS="-m $RAM_SIZE -smp $NUM_CPUS -net nic,model=virtio -net user -usb -device usb-tablet"

  # Additional mode-based options

  if [ "$MODE" = '--boot-iso' ]; then
    # First boot off ISO and subsequently boot off the disk drive
    BOOT_ORDER_OPTIONS="-boot order=cd,once=d"

  elif [ "$MODE" = '--boot-disk' ]; then
    # Boot off the disk drive
    BOOT_ORDER_OPTIONS="-boot order=c"

  else
    echo "$EXE: internal error: unknown mode: $MODE" >&2
    exit 3
  fi

  # Run QEMU

  COMMAND="$QEMU_EXEC $QEMU_OPTIONS \
    -drive file=$IMAGE,if=$DISK_INTERFACE,index=0 \
    $CDROM_OPTIONS \
    $BOOT_ORDER_OPTIONS \
    $EXTRA_QEMU_OPTIONS \
    -vnc 127.0.0.1:$VNC_DISPLAY"

  # -monitor stdio

  # Run QEMU in background (nohup so user can log out without stopping it)

  if echo "$IMAGE" | grep '\.qcow2$' >/dev/null; then
    BASE=$(basename "$IMAGE" .qcow2)
  elif echo "$IMAGE" | grep '\.raw$' >/dev/null; then
    BASE=$(basename "$IMAGE" .raw)
  elif echo "$IMAGE" | grep '\.img$' >/dev/null; then
    BASE=$(basename "$IMAGE" .img)
  else
    BASE=$(basename "$BASE")
  fi
  LOGFILE="$(dirname "$IMAGE")/${BASE}.log"

  cat > "$LOGFILE" <<EOF
# $PROGRAM [ $(date "+%F %T %z") ]

$COMMAND

EOF

  nohup $COMMAND >> "$LOGFILE" 2>&1 &
  QEMU_PID=$!

  # Detect early termination errors
  sleep 3
  if ! ps $QEMU_PID > /dev/null; then
    # QEMU process no longer running
    cat "$LOGFILE"
    rm "$LOGFILE"
    echo "$EXE: error: QEMU failed" 2>&1
    exit 1
  fi
  echo "# PID: $QEMU_PID" >> "$LOGFILE"

  # Output instructions

  PORT=$((5900 + VNC_DISPLAY))

  cat <<EOF

Guest VM is running. Connect to it using VNC (via an SSH tunnel if necessary):
  VNC display: $VNC_DISPLAY (port $PORT)
  Authentication: VNC password not used (not VNC password with an empty string)

When finished using the guest, terminate the VM by either:
  a. shutdown the guest; or
  b. enter "quit" in the QEMU console (Ctrl-Alt-2 in the VNC client).

EOF
}

#----------------------------------------------------------------
# The create command

do_create() {
  # Create

  # Check create parameters

  if [ -z "$CDROM_OPTIONS" ]; then
    echo "$EXE: usage error: create requires at least one --iso file" >&2
    exit 1
  fi

  # Check for executable

  if ! which qemu-img >/dev/null 2>&1; then
    echo "$EXE: error: program not found: qemu-img" >&2
  fi

  # Create disk image
  # e.g. qemu-img create -f qcow2 example.qcow2 10G

  LOG=/tmp/$PROGRAM.$$ # to suppress output unless it needs to be seen

  if ! qemu-img create -f "$CREATE_DISK_FORMAT" \
       "$IMAGE" "${DISK_SIZE_GIB}G" >$LOG 2>&1; then
    cat $LOG
    rm $LOG
    echo "$EXE: error: qemu-image could not create disk image: $IMAGE"
    exit 1
  fi

  if [ -n "$VERBOSE" ]; then
    echo "$EXE: creating disk image:"
    cat $LOG
  fi
  rm $LOG

  # Run virtualization, booting from the ISO image

  run_vm --boot-iso
}

#----------------------------------------------------------------
# The run command

do_run() {
  # Run virtualization, booting from the virtual hard disk

  run_vm --boot-disk
}

#----------------------------------------------------------------
# The upload command

do_upload() {

  if echo "$IMAGE" | grep '\.qcow2$' >/dev/null; then
    BASE=$(basename "$IMAGE" .qcow2)
  elif echo "$IMAGE" | grep '\.raw$' >/dev/null; then
    BASE=$(basename "$IMAGE" .raw)
  elif echo "$IMAGE" | grep '\.img$' >/dev/null; then
    BASE=$(basename "$IMAGE" .img)
  else
    BASE=$(basename "$IMAGE")
  fi

  if [ -z "$IMAGE_NAME" ]; then
    IMAGE_NAME="$DEFAULT_IMAGE_NAME_PREFIX $BASE ($(date "+%F %H:%M %z"))"
  fi

  # Check for the needed programs

  if ! which openstack >/dev/null 2>&1; then
    echo "$EXE: error: program not found: openstack" >&2
    exit 1
  fi
  if ! which qemu-img >/dev/null 2>&1; then
    echo "$EXE: error: program not found: qemu-img" >&2
  fi

  # Check RC environment variables have been set

  if [ -z "$OS_AUTH_URL" ] \
       || [ -z "$OS_PROJECT_ID" ] \
       || [ -z "$OS_PROJECT_NAME" ] \
       || [ -z "$OS_USERNAME" ] \
       || [ -z "$OS_PASSWORD" ]; then
    echo "$EXE: error: environment not set, source an OpenStack RC file" >&2
    exit 1
  fi

  # Detect disk image format

  if echo "$IMAGE" | grep -i '\.gz$' > /dev/null; then
    echo "$EXE: error: please un-gzip the file first: $IMAGE" >&2
    exti 1
  fi
  if echo "$IMAGE" | grep -i '\.zip$' > /dev/null; then
    echo "$EXE: error: please un-zip the file first: $IMAGE" >&2
    exti 1
  fi

  UPLOAD_DISK_FORMAT=$( qemu-img info "$IMAGE" \
                          | awk -F ': ' "/file format/ { print \$2 }" )
  if [ -z "$UPLOAD_DISK_FORMAT" ]; then
    echo "$EXE: error: could not detect image format: $IMAGE" >&2
    exit 1
  fi

  if echo "$IMAGE" | grep '\.iso$' > /dev/null; then
    if [ "$UPLOAD_DISK_FORMAT" = 'raw' ]; then
      # Filename suggests it is an ISO image and qemu-img claims is raw, since
      # qemu-img cannot tell the difference between ISO and raw: upload as ISO
      # since Glance does care about the difference.
      UPLOAD_DISK_FORMAT=iso
    fi
  fi

  # Detect minimum disk size needed to use the image

  MIN_GIB_NEEDED=$( qemu-img info "$IMAGE" \
                      | grep 'virtual size' \
                      | sed -E 's/virtual size: ([0-9]+)G .*/\1/' )
  if [ -z "$MIN_GIB_NEEDED" ]; then
    echo "$EXE: error: could not detect minimum disk size: $IMAGE" >&2
    exit 1
  fi

  # Check or calculate the minimum disk size property

  if [ -z "$INSTANCE_MIN_DISK_GIB" ]; then
    # No value provided: use size indicated by the image file
    INSTANCE_MIN_DISK_GIB=$MIN_GIB_NEEDED
  else
    # Value provided: check it is not smaller than the size indicated by the image file
    if [  "$INSTANCE_MIN_DISK_GIB" -lt "$MIN_GIB_NEEDED" ]; then
      echo "$EXE: error: minimum disk size too small: $INSTANCE_MIN_DISK_GIB GiB (need at least ${MIN_GIB_NEEDED} GiB)" >&2
      exit 1
    fi
  fi

  # Upload

  cat <<EOF
Uploading "$IMAGE"
  Image name: $IMAGE_NAME
  Project: $OS_PROJECT_NAME
  Minimum disk size: $INSTANCE_MIN_DISK_GIB GiB
  Minimum RAM size: $INSTANCE_MIN_RAM_MIB MiB
  os_type: $OS_TYPE
EOF

  #MD5_PROPERTY=
  #if which md5sum >/dev/null 2>&1; then
  #  MD5=$(md5sum "$IMAGE"  | sed 's/ .*//')
  #  MD5_PROPERTY="--property owner_specified.openstack.md5=$MD5"
  #  echo "  MD5: $MD5"
  #fi
  #SHA256_PROPERTY=
  #if which sha256sum >/dev/null 2>&1; then
  #  SHA256=$(sha256sum "$IMAGE"  | sed 's/ .*//')
  #  SHA256_PROPERTY="--property owner_specified.openstack.sha256=$SHA256"
  #  echo "  SHA-256: $SHA256"
  #fi

  START=$(date '+%s') # seconds past epoch

  if ! openstack image create \
       --container-format 'bare' \
       --disk-format $UPLOAD_DISK_FORMAT \
       --file "$IMAGE" \
       --progress \
       --private \
       --min-disk "$INSTANCE_MIN_DISK_GIB" \
       --min-ram "$INSTANCE_MIN_RAM_MIB" \
       --project "$OS_PROJECT_ID" \
       --property os_type=$OS_TYPE \
       "$IMAGE_NAME" ; then
    echo "$EXE: openstack image create failed" >&2
    exit 1
  fi

  # --insecure # ignore TLS server certificate

  # Output how long it took

  NOW=$(date '+%s') # seconds past epoch

  SEC=$((NOW - START))

  if [ $SEC -lt 60 ]; then
    echo "Done. Uploaded in ${SEC}s"
  else
    echo "Done. Uploaded in $((SEC / 60))m $((SEC % 60))s"
  fi
}

#----------------------------------------------------------------
# Main

case "$CMD" in
  create)
    do_create
    ;;
  run)
    do_run
    ;;
  upload)
    do_upload
    ;;
  *)
    echo "$EXE: internal error: unknown command: $CMD" >&2
    exit 3
esac

exit 0 # success

#EOF
