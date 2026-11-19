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
        record_result "Bluetooth (hci0)" "FAIL" "hci0 adapter not ready (check boot autoload)"
    fi

    # 3.4 4G LTE (wwan0): Check module presence -> Skip if absent -> Test wwan0 directly
    if grep -qi "2c7c" /sys/bus/usb/devices/*/idVendor 2>/dev/null; then
        WAIT=0
        while [ "$WAIT" -lt 15 ]; do
            ip addr show wwan0 2>/dev/null | grep -q "inet " && break
            sleep 3
            WAIT=$((WAIT + 3))
        done
        if ip addr show wwan0 2>/dev/null | grep -q "inet "; then
            log_line "$BLUE" "Quectel 4G module detected, pinging 223.5.5.5 via wwan0..."
            if ping -I wwan0 -c 3 -W 3 223.5.5.5 | tee -a "$LOG_FILE"; then
                record_result "4G LTE (wwan0)" "PASS" "Modem present and ping via wwan0 succeeded"
            else
                record_result "4G LTE (wwan0)" "FAIL" "wwan0 has IP but ping 223.5.5.5 failed"
            fi
        else
            record_result "4G LTE (wwan0)" "FAIL" "Modem present but wwan0 has no IP (check keepalive service)"
        fi
    else
        record_result "4G LTE (wwan0)" "SKIP" "No Quectel 4G module installed"
    fi
}

test_peripherals() {
    log_line "$CYAN" "\n=================================================================="
    log_line "$CYAN" "  4. PERIPHERALS TESTS (RTC / TPM / LEDs / Watchdog)"
    log_line "$CYAN" "=================================================================="

    # 4.1 RTC Hardware Clock Read, Compare (HH:MM), Write & Verify
    if [ -e /dev/rtc0 ]; then
        log_line "$BLUE" "Reading hardware RTC (/dev/rtc0) and comparing with system time..."
        RTC_RAW=$(hwclock -r -f /dev/rtc0 2>/dev/null)
        if [ -n "$RTC_RAW" ]; then
            SYS_STR=$(date -u "+%Y-%m-%d %H:%M:%S UTC")
            RTC_HM=$(echo "$RTC_RAW" | grep -oE "[0-9]{2}:[0-9]{2}" | head -n 1)
            SYS_HM=$(date -u "+%H:%M")

            log_line "$BLUE" "  Hardware RTC Time : $RTC_RAW (HH:MM = $RTC_HM)"
            log_line "$BLUE" "  System UTC Time   : $SYS_STR (HH:MM = $SYS_HM)"

            if [ "$RTC_HM" = "$SYS_HM" ]; then
                CMP_MSG="Initial HH:MM matched ($RTC_HM == $SYS_HM)"
                log_line "$GREEN" "  [COMPARE] $CMP_MSG"
            else
                CMP_MSG="Initial HH:MM differed (RTC=$RTC_HM vs SYS=$SYS_HM)"
                log_line "$YELLOW" "  [COMPARE] $CMP_MSG"
            fi

            log_line "$BLUE" "Writing system time to RTC (hwclock -w -f /dev/rtc0)..."
            if hwclock -w -f /dev/rtc0 2>/dev/null; then
                RTC_AFTER=$(hwclock -r -f /dev/rtc0 2>/dev/null)
                RTC_AFTER_HM=$(echo "$RTC_AFTER" | grep -oE "[0-9]{2}:[0-9]{2}" | head -n 1)
                SYS_AFTER_HM=$(date -u "+%H:%M")
                log_line "$BLUE" "  RTC After Write   : $RTC_AFTER (HH:MM = $RTC_AFTER_HM)"
                if [ -n "$RTC_AFTER_HM" ] && [ "$RTC_AFTER_HM" = "$SYS_AFTER_HM" ]; then
                    record_result "RTC (/dev/rtc0)" "PASS" "$CMP_MSG; Write & readback verified ($RTC_AFTER_HM)"
                else
                    record_result "RTC (/dev/rtc0)" "FAIL" "RTC readback HH:MM ($RTC_AFTER_HM) mismatch after write ($SYS_AFTER_HM)"
                fi
            else
                record_result "RTC (/dev/rtc0)" "FAIL" "hwclock -w write failed"
            fi
        else
            record_result "RTC (/dev/rtc0)" "FAIL" "hwclock -r read failed"
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
            log_line "$BLUE" "Toggling $led OFF (0) -> ON (1, active high)..."
            echo 0 > "$LED_PATH"
            sleep 1
            echo 1 > "$LED_PATH"
            sleep 1
        else
            log_line "$YELLOW" "LED node not found or not writable: $LED_PATH"
            LED_OK=0
        fi
    done

    if [ "$LED_TESTED" -eq 2 ] && [ "$LED_OK" -eq 1 ]; then
        record_result "User LEDs (led1/led2)" "PASS" "Both user-led1 and user-led2 toggled 0 -> 1 (held HIGH)"
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

    # 4.5 Custom Udev Symlink Nodes Check (/dev/4g_at, /dev/scanner0, /dev/camera0, /dev/camera0_meta)
    log_line "$BLUE" "Checking custom device nodes (/dev/4g_at, /dev/scanner0, /dev/camera0, /dev/camera0_meta)..."
    for dev_node in /dev/4g_at /dev/scanner0 /dev/camera0 /dev/camera0_meta; do
        if [ -e "$dev_node" ]; then
            NODE_DETAIL=$(ls -l "$dev_node" 2>/dev/null)
            log_line "$GREEN" "  [FOUND] $NODE_DETAIL"
            record_result "Device Node ($dev_node)" "PASS" "Exists ($NODE_DETAIL)"
        else
            log_line "$YELLOW" "  [NOT FOUND] $dev_node"
            record_result "Device Node ($dev_node)" "SKIP" "Node not present (peripheral not attached)"
        fi
    done
}

test_audio() {
    log_line "$CYAN" "\n=================================================================="
    log_line "$CYAN" "  5. AUDIO PLAYBACK & 5S RECORDING TEST"
    log_line "$CYAN" "=================================================================="

    REC_FILE="/tmp/rs20_audio_rec.wav"
    rm -f "$REC_FILE"

    if aplay -l 2>/dev/null | grep -q "^card "; then
        aplay -l | tee -a "$LOG_FILE"
        SAMPLE_WAV=$(find /usr/share/sounds -type f -name "*.wav" 2>/dev/null | head -n 1)

        log_line "$BLUE" "[AUDIO Step 1/3] Playing built-in system audio..."
        if [ -n "$SAMPLE_WAV" ]; then
            log_line "$BLUE" "Playing sample file: $SAMPLE_WAV"
            aplay "$SAMPLE_WAV" >/dev/null 2>&1
        else
            log_line "$BLUE" "No built-in .wav found, playing 2s test tone via speaker-test..."
            timeout 3 speaker-test -t sine -f 1000 -l 1 >/dev/null 2>&1
        fi

        log_line "$YELLOW" "[AUDIO Step 2/3] >>> PLEASE SPEAK INTO MIC NOW! Recording for 5 seconds... <<<"
        if arecord -f cd -d 5 "$REC_FILE" 2>/dev/null && [ -s "$REC_FILE" ]; then
            REC_SIZE=$(ls -lh "$REC_FILE" | awk '{print $5}')
            log_line "$GREEN" "[AUDIO Step 2/3] Recording finished ($REC_SIZE saved at $REC_FILE)."

            log_line "$BLUE" "[AUDIO Step 3/3] Playing back recorded audio ($REC_FILE)..."
            if aplay "$REC_FILE" >/dev/null 2>&1; then
                record_result "Audio (Play/Rec/Loop)" "PASS" "Built-in played, 5s recorded ($REC_FILE), playback succeeded"
            else
                record_result "Audio (Play/Rec/Loop)" "FAIL" "Playback of $REC_FILE failed"
            fi
        else
            record_result "Audio (Play/Rec/Loop)" "FAIL" "arecord 5s failed or empty file"
        fi
    else
        record_result "Audio" "SKIP" "No ALSA sound card detected (aplay -l empty)"
    fi
}

test_serial_and_manual_guides() {
    log_line "$CYAN" "\n=================================================================="
    log_line "$CYAN" "  6. SERIAL PORTS (RS232 / RS485) & MANUAL VERIFICATION GUIDES"
    log_line "$CYAN" "=================================================================="

    CONFIGURED_PORTS=""
    MISSING_PORTS=""
    for port in /dev/ttymxc2 /dev/ttymxc3 /dev/ttyRS4850 /dev/ttyRS4851; do
        if [ -c "$port" ]; then
            if stty -F "$port" -echo -onlcr -icanon 115200 2>/dev/null; then
                log_line "$GREEN" "  [OK] Configured $port (-echo -onlcr -icanon 115200)"
                CONFIGURED_PORTS="${CONFIGURED_PORTS} ${port}"
            else
                log_line "$RED" "  [ERR] Failed to configure $port via stty"
                MISSING_PORTS="${MISSING_PORTS} ${port}(err)"
            fi
        else
            log_line "$YELLOW" "  [WARN] Serial node not found: $port"
            MISSING_PORTS="${MISSING_PORTS} ${port}(missing)"
        fi
    done

    if [ -n "$CONFIGURED_PORTS" ] && [ -z "$MISSING_PORTS" ]; then
        record_result "Serial Ports (232/485)" "PASS" "All 4 ports configured at 115200 raw mode"
    elif [ -n "$CONFIGURED_PORTS" ]; then
        record_result "Serial Ports (232/485)" "PASS" "Configured:${CONFIGURED_PORTS} (Missing:${MISSING_PORTS})"
    else
        record_result "Serial Ports (232/485)" "FAIL" "No RS232/RS485 serial nodes found"
    fi

    log_line "$YELLOW" "\n--- [MANUAL VERIFICATION REMINDERS] ---"
    log_line "$BLUE"   "1. RS232 & RS485 Loopback/Transfer Test (Ports configured at 115200):"
    log_line "$NC"     "   - RS232 : /dev/ttymxc2 , /dev/ttymxc3"
    log_line "$NC"     "   - RS485 : /dev/ttyRS4850 , /dev/ttyRS4851"
    log_line "$NC"     "   - Example: cat /dev/ttyRS4850 &  echo 'hello' > /dev/ttyRS4851"
    log_line "$BLUE"   "2. Display & Touch Test:"
    log_line "$NC"     "   - Check LVDS screen display quality and test touchscreen tap/drag response."
    log_line "$BLUE"   "3. Suspend & Wakeup Test Command:"
    log_line "$GREEN"  "   echo mem > /sys/power/state"
    log_line "$BLUE"   "4. Camera Preview Test Command:"
    log_line "$GREEN"  "   /usr/share/examples/multimedia/declarative-camera/declarative-camera"
    log_line "$BLUE"   "5. Reboot & Poweroff Test Commands:"
    log_line "$GREEN"  "   reboot"
    log_line "$GREEN"  "   poweroff"
}

test_gpu_and_vpu() {
    log_line "$CYAN" "\n=================================================================="
    log_line "$CYAN" "  7. GPU (3D/2D) & VPU (1080P HW CODEC) ACCELERATION TESTS"
    log_line "$CYAN" "=================================================================="

    export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/0}"
    if [ -z "$WAYLAND_DISPLAY" ]; then
        WL_SOCK=$(ls "$XDG_RUNTIME_DIR"/wayland-* 2>/dev/null | grep -v '\.lock$' | head -n 1)
        [ -n "$WL_SOCK" ] && export WAYLAND_DISPLAY=$(basename "$WL_SOCK")
    fi

    # 7.1 GPU 3D Hardware Acceleration Test
    if [ -e /dev/galcore ] && command -v glmark2-es2-wayland >/dev/null 2>&1 && [ -n "$WAYLAND_DISPLAY" ]; then
        IRQ_BEFORE=$(awk '/galcore:0/ {print $2}' /proc/interrupts 2>/dev/null | head -n 1)
        IRQ_BEFORE=${IRQ_BEFORE:-0}
        log_line "$BLUE" "Running 2s 3D GPU benchmark (glmark2-es2-wayland)..."
        GL_OUT=$(glmark2-es2-wayland -b build:duration=2.0 2>&1)
        printf "%s\n" "$GL_OUT" | grep -E "GL_VENDOR|GL_RENDERER|FPS:" | tee -a "$LOG_FILE"
        IRQ_AFTER=$(awk '/galcore:0/ {print $2}' /proc/interrupts 2>/dev/null | head -n 1)
        IRQ_AFTER=${IRQ_AFTER:-0}

        if echo "$GL_OUT" | grep -q "Vivante" && [ "$IRQ_AFTER" -gt "$IRQ_BEFORE" ]; then
            RENDERER=$(echo "$GL_OUT" | awk -F': ' '/GL_RENDERER/ {print $2}' | xargs)
            record_result "GPU 3D Acceleration" "PASS" "$RENDERER active (IRQ galcore:0: $IRQ_BEFORE -> $IRQ_AFTER)"
        else
            record_result "GPU 3D Acceleration" "FAIL" "Vivante renderer or IRQ increment not detected"
        fi
    else
        record_result "GPU 3D Acceleration" "SKIP" "/dev/galcore, glmark2-es2-wayland, or Wayland display unavailable"
    fi

    # 7.2 VPU 1080p Hardware Encode + Decode Test
    if command -v gst-launch-1.0 >/dev/null 2>&1 && gst-inspect-1.0 v4l2h264dec >/dev/null 2>&1 && [ -n "$WAYLAND_DISPLAY" ]; then
        VPU_IRQ_BEFORE=$(awk '/hantro/ {sum+=$2} END {print sum+0}' /proc/interrupts 2>/dev/null)
        log_line "$BLUE" "Running 3s 1080p@30fps VPU HW encode+decode pipeline (v4l2h264enc -> v4l2h264dec)..."
        if gst-launch-1.0 videotestsrc num-buffers=90 !             video/x-raw,width=1920,height=1080,framerate=30/1 !             v4l2h264enc ! h264parse ! v4l2h264dec ! waylandsink >/dev/null 2>&1; then
            VPU_IRQ_AFTER=$(awk '/hantro/ {sum+=$2} END {print sum+0}' /proc/interrupts 2>/dev/null)
            if [ "$VPU_IRQ_AFTER" -gt "$VPU_IRQ_BEFORE" ]; then
                record_result "VPU 1080p HW Codec" "PASS" "Hantro HW enc/dec verified (IRQ: $VPU_IRQ_BEFORE -> $VPU_IRQ_AFTER)"
            else
                record_result "VPU 1080p HW Codec" "FAIL" "Pipeline succeeded but VPU IRQ did not increase"
            fi
        else
            record_result "VPU 1080p HW Codec" "FAIL" "GStreamer VPU pipeline failed"
        fi
    else
        record_result "VPU 1080p HW Codec" "SKIP" "GStreamer v4l2h264dec or Wayland display unavailable"
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
test_audio
test_serial_and_manual_guides
test_gpu_and_vpu
print_summary
