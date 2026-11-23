#!/bin/sh

CONF_FILE="/etc/cellular_guard/cellular_env.conf"
GUARD_DIR="/mnt/data/cellular_guard"
REPORT_LOG="${GUARD_DIR}/real_stress_report.log"
MAX_LOG_KB=4096

mkdir -p "$GUARD_DIR"
: > "$REPORT_LOG"
[ -f "$CONF_FILE" ] && . "$CONF_FILE"

RED='\033[1;31m'
GREEN='\033[1;32m'
YELLOW='\033[1;33m'
BLUE='\033[1;34m'
CYAN='\033[1;36m'
NC='\033[0m'

log_rep() {
    color="$1"
    msg="$2"
    TS=$(date '+%Y-%m-%d %H:%M:%S')
    printf "${color}[%s] %s${NC}\n" "$TS" "$msg"
    printf "[%s] %s\n" "$TS" "$msg" >> "$REPORT_LOG"

    if [ -f "$REPORT_LOG" ]; then
        SZ=$(wc -c < "$REPORT_LOG" 2>/dev/null || echo 0)
        if [ "$SZ" -gt $((MAX_LOG_KB * 1024)) ]; then
            tail -n 3000 "$REPORT_LOG" > "${REPORT_LOG}.tmp" && mv -f "${REPORT_LOG}.tmp" "$REPORT_LOG"
        fi
    fi
}

dump_bug_snapshot() {
    reason="$1"
    log_rep "$RED" "==================== [LOGIC-BUG-DETECTED] ===================="
    log_rep "$RED" "Reason: $reason"
    ps -ef | grep -E "quectel|watchdog" | grep -v grep >> "$REPORT_LOG" 2>&1
    ip -4 addr show wwan0 >> "$REPORT_LOG" 2>&1 || true
    lsusb | grep 2c7c >> "$REPORT_LOG" 2>&1 || true
    log_rep "$RED" "=============================================================="
    sync
}

CLEANED=0
cleanup() {
    [ "$CLEANED" -eq 1 ] && return
    CLEANED=1
    trap - EXIT INT TERM
    iptables -D OUTPUT -o wwan0 -p icmp -j DROP 2>/dev/null || true
    [ -n "$JCTL_PID" ] && kill -9 "$JCTL_PID" 2>/dev/null || true
    sync
    log_rep "$CYAN" "[STOP] Real stress test stopped. iptables rule cleaned & network restored. Report: $REPORT_LOG"
    exit 0
}
trap cleanup EXIT
trap 'cleanup; exit 130' INT TERM

log_rep "$CYAN" "=================================================================="
log_rep "$CYAN" "Cellular Guard V2.0 — REAL HARDWARE ENDLESS STRESS & AUDIT"
log_rep "$CYAN" "Mode     : REAL 4G Modem, REAL Services, REAL Fault Injection"
log_rep "$CYAN" "Config   : PING_INTERVALS='${PING_INTERVALS}' | MAX_ERR='${MAX_PING_ERROR_COUNT}'"
log_rep "$CYAN" "Stable   : STABLE_RESET_TIME=${STABLE_RESET_TIME}s | NORMAL=${PING_INTERVAL_NORMAL}s"
log_rep "$CYAN" "Report   : $REPORT_LOG (Persistently saved for review)"
log_rep "$CYAN" "=================================================================="

# 實時監聽真機 quectel-watchdog.service 日誌並進行邏輯審計
LAST_FAIL_TS=0
CUR_EXP_GRADIENT=1

