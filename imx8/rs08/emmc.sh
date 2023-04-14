#!/bin/bash

emmc_size=`fdisk -l /dev/mmcblk2 | grep Disk | grep mmcblk2 | awk {'print $3'} | cut -d "." -f 1`

if [[ ${emmc_size} -ge 6 ]] && [[ ${emmc_size} -le 10 ]];then
	echo eMMC=8G
	echo eMMC=8G
	echo eMMC=8G
	echo eMMC=8G
	echo eMMC=8G
elif [[ ${emmc_size} -ge 13 ]] && [[ ${emmc_size} -le 19 ]];then
	echo eMMC=16G
	echo eMMC=16G
	echo eMMC=16G
	echo eMMC=16G
	echo eMMC=16G
elif [[ ${emmc_size} -ge 28 ]] && [[ ${emmc_size} -le 36 ]];then
	echo eMMC=32G
	echo eMMC=32G
	echo eMMC=32G
	echo eMMC=32G
	echo eMMC=32G
elif [[ ${emmc_size} -ge 58 ]] && [[ ${emmc_size} -le 70 ]];then
	echo eMMC=64G
	echo eMMC=64G
	echo eMMC=64G
	echo eMMC=64G
	echo eMMC=64G
else
	echo eMMC=fail
	echo eMMC=fail
	echo eMMC=fail
	echo eMMC=fail
	echo eMMC=fail
fi
