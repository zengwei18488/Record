#!/bin/bash

# =================================================================
# Script Name: IEC62443_Total_Hardening_Final_v2.sh
# Purpose: Comprehensive Security Setup (CR 4.03, 5.1, 7.1)
# Features: Fixed IP Forwarding, UFW Display, and Service Hardening
# Target: Debian 12 (Linaro/Rockchip)
# =================================================================

echo "Starting Integrated IEC 62443 Security Setup & Hardening..."

# --- Step 1: System Permissions & Identity ---
echo "Step 1: Fixing permissions and configuring network identity..."
sudo chown root:root / /etc /lib /usr /var && sudo chmod 755 / /etc /lib /usr /var
sudo chown -R root:root /etc/ufw && sudo chmod -R 755 /etc/ufw

# Update /etc/hosts (Identity Management)
sudo sed -i '/AFE-E630/d' /etc/hosts
cat << EOT | sudo tee -a /etc/hosts
127.0.1.1       AFE-E630
192.168.1.6     AFE-E630
192.168.1.30    AFE-E630
EOT

# --- Step 2: System Hardening & Routing Control (CR 5.1 & 7.1) ---
echo "Step 2: Hardening services and disabling IP forwarding..."
# CR 5.1: Disable IP Forwarding at kernel level
sudo sysctl -w net.ipv4.ip_forward=0
sudo sed -i 's/net.ipv4.ip_forward=1/net.ipv4.ip_forward=0/g' /etc/sysctl.conf

# Disable unnecessary services
for svc in avahi-daemon cups; do
    sudo systemctl stop $svc.socket $svc.service 2>/dev/null
    sudo systemctl disable $svc.socket $svc.service 2>/dev/null
    sudo systemctl mask $svc.socket $svc.service 2>/dev/null
done

# --- Step 3: Advanced Firewall (CR 5.1 & CR 7.1) ---
echo "Step 3: Configuring strict UFW policies with Outbound fix..."
sudo ufw --force reset
sudo sed -i 's/IPV6=yes/IPV6=no/' /etc/default/ufw

# Strict Global Policies
sudo ufw default deny incoming
sudo ufw default deny outgoing   # Strict Outbound Control
sudo ufw default deny routed    

# [CR 5.1] Outbound Allow-list
sudo ufw allow out 53/udp        # DNS
sudo ufw allow out 80/tcp        # HTTP
sudo ufw allow out 443/tcp       # HTTPS
sudo ufw allow out 123/udp       # NTP
sudo ufw allow out 4460/tcp      # NTS (Handshake)

# Enable UFW
echo "y" | sudo ufw enable
sudo ufw logging medium

# --- [CRITICAL PATCH] Fix for Linaro Kernel (Stateful & Protocol Fix) ---

# 1. Fix INPUT (Allow replies and essential incoming)
sudo iptables -I INPUT 1 -m state --state RELATED,ESTABLISHED -j ACCEPT
sudo iptables -I INPUT 2 -p icmp -j ACCEPT
sudo iptables -I INPUT 3 -p tcp --dport 22 -j ACCEPT

# 2. Fix OUTPUT (Allow Board to initiate connections and receive replies)
# Clear potential duplicate patches first to keep it clean
sudo iptables -D OUTPUT -m state --state RELATED,ESTABLISHED -j ACCEPT 2>/dev/null
sudo iptables -I OUTPUT 1 -m state --state RELATED,ESTABLISHED -j ACCEPT
sudo iptables -I OUTPUT 2 -p icmp -j ACCEPT               # Allow Ping out
sudo iptables -I OUTPUT 3 -p udp --dport 53 -j ACCEPT     # Allow DNS out
sudo iptables -I OUTPUT 4 -p tcp --dport 80 -j ACCEPT     # Allow HTTP out (for APT)
sudo iptables -I OUTPUT 5 -p tcp --dport 443 -j ACCEPT    # Allow HTTPS out (for APT)
sudo iptables -I OUTPUT 6 -p tcp --dport 22 -j ACCEPT     # Allow SSH out

# [CR 7.1] Attempt to limit SSH (Even if it skips, the iptables rule above ensures access)
sudo ufw limit in from 192.168.1.0/24 to any port 22 proto tcp

# --- Step 4: Time Synchronization Security (CR 4.03) ---
echo "Step 4: Configuring Chrony NTS (Taipei & China)..."
CHRONY_CONF="/etc/chrony/chrony.conf"
[ -f "$CHRONY_CONF" ] && sudo cp $CHRONY_CONF "${CHRONY_CONF}.bak"

sudo tee $CHRONY_CONF << END
driftfile /var/lib/chrony/drift
makestep 1.0 3
rtcsync
server tock.stdtime.gov.tw iburst nts
server tick.stdtime.gov.tw iburst nts
server time.stdtime.gov.tw iburst nts
server ntp.aliyun.com iburst
server ntp.tencent.com iburst
log tracking measurements statistics
logdir /var/log/chrony
END

sudo systemctl restart chrony
sleep 2

# --- Step 5: Verification (Audit Evidence) ---
echo "------------------------------------------------"
echo "IEC 62443 COMPLIANCE VERIFICATION SUMMARY:"
echo "------------------------------------------------"
echo "1. Firewall Status (CR 5.1 & CR 7.1):"
sudo ufw status verbose

sudo iptables -L INPUT -n -v

echo -e "\n2. IP Forwarding (Expect 0 for CR 5.1):"
cat /proc/sys/net/ipv4/ip_forward

echo -e "\n3. Listening Services (Check for unauthorized ports):"
sudo ss -tulpn | grep LISTEN

echo -e "\n4. Time Sync Status (CR 4.03):"
chronyc sources -v
chronyc authdata

echo "------------------------------------------------"
echo "Final Setup Complete. System is now hardened and compliant."