journalctl -u quectel-watchdog.service -f -n 0 -o cat | while IFS= read -r line; do
    NOW_TS=$(date +%s)
    case "$line" in
        *"Pre-dial check passed"*)
            log_rep "$GREEN" "[PRE-DIAL] $line"
            ;;
        *"Connectivity check failed"*)
            DELTA_INFO=""
            if [ "$LAST_FAIL_TS" -gt 0 ]; then
                DIFF=$((NOW_TS - LAST_FAIL_TS))
                DELTA_INFO=" [measured_interval=${DIFF}s]"
                # 檢查是否出現間隔異常（例如預期 1200s 卻在 30s 內連續失敗，排除第一次）
                if [ "$CUR_EXP_GRADIENT" -eq 2 ] && [ "$DIFF" -lt 1100 ]; then
                    dump_bug_snapshot "Gradient 2 expected ~1200s interval, but failed again in ${DIFF}s! ($line)"
                elif [ "$CUR_EXP_GRADIENT" -ge 3 ] && [ "$DIFF" -lt 3400 ]; then
                    dump_bug_snapshot "Gradient ${CUR_EXP_GRADIENT} expected ~3600s interval, but failed again in ${DIFF}s! ($line)"
                fi
            fi
            LAST_FAIL_TS="$NOW_TS"
            log_rep "$YELLOW" "[FAIL-AUDIT] ${line}${DELTA_INFO}"
            ;;
        *"Stage "*" Recovery"*)
            LAST_FAIL_TS=0
            CUR_EXP_GRADIENT=$((CUR_EXP_GRADIENT + 1))
            log_rep "$RED" "[RECOVERY-EXEC] $line -> Next Expected Gradient=${CUR_EXP_GRADIENT}"
            ;;
        *"Network stable for"*"resetting gradient to 1"*)
            LAST_FAIL_TS=0
            CUR_EXP_GRADIENT=1
            log_rep "$GREEN" "[GRADIENT-RESET] $line (Verified Anti-Flapping Reset)"
            ;;
        *"4G connection recovered"*)
            LAST_FAIL_TS=0
            log_rep "$GREEN" "[RECOVERED] $line"
            ;;
        *"standby"*|*"Boot check"*|*"quectel-CM process not running"*)
            log_rep "$YELLOW" "[STATE-CHANGE] $line"
            ;;
        *)
            printf "[%s] [RAW] %s\n" "$(date '+%Y-%m-%d %H:%M:%S')" "$line" >> "$REPORT_LOG"
            ;;
    esac
done &
JCTL_PID=$!

# 無限循環實戰壓測：每輪 16.5 小時真實斷網梯度攀升 + 40 分鐘真實恢復與穩定期清零驗證
CYCLE=1
while true; do
    log_rep "$BLUE" ">>> [REAL CYCLE #${CYCLE}] Injecting REAL wwan0 blackhole for 16.5h (59400s)..."
    CUR_EXP_GRADIENT=1
    LAST_FAIL_TS=0
    iptables -D OUTPUT -o wwan0 -p icmp -j DROP 2>/dev/null || true
    iptables -I OUTPUT -o wwan0 -p icmp -j DROP

    C_START=$(date +%s)
    while [ $(($(date +%s) - C_START)) -lt 59400 ]; do
        sleep 1800
        ELAPSED=$(($(date +%s) - C_START))
        WD_ST=$(systemctl is-active quectel-watchdog.service 2>/dev/null || echo "dead")
        if [ "$WD_ST" != "active" ]; then
            dump_bug_snapshot "quectel-watchdog.service died unexpectedly during fault phase (status=$WD_ST)!"
        fi
        log_rep "$BLUE" "[HEARTBEAT] Cycle #${CYCLE} Fault Elapsed=${ELAPSED}s/59400s | watchdog=${WD_ST} | exp_grad=${CUR_EXP_GRADIENT}"
        sync
    done

    log_rep "$GREEN" ">>> [REAL CYCLE #${CYCLE}] 16.5h fault phase finished. Removing blackhole & verifying 40m (2400s) recovery + gradient reset..."
    iptables -D OUTPUT -o wwan0 -p icmp -j DROP 2>/dev/null || true
    sleep 2400

    WWAN_IP=$(ip -4 addr show wwan0 2>/dev/null | awk '/inet / {print $2}' | head -n 1)
    if [ -z "$WWAN_IP" ]; then
        dump_bug_snapshot "Cycle #${CYCLE} failed to recover wwan0 IP within 40 minutes after removing blackhole!"
    fi

    S1=$(grep -c "Stage 1 Recovery" "$REPORT_LOG" 2>/dev/null || echo 0)
    S2=$(grep -c "Stage 2 Recovery" "$REPORT_LOG" 2>/dev/null || echo 0)
    S3=$(grep -c "Stage 3 Recovery" "$REPORT_LOG" 2>/dev/null || echo 0)
    S4=$(grep -c "Stage 4 Recovery" "$REPORT_LOG" 2>/dev/null || echo 0)
    BUGS=$(grep -c "LOGIC-BUG-DETECTED" "$REPORT_LOG" 2>/dev/null || echo 0)

    log_rep "$CYAN" "=================================================================="
    log_rep "$CYAN" "  REAL CYCLE #${CYCLE} AUDIT SUMMARY (wwan0=${WWAN_IP:-NONE})"
    log_rep "$CYAN" "  Stage1=${S1} | Stage2=${S2} | Stage3=${S3} | Stage4=${S4} | BugsDetected=${BUGS}"
    log_rep "$CYAN" "=================================================================="
    sync
    CYCLE=$((CYCLE + 1))
done

