#!/bin/bash

TEST_ITEM="ANT"
DIR=`dirname $0`
flags="/run/media/mmcblk1p1/flag_logs"
DEVICE_PORT="/dev/ttyUSB2"
TEMPLOG="$flags/temp4G.log"
reset="$flags/reseted"
detect="$flags/detected"
first="$flags/first"
ant="$flags/ant"
lte="$flags/lte"
try=0
loop=2

function detect_modem()
{
  rm -f $TEMPLOG
  sync
  $DIR/sim_detect $DEVICE_PORT 115200 > $TEMPLOG
  sync
}

function reset_modem()
{
  $DIR/hw_reset_modem.sh
  sleep 40
  touch $reset
  sync
}

if [ ! -f $detect ];then
  echo $TEST_ITEM=fail
  exit 0
fi

if [ ! -f $first ];then
  loop=6
  touch $first
  sync
else
  killall QLog
  sleep 1
  usbmon=`fuser /sys/kernel/debug/usb/usbmon/2u | awk '{print $1}'`
  if [ $usbmon ];then
    kill -9 $usbmon
  fi
  
  loop=1
  if [ ! -f $lte ];then
    echo $TEST_ITEM=fail
    exit 0
  fi
fi

while true
do
  ((try++))
  if [ $try -gt $loop ];then
    echo $TEST_ITEM=fail
    sleep 1
    cat $TEMPLOG
    exit 0
  fi
  echo try times=$try

  if [ $try -ne 1 ]; then
    detect_modem
  fi

  qeng=`grep +QENG: $TEMPLOG` >> /dev/null 2>&1
  if [[ $qeng == *CONN* ]]&&[[ $qeng == *LTE* ]];then
    source $DIR/4g_signal.sh
    exit 0
  #elif [[ $qeng == *CONN* ]]&&[[ $qeng == *CDMA* ]];then
  #  source $DIR/3g_signal.sh
  #  exit 0
  #elif [[ $qeng == *CONN* ]]&&[[ $qeng == *GSM* ]];then
  #  source $DIR/3g_signal.sh
  #  exit 0
  elif [ $try -eq 4 ]&&[ ! -f $reset ];then
    reset_modem
  else
    sleep 10
  fi
done
