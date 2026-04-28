#!/bin/bash

# =================================================================
# Script Name: IEC62443_CR7_02_Resource_Management_Final.sh
# Purpose: Configure & Verify Resource Quotas (CPU/Memory)
# Compliance: IEC 62443-4-2 CR 7.2 (Resource Management)
# Target: Debian 12 (Linaro/Rockchip)
# =================================================================

# 定義顏色
GREEN='\033[0;32m'
RED='\033[0;31m'
BLUE='\033[1;34m'
BOLD='\033[1m'
NC='\033[0m'

echo -e "${BLUE}Starting IEC 62443 CR 7.2 Resource Management Setup...${NC}"

# --- 1. 環境驗證 (cgroup v2) ---
echo -n "Verifying cgroup v2 support..."
if mount | grep -q "cgroup2 on /sys/fs/cgroup type cgroup2"; then
    echo -e "${GREEN} [OK]${NC}"
else
    echo -e "${RED} [FAIL] cgroup v2 not found. Check kernel settings.${NC}"
    exit 1
fi

# --- 2. 建立測試組件與服務 ---
echo "Configuring CPU Quota Test Service (Limit: 20%)..."

# 建立無限迴圈腳本
sudo tee /usr/local/bin/cpu-hog.sh << EOT > /dev/null
#!/bin/bash
while true; do :; done
EOT
sudo chmod +x /usr/local/bin/cpu-hog.sh

# 建立受控 Systemd 服務 (CR 7.2 核心配置)
sudo tee /etc/systemd/system/cpu-hog.service << EOT > /dev/null
[Unit]
Description=IEC 62443 CR 7.02 Resource Management Test
[Service]
ExecStart=/usr/local/bin/cpu-hog.sh
CPUAccounting=true
CPUQuota=20%
MemoryAccounting=true
MemoryMax=100M
Restart=always
EOT

sudo systemctl daemon-reload
sudo systemctl enable --now cpu-hog.service

# --- 3. 數據採樣與校驗 ---
echo -e "${BOLD}Sampling real-time metrics...${NC}"
sleep 2
PID=$(pgrep -f cpu-hog.sh)

# 採樣兩次以獲得精確數值
S1=$(top -b -n 2 -d 0.5 -p "$PID" | grep "$PID" | tail -n 1 | awk '{print $9}')
sleep 1; echo -n ".";
S2=$(top -b -n 2 -d 0.5 -p "$PID" | grep "$PID" | tail -n 1 | awk '{print $9}')
AVG_CPU=$(echo "scale=2; ($S1+$S2)/2" | bc)

# --- 4. 產出彩色審計報告 ---
echo -e "\n"
echo -e "${BLUE}==========================================================${NC}"
echo -e "${BLUE}      IEC 62443 CR 7.2 RESOURCE MANAGEMENT REPORT         ${NC}"
echo -e "${BLUE}==========================================================${NC}"
printf "${BOLD}%-25s | %-15s | %-15s${NC}\n" "Requirement Item" "Target/Config" "Measured/Status"
echo "----------------------------------------------------------"

# 判定 CPU Quota
if (( $(echo "$AVG_CPU <= 25.0" | bc -l) )) && (( $(echo "$AVG_CPU >= 15.0" | bc -l) )); then
    STAT_702_LBL="[ PASS ]"
    COLOR_702=$GREEN
else
    STAT_702_LBL="[ FAIL ]"
    COLOR_702=$RED
fi
printf "%-25s | %-15s | %b%-15s%b\n" "CPU Quota Limitation" "20.0%" "$COLOR_702" "$AVG_CPU% $STAT_702_LBL" "$NC"

# 判定 Memory Limit
MEM_SET=$(systemctl show cpu-hog.service -p MemoryMax --value)
if [ "$MEM_SET" == "104857600" ]; then
    printf "%-25s | %-15s | %b%-15s%b\n" "Memory Soft/Hard Limit" "100M" "$GREEN" "[ PASS ]" "$NC"
else
    printf "%-25s | %-15s | %b%-15s%b\n" "Memory Soft/Hard Limit" "100M" "$RED" "[ FAIL ]" "$NC"
fi

echo "----------------------------------------------------------"
# 最終判定
if [ "$COLOR_702" == "$GREEN" ] && [ "$MEM_SET" == "104857600" ]; then
    echo -e "${BOLD}FINAL COMPLIANCE STATUS: ${GREEN}[ PASS ]${NC}"
else
    echo -e "${BOLD}FINAL COMPLIANCE STATUS: ${RED}[ FAIL ]${NC}"
fi
echo -e "${BLUE}==========================================================${NC}"

# --- 5. 清理環境 ---
sudo systemctl stop cpu-hog.service
sudo systemctl disable cpu-hog.service > /dev/null 2>&1
sudo rm /etc/systemd/system/cpu-hog.service
echo "Cleanup: Test service removed. Evidence is ready."
