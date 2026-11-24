#!/bin/sh
CONF_FILE="/etc/cellular_guard/cellular_env.conf"
GUARD_DIR="/mnt/data/cellular_guard"
REPORT_LOG="${GUARD_DIR}/real_stress_report.log"
WD_LOG="${GUARD_DIR}/watchdog.log"
mkdir -p "$GUARD_DIR"
: > "$REPORT_LOG"
[ -f "$CONF_FILE" ] && . "$CONF_FILE"

PING_INTERVALS="${PING_INTERVALS:-60 1200 3600 3600}"
MAX_PING_ERROR_COUNT="${MAX_PING_ERROR_COUNT:-3 3 5 12}"
PING_INTERVAL_NORMAL="${PING_INTERVAL_NORMAL:-600}"
STABLE_RESET_TIME="${STABLE_RESET_TIME:-1800}"
MAX_LOG_SIZE="${MAX_LOG_SIZE:-100}"

RED='\033[1;31m'; GREEN='\033[1;32m'; YELLOW='\033[1;33m'; BLUE='\033[1;34m'; CYAN='\033[1;36m'; NC='\033[0m'

log_rep() {
    TS=$(date '+%Y-%m-%d %H:%M:%S')
    printf "${1}[%s] %s${NC}\n" "$TS" "$2"
    printf "[%s] %s\n" "$TS" "$2" >> "$REPORT_LOG"
    SZ=$(wc -c < "$REPORT_LOG" 2>/dev/null || echo 0)
    [ "$SZ" -gt 4194304 ] && tail -n 3000 "$REPORT_LOG" > "${REPORT_LOG}.tmp" && mv -f "${REPORT_LOG}.tmp" "$REPORT_LOG"
    return 0
}

dump_bug() {
    log_rep "$RED" "=== [LOGIC-BUG-DETECTED] $1 ==="
    ps -ef | grep -E "quectel|watchdog" | grep -v grep >> "$REPORT_LOG" 2>&1
    ip -4 addr show wwan0 >> "$REPORT_LOG" 2>&1 || true
    lsusb | grep 2c7c >> "$REPORT_LOG" 2>&1 || true
    sync
}

get_nth() {
    c=0; last=""
    for i in $1; do last="$i"; [ "$c" -eq "$2" ] && echo "$i" && return; c=$((c+1)); done
    echo "$last"
}

calc_durations() {
    total=0; idx=0
    for cnt in $MAX_PING_ERROR_COUNT; do
        iv=$(get_nth "$PING_INTERVALS" "$idx")
        total=$((total + cnt * (iv + 45)))
        idx=$((idx + 1))
    done
    FAULT_DURATION=$((total + 600))
    LAST_IV=$(get_nth "$PING_INTERVALS" "$((idx - 1))")
    RECOVER_DURATION=$((LAST_IV + STABLE_RESET_TIME + 300))
}
calc_durations

check_item() {
    if eval "$1"; then log_rep "$GREEN" "[PASS] $2"; else dump_bug "$3"; fi
}

preflight_audit() {
    log_rep "$CYAN" "--- [PRE-FLIGHT AUDIT] Checking configs & isolation ---"
    check_item '[ -f "$CONF_FILE" ]' "Config loaded: $CONF_FILE" "Missing $CONF_FILE"
    check_item 'grep -q "2c7c" /lib/udev/rules.d/77-mm-ignore-quectel.rules /etc/udev/rules.d/77-mm-ignore-quectel.rules 2>/dev/null' "ModemManager ignore rule active" "Missing MM ignore rule"
    check_item 'grep -q "unmanaged-devices=interface-name:wwan" /etc/NetworkManager/conf.d/unmanaged-wwan.conf 2>/dev/null' "NetworkManager wwan* unmanaged" "Missing NM unmanaged rule"
    check_item 'ls /var/log-persistent/journal/*/system.journal >/dev/null 2>&1' "Persistent system.journal flushed & active" "Persistent journal dir empty (journalctl --flush missing)"
    SLEEP_HOOK=$(ls /lib/systemd/system-sleep/quectel-sleep-hook /usr/lib/systemd/system-sleep/quectel-sleep-hook 2>/dev/null | head -n 1)
    check_item '[ -n "$SLEEP_HOOK" ] && [ -x "$SLEEP_HOOK" ] && ! grep -q "pkill.*quectel-CM" "$SLEEP_HOOK"' "Clean 16mA sleep-hook verified" "Sleep-hook missing or kills quectel-CM"
    check_item 'systemctl is-active --quiet quectel-cm.service && systemctl is-active --quiet quectel-watchdog.service' "quectel-cm & quectel-watchdog active" "Core services not active"
}

