#!/bin/bash

# =================================================================
# Project: AFE-E630 (Debian 12)
# Purpose: Strict Compliance Verification for CR 3.14 & CR 2.11 RE(1)
# =================================================================

# 檢查 root 權限
if [ "$EUID" -ne 0 ]; then 
  echo "Error: Please run as root (sudo)."
  exit 1
fi

echo "--------------------------------------------------"
echo "Starting IEC 62443 Time Synchronization Audit"
echo "--------------------------------------------------"

# 定義顯示結果的函數
print_result() {
    if [ $1 -eq 0 ]; then
        echo -e "\e[32m[ PASS ]\e[0m $2"
    else
        echo -e "\e[31m[ FAIL ]\e[0m $2"
    fi
}

# 1. 檢查 NTP 服務運行狀態 (CR 3.14)
echo "1. Verifying NTP Service Status..."
systemctl is-active --quiet chrony
print_result $? "Chrony service is active and running."

# 2. 檢查系統時鐘同步狀態 (CR 3.14)
echo -e "\n2. Checking System Clock Synchronization..."
# 使用 timedatectl 檢查核心同步標記
timedatectl_status=$(timedatectl status)
echo "$timedatectl_status" | grep -q "System clock synchronized: yes"
print_result $? "System clock is synchronized with a reliable source."

# 3. 檢查 Chrony 詳細跟蹤狀態 (CR 3.14)
echo -e "\n3. Checking Chrony Tracking Details..."
# 檢查時間偏差 (Offset) 是否在可接受範圍 (例如小於 1秒)
OFFSET=$(chronyc tracking | grep "Last offset" | awk '{print $4}' | sed 's/-//')
if (( $(echo "$OFFSET < 1.0" | bc -l) )); then
    print_result 0 "System clock offset ($OFFSET s) is within strict limits (< 1s)."
else
    print_result 1 "System clock offset ($OFFSET s) is too high."
fi

# 4. 檢查硬體時鐘 (RTC) 同步 (CR 3.14 RE)
# 確保系統時間已寫回 RK3568 的實體 RTC
echo -e "\n4. Verifying RTC (Hardware Clock) Integration..."
echo "$timedatectl_status" | grep -q "RTC time:"
print_result $? "Hardware Clock (RTC) is detected and accessible."

# 5. 驗證日誌時間戳記一致性 (CR 2.11 RE 1)
echo -e "\n5. Verifying Audit Log Timestamp Precision (journalctl)..."
# 檢查最近一筆日誌是否有微秒級別的時間戳記
LAST_LOG=$(journalctl -n 1 --no-hostname --output=short-precise | tail -n 1)
if [[ $LAST_LOG =~ [0-9]{2}:[0-9]{2}:[0-9]{2}\.[0-9]{6} ]]; then
    print_result 0 "Journald generates high-precision timestamps (microsecond level)."
else
    print_result 1 "Journald timestamps lack the required precision."
fi

echo -e "\n--------------------------------------------------"
echo "Verification Summary for AFE-E630:"
chronyc sources -v | grep "\^*"
echo "--------------------------------------------------"
