#!/bin/bash

DIR=`dirname $0`

#$DIR/write_uuid.sh >> /dev/null
#sync
#$DIR/write_uuid /dev/mtd0 0xe0000

#:<<!
if [ -f /run/media/mmcblk2p1/config.json ];then
    uuid=`cat /run/media/mmcblk2p1/config.json | grep uuid | awk -F 'uuid' '{print $2}' | awk -F '"' '{print $3}'`
    len=${#uuid}
    if [ $len -lt 24 ];then
        echo [UUID] Read Fail!
    else
        echo [UUID] Read Success!
        echo uuid:$uuid
    fi
else
    echo [UUID] Read Fail!
fi
#!
