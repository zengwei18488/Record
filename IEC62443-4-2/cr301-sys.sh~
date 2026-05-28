#!/bin/bash

# =================================================================
# Project: AFE-E630 (Debian 12)
# Requirements: IEC 62443 CR 3.01 (Communication Integrity)
# Logic: Fix Permissions -> Hardened SSH -> Service Minimization
# =================================================================

if [ "$EUID" -ne 0 ]; then 
  echo "Error: Please run as root (sudo)."
  exit 1
fi

echo "--- 0. Foundation: Fixing System Permissions ---"
# 1. 恢復系統目錄所有權與基本權限
sudo chown root:root /etc /lib /usr /usr/sbin
sudo chmod 755 /etc /lib /usr /usr/sbin

# 2. 批量修復 /etc 權限 (目錄 755, 檔案 644)
sudo find /etc -type d -exec chmod 755 {} +
sudo find /etc -type f -exec chmod 644 {} +

# 3. 鎖定敏感安全性檔案 (僅 root 可讀寫)
sudo chmod 600 /etc/shadow /etc/gshadow
sudo chmod 600 /etc/ssh/ssh_host_*_key
sudo chmod 644 /etc/ssh/ssh_host_*.pub

echo "--- 1. Hardening SSH Configuration (SL 2 Standard) ---"
SSHD_CONFIG="/etc/ssh/sshd_config"
sudo cp $SSHD_CONFIG ${SSHD_CONFIG}.bak

# 寫入穩定且加固的配置
sudo tee $SSHD_CONFIG > /dev/null << EOF
# --- AFE-E630 SSH Security Policy ---
Port 22
Protocol 2
PermitRootLogin no
PasswordAuthentication yes
PubkeyAuthentication yes
UsePAM yes
X11Forwarding no

# Session Management (CR 2.05 / 2.06)
MaxSessions 5
TCPKeepAlive no
ClientAliveInterval 300
ClientAliveCountMax 3

# Cryptography (SL 2 compliant)
Ciphers aes128-ctr,aes192-ctr,aes256-ctr,aes128-gcm@openssh.com,aes256-gcm@openssh.com
MACs hmac-sha2-256,hmac-sha2-512

# SFTP Subsystem (確保 SCP/SFTP 可用)
Subsystem sftp /usr/lib/openssh/sftp-server
EOF

sudo systemctl restart ssh

echo "--- 2. Service Minimization (Replacement for UFW) ---"
# 因為內核模組缺失，我們採用關閉非必要服務來達成「最小化端口開放」
# 關閉您系統中暴露的 VPN, L2TP 與 MQTT 服務
services_to_disable=("charon" "xl2tpd" "mosquitto")

for svc in "${services_to_disable[@]}"; do
    if systemctl list-unit-files | grep -q "^$svc.service"; then
        echo "Disabling service: $svc"
        sudo systemctl stop $svc
        sudo systemctl disable $svc
    fi
done

# 確保清除任何殘留的錯誤防火牆規則
if command -v ufw > /dev/null; then
    sudo ufw disable
fi
sudo iptables -F
sudo iptables -P INPUT ACCEPT

echo "--- 3. Setting Security Warning Banner ---"
sudo tee /etc/issue > /dev/null << EOF
***************************************************************************
* AFE-E630 SECURITY NOTICE:                                               *
* - Root login is disabled. Please login as 'linaro'.                     *
* - Encrypted Communication (SSH Protocol 2) is enforced.                 *
* - Unauthorized network services are disabled by default.                *
***************************************************************************
EOF

echo "--------------------------------------------------"
echo "AFE-E630 Hardening Complete!"
echo "Verify ports with: ss -tulpn | grep LISTEN"
echo "Verify SCP with: scp -v test_file linaro@<IP>:/tmp"
echo "--------------------------------------------------"
