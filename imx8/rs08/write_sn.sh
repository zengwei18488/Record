#!/bin/bash

DIR=`dirname $0`

sn_len=`hexdump -d -s 0xd000c -n 0x01 /dev/mtd0 |grep d000c | awk '{print $2}' |awk '{print int($0)}'`
if [ ${sn_len} -lt 32 ] && [ ${sn_len} -gt 0 ];then
  iot_sn=`hexdump -c -s 0xd000d -n ${sn_len} /dev/mtd0 |grep d000d | awk '{$1="";print $0}' | sed 's/ //g'`
  iot_sn=`grep ${iot_sn} $DIR/sn.txt |awk '{print $1}'`
  $DIR/write_uuid /dev/mtd0 0xd8000 ${iot_sn}
fi
