#!/bin/bash

# =================================================================
# Project: AFE-E630 (Debian 12)
# Requirements: IEC 62443-4-2 CR 3.3 Security Patches (SL2)
# Strategy: Automated security-only updates with availability protection
# =================================================================

# 檢查 root 權限
if [ "$EUID" -ne 0 ]; then 
  echo "Error: Please run as root (sudo)."
  exit 1
fi

echo "--- 1. Installing unattended-upgrades ---"
#sudo apt-get update && sudo apt-get install -y unattended-upgrades

echo "--- 2. Enabling Auto-updates (Non-interactive) ---"
# 預先設定選單答案為 "True"
sudo debconf-set-selections <<< "unattended-upgrades unattended-upgrades/enable_auto_updates select true"
# 套用設定，這步替代了手動的 dpkg-reconfigure --priority=low
sudo dpkg-reconfigure -f noninteractive unattended-upgrades

echo "--- 3. Hardening Configuration for Industrial Stability ---"
# 強制設定：僅更新安全性補丁、禁止自動重啟、自動清理快取
sudo tee /etc/apt/apt.conf.d/52-afe-security-only > /dev/null << EOF
Unattended-Upgrade::Allowed-Origins {
    "\${distro_id}:\${distro_codename}-security";
};
Unattended-Upgrade::Automatic-Reboot "false";
Unattended-Upgrade::Remove-Unused-Dependencies "true";
EOF

echo "--- 4. Running Verification (Verification) ---"

# 定義檢測函數
print_status() {
    if [ $1 -eq 0 ]; then
        echo -e "[\e[32m PASS \e[0m] $2"
    else
        echo -e "[\e[31m FAIL \e[0m] $2"
    fi
}

# (A) 檢查服務是否啟動
systemctl is-enabled unattended-upgrades > /dev/null 2>&1
print_status $? "Unattended-upgrades service is enabled."

# (B) 檢查配置檔案是否存在
if [ -f /etc/apt/apt.conf.d/20auto-upgrades ] && grep -q '1' /etc/apt/apt.conf.d/20auto-upgrades; then
    print_status 0 "Auto-upgrade policy is correctly applied."
else
    print_status 1 "Auto-upgrade policy check failed."
fi

# (C) 執行模擬測試 (Dry-run) 確保配置無誤
echo "Running dry-run test (this may take a few seconds)..."
sudo unattended-upgrade --dry-run --debug > /dev/null 2>&1
print_status $? "Dry-run verification completed (Configuration is valid)."

echo "--------------------------------------------------"
echo "AFE-E630 CR 3.3 Hardening Complete!"
echo "--------------------------------------------------"
