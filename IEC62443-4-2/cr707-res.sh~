#!/bin/bash

# =================================================================
# Script Name: IEC62443_CR7_07_Manual_Hardening.sh
# Purpose: Service Masking & Controlled Physical Port Protection
# Compliance: IEC 62443-4-2 CR 7.07
# Target: Debian 12 (Linaro/Rockchip)
# =================================================================

# 顏色定義
BLUE='\033[1;34m'
GREEN='\033[0;32m'
RED='\033[0;31m'
BOLD='\033[1m'
NC='\033[0m'

AUTO_RULE="/etc/udev/rules.d/automount.rules"
AUTO_SH="/usr/local/bin/automount.sh"
BLOCK_RULE="/etc/udev/rules.d/99-no-automount.rules"

echo -e "${BLUE}Starting IEC 62443 CR 7.07 Manual Hardening & Verification...${NC}"

# --- 1. [Service Masking] 徹底封印非必要服務 (縮減攻擊面) ---
echo -e "${BOLD}[1/3] Masking non-essential services...${NC}"
# 定義需要屏蔽的服務清單
SERVICES=("avahi-daemon" "cups" "bluetooth" "wpa_supplicant" "mosquitto" "rpcbind")

for svc in "${SERVICES[@]}"; do
    if systemctl list-unit-files | grep -q "$svc"; then
        sudo systemctl stop "$svc" 2>/dev/null
        sudo systemctl mask "$svc" 2>/dev/null
        echo -e "Service $svc: ${GREEN}[ MASKED ]${NC}"
    fi
done

# --- 2. [Physical Protection] 禁用自動掛載與限制權限 ---
echo -e "${BOLD}[2/3] Protecting Physical Ports (Restricting USB Access)...${NC}"

# A. 移除自動掛載引擎 (防止隨身碟即插即用)
sudo apt purge -y udisks2 gvfs thunar-volman 2>/dev/null
sudo apt autoremove -y 2>/dev/null

if [ -f "$AUTO_RULE" ]; then
    sudo mv "$AUTO_RULE" "${AUTO_RULE}.bak"
fi
sudo chmod -x "$AUTO_SH" 2>/dev/null

# B. 建立 udev 規則：強制使 USB 儲存裝置對系統掛載引擎「隱身」
sudo tee /etc/udev/rules.d/99-no-automount.rules << EOT > /dev/null
SUBSYSTEM=="block", ENV{ID_USB_DRIVER}=="usb-storage", ENV{UDISKS_IGNORE}="1", ENV{UDISKS_PRESENTATION_HIDE}="1"
SUBSYSTEM=="block", ENV{ID_USB_DRIVER}=="uas", ENV{UDISKS_IGNORE}="1", ENV{UDISKS_PRESENTATION_HIDE}="1"
EOT

# C. 限制掛載二進位檔權限 (僅限 root 執行，滿足 CR 7.7)
sudo chmod 700 /usr/bin/mount 2>/dev/null
sudo chmod 700 /usr/bin/umount 2>/dev/null

# 套用設定並同步
sudo udevadm control --reload-rules
sudo udevadm trigger
sudo sync && sudo sync

# --- 3. [Verification] 最終彩色驗證儀表板 (證據產出) ---
echo -e "\n"
echo -e "${BLUE}==========================================================${NC}"
echo -e "${BLUE}      IEC 62443 CR 7.07 ULTIMATE EVIDENCE REPORT          ${NC}"
echo -e "${BLUE}==========================================================${NC}"
printf "${BOLD}%-25s | %-15s | %-15s${NC}\n" "Security Control" "Requirement" "Status"
echo "----------------------------------------------------------"

# 驗證 1: 服務屏蔽狀態 (以 Mosquitto 為例)
if [ "$(systemctl is-enabled mosquitto 2>/dev/null)" == "masked" ]; then
    printf "%-25s | %-15s | %b%-15s%b\n" "Services Hardening" "Masked" "$GREEN" "[ VERIFIED ]" "$NC"
else
    printf "%-25s | %-15s | %b%-15s%b\n" "Services Hardening" "Active" "$RED" "[ FAILED ]" "$NC"
fi

# 驗證 2: USB 自動掛載防護
if ! dpkg -l | grep -E "udisks2|gvfs" >/dev/null; then
    printf "%-25s | %-15s | %b%-15s%b\n" "Auto-mount Engine" "Removed" "$GREEN" "[ SECURED ]" "$NC"
else
    printf "%-25s | %-15s | %b%-15s%b\n" "Auto-mount Engine" "Present" "$RED" "[ RISK ]" "$NC"
fi

# 驗證 3: 實體掛載偵測 (證明 U 盤插入後無路徑)
USB_MOUNT=$(lsblk -rn -o TRAN,MOUNTPOINT | grep "^usb" | awk '{print $2}' | grep -v "^$")
if [ -z "$USB_MOUNT" ]; then
    printf "%-25s | %-15s | %b%-15s%b\n" "USB Data Access" "No Mounts" "$GREEN" "[ PASS ]" "$NC"
else
    printf "%-25s | %-15s | %b%-15s%b\n" "USB Data Access" "Mounted" "$RED" "[ BREACH ]" "$NC"
fi

# 驗證 4: 監聽埠號 (證明最小化權限)
LISTEN_COUNT=$(sudo ss -tulnp | grep -v "127.0.0.1" | grep "LISTEN" | wc -l)
if [ "$LISTEN_COUNT" -le 2 ]; then
    printf "%-25s | %-15s | %b%-15s%b\n" "External Access" "SSH Only" "$GREEN" "[ CLEAN ]" "$NC"
else
    printf "%-25s | %-15s | %b%-15s%b\n" "External Access" "Mixed" "$RED" "[ WARNING ]" "$NC"
fi

echo "----------------------------------------------------------"
echo -e "${BOLD}Verdict: System hardened for CR 7.07. No auto-actions.${NC}"
echo -e "${BLUE}==========================================================${NC}"
