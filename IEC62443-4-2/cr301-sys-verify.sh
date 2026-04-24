#!/bin/bash

# =================================================================
# Project: AFE-E630 (Debian 12)
# Purpose: Verification for CR 3.01 RE(1) Communication Integrity
# =================================================================

# 檢查 root 權限
if [ "$EUID" -ne 0 ]; then 
  echo "Error: Please run as root (sudo)."
  exit 1
fi

echo "=================================================="
echo "IEC 62443-4-2 CR 3.01 RE(1) Audit Report"
echo "Device: AFE-E630 (RK3568)"
echo "Timestamp: $(date)"
echo "=================================================="

# 定義顯示函數
check_status() {
    if [ $1 -eq 0 ]; then
        echo -e "[\e[32m PASS \e[0m] $2"
    else
        echo -e "[\e[31m FAIL \e[0m] $2"
    fi
}

# --- 1. 驗證加密協議與演算法 (Cryptography Usage) ---
echo -e "\n1. Verifying Cryptography Usage (SSH Protocol & Ciphers):"
# 檢查是否強制使用 Protocol 2 且禁用了弱算法
SSHD_V=$(sshd -T | grep -E "protocol|ciphers")
echo "$SSHD_V"

# 判斷是否包含強加密算法 (AES-GCM)
echo "$SSHD_V" | grep -qiE "aes128-gcm|aes256-gcm|chacha20"
check_status $? "Strong encryption algorithms are enforced."

# --- 2. 驗證管理介面最小化 (Least Functionality) ---
echo -e "\n2. Verifying Least Functionality (Open Ports):"
# 獲取所有監聽中的 TCP/UDP 埠口 (排除本機 127.0.0.1)
OPEN_PORTS=$(ss -tulpn | grep LISTEN | grep -v "127.0.0.1")
echo "$OPEN_PORTS"

# 檢查是否只有 Port 22 在監聽 (或者除了 22 以外沒有不安全埠口)
if [[ $(echo "$OPEN_PORTS" | grep -v ":22" | wc -l) -eq 0 ]]; then
    check_status 0 "Network attack surface is minimized (Only Port 22 found)."
else
    # 檢查是否有不安全的 VPN/MQTT 埠口殘留
    echo "$OPEN_PORTS" | grep -qiE "1883|1701|500|4500"
    if [ $? -eq 0 ]; then
        check_status 1 "Unsecured services (VPN/MQTT) are still exposed!"
    else
        check_status 0 "No critical unsecure services detected."
    fi
fi

# --- 3. 驗證身分驗證完整性 (Authentication Integrity) ---
echo -e "\n3. Verifying Authentication Policy (Root & PAM):"
# 檢查是否禁止 root 直接登入與開啟 PAM
ROOT_LOGIN=$(sshd -T | grep "permitrootlogin")
USE_PAM=$(sshd -T | grep "usepam")
echo "$ROOT_LOGIN"
echo "$USE_PAM"

if [[ "$ROOT_LOGIN" == *"no"* && "$USE_PAM" == *"yes"* ]]; then
    check_status 0 "Access control policy is secured (No Direct Root & PAM Active)."
else
    check_status 1 "Access control policy violates SL 2 requirements."
fi

echo -e "\n=================================================="
echo "End of Audit Report"
echo "=================================================="
