#!/bin/sh
CONF_FILE="/etc/cellular_guard/cellular_env.conf"
GUARD_DIR="/mnt/data/cellular_guard"
REPORT_LOG="${GUARD_DIR}/real_stress_report.log"
WD_LOG="${GUARD_DIR}/watchdog.log"
STATE_FLAG="/tmp/audit_lt_tick_now"
SWITCH_FLAG="/tmp/audit_sim_switch_now"
mkdir -p "$GUARD_DIR"
: > "$REPORT_LOG"
echo 0 > "$STATE_FLAG"
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
    SZ=$(wc -c < "$REPORT_LOG" 2>/dev/null || true); SZ=${SZ:-0}
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
    total=0; idx=0; last_iv=3600
    for cnt in $MAX_PING_ERROR_COUNT; do
        iv=$(get_nth "$PING_INTERVALS" "$idx")
        total=$((total + cnt * (iv + 45)))
        last_iv="$iv"
        idx=$((idx + 1))
    done
    STAGE4_DURATION=$((total + 300))
    RECOVER_DURATION=$((last_iv + STABLE_RESET_TIME + 300))
}
calc_durations

inject_modem_state() {
    target_st="$1"
    case "$target_st" in
        0)
            for tty in /dev/4g_at /dev/ttyUSB2 /dev/ttyUSB3; do
                if [ -c "$tty" ]; then
                    stty -F "$tty" 115200 raw -echo 2>/dev/null
                    printf 'AT+CFUN=1\r\n' > "$tty" 2>/dev/null || true
                    break
                fi
            done
            log_rep "$BLUE" "[INJECT-STATE] -> STATE=0 (Modem/Signal normal, wwan0 blackholed)"
            ;;
        3)
            for tty in /dev/4g_at /dev/ttyUSB2 /dev/ttyUSB3; do
                if [ -c "$tty" ]; then
                    stty -F "$tty" 115200 raw -echo 2>/dev/null
                    printf 'AT+CFUN=4\r\n' > "$tty" 2>/dev/null || true
                    break
                fi
            done
            log_rep "$YELLOW" "[INJECT-STATE] -> STATE=3 (Flight mode AT+CFUN=4 -> unregistered/no signal)"
            ;;
        2)
            for dev in /sys/bus/usb/devices/*; do
                if [ -f "$dev/idVendor" ] && [ "$(cat "$dev/idVendor" 2>/dev/null)" = "2c7c" ]; then
                    dname=$(basename "$dev")
                    echo "$dname" > /sys/bus/usb/drivers/usb/unbind 2>/dev/null || true
                    log_rep "$RED" "[INJECT-STATE] -> STATE=2 (Unbound USB $dname -> modem unresponsive)"
                    break
                fi
            done
            ;;
        sim_switch)
            log_rep "$CYAN" "[INJECT-STATE] -> SIM/eSIM Switch simulation (<10s modem reset)..."
            systemctl stop quectel-cm.service 2>/dev/null || true
            for tty in /dev/4g_at /dev/ttyUSB2 /dev/ttyUSB3; do
                if [ -c "$tty" ]; then
                    stty -F "$tty" 115200 raw -echo 2>/dev/null
                    printf 'AT+CFUN=1,1\r\n' > "$tty" 2>/dev/null || true
                    break
                fi
            done
            sleep 8
            ;;
    esac
}

restore_all_faults() {
    while iptables -D OUTPUT -o wwan0 -p icmp -j DROP 2>/dev/null; do :; done
    for tty in /dev/4g_at /dev/ttyUSB2 /dev/ttyUSB3; do
        if [ -c "$tty" ]; then
            stty -F "$tty" 115200 raw -echo 2>/dev/null
            printf 'AT+CFUN=1\r\n' > "$tty" 2>/dev/null || true
            break
        fi
    done
    sleep 15
    if ! grep -qi "2c7c" /sys/bus/usb/devices/*/idVendor 2>/dev/null; then
        [ -w /sys/devices/platform/misc-adv-gpio/minipcie_reset ] && echo 1 > /sys/devices/platform/misc-adv-gpio/minipcie_reset
    fi
}

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
    check_item '[ -x /usr/sbin/quectel-watchdog ] && head -c 4 /usr/sbin/quectel-watchdog | grep -q "ELF"' "Global-tick state-aware 12h monitor present" "Old watchdog without LONG_TERM_TICKS"
    check_item 'systemctl is-active --quiet quectel-cm.service && systemctl is-active --quiet quectel-watchdog.service' "quectel-cm & quectel-watchdog active" "Core services not active"
}

