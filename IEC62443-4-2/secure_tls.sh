#!/bin/bash

echo "=========================================="
echo "      OpenSSL Security Level Detector"
echo "=========================================="

# 1. OpenSSL Version Info
OSSL_VER=$(openssl version)
echo "[System]: $OSSL_VER"

# 2. Check SECLEVEL in Config
CONF_LEVEL=$(grep -E "SECLEVEL=" /etc/ssl/openssl.cnf | awk -F'=' '{print $2}' | xargs || echo "Not explicitly defined")
echo "[Config]: Current SECLEVEL = $CONF_LEVEL"

# 3. Check Minimum Protocol
MIN_PROTO=$(grep -E "MinProtocol" /etc/ssl/openssl.cnf | awk -F'=' '{print $2}' | xargs || echo "No restriction")
echo "[Config]: MinProtocol = $MIN_PROTO"

echo -e "\n--- Weak Algorithm Statistics ---"

# 4. Count Insecure Suites
SSL3_COUNT=$(openssl ciphers -v | grep -c "SSLv3")
TLS1_COUNT=$(openssl ciphers -v | grep -c -E "TLSv1$|TLSv1.1")
SHA1_COUNT=$(openssl ciphers -v | grep -c "SHA1")

echo "SSLv3   Suites: $SSL3_COUNT"
echo "TLSv1.x Suites: $TLS1_COUNT"
echo "SHA1    Algos : $SHA1_COUNT"

echo -e "\n--- Security Assessment ---"
if [ "$SSL3_COUNT" -eq 0 ] && [ "$SHA1_COUNT" -eq 0 ] && [[ "$MIN_PROTO" == *"TLSv1.2"* ]]; then
    echo "✅ STATUS: Compliant with Modern Security Standards (SECLEVEL 2+)"
else
    echo "⚠️  STATUS: Vulnerable (Running at SECLEVEL 1 or below)"
    echo "    Reason: Legacy protocols/hashes are still enabled."
fi
echo "=========================================="
