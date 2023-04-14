#!/bin/bash

ddr_size=`free -h | grep Mem | awk {'print $2'} | cut -d "G" -f 1`

if [[ $(echo "$ddr_size >= 1.5"|bc) = 1 ]] && [[ $(echo "$ddr_size <= 2.5"|bc) = 1 ]];then
	echo DDR=2G
	echo DDR=2G
	echo DDR=2G
	echo DDR=2G
	echo DDR=2G
elif [[ $(echo "$ddr_size >= 2.5"|bc) = 1 ]] && [[ $(echo "$ddr_size <= 3.5"|bc) = 1 ]];then
	echo DDR=3G
	echo DDR=3G
	echo DDR=3G
	echo DDR=3G
	echo DDR=3G
elif [[ $(echo "$ddr_size >= 3.5"|bc) = 1 ]] && [[ $(echo "$ddr_size <= 4.5"|bc) = 1 ]];then
	echo DDR=4G
	echo DDR=4G
	echo DDR=4G
	echo DDR=4G
	echo DDR=4G
else
	echo DDR=fail
	echo DDR=fail
	echo DDR=fail
	echo DDR=fail
	echo DDR=fail
fi