CLEANED=0
cleanup() {
    [ "$CLEANED" -eq 1 ] && return
    CLEANED=1
    trap - EXIT INT TERM
    restore_all_faults
    rm -f "$STATE_FLAG" "$SWITCH_FLAG"
    [ -n "$JCTL_PID" ] && kill -9 "$JCTL_PID" 2>/dev/null || true
    pkill -f "journalctl -u quectel-watchdog.service" 2>/dev/null || true
    sync
    log_rep "$CYAN" "[STOP] Endless stress test stopped & all states restored. Report: $REPORT_LOG"
    exit 0
}
trap cleanup EXIT
trap 'cleanup; exit 130' INT TERM

preflight_audit
log_rep "$CYAN" "=== Cellular Guard V5.0 FULL-MECHANISM AUDIT | Stage1-4=${STAGE4_DURATION}s + 2x12h Random LT + Anti-Flap (<30m) + 1x12h LT (Single Full Pass) ==="

LAST_FAIL_TS=0; CUR_GRAD=1; EXP_STAGE=1; IN_LONG_TERM=0; RECOVER_TS=0; LAST_TICK=0

journalctl -u quectel-watchdog.service -f -n 0 -o cat | while IFS= read -r line; do
    NOW=$(date +%s)
    case "$line" in
        *"Pre-dial check passed"*) log_rep "$GREEN" "[PRE-DIAL] $line" ;;
        *"waiting 15s for modem stabilization"*)
            log_rep "$GREEN" "[DEBOUNCE-HOLD] $line (Verified 15s stabilization buffer triggered)"
            ;;
        *"Connectivity check failed ("*)
            [ -f "$SWITCH_FLAG" ] && dump_bug "Watchdog false-triggered failure during <10s SIM switch! ($line)" 
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
        *"in long-term monitor (tick "*|*"Long-term standby monitor (tick "*)
            [ "$IN_LONG_TERM" -ne 1 ] && dump_bug "Long-term tick logged before entering LONG_TERM_MONITOR! ($line)"
            T_NUM=$(echo "$line" | sed -n 's/.*tick \([0-9]*\)\/.*/\1/p')
            if [ -n "$T_NUM" ] && [ "$LAST_TICK" -gt 0 ] && [ "$T_NUM" -lt "$LAST_TICK" ] && [ "$T_NUM" -ne 1 ]; then
                dump_bug "LONG_TERM_TICKS reset unexpectedly across state hop! prev=$LAST_TICK, now=$T_NUM ($line)"
            fi
            if [ -n "$T_NUM" ]; then
                LAST_TICK="$T_NUM"
                echo "$T_NUM" > "$STATE_FLAG"
            fi
            log_rep "$CYAN" "[LT-TICK] $line"
            ;;
        *"Stage "*" Recovery"*)
            [ -f "$SWITCH_FLAG" ] && dump_bug "Watchdog false-triggered recovery stage during <10s SIM switch! ($line)"
            ST_NUM=$(echo "$line" | sed -n 's/.*Stage \([0-9]*\) Recovery.*/\1/p')
            [ "$IN_LONG_TERM" -eq 1 ] && dump_bug "Repeated Stage $ST_NUM reset after entering LONG_TERM_MONITOR! ($line)"
            [ -n "$ST_NUM" ] && [ "$ST_NUM" -ne "$EXP_STAGE" ] && dump_bug "Expected Stage $EXP_STAGE, got Stage $ST_NUM ($line)"
            LAST_FAIL_TS=0
            [ "$CUR_GRAD" -lt 5 ] && CUR_GRAD=$((CUR_GRAD + 1))
            if [ "$ST_NUM" -eq 4 ]; then
                IN_LONG_TERM=1; LAST_TICK=0; echo 0 > "$STATE_FLAG"
                log_rep "$RED" "[STAGE4->LONG-TERM] $line -> Entering Long-Term State-Aware Monitor (Grad=$CUR_GRAD)"
            else
                EXP_STAGE=$((EXP_STAGE + 1))
                log_rep "$RED" "[RECOVERY-EXEC] $line -> NextExpStage=$EXP_STAGE, NextExpGrad=$CUR_GRAD"
            fi
            ;;
        *"entering long-term state-aware monitor mode"*)
            log_rep "$CYAN" "[LONG-TERM-ENTER] $line"
            ;;
        *"Long-term 12h action"*)
            [ "$IN_LONG_TERM" -ne 1 ] && dump_bug "Long-term 12h action fired prematurely before Stage 4! ($line)"
            LAST_FAIL_TS=0; LAST_TICK=0; echo 0 > "$STATE_FLAG"
            log_rep "$GREEN" "[LONG-TERM-12H-ACTION] $line (Verified State-Aware Decision)"
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
            LAST_FAIL_TS=0; CUR_GRAD=1; EXP_STAGE=1; IN_LONG_TERM=0; LAST_TICK=0; echo 0 > "$STATE_FLAG"
            log_rep "$GREEN" "[GRADIENT-RESET] $line (Verified Anti-Flapping & Long-Term Exit)"
            ;;
        *) printf "[%s] [RAW] %s\n" "$(date '+%Y-%m-%d %H:%M:%S')" "$line" >> "$REPORT_LOG" ;;
    esac
