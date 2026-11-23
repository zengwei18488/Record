#!/bin/sh

CONF_FILE="/etc/cellular_guard/cellular_env.conf"
IFACE="wwan0"
PING_TARGETS="223.5.5.5 114.114.114.114"
PING_INTERVALS="60 1200 3600 3600"
MAX_PING_ERROR_COUNT="3 3 5 12"
PING_INTERVAL_NORMAL=600
STABLE_RESET_TIME=1800
STANDBY_POLL_INTERVAL=30
FAIL_COUNT=0
RECOVERY_STAGE=0
GRADIENT_IDX=0
CM_CRASH_COUNT=0
MAX_CM_CRASHES=3

MINIPCIE_RESET_NODE="/sys/devices/platform/misc-adv-gpio/minipcie_reset"
[ -f "$CONF_FILE" ] && . "$CONF_FILE"

LOG_FILE="/mnt/data/cellular_guard/watchdog.log"
MAX_LOG_SIZE=${MAX_LOG_SIZE:-100}
mkdir -p /mnt/data/cellular_guard

log_msg() {
    TS=$(date '+%Y-%m-%d %H:%M:%S')
    logger -t quectel-watchdog "$1"
    echo "[quectel-watchdog] $1"
    echo "${TS} [quectel-watchdog] $1" >> "$LOG_FILE"
    if [ -f "$LOG_FILE" ]; then
        CUR_BYTES=$(wc -c < "$LOG_FILE" 2>/dev/null || echo 0)
        MAX_BYTES=$((MAX_LOG_SIZE * 1024))
        if [ "$CUR_BYTES" -gt "$MAX_BYTES" ]; then
            TOTAL_LINES=$(wc -l < "$LOG_FILE" 2>/dev/null || echo 0)
            KEEP_LINES=$((TOTAL_LINES / 2))
            [ "$KEEP_LINES" -lt 10 ] && KEEP_LINES=10
            tail -n "$KEEP_LINES" "$LOG_FILE" > "${LOG_FILE}.tmp" && mv -f "${LOG_FILE}.tmp" "$LOG_FILE"
        fi
    fi
}

