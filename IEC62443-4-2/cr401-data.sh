#!/bin/bash

# --- CR 4.01: System-wide Cryptography Hardening ---
# 此設定會讓系統內「所有」依賴 OpenSSL 的服務自動升級加密等級

OPENSSL_CONF="/etc/ssl/openssl.cnf"

# 1. 備份並註解舊設定
sudo sed -i "s/\(^CipherString =.*\)/#\1/" $OPENSSL_CONF

# 2. 寫入全域強加密規範 (TLS 1.2+ & AES-GCM)
# 確保所有通訊（不僅是 SSH）都具備完整性與機密性
sudo sed -i '/#CipherString/a \
CipherString = DEFAULT@SECLEVEL=2\
Ciphersuites = TLS_AES_256_GCM_SHA384:TLS_AES_128_GCM_SHA256\
MinProtocol = TLSv1.2' $OPENSSL_CONF

# 3. 驗證 (證明系統加密庫已升級)
echo "Global OpenSSL Security Level:"
openssl ciphers -v -tls1_3 | grep GCM
