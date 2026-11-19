#!/bin/sh

CONF_FILE="/etc/cellular_guard/cellular_env.conf"
GUARD_DIR="/mnt/data/cellular_guard"
CONF_BAK="${GUARD_DIR}/cellular_env.conf.bak"
GUARD_LOG="${GUARD_DIR}/cellular_guard.log"
STATUS_FILE="${GUARD_DIR}/status"
STATE_FILE="${GUARD_DIR}/gradient_state"
DRILL_LOG="${GUARD_DIR}/drill_verify.log"

mkdir -p "$GUARD_DIR"
: > "$DRILL_LOG"

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
    printf "[%s] %s\n" "$TS" "$msg" >> "$DRILL_LOG"
}

CLEANED=0
cleanup() {
    [ "$CLEANED" -eq 1 ] && return
    CLEANED=1
    trap - EXIT INT TERM
    iptables -D OUTPUT -o wwan0 -p icmp -j DROP 2>/dev/null || true
    [ -n "$TAIL_PID" ] && kill -9 "$TAIL_PID" 2>/dev/null || true
    if [ -f "$CONF_BAK" ]; then
        mv -f "$CONF_BAK" "$CONF_FILE"
        log_both "$BLUE" "[CLEANUP] Restored original $CONF_FILE and restarting quectel-watchdog.service..."
        systemctl restart quectel-watchdog.service 2>/dev/null || true
    fi
    sync
    log_both "$CYAN" "[SAVED] Full persistent verification log saved at: $DRILL_LOG"
}
trap cleanup EXIT
trap 'cleanup; exit 130' INT TERM

log_both "$CYAN" "=================================================================="
log_both "$CYAN" "Cellular Guard V2.0 — Real-World Keepalive & Anti-Flapping Drill"
log_both "$CYAN" "Persistent Drill Log : $DRILL_LOG"
log_both "$CYAN" "Persistent Guard Log : $GUARD_LOG"
log_both "$CYAN" "=================================================================="