has_quectel_modem() {
    grep -qi "2c7c" /sys/bus/usb/devices/*/idVendor 2>/dev/null
}

get_at_port() {
    for tty in /dev/4g_at /dev/ttyUSB2 /dev/ttyUSB3; do
        if [ -c "$tty" ]; then
            echo "$tty"
            return 0
        fi
    done
    return 1
}

get_nth_val() {
    COUNT=0; LAST=""
    for item in $1; do
        LAST="$item"; [ "$COUNT" -eq "$2" ] && echo "$item" && return
        COUNT=$((COUNT + 1))
    done
    echo "$LAST"
}

# Return codes:
#   0 = Modem healthy, SIM READY & Signal OK
#   1 = Modem healthy & NO SIM inserted
#   2 = Modem abnormal (USB missing, AT port missing, or AT unresponsive)
#   3 = SIM READY, but network registration or signal quality weak/abnormal
query_modem_and_sim() {
    has_quectel_modem || return 2

    TTY_DEV=$(get_at_port)
    [ -z "$TTY_DEV" ] && return 2

    stty -F "$TTY_DEV" 115200 raw -echo 2>/dev/null

    for attempt in 1 2; do
        TMP_OUT="/tmp/at_sim_$$"
        : > "$TMP_OUT"
        timeout 2 cat "$TTY_DEV" > "$TMP_OUT" 2>/dev/null &
        CAT_PID=$!
        sleep 0.2
        printf 'AT+CPIN?\r\n' > "$TTY_DEV"
        wait "$CAT_PID" 2>/dev/null
        RESP=$(cat "$TMP_OUT" 2>/dev/null)
        rm -f "$TMP_OUT"

        if echo "$RESP" | grep -qi "READY"; then
            TMP_SIG="/tmp/at_sig_$$"
            : > "$TMP_SIG"
            timeout 2 cat "$TTY_DEV" > "$TMP_SIG" 2>/dev/null &
            SIG_PID=$!
            sleep 0.2
            printf 'AT+CEREG?;+CREG?;+CSQ\r\n' > "$TTY_DEV"
            wait "$SIG_PID" 2>/dev/null
            SIG_RESP=$(cat "$TMP_SIG" 2>/dev/null)
            rm -f "$TMP_SIG"
            RSSI=$(echo "$SIG_RESP" | awk -F'[:,]' '/\+CSQ:/ {gsub(/ /,"",$2); print $2}' | head -n 1)
            RSSI=${RSSI:-99}
            if echo "$SIG_RESP" | grep -qE "\+(CEREG|CREG): *[0-9]+," && [ "$RSSI" -ne 99 ] && [ "$RSSI" -ge 1 ]; then
                log_msg "Pre-dial check passed: SIM READY, registered, CSQ=${RSSI}"
                return 0
            fi
            log_msg "Pre-dial check waiting: SIM READY, but weak signal/unregistered (CSQ=${RSSI})"
            return 3
        fi
        if echo "$RESP" | grep -qiE "SIM not inserted|CME ERROR: 10|CME ERROR: 13"; then
            [ "$attempt" -eq 2 ] && return 1
        fi
        sleep 1
    done

    TMP_OUT="/tmp/at_ping_$$"
    : > "$TMP_OUT"
    timeout 2 cat "$TTY_DEV" > "$TMP_OUT" 2>/dev/null &
    CAT_PID=$!
    sleep 0.2
    printf 'AT\r\n' > "$TTY_DEV"
    wait "$CAT_PID" 2>/dev/null
    AT_PING=$(cat "$TMP_OUT" 2>/dev/null)
    rm -f "$TMP_OUT"

    if echo "$AT_PING" | grep -qi "OK"; then
        return 3
    fi

    return 2
}

send_at_reset() {
    TTY_DEV=$(get_at_port)
    if [ -n "$TTY_DEV" ]; then
        stty -F "$TTY_DEV" 115200 raw -echo 2>/dev/null
        printf 'AT+CFUN=1,1\r\n' > "$TTY_DEV"
        log_msg "Sent AT+CFUN=1,1 via $TTY_DEV"
        return 0
    fi
    return 1
}

usb_bus_rebind() {
    for dev in /sys/bus/usb/devices/*; do
        if [ -f "$dev/idVendor" ] && [ "$(cat "$dev/idVendor" 2>/dev/null)" = "2c7c" ]; then
            devname=$(basename "$dev")
            log_msg "Rebinding USB device $devname..."
            echo "$devname" > /sys/bus/usb/drivers/usb/unbind 2>/dev/null
            sleep 2
            echo "$devname" > /sys/bus/usb/drivers/usb/bind 2>/dev/null
            return 0
        fi
    done
    return 1
}

hardware_power_cycle() {
    if [ ! -w "$MINIPCIE_RESET_NODE" ]; then
        log_msg "Hardware reset error: $MINIPCIE_RESET_NODE not found or not writable."
        return 1
    fi

    log_msg "Triggering Mini PCIe hardware reset via $MINIPCIE_RESET_NODE..."
    echo 1 > "$MINIPCIE_RESET_NODE"
    log_msg "Mini PCIe hardware reset triggered, waiting for modem cold boot..."
    return 0
}

standby_polling_loop() {
    REASON="$1"
    log_msg "${REASON} Stopping quectel-cm and entering low-frequency polling (${STANDBY_POLL_INTERVAL}s)..."
    systemctl stop quectel-cm.service

    MODEM_ERR_COUNT=0
    STANDBY_STAGE=0

    while true; do
        sleep "$STANDBY_POLL_INTERVAL"

        query_modem_and_sim
        STATE=$?

        case "$STATE" in
            0)
                log_msg "Modem, SIM & Signal READY! Starting quectel-cm and resuming normal watchdog."
                FAIL_COUNT=0
                RECOVERY_STAGE=0
                CM_CRASH_COUNT=0
                systemctl start quectel-cm.service
                sleep 12
                return 0
                ;;
            3)
                log_msg "SIM READY, waiting for network registration & valid signal..."
                ;;
            1)
                if [ "$MODEM_ERR_COUNT" -gt 0 ] || [ "$STANDBY_STAGE" -gt 0 ]; then
                    log_msg "Modem recovered during standby; continuing low-frequency polling..."
                fi
                MODEM_ERR_COUNT=0
                STANDBY_STAGE=0
                ;;
            *)
                MODEM_ERR_COUNT=$((MODEM_ERR_COUNT + 1))
                CUR_MAX_FAILS=$(get_nth_val "$MAX_PING_ERROR_COUNT" "$GRADIENT_IDX")
                log_msg "Modem abnormal during standby polling ($MODEM_ERR_COUNT/$CUR_MAX_FAILS)"

                if [ "$MODEM_ERR_COUNT" -ge "$CUR_MAX_FAILS" ]; then
                    MODEM_ERR_COUNT=0
                    STANDBY_STAGE=$((STANDBY_STAGE + 1))

                    case "$STANDBY_STAGE" in
                        1)
                            log_msg "Standby Recovery Stage 1: Soft-resetting Quectel modem (AT+CFUN=1,1)..."
                            send_at_reset
                            sleep 10
                            ;;
                        2)
                            log_msg "Standby Recovery Stage 2: Rebinding USB bus for Quectel modem..."
                            usb_bus_rebind
                            sleep 10
                            ;;
                        *)
                            log_msg "Standby Recovery Stage 3: Hardware power-cycling Quectel modem..."
                            hardware_power_cycle
                            sleep 15
                            STANDBY_STAGE=0
                            ;;
                    esac
                fi
                ;;
        esac
    done
}

ensure_cm_running() {
    if ! pgrep -x quectel-CM >/dev/null 2>&1; then
        query_modem_and_sim
        Q_RC=$?
        if [ "$Q_RC" -eq 1 ]; then
            standby_polling_loop "Modem is healthy, but no SIM card detected."
            return 0
        elif [ "$Q_RC" -ne 0 ]; then
            standby_polling_loop "Waiting for modem/SIM/signal ready before starting dialer (state=$Q_RC)."
            return 0
        fi

        CM_CRASH_COUNT=$((CM_CRASH_COUNT + 1))
        log_msg "quectel-CM process not running ($CM_CRASH_COUNT/$MAX_CM_CRASHES)! Restarting service..."
        if [ "$CM_CRASH_COUNT" -ge "$MAX_CM_CRASHES" ]; then
            standby_polling_loop "quectel-CM failed to stay running after $MAX_CM_CRASHES attempts."
            return 0
        fi

        systemctl restart quectel-cm.service
        sleep 3
    fi
}

check_internet() {
    ensure_cm_running

    if ! ip addr show "$IFACE" 2>/dev/null | grep -q "inet "; then
        return 1
    fi
    for target in $PING_TARGETS; do
        if ping -I "$IFACE" -c 2 -W 2 "$target" >/dev/null 2>&1; then
            return 0
        fi
    done
    return 1
}

sleep 15

if ! has_quectel_modem; then
    log_msg "No Quectel 4G module detected on this board. Watchdog exiting cleanly."
    exit 0
fi

query_modem_and_sim
INIT_STATE=$?
if [ "$INIT_STATE" -eq 0 ]; then
    systemctl start quectel-cm.service
    sleep 12
elif [ "$INIT_STATE" -eq 1 ]; then
    standby_polling_loop "Boot check: no SIM card detected."
else
    standby_polling_loop "Boot check: waiting for modem/SIM/signal ready (state=$INIT_STATE)."
fi

log_msg "4G Watchdog started (normal=${PING_INTERVAL_NORMAL}s, gradients='${PING_INTERVALS}')"
STABLE_ELAPSED=0

while true; do
    if check_internet; then
        if [ "$FAIL_COUNT" -gt 0 ] || [ "$RECOVERY_STAGE" -gt 0 ] || [ "$CM_CRASH_COUNT" -gt 0 ]; then
            log_msg "4G connection recovered on $IFACE."
        fi
        FAIL_COUNT=0
        RECOVERY_STAGE=0
        CM_CRASH_COUNT=0
        if [ "$GRADIENT_IDX" -gt 0 ] && [ "$STABLE_ELAPSED" -ge "$STABLE_RESET_TIME" ]; then
            log_msg "Network stable for ${STABLE_ELAPSED}s, resetting gradient to 1."
            GRADIENT_IDX=0
        fi
        CUR_SLEEP="$PING_INTERVAL_NORMAL"
    else
        STABLE_ELAPSED=0
        query_modem_and_sim
        if [ "$?" -eq 1 ]; then
            standby_polling_loop "Modem is healthy, but no SIM card detected."
            continue
        fi

        CUR_MAX_FAILS=$(get_nth_val "$MAX_PING_ERROR_COUNT" "$GRADIENT_IDX")
        CUR_SLEEP=$(get_nth_val "$PING_INTERVALS" "$GRADIENT_IDX")
        FAIL_COUNT=$((FAIL_COUNT + 1))
        log_msg "Connectivity check failed ($FAIL_COUNT/$CUR_MAX_FAILS, gradient=$((GRADIENT_IDX + 1)))"

        if [ "$FAIL_COUNT" -ge "$CUR_MAX_FAILS" ]; then
            FAIL_COUNT=0
            RECOVERY_STAGE=$((RECOVERY_STAGE + 1))
            GRADIENT_IDX=$((GRADIENT_IDX + 1))

            case "$RECOVERY_STAGE" in
                1)
                    log_msg "Stage 1 Recovery: Restarting quectel-cm.service..."
                    systemctl restart quectel-cm.service
                    sleep 10
                    ;;
                2)
                    log_msg "Stage 2 Recovery: Soft-resetting Quectel modem (AT+CFUN=1,1)..."
                    systemctl stop quectel-cm.service
                    send_at_reset
                    sleep 10
                    systemctl start quectel-cm.service
                    sleep 10
                    ;;
                3)
                    log_msg "Stage 3 Recovery: Rebinding USB bus for Quectel modem..."
                    systemctl stop quectel-cm.service
                    usb_bus_rebind
                    sleep 10
                    systemctl start quectel-cm.service
                    sleep 10
                    ;;
                *)
                    log_msg "Stage 4 Recovery: Hardware power-cycling Quectel modem..."
                    systemctl stop quectel-cm.service
                    hardware_power_cycle
                    sleep 15
                    RECOVERY_STAGE=0
                    CM_CRASH_COUNT=0
                    standby_polling_loop "Full 4-stage recovery completed without connection."
                    continue
                    ;;
            esac
        fi
    fi

    WAIT_SEC=0
    while [ "$WAIT_SEC" -lt "$CUR_SLEEP" ]; do
        sleep 5
        WAIT_SEC=$((WAIT_SEC + 5))
        STABLE_ELAPSED=$((STABLE_ELAPSED + 5))
        ensure_cm_running
    done
done
