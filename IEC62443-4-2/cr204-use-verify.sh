#!/bin/bash

# =================================================================
# Project: AFE-E630 (Debian 12)
# Purpose: Verification for IMA Integrity (CR 2.04 RE 1)
# =================================================================

# Check root privileges
if [ "$EUID" -ne 0 ]; then 
  echo "Error: Please run as root (sudo)."
  exit 1
fi

echo "--------------------------------------------------"
echo "Starting IMA/EVM Integrity Verification"
echo "--------------------------------------------------"

# 定義顯示結果的函數
print_result() {
    if [ $1 -eq 0 ]; then
        echo -e "\e[32m[ PASS ]\e[0m $2"
    else
        echo -e "\e[31m[ FAIL ]\e[0m $2"
    fi
}

# 1. 檢查內核啟動參數 (Boot Cmdline)
echo "1. Checking Kernel Command Line Parameters..."
CMDLINE=$(cat /proc/cmdline)
[[ "$CMDLINE" == *"ima_appraise="* ]] && [[ "$CMDLINE" == *"ima_hash=sha256"* ]]
print_result $? "IMA parameters (appraise & hash) found in boot cmdline."

# 2. 檢查 IMA 核心介面是否存在
echo -e "\n2. Checking IMA SecurityFS Interface..."
if [ -d "/sys/kernel/security/ima" ]; then
    print_result 0 "IMA SecurityFS is mounted and accessible."
else
    print_result 1 "IMA SecurityFS NOT found. IMA might not be enabled in kernel."
fi

# 3. 檢查是否有動態度量清單 (Measurement List)
echo -e "\n3. Checking IMA Runtime Measurements..."
if [ -f "/sys/kernel/security/ima/ascii_runtime_measurements" ]; then
    MEASURE_COUNT=$(sudo head -n 10 /sys/kernel/security/ima/ascii_runtime_measurements | wc -l)
    if [ "$MEASURE_COUNT" -gt 0 ]; then
        print_result 0 "Runtime measurement list is active and recording."
    else
        print_result 1 "Measurement list is empty."
    fi
else
    print_result 1 "Cannot access measurement list."
fi

# 4. 檢查檔案擴展屬性 (Extended Attributes - security.ima)
echo -e "\n4. Checking File Extended Attributes (xattr)..."
# 檢查是否安裝了 getfattr 工具
if ! command -v getfattr &> /dev/null; then
    echo "[ INFO ] Installing 'attr' package for verification..."
    apt-get install -y attr &>/dev/null
fi

# 檢查 /bin/ls 是否已經被計算並貼上標籤
IMA_ATTR=$(getfattr -m security.ima -d /bin/ls 2>/dev/null)
if [[ "$IMA_ATTR" == *"security.ima="* ]]; then
    print_result 0 "File /bin/ls has 'security.ima' attribute (Hash calculated)."
else
    print_result 1 "File /bin/ls is missing 'security.ima' attribute. (Scan might be needed)"
fi

echo "--------------------------------------------------"
echo "Verification Complete."