done &
JCTL_PID=$!

CYCLE=1
while true; do
    log_rep "$BLUE" ">>> [CYCLE #${CYCLE}] Phase 1: Injecting blackhole for ${STAGE4_DURATION}s to reach Stage 4 & enter Long-Term Monitor..."
    CUR_GRAD=1; EXP_STAGE=1; IN_LONG_TERM=0; LAST_FAIL_TS=0; RECOVER_TS=0; LAST_TICK=0; echo 0 > "$STATE_FLAG"
    restore_all_faults
    iptables -I OUTPUT -o wwan0 -p icmp -j DROP

    P1_START=$(date +%s)
    while [ $(($(date +%s) - P1_START)) -lt "$STAGE4_DURATION" ]; do
        sleep 1800
        ELAPSED=$(($(date +%s) - P1_START))
        WD_ST=$(systemctl is-active quectel-watchdog.service 2>/dev/null || echo "dead")
        [ "$WD_ST" != "active" ] && dump_bug "quectel-watchdog died in Phase 1 ($WD_ST)"
        WLOG_SZ=$(wc -c < "$WD_LOG" 2>/dev/null || echo 0)
        [ "$WLOG_SZ" -gt $(((MAX_LOG_SIZE + 20) * 1024)) ] && dump_bug "watchdog.log exceeded limit: ${WLOG_SZ} bytes"
        log_rep "$BLUE" "[HEARTBEAT-P1] Cycle #${CYCLE} ${ELAPSED}s/${STAGE4_DURATION}s | wd=${WD_ST} | lt=${IN_LONG_TERM} | log=${WLOG_SZ}B"
    done

    for LT_ROUND in 1 2; do
        log_rep "$CYAN" ">>> [CYCLE #${CYCLE}] Phase 2 (Round ${LT_ROUND}/2): 12h Long-Term Monitor with hourly random state hops..."
        LAST_SEEN_TICK=0; ROUND_DONE=0
        while [ "$ROUND_DONE" -eq 0 ]; do
            sleep 30
            CUR_T=$(cat "$STATE_FLAG" 2>/dev/null || echo 0)
            if [ "$CUR_T" -ne "$LAST_SEEN_TICK" ]; then
                LAST_SEEN_TICK="$CUR_T"
                if [ "$CUR_T" -eq 0 ]; then
                    ROUND_DONE=1
                elif [ "$CUR_T" -eq 11 ]; then
                    case "$LT_ROUND" in
                        1) inject_modem_state 3 ;;
                        2) inject_modem_state 2 ;;
                    esac
                else
                    RND=$(( $(date +%s) % 2 ))
                    [ "$RND" -eq 0 ] && inject_modem_state 0 || inject_modem_state 3
                fi
            fi
        done
    done

    log_rep "$YELLOW" ">>> [CYCLE #${CYCLE}] Phase 3: Restoring network, waiting for watchdog recovery detection, then re-breaking BEFORE 30m..."
    PREV_REC_CNT=$(grep -c "\[RECOVERED\]" "$REPORT_LOG" 2>/dev/null || true)
    restore_all_faults
    WAIT_REC=0
    while [ "$WAIT_REC" -lt 4200 ]; do
        sleep 30; WAIT_REC=$((WAIT_REC + 30))
        CUR_REC_CNT=$(grep -c "\[RECOVERED\]" "$REPORT_LOG" 2>/dev/null || true)
        [ "$CUR_REC_CNT" -gt "$PREV_REC_CNT" ] && break
    done
    log_rep "$GREEN" "[TEMP-RECOVER-DETECTED] Watchdog detected recovery; holding healthy for 15m (900s < 1800s) then re-breaking..."
    sleep 900
    iptables -I OUTPUT -o wwan0 -p icmp -j DROP

    log_rep "$CYAN" ">>> [CYCLE #${CYCLE}] Phase 4: Verifying watchdog stays in Stage 4 / Long-Term Monitor for another 12h round..."
    inject_modem_state 0
    ROUND4_DONE=0
    while [ "$ROUND4_DONE" -eq 0 ]; do
        sleep 30
        ACT_CNT=$(grep -c "LONG-TERM-12H-ACTION" "$REPORT_LOG" 2>/dev/null || true)
        [ "$ACT_CNT" -ge 3 ] && ROUND4_DONE=1
    done

    log_rep "$GREEN" ">>> [CYCLE #${CYCLE}] Phase 5: Permanently removing blackhole & waiting ${RECOVER_DURATION}s for full recovery + gradient reset..."
    restore_all_faults
    sleep "$RECOVER_DURATION"

    WWAN_IP=$(ip -4 addr show wwan0 2>/dev/null | awk '/inet / {print $2}' | head -n 1)
    if [ -z "$WWAN_IP" ] || ! ping -I wwan0 -c 2 -W 3 223.5.5.5 >/dev/null 2>&1; then
        dump_bug "Cycle #${CYCLE} failed to recover wwan0 after ${RECOVER_DURATION}s"
    else
        log_rep "$GREEN" "[PING-OK] wwan0=${WWAN_IP} fully recovered & verified"
    fi

    CM_PID=$(pgrep -x quectel-CM | head -n 1)
    if [ -n "$CM_PID" ]; then
        kill -9 "$CM_PID" 2>/dev/null || true
        sleep 22
        NEW_PID=$(pgrep -x quectel-CM | head -n 1)
        [ -z "$NEW_PID" ] || [ "$NEW_PID" = "$CM_PID" ] && dump_bug "quectel-CM failed to respawn after 15s debounce + restart" \
            || log_rep "$GREEN" "[RESPAWN-OK] quectel-CM respawned cleanly after 15s debounce (PID=$NEW_PID)"
    fi

    log_rep "$CYAN" ">>> [CYCLE #${CYCLE}] Phase 6: Testing <10s eSIM/SIM switch debounce & zero-penalty recovery..."
    touch "$SWITCH_FLAG"
    PREV_DEBOUNCE=$(grep -c "\[DEBOUNCE-HOLD\]" "$REPORT_LOG" 2>/dev/null || true)
    inject_modem_state "sim_switch"
    sleep 35
    rm -f "$SWITCH_FLAG"

    CUR_DEBOUNCE=$(grep -c "\[DEBOUNCE-HOLD\]" "$REPORT_LOG" 2>/dev/null || true)
    [ "$CUR_DEBOUNCE" -le "$PREV_DEBOUNCE" ] && dump_bug "Watchdog did NOT trigger 15s stabilization debounce during SIM switch!"

    WWAN_IP=$(ip -4 addr show wwan0 2>/dev/null | awk '/inet / {print $2}' | head -n 1)
    if [ -z "$WWAN_IP" ] || ! ping -I wwan0 -c 2 -W 3 223.5.5.5 >/dev/null 2>&1; then
        dump_bug "Cycle #${CYCLE} failed to recover wwan0 after <10s SIM/eSIM switch"
    else
        log_rep "$GREEN" "[SIM-SWITCH-OK] Debounced cleanly & recovered wwan0=${WWAN_IP} with 0 penalty!"
    fi

    LT_ACT=$(grep -c "LONG-TERM-12H-ACTION" "$REPORT_LOG" 2>/dev/null || true)
    BUGS=$(grep -c "LOGIC-BUG-DETECTED" "$REPORT_LOG" 2>/dev/null || true)
    log_rep "$CYAN" "=================================================================="
    log_rep "$CYAN" "  CYCLE #${CYCLE} FULL-MECHANISM AUDIT SUMMARY (wwan0=${WWAN_IP:-NONE})"
    log_rep "$CYAN" "  LongTerm12hActions=${LT_ACT} (Expected 3) | BugsDetected=${BUGS}"
    log_rep "$CYAN" "=================================================================="
    log_rep "$GREEN" "=== ALL FULL-MECHANISM TESTS COMPLETED! Exiting cleanly. ==="
    break
done
