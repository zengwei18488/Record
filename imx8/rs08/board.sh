#!/bin/bash

try=0

while true
do
  ((try++))
  if [ $try -gt 10 ];then
    echo "V1.5"
    exit 0
  fi

  lsusb | grep "EC21" >> /dev/null
  if [ $? -eq 0 ]; then
   echo "V2.0"
   exit 0
  else
   sleep 1
  fi
done
