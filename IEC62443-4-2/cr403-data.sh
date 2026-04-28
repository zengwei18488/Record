#!/bin/bash

# =================================================================
# Script: IEC62443_Compliance_Final.sh
# Purpose: Meet CR 4.01, 4.02, and 4.03 without UFW
# Features: Iptables, Chrony NTS, Chronyc Verification, TCP Wrappers
# =================================================================

echo "Starting IEC 62443-4-2 Compliance Setup..."

# 1. Install necessary lightweight tools
sudo apt update
sudo apt install -y iptables iptables-persistent chrony dnsutils

# 2. Configure Iptables (Firewall Policy)
echo "Configuring Iptables rules..."
sudo iptables -F
sudo iptables -X
sudo iptables -P INPUT DROP
sudo iptables -P FORWARD DROP
sudo iptables -P OUTPUT ACCEPT

# Allow Loopback and Established Connections (Crucial for SCP)
sudo iptables -A INPUT -i lo -j ACCEPT
sudo iptables -A INPUT -m state --state ESTABLISHED,RELATED -j ACCEPT

# Allow Essential Services
sudo iptables -A INPUT -p tcp --dport 22 -j ACCEPT   # SSH
sudo iptables -A INPUT -p udp --dport 123 -j ACCEPT  # NTP
sudo iptables -A INPUT -p tcp --dport 4460 -j ACCEPT # NTS

# Save Iptables Rules
sudo netfilter-persistent save

# 3. Configure TCP Wrappers (Extra Layer for IEC 62443)
echo "Configuring TCP Wrappers..."
echo "sshd: ALL" | sudo tee -a /etc/hosts.allow
# Note: You can replace ALL with a specific IP like "sshd: 172.21.171.105"

# 4. Configure Chrony (Time Sync Security - CR 4.03)
CHRONY_CONF="/etc/chrony/chrony.conf"
sudo cp $CHRONY_CONF "${CHRONY_CONF}.bak"
sudo tee $CHRONY_CONF << END
driftfile /var/lib/chrony/drift
makestep 1.0 3
rtcsync

# Taipei NTS Sources (CR 4.03 Encrypted)
server tock.stdtime.gov.tw iburst nts
server tick.stdtime.gov.tw iburst nts
server time.stdtime.gov.tw iburst nts

# China Sources (Low Latency)
server ://aliyun.com iburst
server ://tencent.com iburst

# Audit Logs
log tracking measurements statistics
logdir /var/log/chrony
END

sudo systemctl restart chrony

# 5. Automated Verification via Chronyc
echo "------------------------------------------------"
echo "VERIFICATION (Executing chronyc commands):"
echo "------------------------------------------------"

# Check if chrony is actually running
if systemctl is-active --quiet chrony; then
    echo "[OK] Chrony service is running."
else
    echo "[ERROR] Chrony service failed to start."
fi

echo -e "\n1. NTP Sources Status (chronyc sources):"
# Show sources and their status
chronyc sources -v

echo -e "\n2. NTS Authentication Data (chronyc authdata):"
# Verify if NTS (encryption) is active
chronyc authdata

echo -e "\n3. Tracking Info (chronyc tracking):"
# Check system clock performance
chronyc tracking

echo "------------------------------------------------"
echo "Setup Complete. Iptables and Chrony are active."
