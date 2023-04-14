#!/bin/bash

DIR=`dirname $0`
#$DIR/write_sn.sh >> /dev/null
sn_len=`hexdump -d -s 0xd8000 -n 0x01 /dev/mtd0 |grep d8000 | awk '{print $2}' |awk '{print int($0)}'`
if [ ${sn_len} -lt 32 ] && [ ${sn_len} -gt 0 ];then
  hexdump -c -s 0xd8001 -n ${sn_len} /dev/mtd0 |grep d8001 | awk '{$1="";print $0}' | sed 's/ //g'
else
  echo "Invalid SN"
fi
