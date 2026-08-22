How the images are built:

Each image is built automatically in the
[anyvm-org/debian-builder](https://github.com/anyvm-org/debian-builder)
repo's GitHub Actions: it downloads the official Debian generic cloud
image, customizes it (serial console, ssh host keys, network config,
first-boot setup), boots it in QEMU, pre-installs the packages listed
in the conf, and exports the disk as a compressed qcow2 image. No
interactive installer is run.

Upstream media: the official Debian cloud images from
https://cloud.debian.org/images/cloud/.
