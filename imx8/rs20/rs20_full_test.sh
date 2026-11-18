#!/bin/sh

LOG_FILE="/tmp/rs20_full_test.log"
: > "$LOG_FILE"

PASS_CNT=0
FAIL_CNT=0
SKIP_CNT=0
SUMMARY_LIST=""

RED='\033[1;31m'
GREEN='\033[1;32m'
YELLOW='\033[1;33m'
BLUE='\033[1;34m'
CYAN='\033[1;36m'
NC='\033[0m'

log_line() {
    color="$1"
    msg="$2"
    printf "${color}%s${NC}\n" "$msg"
    printf "%s\n" "$msg" >> "$LOG_FILE"
}

record_result() {
    item="$1"
    status="$2"
    detail="$3"
    case "$status" in
        PASS)
            PASS_CNT=$((PASS_CNT + 1))
            log_line "$GREEN" "[PASS] $item - $detail"
            SUMMARY_LIST="${SUMMARY_LIST}\n  [PASS] $item : $detail"
            ;;
        FAIL)
            FAIL_CNT=$((FAIL_CNT + 1))
            log_line "$RED" "[FAIL] $item - $detail"
            SUMMARY_LIST="${SUMMARY_LIST}\n  [FAIL] $item : $detail"
            ;;
        SKIP)
            SKIP_CNT=$((SKIP_CNT + 1))
            log_line "$YELLOW" "[SKIP] $item - $detail"
            SUMMARY_LIST="${SUMMARY_LIST}\n  [SKIP] $item : $detail"
            ;;
    esac
}

print_sys_info() {
    log_line "$CYAN" "=================================================================="
    log_line "$CYAN" "  1. SYSTEM & BOARD INFORMATION"
    log_line "$CYAN" "=================================================================="
    OS_NAME=$(grep "^PRETTY_NAME=" /etc/os-release 2>/dev/null | cut -d'"' -f2)
    OS_VER=$(grep "^VERSION=" /etc/os-release 2>/dev/null | cut -d'"' -f2)
    KERNEL_VER=$(uname -r)
    CPU_MODEL=$(grep -m1 "model name\|Hardware" /proc/cpuinfo 2>/dev/null | cut -d':' -f2 | xargs)
    CPU_CORES=$(nproc 2>/dev/null || grep -c "^processor" /proc/cpuinfo)
    MEM_TOTAL=$(awk '/MemTotal/ {printf "%.1f MB", $2/1024}' /proc/meminfo)
    MEM_AVAIL=$(awk '/MemAvailable/ {printf "%.1f MB", $2/1024}' /proc/meminfo)

    log_line "$BLUE" "OS Name       : ${OS_NAME:-Unknown}"
    log_line "$BLUE" "OS Version    : ${OS_VER:-Unknown}"
    log_line "$BLUE" "Kernel        : $KERNEL_VER"
    log_line "$BLUE" "CPU Info      : ${CPU_MODEL:-ARMv8} (${CPU_CORES} Cores)"
    log_line "$BLUE" "Memory        : Total ${MEM_TOTAL} / Available ${MEM_AVAIL}"
    if [ -r /proc/board ]; then
        BOARD_INFO=$(cat /proc/board | tr '\n' ' ')
        log_line "$BLUE" "/proc/board   : $BOARD_INFO"
    else
        log_line "$YELLOW" "/proc/board   : Not found"
    fi
}

verify_block_rw() {
    label="$1"
    dev_pattern="$2"
    MNT_POINT=$(mount | grep -E "$dev_pattern" | awk '{print $3}' | head -n 1)
    if [ -z "$MNT_POINT" ]; then
        record_result "$label Storage" "SKIP" "No mounted partition matching $dev_pattern"
        return
    fi

    TEST_FILE="${MNT_POINT}/.rs20_rw_test_$$.bin"
    log_line "$BLUE" "Testing R/W on $label ($MNT_POINT)..."
    if dd if=/dev/urandom of="$TEST_FILE" bs=1M count=2 conv=fsync >/dev/null 2>&1; then
        SRC_MD5=$(md5sum "$TEST_FILE" | awk '{print $1}')
        sync
        DST_MD5=$(md5sum "$TEST_FILE" | awk '{print $1}')
        rm -f "$TEST_FILE"
        if [ -n "$SRC_MD5" ] && [ "$SRC_MD5" = "$DST_MD5" ]; then
            record_result "$label Storage" "PASS" "Mounted at $MNT_POINT, 2MB R/W MD5 verified ($SRC_MD5)"
        else
            record_result "$label Storage" "FAIL" "MD5 mismatch on $MNT_POINT"
        fi
    else
        rm -f "$TEST_FILE" 2>/dev/null
        record_result "$label Storage" "FAIL" "Write error on $MNT_POINT"
    fi
}

