#!/bin/bash

DIR=`dirname $0`
qlogs="/run/media/mmcblk1p1/qlog_files"

killall QLog
sleep 1
sync
rm -fr $qlogs
echo -e "AT+QCFG=\"DBGCTL\",0\r\n" >/dev/ttyUSB2
echo -e "AT+CFUN=0\r\n" >/dev/ttyUSB2
echo -e "AT+CFUN=1\r\n" >/dev/ttyUSB2
sync
mkdir $qlogs
sync

usbmon=`fuser /sys/kernel/debug/usb/usbmon/2u | awk '{print $1}'`
if [ $usbmon ];then
  kill -9 $usbmon
fi
cat /sys/kernel/debug/usb/usbmon/2u > $qlogs/usbmon.log &
sync
$DIR/QLog -s $qlogs &
sync