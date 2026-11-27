#!/bin/sh

PORTS="/dev/ttymxc2 /dev/ttymxc3 /dev/ttyRS4850 /dev/ttyRS4851"
TMP_DIR="/tmp/uart_suspend_audit"
mkdir -p "$TMP_DIR"
rm -f "${TMP_DIR}"/*

RED='\033[1;31m'
GREEN='\033[1;32m'
YELLOW='\033[1;33m'
BLUE='\033[1;34m'
CYAN='\033[1;36m'
BOLD='\033[1m'
NC='\033[0m'

log_banner() {
    printf "\n${CYAN}==========================================================================${NC}\n"
    printf "${BOLD}${CYAN}  %s${NC}\n" "$1"
    printf "${CYAN}==========================================================================${NC}\n"
}

get_uart_detail() {
    port="$1"
    stty_out=$(stty -F "$port" -a 2>/dev/null)
    spd=$(echo "$stty_out" | grep -oE "speed [0-9]+ baud" | awk '{print $2}')
    f_echo=$(echo "$stty_out" | grep -oE "(^| )-?echo( |$)" | xargs)
    f_onlcr=$(echo "$stty_out" | grep -oE "(^| )-?onlcr( |$)" | xargs)
    f_icanon=$(echo "$stty_out" | grep -oE "(^| )-?icanon( |$)" | xargs)
    echo "speed=${spd:-?} ${f_echo} ${f_onlcr} ${f_icanon}"
}

log_banner "STEP 1: CONFIGURE & SNAPSHOT ALL 4 SERIAL PORTS (PRE-SUSPEND)"

ACTIVE_PORTS=""
for port in $PORTS; do
    name=$(basename "$port")
    if [ ! -c "$port" ]; then
        printf "${RED}[MISSING] %-15s : Device node not found!${NC}\n" "$port"
        continue
    fi

    stty -F "$port" 115200 -echo -onlcr -icanon 2>/dev/null
    real_dev=$(readlink -f "$port")
    maj_min=$(stat -c "%t:%T" "$real_dev" 2>/dev/null || echo "?:?")
    detail=$(get_uart_detail "$port")

    echo "$real_dev" > "${TMP_DIR}/${name}.real"
    echo "$maj_min"  > "${TMP_DIR}/${name}.devnum"
    echo "$detail"   > "${TMP_DIR}/${name}.stty"
    ACTIVE_PORTS="${ACTIVE_PORTS} ${port}"

    printf "${GREEN}[READY]   %-15s -> %-12s (ID: %-5s) | %s${NC}\n" "$port" "$real_dev" "$maj_min" "$detail"
done

log_banner "STEP 2: START CONTINUOUS TX WORKER WITH AUTO-RECONNECT ON EIO"

python3 - "$TMP_DIR" $ACTIVE_PORTS << 'PYEOF' &
import sys, time, os, errno

tmp_dir = sys.argv[1]
ports = sys.argv[2:]
fds = {}
reconnect_cnt = {p: 0 for p in ports}

for p in ports:
    name = os.path.basename(p)
    try:
        fds[p] = os.open(p, os.O_RDWR | os.O_NOCTTY)
    except Exception as e:
        with open(f"{tmp_dir}/{name}.err", "w") as f:
            f.write(f"Initial open failed: {repr(e)}")

seq = 0
while True:
    for p in ports:
        name = os.path.basename(p)
        if p not in fds:
            try:
                if os.path.exists(p):
                    fds[p] = os.open(p, os.O_RDWR | os.O_NOCTTY)
                    reconnect_cnt[p] += 1
                    with open(f"{tmp_dir}/{name}.reconn", "w") as f:
                        f.write(str(reconnect_cnt[p]))
            except Exception:
                continue

        if p in fds:
            try:
                os.write(fds[p], f"[{name}]_TX_SEQ_{seq}\r\n".encode())
                with open(f"{tmp_dir}/{name}.seq", "w") as f:
                    f.write(str(seq))
            except OSError as e:
                try:
                    os.close(fds[p])
                except Exception:
                    pass
                del fds[p]
                if e.errno not in (errno.EIO, errno.ENODEV, errno.ENXIO):
                    with open(f"{tmp_dir}/{name}.err", "w") as f:
                        f.write(f"Unexpected error at seq={seq}: {repr(e)}")
    seq += 1
    time.sleep(0.2)
PYEOF
TX_PID=$!
sleep 2

if ! kill -0 "$TX_PID" 2>/dev/null; then
    printf "${RED}[FATAL] Background TX worker died prematurely before suspend!${NC}\n"
    exit 1
fi
printf "${BLUE}[RUNNING] All 4 UARTs actively transmitting every 200ms (Worker PID: %s)${NC}\n" "$TX_PID"

log_banner "STEP 3: ENTERING SYSTEM SUSPEND (PRESS POWER/WAKE KEY AFTER 5s)"
sleep 1
systemctl suspend
sleep 4

log_banner "STEP 4: POST-RESUME AUDIT REPORT (SYMLINK / STTY / TX RECOVERY)"

PASS_CNT=0
FAIL_CNT=0

for port in $PORTS; do
    name=$(basename "$port")
    printf "\n${BOLD}>>> Auditing Port: %s${NC}\n" "$port"

    if [ ! -c "$port" ]; then
        printf "  ${RED}[FAIL] Node Status  : Device %s disappeared after resume!${NC}\n" "$port"
        FAIL_CNT=$((FAIL_CNT + 1))
        continue
    fi

    pre_real=$(cat "${TMP_DIR}/${name}.real" 2>/dev/null)
    pre_stty=$(cat "${TMP_DIR}/${name}.stty" 2>/dev/null)

    post_real=$(readlink -f "$port")
    post_num=$(stat -c "%t:%T" "$post_real" 2>/dev/null || echo "?:?")
    post_stty=$(get_uart_detail "$port")
    last_seq=$(cat "${TMP_DIR}/${name}.seq" 2>/dev/null || echo "0")
    reconn=$(cat "${TMP_DIR}/${name}.reconn" 2>/dev/null || echo "0")

    port_ok=1

    # 1. 检查固定物理映射路径是否有效
    if [ -c "$port" ]; then
        if [ "$pre_real" = "$post_real" ]; then
            printf "  ${GREEN}[PASS] Node Mapping : %s -> %s (ID: %s) [Static]${NC}\n" "$port" "$post_real" "$post_num"
        else
            printf "  ${GREEN}[PASS] Node Mapping : %s -> %s (ID: %s) [Re-enumerated from %s, Symlink Valid]${NC}\n" "$port" "$post_real" "$post_num" "$pre_real"
        fi
    else
        printf "  ${RED}[FAIL] Node Mapping : %s broken!${NC}\n" "$port"
        port_ok=0
    fi

    # 2. 检查波特率与标志位恢复
    if [ "$pre_stty" = "$post_stty" ]; then
        printf "  ${GREEN}[PASS] UART Config  : %s [Restored/Kept]${NC}\n" "$post_stty"
    else
        printf "  ${RED}[FAIL] Config Lost  : Pre=[%s]  ===>  Post=[%s]${NC}\n" "$pre_stty" "$post_stty"
        port_ok=0
    fi

    # 3. 检查发数线程在唤醒后是否继续增长（验证断线重连后实际发包成功）
    seq_t1=$(cat "${TMP_DIR}/${name}.seq" 2>/dev/null || echo "0")
    sleep 1
    seq_t2=$(cat "${TMP_DIR}/${name}.seq" 2>/dev/null || echo "0")

    if [ -f "${TMP_DIR}/${name}.err" ]; then
        err_msg=$(cat "${TMP_DIR}/${name}.err")
        printf "  ${RED}[FAIL] TX Stream    : Fatal Error! (%s)${NC}\n" "$err_msg"
        port_ok=0
    elif [ "$seq_t2" -gt "$seq_t1" ]; then
        printf "  ${GREEN}[PASS] TX Stream    : Resumed & transmitting! (SEQ: %s -> %s | Auto-Reconnects: %s)${NC}\n" "$seq_t1" "$seq_t2" "$reconn"
    else
        printf "  ${RED}[FAIL] TX Stream    : Stalled after resume! (SEQ stuck at %s)${NC}\n" "$seq_t2"
        port_ok=0
    fi

    if [ "$port_ok" -eq 1 ]; then
        PASS_CNT=$((PASS_CNT + 1))
    else
        FAIL_CNT=$((FAIL_CNT + 1))
    fi
done

kill -9 "$TX_PID" 2>/dev/null || true

log_banner "FINAL SUMMARY: PASS=${PASS_CNT} | FAIL=${FAIL_CNT}"
if [ "$FAIL_CNT" -eq 0 ]; then
    printf "${GREEN}${BOLD}  ALL 4 SERIAL PORTS PASSED SUSPEND/RESUME & RECONNECT AUDIT!${NC}\n\n"
else
    printf "${RED}${BOLD}  DETECTED %s PORT ISSUE(S) - CHECK RED ITEMS ABOVE!${NC}\n\n" "$FAIL_CNT"
fi