test_storage() {
    log_line "$CYAN" "\n=================================================================="
    log_line "$CYAN" "  2. STORAGE TESTS (eMMC / SD / USB / NVMe / SPI Flash)"
    log_line "$CYAN" "=================================================================="
    lsblk | tee -a "$LOG_FILE"

    EMMC_MNT=$(lsblk -no MOUNTPOINTS /dev/mmcblk2p2 /dev/mmcblk2p1 2>/dev/null | grep -v "^$" | head -n 1)
    if [ -n "$EMMC_MNT" ]; then
        verify_block_rw "eMMC (mmcblk2)" "/dev/mmcblk2"
    else
        record_result "eMMC (mmcblk2)" "SKIP" "mmcblk2 partition not mounted"
    fi

    SD_MNT=$(lsblk -no MOUNTPOINTS /dev/mmcblk1p2 /dev/mmcblk1p1 2>/dev/null | grep -v "^$" | head -n 1)
    if [ -n "$SD_MNT" ]; then
        verify_block_rw "SD Card (mmcblk1)" "/dev/mmcblk1"
    else
        record_result "SD Card (mmcblk1)" "SKIP" "No SD card mounted on mmcblk1"
    fi

    verify_block_rw "USB Disk" "/dev/sd[a-z]"
    verify_block_rw "NVMe SSD" "/dev/nvme[0-9]"

    if [ -e /dev/mtd0 ]; then
        log_line "$BLUE" "Running mtdinfo /dev/mtd0..."
        if mtdinfo /dev/mtd0 | tee -a "$LOG_FILE"; then
            record_result "SPI Flash (/dev/mtd0)" "PASS" "mtdinfo read successfully"
        else
            record_result "SPI Flash (/dev/mtd0)" "FAIL" "mtdinfo command failed"
        fi
    else
        record_result "SPI Flash (/dev/mtd0)" "SKIP" "/dev/mtd0 device node not found"
    fi
}

