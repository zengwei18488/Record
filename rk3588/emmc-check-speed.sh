#!/bin/bash

TARGET_DEV="/dev/mmcblk0"
MAX_LOOPS=5000
loop=1

# Color Definitions
YELLOW='\033[1;33m'
GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m' # No Color

printf "=========================================\n"
printf "  eMMC Bus Degradation Counter Started\n"
printf "  Monitoring Device: $TARGET_DEV\n"
printf "=========================================\n"

while [ $loop -le $MAX_LOOPS ]
do
    # Read the extcsd register directly from hardware
    extcsd_info=$(mmc extcsd read "$TARGET_DEV" 2>&1)
    
    # Extract the Revision string
    rev_version=$(printf "%s" "$extcsd_info" | grep -i "Extended CSD rev")

    # Check if it degraded to MMC 4.0 or rev 1.0
    if printf "%s" "$rev_version" | grep -qE "MMC 4.0|rev 1.0"; then
        printf "\n${RED}[CRITICAL ALERT] Bus degradation detected!${NC}\n"
        printf "Degraded to: %s\n" "$rev_version"
        printf "Happened at Loop Counter: #%d\n" "$loop"
        printf "Timestamp: %s\n" "$(date '+%Y-%m-%d %H:%M:%S')"
        exit 1
    fi

    # Output progress on a single line with color distinction
    # Yellow for loop number, Green for OK status
    printf "\r[Loop #${YELLOW}%d${NC}] Current Status: %s (${GREEN}OK${NC})" "$loop" "$rev_version"
    
    # Small delay (0.5s) to avoid overwhelming the system bus
    sleep 0.5
    loop=$((loop + 1))
done

printf "\n\n${GREEN}[SUCCESS] Completed $MAX_LOOPS loops. No degradation found.${NC}\n"
