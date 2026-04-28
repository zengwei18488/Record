#!/bin/bash

# =================================================================
# Script Name: IEC62443_CR6_02_Continuous_Monitoring.sh
# Purpose: Real-time detection and reporting of security breaches
# =================================================================

echo "Configuring Continuous Monitoring (CR 6.2) per industry practices..."

# 1. Detection: Real-time Intrusion Monitoring (Fail2Ban)
# Detects brute force and characterizes it by banning source IPs
sudo apt update && sudo apt install -y fail2ban
sudo cp -a /etc/fail2ban/jail.conf /etc/fail2ban/jail.local
sudo sed -i '/^\[sshd\]/,/^\[/ s/enabled = .*/enabled = true/' /etc/fail2ban/jail.local
sudo sed -i '/^\[sshd\]/,/^\[/ s/backend = .*/backend = systemd/' /etc/fail2ban/jail.local
sudo systemctl restart fail2ban

# 2. Characterization: Kernel & Critical File Monitoring (Auditd)
# Monitors who, when, and how security-critical files are accessed
sudo apt install -y auditd
sudo tee /etc/audit/rules.d/cr6_02_monitoring.rules << "EOT"
# Monitor execution of sensitive management tools
-w /usr/bin/sudo -p x -k monitor_priv_esc
-w /usr/sbin/sshd -p x -k monitor_remote_access

# Monitor kernel module changes (Detect rootkits/breaches)
-w /sbin/insmod -p x -k module_change
-w /sbin/rmmod -p x -k module_change
-w /sbin/modprobe -p x -k module_change
EOT
sudo augenrules --load

# 3. Reporting: Persistent & Reliable Logging (Journald)
# Ensures logs are reported/stored in a timely and persistent manner
sudo mkdir -p /var/log/journal
sudo sed -i 's/^#Storage=.*/Storage=persistent/' /etc/systemd/journald.conf
sudo sed -i 's/^#ForwardToConsole=.*/ForwardToConsole=yes/' /etc/systemd/journald.conf
sudo systemctl restart systemd-journald

# 4. Verification Check
echo "------------------------------------------------"
echo "CR 6.2 Monitoring Capability Verification:"
echo "------------------------------------------------"
echo "1. Network Detection (Fail2Ban): $(sudo fail2ban-client status sshd | grep 'Status')"
echo "2. System Detection (Audit Rules):"
sudo auditctl -l | grep -E "module|sudo"
echo "3. Log Persistence: $(ls -d /var/log/journal 2>/dev/null || echo 'Not Found')"
echo "------------------------------------------------"
