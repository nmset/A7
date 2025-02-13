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

See the original [forum thread](https://archlinuxarm.org/forum/viewtopic.php?f=67&t=17166) leading to this project. Any comment should continue in this discussion.

### Notes

A [patched device tree](resources/dts/README.md) for this board is proposed to enable network connection on its ethernet port. This concerns kernel v6.13.

### Disclaimer

This project is provided as is with no guarantees. Use at your own risks.

