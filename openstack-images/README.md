Creating OpenStack images
=========================

The _q-image-maker.sh_ script simplifies the process of creating and
uploading an image to OpenStack.

It invokes the QEMU commands to create the image file, and to run a
virtual machine instance with it, so the operating system can be
installed onto it. It also runs the OpenStack command to upload the
image.

While those steps can be performed directly using the QEMU and
OpenStack commands, this script invokes them with the options needed
for common tasks. Therefore, the user does not have to remember their
complicated options.

## Example

It can involve only two or three steps to create and upload an image.

```sh
./q-image-maker.sh create --iso os-install-disc.iso image.qcow2

./q-image-maker.sh run image.qcow2  # optional

./q-image-maker.sh upload --name "My new image" --min-disk 10  image.qcow2
```

It also involes the steps needed to install the operating system into
the image and to prepare it for use as an image.  Those are performed
over a VNC session, and are similar to installing the operating system
onto any physical or virtual machine.

## Documentation

- [README-init.md](README-init.md) common instructions for both Linux and Windows images.

- [README-linux.md](README-linux.md)

- [README-windows.md](README-windows.md)

- [q-image-maker](q-image-maker.md) manual page

