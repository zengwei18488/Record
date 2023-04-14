#!/bin/bash

DIR=`dirname $0`

spi_uuid=`$DIR/write_uuid /dev/mtd0 0xe0000 | grep readback | cut -d ":" -f 3`
len=${#spi_uuid}
echo "spi_uuid = ${spi_uuid}"
if [ $len -lt 24 ];then
	echo SPI uuid Read Fail!
	exit 0
fi


if [ -f /run/media/mmcblk2p1/config.json ];then
	uuid=$(cat /run/media/mmcblk2p1/config.json)
	uuid=$(echo ${uuid#*uuid} | cut -d '"' -f 3)
	echo "uuid     = $uuid"
fi

if [ x${spi_uuid} != x${uuid} ];then
	sed -i 's/'${uuid}'/'${spi_uuid}'/g' /run/media/mmcblk2p1/config.json
	sync

	uuid=$(cat /run/media/mmcblk2p1/config.json)
	uuid=$(echo ${uuid#*uuid} | cut -d '"' -f 3)
	echo "new uuid = ${uuid}"
	if [ x${spi_uuid} != x${uuid} ];then
		echo "update fail"
	else
		echo "update success"
	fi
else
	echo "uuid same"
	echo "update success"
fi



