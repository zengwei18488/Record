#!/bin/bash

TEST_ITEM="SIM ICCID"
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

rm -fr $flags
sync
mkdir $flags
sync

while true
do
  ((try++))
  if [ $try -gt 3 ];then
    #echo $TEST_ITEM test failed
    error=`sed -n '/AT+CPIN/,/AT+QMBNCFG/{p}' $TEMPLOG | grep ERROR`
    echo iccid=$error
    sleep 1
    cat $TEMPLOG
    exit 0
  fi
  echo try times=$try

  detect_modem
  mbn=`grep +QMBNCFG: $TEMPLOG`
  if [[ $mbn != *1* ]];then
    echo enable MBN
    echo -e "AT+QMBNCFG=\"AUTOSEL\",1\r" >$DEVICE_PORT
  fi

  grep +CCID: $TEMPLOG >> /dev/null 2>&1
  if [ $? == 0 ];then
    iccid=`grep +CCID: $TEMPLOG | awk '{print $2}'`
    if [ ${#iccid} -ge 10 ]&&[[ $iccid == 89* ]];then
      echo iccid=$iccid
      touch $detect
      sync
      exit 0
    fi
  elif [ ! -f $reset ];then
    reset_modem
  fi
done
