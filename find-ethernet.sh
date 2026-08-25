#!/bin/bash

# Define colors for professional logging
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo "===================================================="
echo " SCANNING SYSTEM FOR PURE HARDWARE LAN PORTS...    "
echo "===================================================="

eth_count=0

for dev in /sys/class/net/*; do
    # 1. Must have a real hardware device bound
    if [ -e "$dev/device" ]; then
        
        # 2. Must NOT be a Wi-Fi/Wireless extension interface
        if [ ! -d "$dev/wireless" ]; then
            
            bus_path=$(readlink -f "$dev/device")
            sub_system=$(readlink -f "$dev/device/subsystem")
            bus_type="${sub_system##*/}"
            
            # 3. Filter out software virtual networks
            # 4. Filter out USB-bus networks (Eliminates 4G/5G USB Modems like wwan0)
            if [[ "$bus_path" != *"virtual"* ]] && [ "$bus_type" != "usb" ]; then
                dev_name="${dev##*/}"
                mac_addr=$(cat "$dev/address" 2>/dev/null)
                
                # 5. Read physical carrier status
                if [ -f "$dev/carrier" ] && [ "$(cat "$dev/carrier" 2>/dev/null)" = "1" ]; then
                    link_status="CONNECTED"
                else
                    link_status="DISCONNECTED"
                fi
                
                echo -e "${GREEN}[DETECTED]${NC} Interface Name : ${YELLOW}$dev_name${NC}"
                echo "  ├─ Bus Subsystem : $bus_type"
                echo "  ├─ Hardware Node : $bus_path"
                echo "  ├─ MAC Address   : $mac_addr"
                echo "  └─ Carrier Link  : $link_status"
                echo "----------------------------------------------------"
                ((eth_count++))
            fi
        fi
    fi
done

echo "===================================================="
echo -e "${BLUE}[SCAN REPORT]${NC} Identification Finished Successfully."
echo -e "Total Pure Hardware LAN Interfaces Found: ${GREEN}$eth_count${NC}"
echo "===================================================="

exit 0
