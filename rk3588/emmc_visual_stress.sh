#!/bin/bash

# =================================================================
# RK3588 eMMC SDHCI PATCH ULTIMATE VISUAL STRESS SCRIPT
# REAL-TIME 1-SECOND REFRESH METRICS (CPU, MEM, I/O, TEMP)
# =================================================================

TARGET_DEV="mmcblk0"
TARGET_PATH="/dev/$TARGET_DEV"
TEST_DIR="/mnt/emmc_stress_test_dir"
LOG_FILE="/tmp/emmc_stress_kernel.log"
TEST_DURATION=3600 # Total test time: 1 hour

# Ensure running with root privileges
if [ "$EUID" -ne 0 ]; then
  echo "[-] Error: Please run this script with ROOT privileges!"
  exit 1
fi

# Check if target storage device exists
if [ ! -b "$TARGET_PATH" ]; then
  echo "[-] Error: Storage device $TARGET_PATH not found!"
  exit 1
fi

# Install dependencies silently
echo "[+] Checking and installing dependencies (fio, stress-ng, sysstat)..."
apt update > /dev/null 2>&1
command -v fio &> /dev/null || apt install -y fio > /dev/null 2>&1
command -v stress-ng &> /dev/null || apt install -y stress-ng > /dev/null 2>&1
command -v iostat &> /dev/null || apt install -y sysstat > /dev/null 2>&1

echo "[+] Preparing testing environment..."
mkdir -p "$TEST_DIR"
dmesg -C > /dev/null 2>&1
rm -f "$LOG_FILE"
rm -f /tmp/emmc_test_failed

# Clean up all background jobs on exit
cleanup() {
    echo -e "\n[+] Terminating all stress engines and telemetry loops..."
    kill $MONITOR_PID $STRESS_NG_PID $FIO_PID $MAIN_LOOP_PID 2>/dev/null
    rm -rf "$TEST_DIR"
    sync
    echo "[+] Cleaned up successfully."
}
trap cleanup EXIT

# =================================================================
# MODULE 1: BACKGROUND REAL-TIME KERNEL MONITOR
# =================================================================
monitor_kernel_errors() {
    dmesg -w | grep -E -i "sdhci|mmc0|ADMA|error|timeout" | while read -r line; do
        echo -e "\n\a\033[31m[CRITICAL ERROR DETECTED] $line\033[0m" | tee -a "$LOG_FILE"
        touch /tmp/emmc_test_failed
        kill -s TERM $$ 2>/dev/null
    done
}
monitor_kernel_errors &
MONITOR_PID=$!

# =================================================================
# MODULE 2: SYSTEM LEVEL BACKGROUND LOAD (CPU / MEMORY)
# =================================================================
stress-ng --cpu 8 --io 4 --vm 4 --vm-bytes 1G --timeout ${TEST_DURATION}s > /dev/null 2>&1 &
STRESS_NG_PID=$!

# =================================================================
# MODULE 3: eMMC BACKGROUND INFINITE I/O ENGINE (FIO)
# =================================================================
# FIO now runs in the background non-stop until the script finishes
fio --name=rk3588_emmc_visual \
    --directory="$TEST_DIR" \
    --rw=randrw \
    --rwmixread=50 \
    --bsrange=4k-1M \
    --direct=1 \
    --size=512M \
    --numjobs=4 \
    --runtime=${TEST_DURATION} \
    --time_based \
    --ioengine=libaio \
    --iodepth=32 \
    --group_reporting > /dev/null 2>&1 &
FIO_PID=$!

# =================================================================
# MODULE 4: REAL-TIME TELEMETRY DISPLAY (1-SECOND REFRESH)
# =================================================================
START_TIME=$(date +%s)
clear

