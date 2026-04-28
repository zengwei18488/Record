#!/bin/bash

# =================================================================
# Script Name: IEC62443_UFW_Final_Fix.sh
# Purpose: 1. Fix Permissions 2. Enable IPv4-only UFW 
#          3. Fix Incoming/Outgoing Ping, SSH, and SCP
# Target: Debian 12 (Linaro/Rockchip)
# =================================================================

echo "Step 1: Fixing System Permissions (Security Compliance)..."
sudo chown root:root / /etc /lib /usr /var
sudo chown -R root:root /etc/ufw
sudo chmod 755 / /etc /lib /usr /var
sudo chmod -R 755 /etc/ufw

echo "Step 2: Resetting UFW and Disabling IPv6..."
sudo ufw --force reset
# Disable IPv6 to prevent 'ip6tables' errors on Linaro kernel
sudo sed -i 's/IPV6=yes/IPV6=no/' /etc/default/ufw

echo "Step 3: Patching /etc/ufw/before.rules (High Priority Fix)..."
# We inject rules at the top of 'ufw-before-input' to ensure 
# they are processed BEFORE any 'deny' logic.
# 1. Allow all ICMP (Ping)
# 2. Allow SSH (22) directly to bypass state tracking issues
# 3. Allow established/related for SCP stability
sudo sed -i '/\*filter/a \
:ufw-before-output - [0:0] \
-A ufw-before-input -p icmp -j ACCEPT \
-A ufw-before-output -p icmp -j ACCEPT \
-A ufw-before-input -p tcp --dport 22 -j ACCEPT \
-A ufw-before-input -m state --state RELATED,ESTABLISHED -j ACCEPT \
-A ufw-before-output -m state --state RELATED,ESTABLISHED -j ACCEPT \
' /etc/ufw/before.rules

echo "Step 4: Setting UFW Policies and Essential Rules..."
sudo ufw default deny incoming
sudo ufw default allow outgoing

# Explicitly allow services (Redundancy for ufw status clarity)
sudo ufw allow 22/tcp          # Incoming SSH
sudo ufw allow out 53          # Outgoing DNS
sudo ufw allow out 123/udp     # Outgoing NTP
sudo ufw allow out 4460/tcp    # Outgoing NTS (for CR 4.03)

echo "Step 5: Enabling UFW..."
echo "y" | sudo ufw enable
sudo ufw logging low

# 1. 在 UFW 鏈的最前端強制插入「接受所有 ICMP 進入」
sudo iptables -I INPUT 1 -p icmp -j ACCEPT

# 2. 在 UFW 鏈的最前端強制插入「接受 22 埠 TCP 進入」
sudo iptables -I INPUT 2 -p tcp --dport 22 -j ACCEPT

# 3. 確保回傳封包不論狀態一律放行
sudo iptables -I INPUT 3 -m state --state RELATED,ESTABLISHED -j ACCEPT

echo "------------------------------------------------"
echo "VERIFICATION:"
echo "------------------------------------------------"
sudo ufw status verbose

echo -e "\nConnectivity Tests:"
echo -n "Internal -> External Ping (8.8.8.8): "
ping -c 1 -W 2 8.8.8.8 > /dev/null && echo "SUCCESS" || echo "FAILED"

echo -e "\n[ACTION REQUIRED]:"
echo "Please try to Ping and SSH TO this board from your external host."
echo "If it still fails, check: 'sudo tail -f /var/log/ufw.log'"
echo "------------------------------------------------"
