#!/bin/bash

DIR=`dirname $0`
flags="/run/media/mmcblk1p1/flag_logs"
DEVICE_PORT="/dev/ttyUSB2"
TEMPLOG="$flags/temp4G.log"
reset="$flags/reseted"
detect="$flags/detected"
ant="$flags/ant"
lte="$flags/lte"
wait=0
try=0
num=0

ifconfig eth0 down
ifconfig eth1 down

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
  echo 4G network test failed
  exit 0
fi

if [ ! -f $ant ];then
  echo 4G network test failed
  exit 0
fi

while true
do
  num=0
  ((try++))
  if [ $try -gt 4 ];then
    echo 4G network test failed
    sleep 1
    killall quectel-CM >> /dev/null 2>&1
    cat $TEMPLOG
    exit 0
  fi
  echo try times=$try

  if [ $try -ne 1 ]; then
    detect_modem
  fi

  qeng=`grep +QENG: $TEMPLOG` >> /dev/null 2>&1
  #echo qeng=$qeng
  if [[ $qeng == *CONN* ]]&&[[ $qeng == *LTE* ]];then
    while true
    do
      ((num++))
      if [ $num -gt 2 ];then
        #echo 4G network test failed
        #exit 0
        break
      fi
      
      wait=0
      while true
      do
        ((wait++))
        if [ $wait -gt 5 ];then
          if [ ! -f $reset ];then
            reset_modem
          fi
          break
        fi
        
        fuser /dev/cdc-wdm0
        if [ $? -eq 0 ]; then
          killall quectel-CM >> /dev/null 2>&1
          sleep 1
        else
          $DIR/quectel-CM & >> /dev/null 2>&1
          sleep 8
          break;
        fi
      done
      
      ifconfig wwan0
      ifconfig wwan0 | grep "inet addr" >> /dev/null 2>&1
      if [ $? -eq 0 ]; then
        ping -I wwan0 -c 3 -W 5 8.8.8.8 > $flags/adv_temp.txt
        killall quectel-CM >> /dev/null 2>&1
        sleep 1
        grep "0 received" $flags/adv_temp.txt
        if [ $? -ne 0 ]; then
          echo 4G network test pass
          #rm -f $flags/adv_temp.txt
          touch $lte
          sync
          exit 0
        fi
        cat $flags/adv_temp.txt
      else
        killall quectel-CM >> /dev/null 2>&1
        sleep 1
      fi
    done
  elif [ $try -eq 2 ]&&[ ! -f $reset ];then
    reset_modem
  else
    sleep 10
  fi
done
