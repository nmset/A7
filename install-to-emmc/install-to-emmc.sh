#!/bin/bash

# Author: Saleem Edah-Tally [Surgeon] [Hobbyist developer]
# License: CeCILL
# For comments: https://archlinuxarm.org/forum/viewtopic.php?f=67&t=17166

LSHW_SYSTEM="Hardkernel ODROID-M2"
OS_RELEASE=/etc/os-release
WORK_DIR=/tmp/A7
TARGET_BOOT_PART=/dev/mmcblk0p1
TARGET_ROOT_PART=/dev/mmcblk0p2
TARGET_ROOT_MOUNTPOINT=${WORK_DIR}/A7_ROOT
AARCH64_TARBALL=ArchLinuxARM-aarch64-latest.tar.gz
AARCH64_TARBALL_URL="http://os.archlinuxarm.org/os/ArchLinuxARM-aarch64-latest.tar.gz"
CHROOT_SCRIPT=setup-boot.sh
BASE_DIR=$(dirname $(realpath $0))
OS_ID="arch"
CHROOT_COMMAND="arch-chroot"
DEFAULT_HUNG_TASK_TIMEOUT=120
BOOT_TXT_ROOT_PARTITION_PLACE_HOLDER="_ROOT_PARTITION_"
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
  if [ "${OS_ID}" != "archarm" ];then
    echo "${OS_ID} is not handled."
    exit 112
  fi
  echo "# --------------- OS: ${OS_ID}"
  DEFAULT_HUNG_TASK_TIMEOUT=$(cat /proc/sys/kernel/hung_task_timeout_secs)
  echo 600 > /proc/sys/kernel/hung_task_timeout_secs
  return 0
}

# ---------------- Check current root -----------------------------------------
check_current_root()
{
  CURRENT_ROOT=$(findmnt -n -o "SOURCE" /)
  RET=$?
  if [ "${CURRENT_ROOT}" = "${TARGET_ROOT_PART}" ]; then
    echo "# --------------- Current root partition is the target EMMC."
    exit 113
  fi
  echo "# --------------- Current root: ${CURRENT_ROOT}"
  return 0
}

# ---------------- Handle target root partition -------------------------------
# It needs not be on the EMMC.
check_and_set_target_root_partition()
{
  [ $# -lt 1 ] && return 0 # No arg.
  FIRST="$1"
  test -b "$FIRST" &> /dev/null
  RET=$?
  if [ $RET -ne 0 ];then
    echo "# --------------- ${FIRST} is not a block device."
    exit 133
  fi
  if [ "${FIRST}" = "${TARGET_BOOT_PART}" ];then
    echo "# --------------- ${FIRST} must not be the target boot partition."
    exit 134
  fi
  TARGET_ROOT_PART="${FIRST}"
}

# ---------------- Install Arch -----------------------------------------------
install_arch()
{
  cd ${WORK_DIR}
  if [ ! -f ${AARCH64_TARBALL} ];then
    wget "${AARCH64_TARBALL_URL}"
    if [ $? -ne 0 ];then
      echo "# --------------- Error fetching Arch tarball at ${AARCH64_TARBALL_URL}."
      exit 130
    fi
  fi
  tarballFullPath=$(realpath ${AARCH64_TARBALL})
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
  TARGET_ROOT_UUID=$(lsblk -o "UUID" ${TARGET_ROOT_PART} |tail -n 1)
  sed -i "s/${BOOT_TXT_ROOT_PARTITION_PLACE_HOLDER}/UUID=${TARGET_ROOT_UUID}/" ${TARGET_ROOT_MOUNTPOINT}/root/${BOOT_TXT}
  cd - &> /dev/null
  echo "# --------------- Syncing, please wait..."
  nice -n 19 sync
}

# ---------------- Prepare and install target ---------------------------------
setup_and_install_target_partitions()
{
  read -p "Wiping target root partition, this operation is destructive. The EMMC partition will be wiped later on without further notice. Continue? (y/n): " reply
  if [ "${reply}" != "y" ];then
    echo "# --------------- Aborting on request."
    exit 140
  fi
  
  read -p "A patched device tree file allows to enable network on the board's ethernet port, and to allow discovery of storage devices on the USB-C port. Please read the included README.md file in the resources/dts directory. Do you want to use the patched device tree? (y/n): " dtsReply
  [ "${dtsReply}" != "y" ] && USE_PATCHED_DTS=0
  
  mkdir ${TARGET_ROOT_MOUNTPOINT} &> /dev/null
  mount ${TARGET_ROOT_PART} ${TARGET_ROOT_MOUNTPOINT}
  RET=$?
  if [ $RET -ne 0 ];then
    echo "# --------------- Error mounting ${TARGET_ROOT_PART} on ${TARGET_ROOT_MOUNTPOINT}."
    exit 132
  fi
  rm -fR ${TARGET_ROOT_MOUNTPOINT}/*
}

# ---------------- Write chroot script ---------------------------------
setup_boot_in_chroot()
{
# We are still in host OS.
  cd ${TARGET_ROOT_MOUNTPOINT}/root
  cat > ${CHROOT_SCRIPT} <<EOF
#!/bin/bash

mount ${TARGET_BOOT_PART} /boot
if [ $? -ne 0 ];then
  echo "# --------------- Error mounting boot partition in chroot."
  exit 150
fi
echo "# --------------- Wiping boot partition in chroot."
rm -fR /boot/*

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
  # Don't 'rm -fR ${WORK_DIR}'. The content of a persisting inner mount will be lost.
  echo "# --------------- Finished."
}

# *****************************************************************************
# ---------------- PROCESS ----------------------------------------------------
mkdir ${WORK_DIR} &> /dev/null
cd ${WORK_DIR}

check_user
check_system
check_os
check_current_root
check_and_set_target_root_partition "$@"

setup_and_install_target_partitions
install_arch
setup_boot_in_chroot

${CHROOT_COMMAND} ${TARGET_ROOT_MOUNTPOINT} "/root/${CHROOT_SCRIPT}"

finish

exit 0
