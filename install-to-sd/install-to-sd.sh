#!/bin/bash

# Author: Saleem Edah-Tally [Surgeon] [Hobbyist developer]
# License: CeCILL
# For comments: https://archlinuxarm.org/forum/viewtopic.php?f=67&t=17166

LSHW_SYSTEM="Hardkernel ODROID-M2"
OS_RELEASE=/etc/os-release
WORK_DIR=/tmp/A7
TARGET_DEVICE=/dev/mmcblk1
EMMC=/dev/mmcblk0
BLOB_SPL=spl.bin
BLOB_UBOOT=uboot.bin
TARGET_ROOT_MOUNTPOINT=${WORK_DIR}/SD_ROOT
AARCH64_TARBALL=ArchLinuxARM-aarch64-latest.tar.gz
AARCH64_TARBALL_URL="http://os.archlinuxarm.org/os/ArchLinuxARM-aarch64-latest.tar.gz"
FILESYSTEM_NAME_BOOT="SDBOOT"
FILESYSTEM_NAME_ROOT="SDROOT"
CHROOT_SCRIPT=setup-boot.sh
BASE_DIR=$(dirname $(realpath $0))
OS_ID="ubuntu"
CHROOT_COMMAND="chroot"
DEFAULT_HUNG_TASK_TIMEOUT=120
# In chroot
BOOT_TXT=boot.txt
BOOT_SCR=boot.scr
DTS_FILE=rk3588s-odroid-m2.dts
DTB_FILE=rk3588s-odroid-m2.dtb
DTB_DIR_PATH=dtbs/rockchip
PATCHED_DTS_PATH=resources/dts
PATCHED_DTS_FILE=rk3588s-odroid-m2.dts.patched
USE_PATCHED_DTS=1

# ---------------- Check we are root -----------------------------------------------
check_user()
{
  if [ $(id -u) -ne 0 ] || [ "$USER" != "root" ];then
    echo "# --------------- Current shell is not owned by root."
    exit 100
  fi
  return 0
}

# ---------------- Check for M2 -----------------------------------------------
check_system()
{
  SYSTEM=$(lshw -class system |grep "${LSHW_SYSTEM}" |cut -d ":" -f 2)
  if [ "${SYSTEM}" != " ${LSHW_SYSTEM}" ];then
    echo "# --------------- System is not \'${LSHW_SYSTEM}\'."
    exit 110
  fi
  echo "# --------------- System: ${LSHW_SYSTEM}"
  return 0
}

# ---------------- Check current OS -------------------------------------------
check_os()
{
  [ ! -f ${OS_RELEASE} ] && echo "# --------------- ${OS_RELEASE} missing." && exit 111
  OS_ID=$(grep "^ID=" ${OS_RELEASE} |cut -d "=" -f2)
  if [ "${OD_ID}" = "ubuntu" ];then
    CHROOT_COMMAND="chroot"
  elif [ "${OS_ID}" = "archarm" ];then
    CHROOT_COMMAND="arch-chroot"
  else
    echo "${OS_ID} is not handled."
    exit 112
  fi
  echo "# --------------- OS: ${OS_ID}"
  DEFAULT_HUNG_TASK_TIMEOUT=$(cat /proc/sys/kernel/hung_task_timeout_secs)
  echo 600 > /proc/sys/kernel/hung_task_timeout_secs
  return 0
}

# ---------------- Check for SD card ------------------------------------------
check_sd()
{
  test -b ${TARGET_DEVICE} &> /dev/null
  RET=$?
  if [ $RET -ne 0 ]; then
    echo "# --------------- SD card not detected."
    exit 113
  fi
  echo "# --------------- Target block device: ${TARGET_DEVICE}"
  return 0
}

# ---------------- Dump blobs -------------------------------------------------
dump_blobs()
{
  # https://wiki.odroid.com/odroid-m2/board_support/board_support
  echo "# --------------- Dumping boot blobs from EMMC."
  dd if=$EMMC of=$BLOB_SPL skip=64 count=$((1077-64+1))
  RET=$?
  if [ $RET -ne 0 ]; then
    echo "# --------------- Error dumping SPL blob."
    exit 114
  fi
  dd if=$EMMC of=$BLOB_UBOOT skip=2048 count=$((6143-2048+1))
  RET=$?
  if [ $RET -ne 0 ]; then
    echo "# --------------- Error dumping UBOOT blob."
    exit 115
  fi
  return 0
}

