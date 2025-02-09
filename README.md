## A7

This project attemps to install [Arch Linux ARM](https://archlinuxarm.org/) on the [Odroid M2](https://wiki.odroid.com/odroid-m2/odroid-m2) device.

### Installing on an SD card

 - start on the factory OS on the EMMC
 - clone this repository
 - become root: sudo su
 - install these programs if necessary: lshw, parted
 - cd A7/install-to-sd
 - ./install-to-sd.sh

Use a *fast* SD card at least 8 GB in size. The partitions and content on the card will be **lost**. A boot partition and a root partition where Arch is deployed will be created. The SD card is made bootable. Upon success, a reboot should be operating on the SD card.

### Installing on the EMMC

 - boot on an SD card
 - clone this repository
 - become root if necessary: su
 - install these packages if necessary: lshw, wget, util-linux, sed, arch-install-scripts
 - cd A7/install-to-emmc
 - ./install-to-emmc.sh [target_root_partition]

If *target_root_partition* is not provided, it defaults to */dev/mmcblk0p2* on the EMMC. The content of the EMMC's boot partition and that of the target root partition will be **lost**.

Ensure that a good network bandwidth is being used. If packages can't be downloaded during the process, it may not be possible to reboot on the EMMC. The factory OS can be installed again on the EMMC using [instructions](https://wiki.odroid.com/odroid-m2/getting_started/getting_started) of the OEM's wiki.

### Notes

See the original [forum thread](https://archlinuxarm.org/forum/viewtopic.php?f=67&t=17166) leading to this project. Any comment should continue in this discussion.

A [patched device tree](resources/dts/README.md) source for this board is proposed to enable network connection on its ethernet port. This concerns kernel v6.13.

### Disclaimer

This project is provided as is with no guarantees. Use at your own risks.