clear_blackhole() {
    while iptables -D OUTPUT -o wwan0 -p icmp -j DROP 2>/dev/null; do :; done
}

CLEANED=0
cleanup() {
    [ "$CLEANED" -eq 1 ] && return
    CLEANED=1
    trap - EXIT INT TERM
    clear_blackhole
    [ -n "$JCTL_PID" ] && kill -9 "$JCTL_PID" 2>/dev/null || true
    sync
    log_rep "$CYAN" "[STOP] Endless stress test stopped. Report: $REPORT_LOG"
    exit 0
}
trap cleanup EXIT
trap 'cleanup; exit 130' INT TERM

preflight_audit
log_rep "$CYAN" "=== Cellular Guard V4.0 SELF-AUDIT | Fault=${FAULT_DURATION}s | Recover=${RECOVER_DURATION}s ==="

LAST_FAIL_TS=0; CUR_GRAD=1; EXP_STAGE=1; RECOVER_TS=0

journalctl -u quectel-watchdog.service -f -n 0 -o cat | while IFS= read -r line; do
    NOW=$(date +%s)
    case "$line" in
        *"Pre-dial check passed"*) log_rep "$GREEN" "[PRE-DIAL] $line" ;;
        *"Connectivity check failed"*)
            G_NUM=$(echo "$line" | sed -n 's/.*gradient=\([0-9]*\).*/\1/p')
            [ -n "$G_NUM" ] && [ "$G_NUM" -ne "$CUR_GRAD" ] && dump_bug "Expected gradient=$CUR_GRAD, got $G_NUM ($line)"
            DELTA=""
            if [ "$LAST_FAIL_TS" -gt 0 ]; then
                DIFF=$((NOW - LAST_FAIL_TS)); DELTA=" [interval=${DIFF}s]"
                EXP_IV=$(get_nth "$PING_INTERVALS" "$((CUR_GRAD - 1))")
                [ "$DIFF" -lt $((EXP_IV - 5)) ] && dump_bug "Gradient $CUR_GRAD fired too early: ${DIFF}s < ${EXP_IV}s ($line)"
            fi
            LAST_FAIL_TS="$NOW"
            log_rep "$YELLOW" "[FAIL-AUDIT] ${line}${DELTA}"
            ;;
        *"Stage "*" Recovery"*)
            ST_NUM=$(echo "$line" | sed -n 's/.*Stage \([0-9]*\) Recovery.*/\1/p')
            [ -n "$ST_NUM" ] && [ "$ST_NUM" -ne "$EXP_STAGE" ] && dump_bug "Expected Stage $EXP_STAGE, got Stage $ST_NUM ($line)"
            LAST_FAIL_TS=0; CUR_GRAD=$((CUR_GRAD + 1))
            [ "$EXP_STAGE" -lt 4 ] && EXP_STAGE=$((EXP_STAGE + 1)) || EXP_STAGE=1
            log_rep "$RED" "[RECOVERY-EXEC] $line -> NextExpGrad=$CUR_GRAD"
            ;;
        *"4G connection recovered"*)
            LAST_FAIL_TS=0; RECOVER_TS="$NOW"
            log_rep "$GREEN" "[RECOVERED] $line"
            ;;
        *"Network stable for"*"resetting gradient to 1"*)
            if [ "$RECOVER_TS" -gt 0 ]; then
                STABLE_D=$((NOW - RECOVER_TS))
                [ "$STABLE_D" -lt $((STABLE_RESET_TIME - 10)) ] && dump_bug "Gradient reset too early: ${STABLE_D}s < ${STABLE_RESET_TIME}s"
            fi
            LAST_FAIL_TS=0; CUR_GRAD=1; EXP_STAGE=1
            log_rep "$GREEN" "[GRADIENT-RESET] $line (Verified Anti-Flapping)"
            ;;
        *) printf "[%s] [RAW] %s\n" "$(date '+%Y-%m-%d %H:%M:%S')" "$line" >> "$REPORT_LOG" ;;
    esac
