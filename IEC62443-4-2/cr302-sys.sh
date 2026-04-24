#!/bin/bash

# =================================================================
# Project: AFE-E630 (Debian 12)
# Requirements: IEC 62443-4-2 CR 3.02 RE(1)
# Description: Malware Protection (ClamAV) with Verification
# =================================================================

# 檢查 root 權限
if [ "$EUID" -ne 0 ]; then 
  echo "Error: Please run as root (sudo)."
  exit 1
fi

echo "--- 1. Installing ClamAV Packages ---"
sudo apt-get update
sudo apt-get install -y clamav clamav-daemon bc

# 確保服務啟動
sudo systemctl stop clamav-freshclam 2>/dev/null
sudo systemctl enable clamav-daemon

echo "--- 2. Setting Up Automated Scan and Logging ---"
LOG_SCRIPT="/usr/local/bin/log_clamav_version.sh"
CRONTAB="/etc/crontab"

# 建立版本記錄腳本
sudo tee $LOG_SCRIPT > /dev/null << "EOT"
#!/bin/bash
echo "[$(date)] ClamAV Version Info:" > /var/log/clamav_version.log
clamscan --version >> /var/log/clamav_version.log
freshclam --version >> /var/log/clamav_version.log
EOT
sudo chmod +x $LOG_SCRIPT

# 配置 Cron 排程 (若不存在則加入)
if ! grep -q "$LOG_SCRIPT" "$CRONTAB"; then
    sudo tee -a $CRONTAB > /dev/null << EOT
# --- IEC 62443 CR 3.02 Malware Protection Schedule ---
0  0    * * *   root    $LOG_SCRIPT
30 1    * * *   root    /usr/bin/freshclam
0  2    * * *   root    /usr/bin/clamscan -r /home /tmp /var/www --log=/var/log/clamav_scan.log
EOT
fi

echo "--- 3. Running Immediate Verification (Verification) ---"

# 定義結果顯示
print_status() {
    if [ $1 -eq 0 ]; then
        echo -e "[\e[32m PASS \e[0m] $2"
    else
        echo -e "[\e[31m FAIL \e[0m] $2"
    fi
}

# (A) 檢查版本紀錄功能
$LOG_SCRIPT
if [ -f /var/log/clamav_version.log ]; then
    print_status 0 "Version logging script executed successfully."
else
    print_status 1 "Version logging script failed."
fi

# (B) 檢查特徵庫更新功能 (需聯網)
echo "Checking signature update (freshclam)..."
sudo freshclam > /dev/null 2>&1
print_status $? "Malware signatures can be updated."

# (C) 執行壓力測試與快速掃描
echo "Running quick scan on /tmp (Verification)..."
sudo clamscan -r /tmp > /dev/null 2>&1
print_status $? "Antivirus engine (clamscan) is functional."

# (D) 檢查 Cron 配置
if grep -q "clamscan" /etc/crontab; then
    print_status 0 "Automation schedule (crontab) is correctly set."
else
    print_status 1 "Crontab entry missing."
fi

echo "--------------------------------------------------"
echo "AFE-E630 Malware Protection Hardening Complete!"
echo "Version: $(clamscan --version)"
echo "--------------------------------------------------"
