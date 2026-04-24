#!/bin/bash

# =================================================================
# Project: AFE-E630 (Debian 12)
# Requirements: IEC 62443-4-2 CR 3.07 (Error Handling)
# Logic: Use systemd-coredump (Native Debian) instead of Apport
# =================================================================

if [ "$EUID" -ne 0 ]; then 
  echo "Error: Please run as root (sudo)."
  exit 1
fi

echo "--- 1. Installing Native Error Handling Tools ---"
# 安裝 systemd-coredump 代替 apport
sudo apt-get update
sudo apt-get install -y systemd-coredump

echo "--- 2. Configuring Error Handling (Admin Only) ---"
# 設定核心轉儲限制：僅管理員可存取，且限制大小防止磁碟耗盡 (CR 3.07)
COREDUMP_CONF="/etc/systemd/coredump.conf"
sudo tee $COREDUMP_CONF > /dev/null << EOF
[Coredump]
Storage=external
Compress=yes
ProcessSizeMax=100M
ExternalSizeMax=500M
# 關閉任何對外通報機制，僅保留在本地供管理員審核
EOF

# --- 3. 內核級訊息隱藏 (防止洩漏敏感資訊) ---
# kernel.printk = 3 代表僅列印 CRITICAL 或以上的錯誤至控制台
# fs.suid_dumpable = 0 防止有權限的程式洩漏記憶體資料
sudo tee /etc/sysctl.d/53-afe-error-handling.conf > /dev/null << EOF
kernel.printk = 3 4 1 3
fs.suid_dumpable = 0
EOF
sudo sysctl -p /etc/sysctl.d/53-afe-error-handling.conf

echo "--- 4. Enforcing Log Persistence (CR 3.09 Prep) ---"
# 確保錯誤日誌被整合進 systemd-journald
sudo systemctl restart systemd-journald

echo "--------------------------------------------------"
echo "AFE-E630 CR 3.07 Hardening Complete!"
echo "Verify command: coredumpctl list"
echo "--------------------------------------------------"
