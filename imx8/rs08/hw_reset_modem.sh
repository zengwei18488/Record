#!/bin/bash

echo 1 > /sys/class/gpio/export
echo low > /sys/class/gpio/gpio1/direction
sleep 0.3
echo high > /sys/class/gpio/gpio1/direction
echo 1 > /sys/class/gpio/unexport