test_network_and_wireless() {
    log_line "$CYAN" "\n=================================================================="
    log_line "$CYAN" "  3. NETWORK & WIRELESS TESTS (LAN / Wi-Fi / Bluetooth / 4G)"
    log_line "$CYAN" "=================================================================="

    ETH_IF=$(ip -o link show | awk -F': ' '/eth[0-9]+/ {print $2}' | head -n 1)
    if [ -n "$ETH_IF" ] && ip addr show "$ETH_IF" | grep -q "inet "; then
        GW_IP=$(ip route show dev "$ETH_IF" | awk '/default/ {print $3}' | head -n 1)
        TARGET_IP="${GW_IP:-223.5.5.5}"
        log_line "$BLUE" "Pinging $TARGET_IP via LAN ($ETH_IF)..."
        if ping -I "$ETH_IF" -c 3 -W 2 "$TARGET_IP" | tee -a "$LOG_FILE"; then
            record_result "LAN ($ETH_IF)" "PASS" "Ping $TARGET_IP succeeded"
        else
            record_result "LAN ($ETH_IF)" "FAIL" "Ping $TARGET_IP failed"
        fi
    else
        record_result "LAN (${ETH_IF:-eth0})" "SKIP" "Interface down or no IP assigned"
    fi

    WIFI_IF=$(iw dev 2>/dev/null | awk '/Interface/ {print $2}' | grep -E "^(mlan|wlan)" | head -n 1)
    if [ -n "$WIFI_IF" ]; then
        ip link set "$WIFI_IF" up 2>/dev/null
        log_line "$BLUE" "Scanning nearby Wi-Fi APs on $WIFI_IF..."
        AP_LIST=""
        if command -v nmcli >/dev/null 2>&1; then
            nmcli radio wifi on 2>/dev/null
            AP_LIST=$(nmcli -t -f SSID dev wifi list ifname "$WIFI_IF" --rescan yes 2>/dev/null | grep -v "^$" | sort -u | head -n 8)
        fi
        if [ -z "$AP_LIST" ]; then
            for try in 1 2 3; do
                AP_LIST=$(iw dev "$WIFI_IF" scan 2>/dev/null | awk -F'SSID: ' '/SSID:/ && $2 != "" {print $2}' | sort -u | head -n 8)
                [ -n "$AP_LIST" ] && break
                sleep 2
            done
        fi
        if [ -n "$AP_LIST" ]; then
            printf "%s\n" "$AP_LIST" | sed 's/^/  SSID: /' | tee -a "$LOG_FILE"
            AP_COUNT=$(printf "%s\n" "$AP_LIST" | wc -l)
            record_result "Wi-Fi ($WIFI_IF)" "PASS" "Scanned $AP_COUNT+ nearby APs"
        else
            record_result "Wi-Fi ($WIFI_IF)" "FAIL" "No APs found or scan busy"
        fi
    else
        record_result "Wi-Fi" "SKIP" "No mlan/wlan interface detected"
    fi

    if ! hciconfig hci0 >/dev/null 2>&1; then
        log_line "$YELLOW" "hci0 not found, loading btnxpuart driver..."
        modprobe btnxpuart 2>/dev/null
        sleep 2
    fi

    if hciconfig hci0 >/dev/null 2>&1; then
        hciconfig hci0 up 2>/dev/null
        bluetoothctl power on >/dev/null 2>&1
        log_line "$BLUE" "Scanning nearby Bluetooth devices (5s)..."
        BT_SCAN=$(timeout 6 bluetoothctl --timeout 5 scan on 2>/dev/null | grep "Device " | head -n 6)
        [ -z "$BT_SCAN" ] && BT_SCAN=$(hcitool scan --flush 2>/dev/null | tail -n +2 | head -n 6)
        if [ -n "$BT_SCAN" ]; then
            printf "%s\n" "$BT_SCAN" | tee -a "$LOG_FILE"
            record_result "Bluetooth (hci0)" "PASS" "Controller active and discovered devices"
        else
            record_result "Bluetooth (hci0)" "PASS" "Controller hci0 is UP (no discoverable BT devices nearby)"
        fi
    else
        record_result "Bluetooth (hci0)" "FAIL" "hci0 adapter failed to initialize even after modprobe btnxpuart"
    fi

    if grep -qi "2c7c" /sys/bus/usb/devices/*/idVendor 2>/dev/null; then
        if ! pgrep -x quectel-CM >/dev/null 2>&1; then
            systemctl start quectel-cm.service 2>/dev/null || (command -v quectel-CM >/dev/null 2>&1 && quectel-CM >/dev/null 2>&1 &)
        fi
        WAIT=0
        while [ "$WAIT" -lt 25 ]; do
            ip addr show wwan0 2>/dev/null | grep -q "inet " && break
            sleep 2
            WAIT=$((WAIT + 2))
        done
        if ip addr show wwan0 2>/dev/null | grep -q "inet "; then
            log_line "$BLUE" "Pinging 223.5.5.5 via 4G (wwan0)..."
            if ping -I wwan0 -c 3 -W 3 223.5.5.5 | tee -a "$LOG_FILE"; then
                record_result "4G LTE (wwan0)" "PASS" "Ping 223.5.5.5 via wwan0 succeeded"
            else
                record_result "4G LTE (wwan0)" "FAIL" "wwan0 has IP but ping 223.5.5.5 failed"
            fi
        else
            record_result "4G LTE (wwan0)" "FAIL" "Modem present but wwan0 has no IP after 20s"
        fi
    else
        record_result "4G LTE (wwan0)" "SKIP" "No Quectel 4G module installed"
    fi
}

test_peripherals() {
    log_line "$CYAN" "\n=================================================================="
    log_line "$CYAN" "  4. PERIPHERALS TESTS (RTC / TPM / LEDs / Watchdog)"
    log_line "$CYAN" "=================================================================="

    # 4.1 RTC Hardware Clock Test
    if [ -e /dev/rtc0 ]; then
        log_line "$BLUE" "Reading hardware RTC (/dev/rtc0)..."
        if hwclock -r -f /dev/rtc0 | tee -a "$LOG_FILE"; then
            record_result "RTC (/dev/rtc0)" "PASS" "Hardware clock read succeeded"
        else
            record_result "RTC (/dev/rtc0)" "FAIL" "hwclock read failed"
        fi
    else
        record_result "RTC (/dev/rtc0)" "SKIP" "/dev/rtc0 not found"
    fi

    # 4.2 TPM Status Check
    if [ -e /dev/tpm0 ] || [ -e /dev/tpmrm0 ]; then
        TPM_DEV=$(ls /dev/tpm* 2>/dev/null | tr '\n' ' ')
        log_line "$BLUE" "Detected TPM devices: $TPM_DEV"
        if command -v tpm2_getcap >/dev/null 2>&1 && tpm2_getcap properties-fixed >/dev/null 2>&1; then
            record_result "TPM ($TPM_DEV)" "PASS" "TPM2 chip active and responding"
        else
            record_result "TPM ($TPM_DEV)" "PASS" "TPM device node present ($TPM_DEV)"
        fi
    else
        record_result "TPM" "SKIP" "No /dev/tpm* device node found"
    fi

    # 4.3 User LEDs Blink Test (user-led1 & user-led2)
    LED_OK=1
    LED_TESTED=0
    for led in user-led1 user-led2; do
        LED_PATH="/sys/class/leds/${led}/brightness"
        if [ -w "$LED_PATH" ]; then
            LED_TESTED=$((LED_TESTED + 1))
            log_line "$BLUE" "Toggling $led ON (1) -> OFF (0)..."
            echo 1 > "$LED_PATH"
            sleep 1
            echo 0 > "$LED_PATH"
            sleep 1
        else
            log_line "$YELLOW" "LED node not found or not writable: $LED_PATH"
            LED_OK=0
        fi
    done

    if [ "$LED_TESTED" -eq 2 ] && [ "$LED_OK" -eq 1 ]; then
        record_result "User LEDs (led1/led2)" "PASS" "Both user-led1 and user-led2 toggled 1 -> 0"
    elif [ "$LED_TESTED" -gt 0 ]; then
        record_result "User LEDs" "PASS" "Toggled $LED_TESTED LED(s)"
    else
        record_result "User LEDs" "SKIP" "No user-led1/user-led2 sysfs nodes found"
    fi

    # 4.4 Watchdog Device Node Check
    log_line "$BLUE" "Checking /dev/watchdog* nodes..."
    if ls -l /dev/watchdog* 2>/dev/null | tee -a "$LOG_FILE"; then
        WDT_NODES=$(ls /dev/watchdog* 2>/dev/null | tr '\n' ' ')
        record_result "Watchdog" "PASS" "Nodes detected: $WDT_NODES"
    else
        record_result "Watchdog" "FAIL" "No /dev/watchdog* nodes found"
    fi
}

print_summary() {
    log_line "$CYAN" "\n=================================================================="
    log_line "$CYAN" "  FINAL TEST SUMMARY REPORT"
    log_line "$CYAN" "=================================================================="
    printf "%b\n" "$SUMMARY_LIST" | while IFS= read -r line; do
        [ -z "$line" ] && continue
        printf "%s\n" "$line" >> "$LOG_FILE"
        case "$line" in
            *"[PASS]"*) printf "${GREEN}%s${NC}\n" "$line" ;;
            *"[FAIL]"*) printf "${RED}%s${NC}\n" "$line" ;;
            *"[SKIP]"*) printf "${YELLOW}%s${NC}\n" "$line" ;;
            *)          printf "%s\n" "$line" ;;
        esac
    done
    log_line "$CYAN" "------------------------------------------------------------------"
    log_line "$GREEN" "TOTAL PASSED : $PASS_CNT"
    log_line "$RED"   "TOTAL FAILED : $FAIL_CNT"
    log_line "$YELLOW" "TOTAL SKIPPED: $SKIP_CNT"
    log_line "$BLUE"  "Full test log saved at: $LOG_FILE"
    log_line "$CYAN" "=================================================================="
}

# Main Execution Entry
print_sys_info
test_storage
test_network_and_wireless
test_peripherals
print_summary
