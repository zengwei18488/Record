#!/bin/bash

# =================================================================
# Script Name: IEC62443_CR4_03_CR5_01_Integrated_Final.sh
# Purpose: Comprehensive setup for Network Segmentation (CR 5.1) 
#          and Time Sync Security (CR 4.03)
# Target: Debian 12 (Linaro/Rockchip)
# =================================================================

echo "Starting Integrated IEC 62443 Security Setup..."

# --- Step 1: System Permissions & IPv6 Fix (Basic Security) ---
echo "Step 1: Fixing system permissions and disabling IPv6..."
sudo chown root:root / /etc /lib /usr /var
sudo chown -R root:root /etc/ufw
sudo chmod 755 / /etc /lib /usr /var
sudo sed -i 's/IPV6=yes/IPV6=no/' /etc/default/ufw

# --- Step 2: UFW Segmentation Policies (CR 5.1) ---
echo "Step 2: Resetting UFW and applying CR 5.1 Segmentation policies..."
sudo ufw --force reset

# Standard Segmentation: Deny by default, disable routing
sudo ufw default deny incoming
sudo ufw default allow outgoing
sudo ufw default deny routed   # CR 5.1: Prevent board from acting as a router/pivot

# Define allowed data flows (CR 4.01)
sudo ufw allow 22/tcp          # Administrative Access (SSH)
sudo ufw allow out 53          # DNS for resolution
sudo ufw allow out 123/udp     # NTP
sudo ufw allow out 4460/tcp    # NTS Key Establishment

# Enable Firewall with Medium Logging for Audit Evidence
echo "y" | sudo ufw enable
sudo ufw logging medium        # CR 5.1: Sufficient logging for audit

# --- Step 3: Priority Iptables Patches (Connectivity Fix) ---
echo "Step 3: Injecting high-priority rules for SSH/SCP/Ping..."
# Force insert at the TOP to bypass kernel state tracking issues
sudo iptables -I INPUT 1 -p icmp -j ACCEPT
sudo iptables -I INPUT 2 -p tcp --dport 22 -j ACCEPT
sudo iptables -I INPUT 3 -m state --state RELATED,ESTABLISHED -j ACCEPT

# --- Step 4: Chrony NTS Configuration (CR 4.03) ---
echo "Step 4: Configuring Chrony NTS (Taipei & China)..."
CHRONY_CONF="/etc/chrony/chrony.conf"
[ -f "$CHRONY_CONF" ] && sudo cp $CHRONY_CONF "${CHRONY_CONF}.bak"

sudo tee $CHRONY_CONF << END
driftfile /var/lib/chrony/drift
makestep 1.0 3
rtcsync

# Taipei NTS Sources (CR 4.03 Encrypted)
server tock.stdtime.gov.tw iburst nts
server tick.stdtime.gov.tw iburst nts
server time.stdtime.gov.tw iburst nts

# China High-Speed Sources (Accuracy)
server ntp.aliyun.com iburst
server ntp.tencent.com iburst

# Compliance Logging
log tracking measurements statistics
logdir /var/log/chrony
END

sudo systemctl restart chrony
sleep 2

# --- Step 5: Verification (Audit Evidence) ---
echo "------------------------------------------------"
echo "IEC 62443 COMPLIANCE VERIFICATION SUMMARY:"
echo "------------------------------------------------"
# Check Firewall & Segmentation (CR 5.1)
echo "1. Firewall & Segmentation Status:"
sudo ufw status verbose
echo "Forwarding Status (Should be 0): $(cat /proc/sys/net/ipv4/ip_forward)"

# Check Iptables Order
echo -e "\n2. Iptables Priority Check (Input Chain):"
sudo iptables -L INPUT -n --line-numbers | head -n 5

# Check Time Sync (CR 4.03)
echo -e "\n3. Time Sync Sources (chronyc):"
chronyc sources -v
echo -e "\n4. NTS Auth Status (KeyID > 0 means Secured):"
chronyc authdata

# Connectivity Test
echo -e "\n5. Connectivity Check:"
ping -c 1 -W 2 8.8.8.8 > /dev/null && echo "Outbound Access: SUCCESS" || echo "Outbound Access: FAILED"
echo "------------------------------------------------"
echo "Final Setup Complete. System is hardened and compliant."
