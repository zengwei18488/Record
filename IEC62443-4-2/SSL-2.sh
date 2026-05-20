#!/bin/bash

# =================================================================
# Purpose: Final BSP Hardening for IEC 62443-4-2 Compliance
# Target: Debian 12 (Linaro/Rockchip) 
# Logic: Enforcement of TLS 1.2+ and Security Level 2
# =================================================================

# 定義系統真實的 OpenSSLDIR 路徑
CONF_DIR="/usr/lib/ssl"
TARGET_CONF="${CONF_DIR}/openssl.cnf"
ETC_LINK="/etc/ssl/openssl.cnf"

echo "[1/3] Correcting OpenSSL Directory and Link..."
sudo mkdir -p "$CONF_DIR"

echo "[2/3] Writing Hardened Configuration to $TARGET_CONF..."
# 直接重寫設定檔，確保openssl_conf連結位於檔案第一行
sudo tee "$TARGET_CONF" << EOT
# IEC 62443-4-2 CR 4.3 Compliant Configuration
openssl_conf = default_conf

[default_conf]
ssl_conf = ssl_sect

[ssl_sect]
system_default = system_default_sect

[system_default_sect]
MinProtocol = TLSv1.2
CipherString = DEFAULT@SECLEVEL=2
EOT

# 建立軟連結確保相容性
sudo ln -sf "$TARGET_CONF" "$ETC_LINK"

echo "[3/3] Finalizing and Syncing to Disk..."
sudo sync && sudo sync

echo -e "\n--- VERIFICATION ---"
# 驗證是否還有舊協議 (預期輸出應為空)
BAD_PROTO=$(openssl ciphers -v | grep -E "SSLv3|TLSv1$")

if [ -z "$BAD_PROTO" ]; then
    echo "Result: [ PASS ] - Legacy protocols disabled."
else
    echo "Result: [ FAIL ] - Legacy protocols still active."
    echo "$BAD_PROTO"
fi
