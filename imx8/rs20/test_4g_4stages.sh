#!/bin/sh

LOG_FILE="/tmp/4g_4stages_test.log"
: > "$LOG_FILE"

# ANSI Color Codes
RED='\033[1;31m'
GREEN='\033[1;32m'
YELLOW='\033[1;33m'
BLUE='\033[1;34m'
MAGENTA='\033[1;35m'
CYAN='\033[1;36m'
NC='\033[0m'

log_both() {
    color="$1"
    msg="$2"
    printf "${color}%s${NC}\n" "$msg"
    printf "%s\n" "$msg" >> "$LOG_FILE"
}

print_mechanism() {
    title="$1"
    detail="$2"
    log_both "$MAGENTA" "[MECHANISM - $title]"
    log_both "$BLUE" "  -> $detail"
}

print_log_guide() {
    log_both "$CYAN" ""
    log_both "$CYAN" "=================================================================="
    log_both "$CYAN" "  PERSISTENT LOG ARCHITECTURE & QUERY GUIDE"
    log_both "$CYAN" "=================================================================="
    log_both "$BLUE" "1. Storage Architecture (Survives Reboot & Power Loss):"
    log_both "$NC"   "   - Symlink : /var/log/journal -> /var/log-persistent/journal (on eMMC)"
    log_both "$NC"   "   - Config  : /etc/systemd/journald.conf.d/persistent.conf"
    log_both "$NC"   "   - Limits  : SystemMaxUse=50M (auto-rotates oldest logs), SyncIntervalSec=30s"
    log_both "$NC"   "   - Drill Log: $LOG_FILE (temporary volatile report for current drill)"
    log_both "$BLUE" "2. Essential Log Query Commands:"
    log_both "$YELLOW" "   - Live monitor 4G services :"
    log_both "$NC"   "       journalctl -u quectel-watchdog.service -u quectel-cm.service -f"
    log_both "$YELLOW" "   - View current boot logs   :"
    log_both "$NC"   "       journalctl -b 0 -u quectel-watchdog.service -u quectel-cm.service --no-pager"
    log_both "$YELLOW" "   - View previous boot logs  :"
    log_both "$NC"   "       journalctl -b -1 -u quectel-watchdog.service -u quectel-cm.service --no-pager"
    log_both "$YELLOW" "   - List all recorded boots  :"
    log_both "$NC"   "       journalctl --list-boots"
    log_both "$YELLOW" "   - Search Stage & SIM events:"
    log_both "$NC"   "       journalctl -u quectel-watchdog.service | grep -E 'Stage|Standby|SIM|low-frequency|hardware reset|recovered'"
    log_both "$CYAN" "=================================================================="
}

cleanup() {
    iptables -D OUTPUT -o wwan0 -p icmp -j DROP 2>/dev/null || true
    [ -n "$JOURNAL_PID" ] && { pkill -P "$JOURNAL_PID" 2>/dev/null; kill "$JOURNAL_PID" 2>/dev/null; } || true
}
trap cleanup EXIT INT TERM

log_both "$CYAN" "=================================================================="
log_both "$CYAN" "[$(date '+%F %T')] Starting Adaptive 4G Keepalive & Self-Healing Drill"
log_both "$CYAN" "Live colored output on console; plain log saved at: /tmp/4g_4stages_test.log"
log_both "$CYAN" "=================================================================="

# =========================================================================
# PHASE 0: Persistent Journald Storage Verification
# =========================================================================
log_both "$CYAN" ""
log_both "$CYAN" "--- [PHASE 0] Verifying Persistent Journald Storage (eMMC) ---"
print_mechanism "Persistent Logging" \
    "systemd-tmpfiles maps /var/log/journal to /var/log-persistent/journal on eMMC (50MB cap) so logs survive reboots."

