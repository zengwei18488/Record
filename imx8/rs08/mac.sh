#!/bin/bash

if [ -f /sys/class/net/eth0/address ];then
 cat /sys/class/net/eth0/address
fi

if [ -f /sys/class/net/eth1/address ];then
 cat /sys/class/net/eth1/address
fi
