#!/bin/bash

DIR=`dirname $0`

if [ -f /run/media/mmcblk2p1/config.json ];then
    uuid=`cat /run/media/mmcblk2p1/config.json | grep uuid | awk -F 'uuid' '{print $2}' | awk -F '"' '{print $3}'`
    len=${#uuid}
    if [ $len -lt 24 ];then
        echo [UUID] Write Fail!
    else
        $DIR/write_uuid /dev/mtd0 0xe0000 $uuid
    fi
else
    echo [UUID] Write Fail!
fi
