#!/bin/bash

echo "--- CR 3.08: Audit Log Accessibility & Session Security ---"

# 1. 提供安全隨機數 (Secure Session Identifiers)
#sudo apt-get update && sudo apt-get install -y rng-tools-debian
sudo systemctl enable --now rng-tools-debian

# 2. 強制登出時中斷任務 (Interrupt tasks upon logout)
sudo sed -i 's/^#KillUserProcesses=.*/KillUserProcesses=yes/' /etc/systemd/logind.conf
sudo systemctl restart systemd-logind

# 3. 鎖定日誌存取權限 (Accessibility)
sudo mkdir -p /var/log/journal
sudo chown root:adm /var/log/journal
sudo chmod 750 /var/log/journal

echo "--------------------------------------------------"
echo "CR 3.08 Hardening Complete!"
echo "Check Entropy: cat /proc/sys/kernel/random/entropy_avail"
echo "--------------------------------------------------"
