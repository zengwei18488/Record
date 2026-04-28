#!/bin/bash

# =================================================================
# Script Name: IEC62443_CR7_04_Security_Baseline.sh
# Purpose: Create Golden Baseline and Integrity Checksums
# Target: Debian 12 (Linaro/Rockchip)
# =================================================================

# 顏色定義
BLUE='\033[1;34m'
GREEN='\033[0;32m'
RED='\033[0;31m'
BOLD='\033[1m'
NC='\033[0m'

DOC_DIR="/etc/system-docs"
echo -e "${BLUE}Starting IEC 62443 Security Baseline Protection...${NC}"

# --- [保護清單定義] ---
# 1. SSH 設定 (管理權限核心)
# 2. FSTAB (磁碟掛載核心)
# 3. UFW 規則 (網路防禦核心)
# 4. Sysctl (核心加固參數)
# 5. Crontab (自動化排程)

echo -e "${BOLD}Step 1: Creating secure archive directory...${NC}"
sudo mkdir -p $DOC_DIR

echo -e "${BOLD}Step 2: Archiving critical configurations to $DOC_DIR...${NC}"
sudo cp -a /etc/ssh/sshd_config $DOC_DIR/
sudo cp -a /etc/fstab $DOC_DIR/
sudo cp -a /etc/sysctl.d/99-security-hardening.conf $DOC_DIR/ 2>/dev/null || true
sudo cp -a /etc/crontab $DOC_DIR/
[ -f /etc/ufw/user.rules ] && sudo cp -a /etc/ufw/user.rules $DOC_DIR/

# --- [校驗程序生成] ---
echo -e "${BOLD}Step 3: Generating SHA-256 integrity checksums...${NC}"
# 進入目錄產生校驗檔，避免絕對路徑干擾比對
cd $DOC_DIR
sudo sha256sum sshd_config fstab crontab *.conf *.rules 2>/dev/null | sudo tee checksums.txt > /dev/null

echo -e "${GREEN}SUCCESS: Security Baseline is established.${NC}"
echo "----------------------------------------------------------"
ls -dl $DOC_DIR/*
echo "----------------------------------------------------------"
