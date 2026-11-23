#!/bin/sh

CONF_FILE="/etc/cellular_guard/cellular_env.conf"
BACKUP_CONF="/mnt/data/cellular_guard/cellular_env.conf.bak"
GUARD_DIR="/mnt/data/cellular_guard"
VERIFY_LOG="${GUARD_DIR}/verify_4g_now.log"

mkdir -p "$GUARD_DIR"
: > "$VERIFY_LOG"

RED='\033[1;31m'
GREEN='\033[1;32m'
YELLOW='\033[1;33m'
BLUE='\033[1;34m'
CYAN='\033[1;36m'
NC='\033[0m'

log_v() {
    color="$1"
    msg="$2"
    TS=$(date '+%Y-%m-%d %H:%M:%S')
    printf "${color}[%s] %s${NC}\n" "$TS" "$msg"
    printf "[%s] %s\n" "$TS" "$msg" >> "$VERIFY_LOG"
}

CLEANED=0
cleanup() {
    [ "$CLEANED" -eq 1 ] && return
    CLEANED=1
    trap - EXIT INT TERM
    iptables -D OUTPUT -o wwan0 -p icmp -j DROP 2>/dev/null || true
    [ -n "$TAIL_PID" ] && kill -9 "$TAIL_PID" 2>/dev/null || true
    if [ -f "$BACKUP_CONF" ]; then
        mv -f "$BACKUP_CONF" "$CONF_FILE"
        log_v "$CYAN" "[CLEANUP] Restored factory $CONF_FILE and restarting quectel-watchdog.service..."
        systemctl restart quectel-watchdog.service 2>/dev/null || true
    fi
    sync
    log_v "$CYAN" "[SAVED] Full verification log saved at: $VERIFY_LOG"
}
trap cleanup EXIT
trap 'cleanup; exit 130' INT TERM

log_v "$CYAN" "=================================================================="
log_v "$CYAN" "4G Keepalive & Timing Gradient Real-World Verification (~2.5 mins)"
log_v "$CYAN" "Persistent Log: $VERIFY_LOG"
log_v "$CYAN" "=================================================================="

# 1. 檢查硬體與前置體檢狀態
if ! grep -qi "2c7c" /sys/bus/usb/devices/*/idVendor 2>/dev/null; then
    log_v "$RED" "[FAIL] Quectel 4G module (2c7c) not detected!"
    exit 1
fi

if ! ip -4 addr show wwan0 2>/dev/null | grep -q "inet "; then
    log_v "$YELLOW" "[INFO] wwan0 has no IP yet, waiting up to 25s for initial pre-dial & connection..."
    sleep 25
fi

if ip -4 addr show wwan0 2>/dev/null | grep -q "inet "; then
    CUR_IP=$(ip -4 addr show wwan0 | awk '/inet / {print $2}' | head -n 1)
    log_v "$GREEN" "[PASS] Step 1: Pre-dial check & initial connection verified (wwan0=$CUR_IP)"
else
    log_v "$RED" "[FAIL] Step 1: wwan0 failed to obtain IP!"
    exit 1
fi

# 2. 備份配置並寫入加速驗證梯度（5s -> 10s -> 15s，失敗2次升級，穩定期20s）
cp -f "$CONF_FILE" "$BACKUP_CONF"
cat << 'EOF_ACCEL' > "$CONF_FILE"
PING_INTERVALS="5 10 15 20"
MAX_PING_ERROR_COUNT="2 2 2 2"
PING_INTERVAL_NORMAL=10
STABLE_RESET_TIME=20
STANDBY_POLL_INTERVAL=10
PING_TARGETS="223.5.5.5 114.114.114.114"
MINIPCIE_RESET_NODE="/sys/devices/platform/misc-adv-gpio/minipcie_reset"
EOF_ACCEL

log_v "$BLUE" "[STEP 2] Applied accelerated timings (gradients='5 10 15 20', max_err=2, stable_reset=20s)"
systemctl restart quectel-watchdog.service

journalctl -u quectel-watchdog.service -f -n 0 -o cat | while IFS= read -r line; do
    printf "[WATCHDOG] %s\n" "$line" >> "$VERIFY_LOG"
    case "$line" in
        *"Connectivity check failed"*)
            printf "${YELLOW}[WATCHDOG] %s${NC}\n" "$line" ;;
        *"Stage "*" Recovery"*)
            printf "${RED}[WATCHDOG] %s${NC}\n" "$line" ;;
        *"resetting gradient to 1"*|*"Pre-dial check passed"*|*"recovered"*)
            printf "${GREEN}[WATCHDOG] %s${NC}\n" "$line" ;;
        *)
            printf "[WATCHDOG] %s\n" "$line" ;;
    esac
done &
TAIL_PID=$!

# 等待看門狗啟動並完成開機體檢（15s 開機延遲 + 約 5s 體檢）
sleep 22

# 3. 注入真實斷網黑洞，驗證梯度 1 (5s) -> Stage 1 重啟服務 -> 梯度 2 (10s) -> Stage 2 軟復位 -> 梯度 3
log_v "$BLUE" "[STEP 3] Injecting real ICMP blackhole on wwan0 to verify gradient escalation..."
iptables -I OUTPUT -o wwan0 -p icmp -j DROP

WAIT_ESC=0
STAGE2_OK=0
while [ "$WAIT_ESC" -lt 120 ]; do
    if grep -q "Stage 2 Recovery" "$VERIFY_LOG"; then
        STAGE2_OK=1
        break
    fi
    sleep 2
    WAIT_ESC=$((WAIT_ESC + 2))
done

iptables -D OUTPUT -o wwan0 -p icmp -j DROP 2>/dev/null || true

if [ "$STAGE2_OK" -eq 1 ]; then
    log_v "$GREEN" "[PASS] Step 3: Gradient escalation (Gradient 1 -> 2 -> 3) & Stage 1/2 recovery verified in ${WAIT_ESC}s!"
else
    log_v "$RED" "[FAIL] Step 3: Did not reach Stage 2 Recovery within 120s."
    exit 1
fi

# 4. 等待網路恢復與 20s 防震盪穩定期滿期，驗證梯度自動清零重置為 1
log_v "$BLUE" "[STEP 4] Waiting for network recovery and 20s stability window to reset gradient to 1..."
WAIT_REC=0
RESET_OK=0
while [ "$WAIT_REC" -lt 70 ]; do
    if grep -q "resetting gradient to 1" "$VERIFY_LOG"; then
        RESET_OK=1
        break
    fi
    sleep 2
    WAIT_REC=$((WAIT_REC + 2))
done

if [ "$RESET_OK" -eq 1 ]; then
    log_v "$GREEN" "[PASS] Step 4: Anti-flapping window completed & gradient reset to 1 verified in ${WAIT_REC}s!"
else
    log_v "$RED" "[FAIL] Step 4: Gradient did not reset to 1 within 70s."
    exit 1
fi

log_v "$CYAN" "=================================================================="
log_v "$CYAN" "  ALL 4G KEEPALIVE & GRADIENT VERIFICATION CHECKS PASSED!"
log_v "$CYAN" "=================================================================="
