#!/bin/bash

if [ -f /dev/ttyUSB2 ];then
  echo -e "AT+CFUN=1,1\r" >/dev/ttyUSB2
fi
