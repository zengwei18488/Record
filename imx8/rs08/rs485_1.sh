#!/bin/bash

DIR=`dirname $0`
lsusb | grep "EC21 LTE modem" >> /dev/null
if [ $? -eq 0 ]; then
 $DIR/rs485-modbus /dev/ttymxc0 9600 254
else
 $DIR/rs485-modbus /dev/ttymxc0 9600 11
fi
