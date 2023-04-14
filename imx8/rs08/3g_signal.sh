#!/bin/bash

CSQ=`grep "+CSQ:" $TEMPLOG | cut -f2 -d":" | cut -f2 -d" " | cut -f1 -d","`
echo ANT=CSQ=$CSQ

