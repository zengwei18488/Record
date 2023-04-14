#!/bin/bash

ifconfig eth0 up
ifconfig eth1 down
sleep 2

DIR=`dirname $0`
ping -I eth0 -c 2 -W 5 www.baidu.com > $DIR/adv_temp.txt
grep "0 received" $DIR/adv_temp.txt
if [ $? -eq 0 ]; then
 echo external network test failed
else
 echo external network test pass
fi
rm -f $DIR/adv_temp.txt
sync

