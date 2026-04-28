#!/bin/bash
# IEC 62443 CR 7.4 Integrity Verification Tool

DOC_DIR="/etc/system-docs"
RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m'

echo "=========================================================="
echo "      CR 7.4 INTEGRITY VERIFICATION PROCEDURE"
echo "=========================================================="

if [ ! -f "$DOC_DIR/checksums.txt" ]; then
    echo "Error: Baseline checksums not found!"
    exit 1
fi

echo "Checking archived files against Golden Baseline..."
echo "----------------------------------------------------------"

cd $DOC_DIR
# 執行 SHA-256 自動比對
sudo sha256sum -c checksums.txt

if [ $? -eq 0 ]; then
    echo "----------------------------------------------------------"
    echo -e "RESULT: ${GREEN}[ PASS ]${NC}"
    echo "All critical configurations are intact."
else
    echo "----------------------------------------------------------"
    echo -e "RESULT: ${RED}[ FAIL ]${NC}"
    echo "INTEGRITY BREACH DETECTED! Some files have been altered."
fi
echo "=========================================================="
