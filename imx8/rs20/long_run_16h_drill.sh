#!/bin/sh

GUARD_DIR="/mnt/data/cellular_guard"
GUARD_LOG="${GUARD_DIR}/cellular_guard.log"
STATUS_FILE="${GUARD_DIR}/status"
STATE_FILE="${GUARD_DIR}/gradient_state"
FULL_LOG="${GUARD_DIR}/long_run_16h.log"

# 預設持續斷網壓測 16.5 小時 (59400 秒)，完整覆蓋第 1 ~ 第 4 梯度共 4 次重啟
BLACKHOLE_DURATION="${1:-59400}"

mkdir -p "$GUARD_DIR"
: > "$FULL_LOG"

RED='\033[1;31m'
GREEN='\033[1;32m'
YELLOW='\033[1;33m'
BLUE='\033[1;34m'
CYAN='\033[1;36m'
NC='\033[0m'

log_both() {
    color="$1"
    msg="$2"
    TS=$(date '+%Y-%m-%d %H:%M:%S')
    printf "${color}[%s] %s${NC}\n" "$TS" "$msg"
    printf "[%s] %s\n" "$TS" "$msg" >> "$FULL_LOG"
}

CLEANED=0
cleanup() {
    [ "$CLEANED" -eq 1 ] && return
    CLEANED=1
    trap - EXIT INT TERM
    iptables -D OUTPUT -o wwan0 -p icmp -j DROP 2>/dev/null || true
    [ -n "$TAIL_PID" ] && kill -9 "$TAIL_PID" 2>/dev/null || true
    sync
    log_both "$CYAN" "[CLEANUP] Removed iptables DROP rule. Full 16h+ log saved at: $FULL_LOG"
}
trap cleanup EXIT
trap 'cleanup; exit 130' INT TERM

log_both "$CYAN" "=================================================================="
log_both "$CYAN" "Cellular Guard V2.0 — 16.5-Hour Real-Time Gradient Endurance Drill"
log_both "$CYAN" "Target Blackhole Duration : ${BLACKHOLE_DURATION}s (~16.5 hours)"
log_both "$CYAN" "Persistent Full Log File  : $FULL_LOG"
log_both "$CYAN" "=================================================================="

# 1. 檢查模組與初始網路狀態
if ! grep -qi "2c7c" /sys/bus/usb/devices/*/idVendor 2>/dev/null; then
    log_both "$RED" "[FAIL] No Quectel 4G module (2c7c) detected!"
    exit 1
fi

log_both "$BLUE" "[WAIT] Waiting up to 45s for initial OK state before injecting 16.5h blackhole..."
W_INIT=0
while [ "$W_INIT" -lt 45 ]; do
    if [ "$(cat "$STATUS_FILE" 2>/dev/null)" = "OK" ] && pgrep -x quectel-CM >/dev/null 2>&1; then
        break
    fi
    sleep 3
    W_INIT=$((W_INIT + 3))
done

if [ "$(cat "$STATUS_FILE" 2>/dev/null)" != "OK" ]; then
    log_both "$RED" "[FAIL] Initial status is not OK (current=$(cat "$STATUS_FILE" 2>/dev/null)). Check SIM card!"
    exit 1
fi
log_both "$GREEN" "[PASS] Initial 4G connection is OK. Starting 16.5-hour continuous fault injection..."

# 2. 即時同步打印 cellular_guard.log 並完整保存至 long_run_16h.log
touch "$GUARD_LOG"
tail -n 0 -f "$GUARD_LOG" | while IFS= read -r line; do
    printf "%s\n" "$line" >> "$FULL_LOG"
    case "$line" in
        *"ping network error"*|*"failed"*|*"holding gradient"*)
            printf "${YELLOW}%s${NC}\n" "$line" ;;
        *"restarting modem module"*|*"executing frequency point clearing"*|*"hardware reset"*)
            printf "${RED}%s${NC}\n" "$line" ;;
        *"resetting gradient to 1"*|*"registered"*|*"recovered"*)
            printf "${GREEN}%s${NC}\n" "$line" ;;
        *)
            printf "%s\n" "$line" ;;
    esac
done &
TAIL_PID=$!

# 3. 注入真實斷網黑洞並持續計時監控 16.5 小時
START_EPOCH=$(date +%s)
log_both "$RED" "[ACTION] Injecting iptables DROP rule on wwan0 ICMP traffic for ${BLACKHOLE_DURATION}s..."
iptables -I OUTPUT -o wwan0 -p icmp -j DROP

while true; do
    NOW_EPOCH=$(date +%s)
    ELAPSED=$((NOW_EPOCH - START_EPOCH))
    [ "$ELAPSED" -ge "$BLACKHOLE_DURATION" ] && break

    # 每 30 分鐘打印一次心跳進度摘要，方便確認長期運行狀態
    if [ $((ELAPSED % 1800)) -lt 60 ] && [ "$ELAPSED" -gt 60 ]; then
        CUR_ST=$(cat "$STATUS_FILE" 2>/dev/null || echo "unknown")
        CUR_GR=$(tr '\n' ' ' < "$STATE_FILE" 2>/dev/null || echo "GRADIENT_IDX=0")
        HRS=$((ELAPSED / 3600))
        MINS=$(((ELAPSED % 3600) / 60))
        log_both "$BLUE" "[HEARTBEAT] Elapsed=${HRS}h${MINS}m (${ELAPSED}s/${BLACKHOLE_DURATION}s) | status=${CUR_ST} | ${CUR_GR}"
        sync
    fi
    sleep 60
done

# 4. 16.5 小時壓測結束，解除斷網並驗收自動恢復與 30 分鐘穩定清零
log_both "$GREEN" "[ACTION] 16.5-hour blackhole completed! Removing iptables DROP rule..."
iptables -D OUTPUT -o wwan0 -p icmp -j DROP 2>/dev/null || true

# 統計整個 16.5 小時期間真實發生的各項動作次數
SOFT_CNT=$(grep -c "sent AT+CFUN=1,1 soft reset" "$FULL_LOG" 2>/dev/null || echo 0)
USB_CNT=$(grep -c "rebinding USB bus" "$FULL_LOG" 2>/dev/null || echo 0)
HW_CNT=$(grep -c "hardware reset triggered" "$FULL_LOG" 2>/dev/null || echo 0)
FREQ_CNT=$(grep -c "executing frequency point clearing" "$FULL_LOG" 2>/dev/null || echo 0)
FINAL_GR=$(tr '\n' ' ' < "$STATE_FILE" 2>/dev/null || echo "none")

log_both "$CYAN" "=================================================================="
log_both "$CYAN" "  16.5-HOUR REAL-TIME ENDURANCE SUMMARY"
log_both "$CYAN" "=================================================================="
log_both "$BLUE" "  - AT+CFUN=1,1 Soft Resets   : $SOFT_CNT"
log_both "$BLUE" "  - USB Bus Rebinds           : $USB_CNT"
log_both "$BLUE" "  - Mini PCIe Hardware Resets : $HW_CNT"
log_both "$BLUE" "  - Frequency Clearings       : $FREQ_CNT"
log_both "$BLUE" "  - Gradient State at 16.5h   : $FINAL_GR"
log_both "$CYAN" "=================================================================="
