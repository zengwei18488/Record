#!/bin/bash

DIR=`dirname $0`
ping -I eth0 -c 2 -W 5 192.168.1.238 > $DIR/adv_temp.txt
grep "2 received" $DIR/adv_temp.txt
if [ $? -ne 0 ]; then
 echo 3rd internal network test failed
else
 echo 3rd internal network test pass
fi
rm -f $DIR/adv_temp.txt
sync