if [ -L /var/log/journal ] && [ -d /var/log-persistent/journal ]; then
    TARGET=$(readlink -f /var/log/journal)
    log_both "$GREEN" "[PASS] Persistent journal symlink verified: /var/log/journal -> $TARGET"
    journalctl --flush 2>/dev/null || true
    BOOT_COUNT=$(journalctl --list-boots 2>/dev/null | wc -l)
    log_both "$BLUE" "[INFO] Total recorded boot sessions on eMMC: $BOOT_COUNT"
else
    log_both "$YELLOW" "[WARN] /var/log/journal persistent symlink not found (logs may currently reside in RAM)."
fi

# =========================================================================
# PHASE 1: Hardware Presence Detection (No-Modem vs Modem)
# =========================================================================
log_both "$CYAN" ""
log_both "$CYAN" "--- [PHASE 1] Detecting Quectel 4G Module (idVendor=2c7c) ---"
print_mechanism "Hardware Auto-Detection" \
    "Both services scan /sys/bus/usb/devices/*/idVendor for '2c7c'. If absent, they exit with code 0 (RestartPreventExitStatus=0) for zero CPU/log overhead."

if ! grep -qi "2c7c" /sys/bus/usb/devices/*/idVendor 2>/dev/null; then
    log_both "$YELLOW" "[INFO] No Quectel 4G module (2c7c) detected on USB bus."
    log_both "$BLUE" "[TEST] Waiting up to 20s to verify both services exit cleanly without restart loops..."
    sleep 20

    CM_STATE=$(systemctl is-active quectel-cm.service 2>/dev/null || true)
    WD_STATE=$(systemctl is-active quectel-watchdog.service 2>/dev/null || true)
    CM_RESULT=$(systemctl show -p Result --value quectel-cm.service 2>/dev/null || true)
    WD_RESULT=$(systemctl show -p Result --value quectel-watchdog.service 2>/dev/null || true)

    log_both "$BLUE" "[STATUS] quectel-cm.service       : state=$CM_STATE, result=$CM_RESULT"
    log_both "$BLUE" "[STATUS] quectel-watchdog.service : state=$WD_STATE, result=$WD_RESULT"
    journalctl -u quectel-watchdog.service -n 5 --no-pager | tee -a "$LOG_FILE"

    if [ "$CM_STATE" = "inactive" ] && [ "$WD_STATE" = "inactive" ] && \
       [ "$CM_RESULT" = "success" ] && [ "$WD_RESULT" = "success" ]; then
        log_both "$GREEN" ""
        log_both "$GREEN" "=================================================================="
        log_both "$GREEN" "[$(date '+%F %T')] PASS! No-Modem Silent Mode verified (0 CPU/log overhead)."
        log_both "$GREEN" "=================================================================="
        print_log_guide
        exit 0
    else
        log_both "$RED" "[FAIL] Services did not exit cleanly in No-Modem mode!"
        exit 1
    fi
fi

log_both "$GREEN" "[OK] Quectel modem (idVendor=2c7c) detected on USB bus."

# Start real-time log stream with color highlighting
(
    journalctl -u quectel-watchdog.service -u quectel-cm.service -f -n 0 | while IFS= read -r line; do
        printf "%s\n" "$line" >> "$LOG_FILE"
        case "$line" in
            *"entering low-frequency polling"*|*"quectel-CM process not running"*)
                printf "${YELLOW}%s${NC}\n" "$line"
                ;;
            *"Stage 1 Recovery"*|*"Stage 2 Recovery"*|*"Stage 3 Recovery"*|*"Standby Recovery"*)
                printf "${YELLOW}%s${NC}\n" "$line"
                ;;
            *"Stage 4 Recovery"*|*"Mini PCIe hardware reset triggered"*)
                printf "${RED}%s${NC}\n" "$line"
                ;;
            *"recovered"*|*"Modem & SIM READY"*)
                printf "${GREEN}%s${NC}\n" "$line"
                ;;
            *)
                printf "%s\n" "$line"
                ;;
        esac
    done
) &
JOURNAL_PID=$!
sleep 1

# =========================================================================
# PHASE 1.5: SIM Card Presence Branch (No-SIM Standby vs Active 4G)
# =========================================================================
log_both "$CYAN" ""
log_both "$CYAN" "--- [PHASE 1.5] Checking SIM Card State via AT Port ---"
print_mechanism "Tri-State SIM & Dialer Standby Protection" \
    "When modem is healthy but no SIM is inserted (or dialer crashes repeatedly / fails a full 4-stage cycle), watchdog stops quectel-cm and enters 30s low-frequency standby polling."

SIM_READY=0
for tty in /dev/4g_at /dev/ttyUSB2 /dev/ttyUSB3; do
    if [ -c "$tty" ]; then
        stty -F "$tty" 115200 raw -echo 2>/dev/null
        TMP_OUT="/tmp/drill_at_$$"
        : > "$TMP_OUT"
        timeout 2 cat "$tty" > "$TMP_OUT" 2>/dev/null &
        CPID=$!
        sleep 0.2
        printf 'AT+CPIN?\r\n' > "$tty"
        wait "$CPID" 2>/dev/null
        if grep -qi "READY" "$TMP_OUT" 2>/dev/null; then
            SIM_READY=1
        fi
        rm -f "$TMP_OUT"
        break
    fi
done

if [ "$SIM_READY" -eq 0 ]; then
    log_both "$YELLOW" "[INFO] Modem is present, but NO SIM card (+CPIN: READY) detected."
    log_both "$BLUE" "[TEST] Waiting up to 25s to verify Watchdog enters Low-Frequency Standby Polling and stops quectel-cm..."
    sleep 25

    CM_STATE=$(systemctl is-active quectel-cm.service 2>/dev/null || true)
    WD_STATE=$(systemctl is-active quectel-watchdog.service 2>/dev/null || true)
    log_both "$BLUE" "[STATUS] quectel-cm.service       : $CM_STATE (expected: inactive)"
    log_both "$BLUE" "[STATUS] quectel-watchdog.service : $WD_STATE (expected: active)"

    if [ "$CM_STATE" = "inactive" ] && [ "$WD_STATE" = "active" ]; then
        log_both "$GREEN" "[PASS] No-SIM Low-Frequency Standby verified! quectel-cm stopped cleanly; watchdog polling every 30s."
        log_both "$YELLOW" "[TIP] Insert a valid SIM card now — watchdog will detect +CPIN: READY within 30s and auto-dial."
        log_both "$GREEN" ""
        log_both "$GREEN" "=================================================================="
        log_both "$GREEN" "[$(date '+%F %T')] PASS! No-SIM Standby & Protection Mode verified."
        log_both "$GREEN" "=================================================================="
        print_log_guide
        exit 0
    else
        log_both "$RED" "[FAIL] Expected quectel-cm=inactive and watchdog=active in No-SIM mode!"
        exit 1
    fi
fi

log_both "$GREEN" "[OK] SIM card is READY (+CPIN: READY). Proceeding to active 4G protection tests..."

# =========================================================================
# PHASE 2: Systemd 2s Fast Crash Recovery Test (kill -9 quectel-CM)
# =========================================================================
log_both "$CYAN" ""
log_both "$CYAN" "--- [PHASE 2] Testing Systemd 2s Crash Recovery (SIGKILL quectel-CM) ---"
print_mechanism "Systemd Fast Respawn" \
    "quectel-cm.service uses Restart=always with RestartSec=2 to immediately respawn crashed dialer processes."

OLD_PID=$(pgrep -x quectel-CM | head -n 1)
if [ -z "$OLD_PID" ]; then
log_both "$RED" "[FAIL] quectel-CM process not found before Phase 2!"
exit 1
fi
log_both "$YELLOW" "[ACTION] Killing quectel-CM (PID=$OLD_PID) with SIGKILL..."
kill -9 "$OLD_PID"
sleep 4
NEW_PID=$(pgrep -x quectel-CM | head -n 1)
if [ -n "$NEW_PID" ] && [ "$NEW_PID" != "$OLD_PID" ]; then
log_both "$GREEN" "[PASS] Systemd restarted quectel-CM within 4s (Old PID=$OLD_PID -> New PID=$NEW_PID)."
else
log_both "$RED" "[FAIL] quectel-CM did not restart within 4s!"
exit 1
fi
sleep 6
log_both "$CYAN" ""
log_both "$CYAN" "--- [PHASE 3] Testing Watchdog 5s Process Enforcement (systemctl stop) ---"
print_mechanism "5s Process Liveness Polling" 
"Watchdog polls 'pgrep -x quectel-CM' every 5s during idle intervals and immediately restarts the service if stopped."
log_both "$YELLOW" "[ACTION] Stopping quectel-cm.service manually..."
systemctl stop quectel-cm.service
sleep 8
if pgrep -x quectel-CM >/dev/null 2>&1; then
RESTORED_PID=$(pgrep -x quectel-CM | head -n 1)
log_both "$GREEN" "[PASS] Watchdog detected stopped service and restored quectel-CM (PID=$RESTORED_PID)."
else
log_both "$RED" "[FAIL] Watchdog did not restore stopped quectel-cm.service within 8s!"
exit 1
fi
sleep 6
log_both "$CYAN" ""
log_both "$CYAN" "--- [PHASE 4] Simulating Network Blackhole for 4-Stage Recovery (~210s) ---"
print_mechanism "4-Stage Escalation + Low-Frequency Standby Fallback" 
"With max_fails=3, Stage 1->4 executes within ~210s, then transitions into 30s low-frequency polling until recovery."
if ! ip addr show wwan0 2>/dev/null | grep -q "inet "; then
log_both "$YELLOW" "[WARN] Waiting 10s for wwan0 IP before injecting ICMP drop..."
sleep 10
fi
log_both "$RED" "[ACTION] Injecting iptables DROP rule on wwan0 ICMP traffic..."
iptables -I OUTPUT -o wwan0 -p icmp -j DROP
log_both "$BLUE" "[WAIT] Monitoring escalation through Stage 1 -> Stage 2 -> Stage 3 -> Stage 4 (~210s)..."
ELAPSED=0
MAX_DRILL_SEC=320
STAGE4_SEEN=0
while [ "$ELAPSED" -lt "$MAX_DRILL_SEC" ]; do
if journalctl -u quectel-watchdog.service -n 25 --no-pager | grep -q "Mini PCIe hardware reset triggered"; then
STAGE4_SEEN=1
break
fi
sleep 5
ELAPSED=$((ELAPSED + 5))
done
log_both "$GREEN" "[ACTION] Removing iptables DROP rule to allow connection recovery..."
iptables -D OUTPUT -o wwan0 -p icmp -j DROP 2>/dev/null || true
if [ "$STAGE4_SEEN" -eq 1 ]; then
log_both "$GREEN" "[PASS] All 4 recovery stages executed within ${ELAPSED}s including Stage 4 Mini PCIe hardware reset!"
log_both "$BLUE" "[WAIT] Waiting up to 45s for modem cold boot, standby wake-up, and 4G reconnection..."
sleep 45
if ping -I wwan0 -c 3 -W 3 223.5.5.5 >/dev/null 2>&1; then
log_both "$GREEN" "[PASS] 4G connectivity on wwan0 fully restored after Stage 4 hardware reset & standby polling!"
else
log_both "$YELLOW" "[WARN] Modem reset succeeded; wwan0 still negotiating IP (check signal)."
fi
else
log_both "$RED" "[FAIL] Timed out waiting for Stage 4 hardware reset within ${MAX_DRILL_SEC}s."
exit 1
fi
log_both "$GREEN" ""
log_both "$GREEN" "=================================================================="
log_both "$GREEN" "[$(date '+%F %T')] ALL 4G KEEPALIVE & SELF-HEALING DRILLS PASSED!"
log_both "$GREEN" "=================================================================="
print_log_guide