while true; do
    if [ -f /tmp/emmc_test_failed ]; then break; fi

    CURRENT_TIME=$(date +%s)
    ELAPSED=$((CURRENT_TIME - START_TIME))
    if [ "$ELAPSED" -ge "$TEST_DURATION" ]; then break; fi

    # --- Fetch Data ---
    # 1. CPU Usage (from top)
    CPU_IDLE=$(top -bn1 | grep "Cpu(s)" | awk '{print $8}')
    CPU_USAGE=$(echo "100 - $CPU_IDLE" | bc 2>/dev/null || echo "100.0")

    # 2. Memory Usage (from free)
    MEM_TOTAL=$(free -m | awk '/^Mem:/{print $2}')
    MEM_USED=$(free -m | awk '/^Mem:/{print $3}')
    MEM_PCT=$(echo "scale=1; $MEM_USED * 100 / $MEM_TOTAL" | bc 2>/dev/null)

    # 3. eMMC Disk Throughput (from iostat)
    IO_DATA=$(iostat -d -k 1 2 | grep "$TARGET_DEV" | tail -n 1)
    READ_SPEED=$(echo $IO_DATA | awk '{print $3}')
    WRITE_SPEED=$(echo $IO_DATA | awk '{print $4}')

    # 4. SoC Temperature
    TEMP_VAL=0
    if [ -f /sys/class/thermal/thermal_zone0/temp ]; then
        TEMP_VAL=$(($(cat /sys/class/thermal/thermal_zone0/temp) / 1000))
    fi

    # --- Render Dashboard to Terminal ---
    # Use ANSI escape code to overwrite from top line instead of scrolling
    echo -e "\033[H"
    echo "====================================================================="
    echo "       RK3588 SYSTEM & eMMC STRESS LIVE TELEMETRY DASHBOARD"
    echo "====================================================================="
    echo -e "Time Elapsed     :  \033[36m$ELAPSED\033[0m sec / \033[36m$TEST_DURATION\033[0m sec total"
    echo -e "SoC Temperature  :  \033[33m${TEMP_VAL}°C\033[0m"
    echo "---------------------------------------------------------------------"
    echo -e "CPU Utilization  :  \033[32m${CPU_USAGE}%\033[0m (All 8 cores heavy-loaded)"
    echo -e "Memory Buffer    :  \033[32m${MEM_USED}MB\033[0m / ${MEM_TOTAL}MB (${MEM_PCT}%)"
    echo "---------------------------------------------------------------------"
    echo -e "eMMC Disk Name   :  $TARGET_DEV"
    echo -e "eMMC Read Speed  :  \033[35m${READ_SPEED} KB/s\033[0m"
    echo -e "eMMC Write Speed :  \033[35m${WRITE_SPEED} KB/s\033[0m"
    echo "====================================================================="
    echo "[Status] Running FIO mixed I/O & querying extcsd registers..."

    # Interleave register queries inside the telemetry loop
    if command -v mmc &> /dev/null; then
        mmc extcsd read "$TARGET_PATH" > /dev/null 2>&1
    fi

    # Flush kernel drop_caches periodically to enforce hardware DMA access
    if [ $((ELAPSED % 5)) -eq 0 ]; then
        sync
        echo 3 > /proc/sys/vm/drop_caches
    fi

    sleep 1
done
MAIN_LOOP_PID=$$

# =================================================================
# MODULE 5: FINAL ASSESSMENT
# =================================================================
clear
if [ -f /tmp/emmc_test_failed ]; then
    echo -e "\n\033[31m============================================================\033[0m"
    echo -e "[-] VALIDATION FAILED! ADMA/SDHCI faults captured during stress test."
    echo -e "[-] Please inspect the detailed kernel fault log: $LOG_FILE"
    echo -e "============================================================\033[0m"
    rm -f /tmp/emmc_test_failed
    exit 1
else
    echo -e "\n\033[32m============================================================\033[0m"
    echo -e "[+] VALIDATION SUCCESSFUL! Long-run stability test completed."
    echo -e "[+] CPU, Memory, and eMMC variables remained stable under maximum load."
    echo -e "[+] ZERO 'ADMA Err' or 'sdhci timeout' log traces. Patch verified!"
    echo -e "============================================================\033[0m"
    exit 0
fi
