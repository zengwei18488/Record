#!/bin/bash

loop=1
rsrp=4

while true
do
  if [[ $qeng == *,* ]];then
    qeng=${qeng%,*}
    #echo $loop $qeng
    if [ $loop -lt $rsrp ];then
      ((loop++))
    else
      break;
    fi
  else
    echo $TEST_ITEM=fail
    exit 0
  fi
done

qeng=`echo ${qeng##*,}`
if [ ${#qeng} -lt 5 ];then
  echo ANT=LTE=${qeng}dBm
  touch $ant
  sync
else
  echo $TEST_ITEM=fail
fi
