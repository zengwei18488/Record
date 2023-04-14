#!/bin/bash

#cat /run/media/mmcblk2p1/image-version-info
cat /run/media/mmcblk2p1/os-release | grep "PRETTY_NAME=" | cut -d "\"" -f 2

