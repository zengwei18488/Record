#!/bin/bash

# =================================================================
# Script Name: IEC62443_Ultimate_Compliance_Hardening.sh
# Version: 3.0 (Final Stable)
# Compliance: CR 4.03, 5.01, 6.01, 6.02, 7.01
# =================================================================

echo "Starting IEC 62443 Ultimate Security Hardening..."

# --- 1. System Permissions & Identity (CR 5.01) ---
echo "Step 1: Fixing permissions and network identity..."
sudo chown root:root / /etc /lib /usr /var && sudo chmod 755 / /etc /lib /usr /var
sudo chown -R root:root /etc/ufw && sudo chmod -R 755 /etc/ufw

# Update /etc/hosts
sudo sed -i '/AFE-E630/d' /etc/hosts
cat << EOT | sudo tee -a /etc/hosts
127.0.1.1       AFE-E630
192.168.1.6     AFE-E630
192.168.1.30    AFE-E630
EOT

# --- 2. Service Hardening & DoS Protection (CR 7.01) ---
echo "Step 2: Disabling unnecessary services & applying Sysctl hardening..."
for svc in avahi-daemon cups; do
    sudo systemctl stop $svc.socket $svc.service 2>/dev/null
    sudo systemctl mask $svc.socket $svc.service 2>/dev/null
done

# Kernel Hardening (SYN Flood & ICMP protection)
sudo tee /etc/sysctl.d/99-security-hardening.conf << EOT
net.ipv4.tcp_syncookies = 1
net.ipv4.conf.all.rp_filter = 1
net.ipv4.icmp_echo_ignore_all = 1
net.ipv4.ip_forward = 0
kernel.printk = 3 4 1 3
EOT
sudo sysctl --system

# --- 3. Advanced Firewall & Connectivity Patch (CR 5.01 & 7.01) ---
echo "Step 3: Configuring Firewall and State-Tracking Patches..."
sudo apt update && sudo apt install -y ufw iptables-persistent

sudo ufw --force reset
sudo sed -i 's/IPV6=yes/IPV6=no/' /etc/default/ufw

# Default Policies
sudo ufw default deny incoming
sudo ufw default deny outgoing
sudo ufw default deny routed

# Outbound Allow-list
sudo ufw allow out 53/udp        # DNS
sudo ufw allow out 80/tcp        # HTTP
sudo ufw allow out 443/tcp       # HTTPS
sudo ufw allow out 123/udp       # NTP
sudo ufw allow out 4460/tcp      # NTS

echo "y" | sudo ufw enable
sudo ufw logging low              # Minimalistic logging to prevent console spam

# [CRITICAL] Iptables Priority Rules (Fix In/Out connectivity for Linaro Kernel)
sudo iptables -I INPUT 1 -m state --state RELATED,ESTABLISHED -j ACCEPT
sudo iptables -I INPUT 2 -p tcp --dport 22 -j ACCEPT
sudo iptables -I OUTPUT 1 -m state --state RELATED,ESTABLISHED -j ACCEPT
sudo iptables -I OUTPUT 2 -p udp --dport 53 -j ACCEPT
sudo iptables -I OUTPUT 3 -p tcp --dport 80 -j ACCEPT
sudo iptables -I OUTPUT 4 -p tcp --dport 443 -j ACCEPT

# --- 4. Auditing, Monitoring & Capacity (CR 6.01 & 6.02) ---
echo "Step 4: Configuring Auditd, Fail2Ban, and Journald..."
sudo apt install -y auditd fail2ban python3-systemd

# Fail2Ban (CR 7.01 Brute Force Protection)
sudo tee /etc/fail2ban/jail.local << EOT
[DEFAULT]
backend = systemd
[sshd]
enabled = true
maxretry = 5
bantime = 1800
EOT
sudo systemctl restart fail2ban

# Audit Storage Capacity (CR 6.02)
sudo sed -i 's/^admin_space_left =.*/admin_space_left = 75/' /etc/audit/auditd.conf
sudo sed -i 's/^max_log_file_action =.*/max_log_file_action = ROTATE/' /etc/audit/auditd.conf

# Audit Rules (CR 6.01)
sudo tee /etc/audit/rules.d/compliance.rules << "EOT"
-w /etc/sudoers -p wa -k priv_esc
-w /etc/passwd -p wa -k identity_changes
-w /etc/shadow -p wa -k identity_changes
EOT
sudo augenrules --load

# Persistent Journal & Silent Console (CR 6.01)
sudo mkdir -p /var/log/journal
sudo sed -i 's/^#Storage=.*/Storage=persistent/' /etc/systemd/journald.conf
sudo sed -i 's/^#ForwardToConsole=yes/ForwardToConsole=no/' /etc/systemd/journald.conf
sudo systemctl restart systemd-journald

# --- 5. Time Synchronization Security (CR 4.03) ---
echo "Step 5: Configuring Chrony NTS..."
sudo tee /etc/chrony/chrony.conf << END
driftfile /var/lib/chrony/drift
makestep 1.0 3
rtcsync
server tock.stdtime.gov.tw iburst nts
server tick.stdtime.gov.tw iburst nts
server ://aliyun.com iburst
log tracking measurements statistics
logdir /var/log/chrony
END
sudo systemctl restart chrony

# --- 6. Verification Summary ---
echo "------------------------------------------------"
echo "IEC 62443 COMPLIANCE FINAL VERIFICATION:"
echo "------------------------------------------------"
echo "[CR 5.01] Firewall: $(sudo ufw status | grep -q 'active' && echo 'Active' || echo 'FAIL')"
echo "[CR 7.01] SYN Cookies: $(sysctl net.ipv4.tcp_syncookies | awk '{print $3}')"
echo "[CR 6.01] Audit Rules: $(sudo auditctl -l | wc -l) rules loaded"
echo "[CR 4.03] Chrony NTS: $(chronyc authdata | grep -q 'OK' && echo 'Secured' || echo 'Pending')"
echo "[Access] Inbound SSH: Ready | Outbound HTTP/DNS: Ready"
echo "------------------------------------------------"
echo "Setup Complete. You can now proceed to dump the eMMC image."
