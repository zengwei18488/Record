#!/bin/bash

# =================================================================
# Script Name: IEC62443_CR7_04_SingleFile_Schedule.sh
# Purpose: Configure Automated Backup via Single /etc/crontab File
# Target: Debian 12 (Linaro/Rockchip)
# =================================================================

# 顏色定義
BLUE='\033[1;34m'
GREEN='\033[0;32m'
BOLD='\033[1m'
NC='\033[0m'

echo -e "${BLUE}Configuring CR 7.4 Automated Backup via /etc/crontab...${NC}"

# --- 1. 定義路徑 ---
TIMESHIFT_CFG="/etc/timeshift/default.json"
CRONTAB_FILE="/etc/crontab"

# --- 2. 確保環境為可寫 (針對嵌入式系統) ---
sudo mount -o remount,rw / 2>/dev/null

# --- 3. 備份與修改 Timeshift 設定 ---
if [ -f "$TIMESHIFT_CFG" ]; then
    sudo cp "$TIMESHIFT_CFG" "${TIMESHIFT_CFG}.bak"
    # 開啟每日備份排程
    sudo sed -i 's/"schedule_daily" : "false"/"schedule_daily" : "true"/' "$TIMESHIFT_CFG"
    echo "Timeshift config updated and backed up."
else
    echo -e "\033[0;31mError: Timeshift config not found at $TIMESHIFT_CFG\033[0m"
    exit 1
fi

# --- 4. 停止圖形界面干擾 ---
pidof timeshift-gtk && sudo killall timeshift-gtk 2>/dev/null

# --- 5. 修改 /etc/crontab (單一檔案注入) ---
echo "Injecting schedule into $CRONTAB_FILE..."

# 先移除舊的紀錄以免重複
sudo sed -i '/timeshift --check/d' "$CRONTAB_FILE"

# 注入新規則：每小時執行一次 (或測試用改為 * * * * * )
# 格式：分鐘 小時 日 月 週 使用者 指令
echo "0 * * * * root timeshift --check --scripted" | sudo tee -a "$CRONTAB_FILE" > /dev/null

# --- 6. 持久化與重啟 ---
# 關鍵：強制寫入硬碟並重啟服務
sudo sync
sudo sync
sudo systemctl restart cron

echo -e "\n"
echo -e "${BLUE}==========================================================${NC}"
echo -e "${BLUE}      IEC 62443 CR 7.4 SINGLE-FILE VERIFICATION           ${NC}"
echo -e "${BLUE}==========================================================${NC}"
printf "${BOLD}%-25s | %-20s${NC}\n" "Control Item" "Status"
echo "----------------------------------------------------------"

# 驗證 1: Crontab 內容
if grep -q "timeshift --check" "$CRONTAB_FILE"; then
    printf "%-25s | ${GREEN}%-20s${NC}\n" "Crontab Entry" "[ INJECTED ]"
else
    printf "%-25s | \033[0;31m%-20s\033[0m\n" "Crontab Entry" "[ FAILED ]"
fi

# 驗證 2: 服務狀態
if systemctl is-active --quiet cron; then
    printf "%-25s | ${GREEN}%-20s${NC}\n" "Cron Service" "[ RUNNING ]"
fi

echo "----------------------------------------------------------"
echo -e "Note: Verification entry added to the bottom of $CRONTAB_FILE"
echo -e "${BLUE}==========================================================${NC}"
