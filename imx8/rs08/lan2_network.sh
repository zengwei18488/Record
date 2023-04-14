#!/bin/bash

ifconfig eth0 down
ifconfig | grep eth1
if [ $? -ne 0 ]; then
 ifconfig eth1 up
 sleep 3
fi

DIR=`dirname $0`
ping -I eth1 -c 2 -W 5 www.baidu.com > $DIR/adv_temp.txt
grep "0 received" $DIR/adv_temp.txt
if [ $? -eq 0 ]; then
 echo lan2 network test failed
else
 echo lan2 network test pass
fi

rm -f $DIR/adv_temp.txt
sync
ifconfig eth1 down
