This file, [rk3588s-odroid-m2.dts.patched](rk3588s-odroid-m2.dts.patched), has been generated as such:

 - apply [this patch](https://github.com/tobetter/linux/commit/3b3b1bcbce41e5800daabd2277c682f56d80e8d4) to the Linux source tree at revision v6.13
 - apply [this patch](../patch/linux_aarch64_odroid_m2_usbc_dtb.diff) also
 - build the device trees (make dtbs)
 - decompile the resulting rk3588s-odroid-m2.dtb file.

It is proposed as an alternatve to upstream device tree
 - to enable network on the board's ethernet port,
 - to allow storage devices to be discovered on the USB-C port.

Using this file during installation is optional.