# ---------------- Create partitions ------------------------------------------
create_partitions()
{
  export PATH=/sbin:$PATH # parted is there in Ubuntu.
  echo "# --------------- Blanking FAT of target SD card partitions."
  dd if=/dev/zero of=${TARGET_DEVICE} bs=4M count=1 conv=fsync
  echo "# --------------- Creating MBR partitions." # 512 MiB for boot partition.
  parted /dev/mmcblk1 mklabel msdos
  RET=$?
  parted /dev/mmcblk1 mkpart primary ext4 6144s 1054719s
  [ $RET -eq 0 ] && RET=$?
  parted /dev/mmcblk1 mkpart primary ext4 1054720s 100%
  RET=$?
  if [ $RET -ne 0 ]; then
    echo "# --------------- Error creating partitions on SD."
    exit 116
  fi
  return 0
}

# ---------------- Flash blobs to SD ------------------------------------------
flash_blobs()
{
  echo "# --------------- Copying SPL to target device."
  dd if=${BLOB_SPL} of=${TARGET_DEVICE} conv=fsync seek=64
  RET=$?
  if [ $RET -ne 0 ]; then
    echo "# --------------- Error flashing SPL blob."
    exit 117
  fi
  
  echo "# --------------- Copying UBOOT to target device."
  dd if=${BLOB_UBOOT} of=${TARGET_DEVICE} conv=fsync seek=2048
  RET=$?
  if [ $RET -ne 0 ]; then
    echo "# --------------- Error flashing UBOOT blob."
    exit 118
  fi
}

# ---------------- Create filesystems -----------------------------------------
create_filesystems()
{
  echo "# --------------- Creating EXT4 file systems."
  mkfs.ext4 -L "${FILESYSTEM_NAME_BOOT}" ${TARGET_DEVICE}p1
  RET=$?
  if [ $RET -ne 0 ]; then
    echo "# --------------- Error creating EXT4 file system on ${TARGET_DEVICE}p1."
    exit 119
  fi
  
  mkfs.ext4 -L "${FILESYSTEM_NAME_ROOT}" ${TARGET_DEVICE}p2
  RET=$?
  if [ $RET -ne 0 ]; then
    echo "# --------------- Error creating EXT4 file system on ${TARGET_DEVICE}p2."
    exit 120
  fi
}

# ---------------- Install Arch -----------------------------------------------
install_arch()
{
  if [ ! -f ${AARCH64_TARBALL} ];then
    wget "${AARCH64_TARBALL_URL}"
    if [ $? -ne 0 ];then
        echo "# --------------- Error fetching Arch tarball at ${AARCH64_TARBALL_URL}."
        exit 130
    fi
  fi
  tarballFullPath=$(realpath ${AARCH64_TARBALL})
  mkdir -p ${TARGET_ROOT_MOUNTPOINT}
  mount LABEL="${FILESYSTEM_NAME_ROOT}" ${TARGET_ROOT_MOUNTPOINT}
  RET=$?
  if [ $RET -ne 0 ];then
    echo "# --------------- Error mounting target root partition."
    exit 131
  fi
  cd ${TARGET_ROOT_MOUNTPOINT}
  echo "# --------------- Unpacking ${AARCH64_TARBALL} on ${TARGET_ROOT_MOUNTPOINT}."
  nice -n 19 tar -xzf ${tarballFullPath}
  RET=$?
  if [ $RET -ne 0 ];then
    cd - &> /dev/null
    echo "# --------------- Error unpacking ${AARCH64_TARBALL} on ${TARGET_ROOT_MOUNTPOINT}."
    exit 132
  fi
  cp ${BASE_DIR}/${BOOT_TXT} ${TARGET_ROOT_MOUNTPOINT}/root/
  cp ${BASE_DIR}/../${PATCHED_DTS_PATH}/${PATCHED_DTS_FILE} ${TARGET_ROOT_MOUNTPOINT}/root/
  cd - &> /dev/null
  echo "# --------------- Syncing, please wait..."
  nice -n 19 sync
}