# 1. Hardware & Status Check
log_both "$CYAN" "--- [STEP 1] Verifying Hardware & Current Persistent Status ---"
if ! grep -qi "2c7c" /sys/bus/usb/devices/*/idVendor 2>/dev/null; then
    log_both "$YELLOW" "[INFO] No Quectel 4G module (2c7c) detected on USB bus."
    exit 0
fi

CUR_STATUS=$(cat "$STATUS_FILE" 2>/dev/null || echo "none")
log_both "$BLUE" "[INFO] Initial status: $CUR_STATUS"
if [ "$CUR_STATUS" = "sim_error10" ] || [ "$CUR_STATUS" = "sim_error" ]; then
    log_both "$YELLOW" "[WARN] SIM error state ($CUR_STATUS) detected. Insert a valid SIM card to test network gradients."
    exit 1
fi

# 2. Backup production config to /mnt/data and apply accelerated real-action timings
log_both "$CYAN" "--- [STEP 2] Applying Accelerated Timings (With 20s Anti-Flapping Window) ---"
[ -f "$CONF_FILE" ] && cp -f "$CONF_FILE" "$CONF_BAK"

cat << 'EOC' > "$CONF_FILE"
CHECK_INTERVAL=28800
PING_INTERVALS="5 10 15 15"
PING_INTERVAL_NORMAL=5
STABLE_RESET_TIME=20
MAX_SIM_ERROR_COUNT=4
MAX_PING_ERROR_COUNT="2 2 2 2"
MAX_FREQUENCY_ERROR_COUNT_MIN=2
MAX_FREQUENCY_ERROR_COUNT_MAX=2
MAX_LOG_SIZE=100
PING_TARGETS="223.5.5.5 114.114.114.114 8.8.8.8"
MINIPCIE_RESET_NODE="/sys/devices/platform/misc-adv-gpio/minipcie_reset"
EOC
sync

rm -f "$STATE_FILE"
systemctl restart quectel-watchdog.service

touch "$GUARD_LOG"
tail -n 0 -f "$GUARD_LOG" | while IFS= read -r line; do
    printf "%s\n" "$line" >> "$DRILL_LOG"
    case "$line" in
        *"ping network error"*|*"failed"*|*"holding gradient"*)
            printf "${YELLOW}%s${NC}\n" "$line" ;;
        *"restarting modem module"*|*"executing frequency point clearing"*|*"hardware reset"*)
            printf "${RED}%s${NC}\n" "$line" ;;
        *"resetting gradient to 1"*|*"registered"*)
            printf "${GREEN}%s${NC}\n" "$line" ;;
        *)
            printf "%s\n" "$line" ;;
    esac
done &
TAIL_PID=$!

# 3. Verify Pre-Dial Verification & Initial OK
log_both "$CYAN" "--- [STEP 3] Waiting for Pre-Dial Verification & Initial OK State ---"
WAIT_SEC=0
while [ "$WAIT_SEC" -lt 45 ]; do
    if [ "$(cat "$STATUS_FILE" 2>/dev/null)" = "OK" ] && pgrep -x quectel-CM >/dev/null 2>&1; then
        break
    fi
    sleep 3
    WAIT_SEC=$((WAIT_SEC + 3))
done

if [ "$(cat "$STATUS_FILE" 2>/dev/null)" = "OK" ]; then
    log_both "$GREEN" "[PASS] Pre-dial checks passed -> quectel-CM running -> Status=OK"
else
    log_both "$RED" "[FAIL] Failed to reach initial OK state (status=$(cat "$STATUS_FILE" 2>/dev/null))"
    exit 1
fi

# 4. Inject Real Network Blackhole -> Verify Gradient Escalation & Freq Clear
log_both "$CYAN" "--- [STEP 4] Injecting Real Network Blackhole (Verifying Resets & Freq Clear) ---"
DRILL_TS=$(date '+%Y-%m-%d %H:%M:%S')
log_both "$RED" "[ACTION] Dropping outbound ICMP on wwan0 via iptables..."
iptables -I OUTPUT -o wwan0 -p icmp -j DROP

ELAPSED=0
MAX_WAIT=180
FREQ_CLEAR_SEEN=0
NET_ERR_SEEN=0

while [ "$ELAPSED" -lt "$MAX_WAIT" ]; do
    if [ "$NET_ERR_SEEN" -eq 0 ] && [ "$(cat "$STATUS_FILE" 2>/dev/null)" = "network_error" ]; then
        NET_ERR_SEEN=1
        log_both "$GREEN" "[PASS] Status file switched to 'network_error'"
    fi
    if awk -v ts="$DRILL_TS" '$0 >= ts' "$GUARD_LOG" | grep -q "executing frequency point clearing"; then
        FREQ_CLEAR_SEEN=1
        break
    fi
    sleep 3
    ELAPSED=$((ELAPSED + 3))
done

log_both "$GREEN" "[ACTION] Removing iptables DROP rule to allow recovery..."
iptables -D OUTPUT -o wwan0 -p icmp -j DROP 2>/dev/null || true

if [ "$FREQ_CLEAR_SEEN" -eq 1 ]; then
    SAVED_STATE=$(tr '\n' ' ' < "$STATE_FILE" 2>/dev/null || echo "none")
    log_both "$GREEN" "[PASS] Real gradient escalation & frequency clearing verified within ${ELAPSED}s!"
    log_both "$BLUE" "[INFO] Persistent gradient_state before recovery: $SAVED_STATE"
else
    log_both "$RED" "[FAIL] Timed out waiting for real gradient escalation & frequency clearing (${MAX_WAIT}s)"
    exit 1
fi

# 5. Verify Anti-Flapping Hold Window (20s) Before Gradient Reset
log_both "$CYAN" "--- [STEP 5] Verifying Anti-Flapping Hold Window (20s) & Final Gradient Reset ---"
REC_WAIT=0
while [ "$REC_WAIT" -lt 60 ]; do
    if [ "$(cat "$STATUS_FILE" 2>/dev/null)" = "OK" ]; then
        break
    fi
    sleep 3
    REC_WAIT=$((REC_WAIT + 3))
done

if [ "$(cat "$STATUS_FILE" 2>/dev/null)" != "OK" ]; then
    log_both "$YELLOW" "[WARN] Modem still re-registering after frequency clear (status=$(cat "$STATUS_FILE" 2>/dev/null))"
    exit 1
fi

# Check immediately upon OK: gradient MUST still be > 0 (not cleared prematurely)
HOLD_IDX=$(awk -F= '/GRADIENT_IDX/ {print $2}' "$STATE_FILE" 2>/dev/null || echo 0)
if [ "${HOLD_IDX:-0}" -gt 0 ]; then
    log_both "$GREEN" "[PASS] Anti-flapping hold verified: Status=OK, but GRADIENT_IDX=${HOLD_IDX} held during 20s stability window!"
else
    log_both "$RED" "[FAIL] Gradient reset prematurely before STABLE_RESET_TIME (20s) elapsed!"
    exit 1
fi

# Wait full 25s for stability window to complete and verify gradient resets to 0
log_both "$BLUE" "[WAIT] Waiting 25s for continuous healthy stability window to complete..."
sleep 25

FINAL_IDX=$(awk -F= '/GRADIENT_IDX/ {print $2}' "$STATE_FILE" 2>/dev/null || echo -1)
FINAL_STATE=$(tr '\n' ' ' < "$STATE_FILE" 2>/dev/null || echo "none")

if [ "${FINAL_IDX:-1}" -eq 0 ]; then
    log_both "$GREEN" "[PASS] Full 20s stability window completed -> Persistent gradient_state cleared to 0: $FINAL_STATE"
else
    log_both "$RED" "[FAIL] Expected GRADIENT_IDX=0 after stability window, got: $FINAL_STATE"
    exit 1
fi

log_both "$GREEN" "=================================================================="
log_both "$GREEN" "ALL REAL-WORLD KEEPALIVE, GRADIENT & ANTI-FLAPPING DRILLS PASSED!"
log_both "$GREEN" "=================================================================="