done &
JCTL_PID=$!

CYCLE=1
while true; do
    log_rep "$BLUE" ">>> [CYCLE #${CYCLE}] Phase 1: Injecting wwan0 blackhole for ${FAULT_DURATION}s..."
    CUR_GRAD=1; EXP_STAGE=1; LAST_FAIL_TS=0; RECOVER_TS=0
    clear_blackhole
    iptables -I OUTPUT -o wwan0 -p icmp -j DROP

    C_START=$(date +%s)
    while [ $(($(date +%s) - C_START)) -lt "$FAULT_DURATION" ]; do
        sleep 1800
        ELAPSED=$(($(date +%s) - C_START))
        WD_ST=$(systemctl is-active quectel-watchdog.service 2>/dev/null || echo "dead")
        [ "$WD_ST" != "active" ] && dump_bug "quectel-watchdog died during fault phase ($WD_ST)"
        WLOG_SZ=$(wc -c < "$WD_LOG" 2>/dev/null || echo 0)
        [ "$WLOG_SZ" -gt $(((MAX_LOG_SIZE + 20) * 1024)) ] && dump_bug "watchdog.log exceeded limit: ${WLOG_SZ} bytes"
        log_rep "$BLUE" "[HEARTBEAT] Cycle #${CYCLE} ${ELAPSED}s/${FAULT_DURATION}s | wd=${WD_ST} | log=${WLOG_SZ}B"
        sync
    done

    log_rep "$GREEN" ">>> [CYCLE #${CYCLE}] Phase 2: Removing blackhole & waiting ${RECOVER_DURATION}s for recovery + gradient reset..."
    clear_blackhole
    sleep "$RECOVER_DURATION"

    WWAN_IP=$(ip -4 addr show wwan0 2>/dev/null | awk '/inet / {print $2}' | head -n 1)
    if [ -z "$WWAN_IP" ] || ! ping -I wwan0 -c 2 -W 3 223.5.5.5 >/dev/null 2>&1; then
        dump_bug "Cycle #${CYCLE} failed to recover wwan0 after ${RECOVER_DURATION}s"
    else
        log_rep "$GREEN" "[PING-OK] wwan0=${WWAN_IP} recovered & verified"
    fi

    CM_PID=$(pgrep -x quectel-CM | head -n 1)
    if [ -n "$CM_PID" ]; then
        kill -9 "$CM_PID" 2>/dev/null || true
        sleep 10
        NEW_PID=$(pgrep -x quectel-CM | head -n 1)
        [ -z "$NEW_PID" ] || [ "$NEW_PID" = "$CM_PID" ] && dump_bug "quectel-CM failed to respawn in 10s" \
            || log_rep "$GREEN" "[RESPAWN-OK] quectel-CM respawned (PID=$NEW_PID)"
    fi

    BUGS=$(grep -c "LOGIC-BUG-DETECTED" "$REPORT_LOG" 2>/dev/null || echo 0)
    log_rep "$CYAN" "=== CYCLE #${CYCLE} SUMMARY | wwan0=${WWAN_IP:-NONE} | BugsDetected=${BUGS} ==="
    sync
    CYCLE=$((CYCLE + 1))
done