# ---------------- Prepare and install target ---------------------------------
setup_and_install_sd()
{
  read -p "Creating partitions on the SD card, this operation is destructive. Continue? (y/n): " reply
  if [ "${reply}" != "y" ];then
    echo "# --------------- Aborting on request."
    exit 140
  fi
  
  read -p "A patched device tree file allows to enable network on the board's ethernet port. Please read the included README.md file in the resources/dts directory. Do you want to use the patched device tree? (y/n): " dtsReply
  [ "${dtsReply}" != "y" ] && ${USE_PATCHED_DTS}=0

  create_partitions
  flash_blobs
  create_filesystems
  install_arch
}

# ---------------- Write chroot script ---------------------------------
setup_boot_in_chroot()
{
# We are still in host OS.
  cd ${TARGET_ROOT_MOUNTPOINT}/root
  cat > ${CHROOT_SCRIPT} <<EOF
#!/bin/bash

mount LABEL=${FILESYSTEM_NAME_BOOT} /boot
if [ $? -ne 0 ];then
  echo "# --------------- Error mounting boot partition in chroot."
  exit 150
fi
mv /root/${BOOT_TXT} /boot/
cd /boot

echo "# --------------- Updating ARCH in chroot"
pacman-key --init
nice -n 19 pacman-key --populate archlinuxarm
nice -n 19 pacman -Syu --noconfirm # +++
if [ $? -ne 0 ];then # Doesn't work if download fails.
  echo "# --------------- Error updating ARCH in chroot."
  exit 151
fi
echo "# --------------- Syncing, please wait..."
nice -n 19 sync

echo "# --------------- Installing uboot-tools, dtc in chroot."
pacman -S --noconfirm uboot-tools dtc
if [ $? -ne 0 ];then
  echo "# --------------- Error installing uboot-tools, dtc in chroot."
  exit 152
fi

echo "# --------------- Creating boot.scr"
mkimage -A arm64 -O linux -T script -C none -n "U-Boot boot script" -d ${BOOT_TXT} ${BOOT_SCR}
if [ $? -ne 0 ];then
  echo "# --------------- Error creating ${BOOT_SCR} in chroot."
  exit 153
fi

if [ ${USE_PATCHED_DTS} -ne 1 ];then
  ln -s ${DTB_DIR_PATH}/${DTB_FILE} .
else
  echo "# --------------- Patching ${DTB_FILE}."
  mv /root/${PATCHED_DTS_FILE} .
  dtc -q -I dts -O dtb -o ${DTB_FILE} ${PATCHED_DTS_FILE}
  if [ $? -ne 0 ];then
    echo "# --------------- Error compiling ${PATCHED_DTS_FILE} in chroot."
    exit 155
  fi
fi

cd
umount -l /boot
if [ $? -ne 0 ];then
  echo "# --------------- Error unmounting boot partition in chroot."
  exit 156
fi

exit 0

EOF

chmod +x ${CHROOT_SCRIPT}
cd - &> /dev/null

}

# ---------------- Cleanup ----------------------------------------------------
finish()
{
  echo ${DEFAULT_HUNG_TASK_TIMEOUT} > /proc/sys/kernel/hung_task_timeout_secs
  unlink ${TARGET_ROOT_MOUNTPOINT}/root/${CHROOT_SCRIPT}
  cd
  umount -l ${TARGET_ROOT_MOUNTPOINT}
  RET=$?
  if [ $RET -ne 0 ];then
    echo "# --------------- Error unmounting target root partition."
    exit 133
  fi
  # Do not 'rm -fR ${WORK_DIR}', persisting inner mounts would be wiped.
  echo "# --------------- Finished."
}

# *****************************************************************************
# ---------------- PROCESS ----------------------------------------------------
mkdir ${WORK_DIR} &> /dev/null
cd ${WORK_DIR}

check_user
check_system
check_os
check_sd

dump_blobs
setup_and_install_sd # Does many things.
setup_boot_in_chroot

${CHROOT_COMMAND} ${TARGET_ROOT_MOUNTPOINT} "/root/${CHROOT_SCRIPT}"

finish

exit 0
