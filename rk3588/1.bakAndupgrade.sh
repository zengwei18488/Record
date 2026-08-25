#!/bin/bash
set -e

# ==================== IDEMPOTENT PRE-CHECK (ANTI-DUPLICATE) ====================
if [ -f /root/latest_backup_dir.txt ] || [ -f /root/test_stage.txt ]; then
    echo "================================================================="
    echo "Notice: Backup already exists or test is already in progress."
    echo "Skipping Step 1 to prevent duplicate operations."
    echo "Current stage indicator: $(cat /root/test_stage.txt 2>/dev/null || echo "STAGE1 (Dir exists)")"
    echo "================================================================="
    exit 0
fi
# ========================================================================

# ==================== PARAMETER PARSING START ====================
FORCE_MODE="false"

# Only check the very first argument ($1), ignore any subsequent ones
if [ "$1" = "-f" ]; then
    FORCE_MODE="true"
    echo "Notice: Force mode (-f) enabled. fwrev safety check will be bypassed."
fi
# ===================== PARAMETER PARSING END =====================

# 1. Generate unique identifiers and directory
OP_TIME=$(date +%Y%m%d_%H%M%S)
BATCH_ID="backup_${OP_TIME}_$((RANDOM%8999+1000))"
BACKUP_DIR="/root/${BATCH_ID}"
mkdir -p "$BACKUP_DIR"

# Record the current backup directory path for step2 and step3
echo "$BACKUP_DIR" > /root/latest_backup_dir.txt

# Record the exact log filename to let step3 know which file to protect from deletion
echo "system_info_${OP_TIME}.log" > /root/permanent_log_name.txt

echo "===== [Step 1] Start backup to unique directory: $BACKUP_DIR ====="
dd if=/dev/mmcblk0boot0 of="${BACKUP_DIR}/mmcblk0boot0.bak" bs=4M 2>/dev/null
dd if=/dev/mmcblk0boot1 of="${BACKUP_DIR}/mmcblk0boot1.bak" bs=4M 2>/dev/null
echo "Boot partitions backup completed."

# 2. Save individual files for Step 3 automated check
if [ -f /proc/board ]; then
    cat /proc/board > "${BACKUP_DIR}/board_info.bak"
else
    echo "Warning: /proc/board does not exist" > "${BACKUP_DIR}/board_info.bak"
fi

ifconfig eth0 | grep -oE '([0-9a-fA-F]{2}:){5}[0-9a-fA-F]{2}' > "${BACKUP_DIR}/eth0_mac.bak" || echo "none" > "${BACKUP_DIR}/eth0_mac.bak"
ifconfig eth1 | grep -oE '([0-9a-fA-F]{2}:){5}[0-9a-fA-F]{2}' > "${BACKUP_DIR}/eth1_mac.bak" || echo "none" > "${BACKUP_DIR}/eth1_mac.bak"

# 3. Gather ALL information into one single permanent file and print to serial console (tee)
echo "===== [Step 1] Gathering and Printing Comprehensive System Info ====="
{
    echo "=================================================="
    echo " Operation Time: $(date '+%Y-%m-%d %H:%M:%S')"
    echo "=================================================="
    
    echo -e "\n[Board Information]"
    cat "${BACKUP_DIR}/board_info.bak"

    echo -e "\n[Network MAC Addresses]"
    echo "eth0: $(cat ${BACKUP_DIR}/eth0_mac.bak)"
    echo "eth1: $(cat ${BACKUP_DIR}/eth1_mac.bak)"

    echo -e "\n[eMMC Hardware Information]"
    echo "--- mmc prv info ---"
    PRV_FILES=$(find /sys/ -name prv 2>/dev/null | grep mmc0 || true)
    if [ ! -z "$PRV_FILES" ]; then
        for f in $PRV_FILES; do echo "[$f]: $(cat $f)"; done
    else
        echo "none"
    fi

    echo "--- mmc fwrev info ---"
    FWREV_FILES=$(find /sys/ -name fwrev 2>/dev/null | grep mmc0 || true)
    if [ ! -z "$FWREV_FILES" ]; then
        for f in $FWREV_FILES; do echo "[$f]: $(cat $f)"; done
    else
        echo "none"
    fi
    echo "=================================================="
} | tee "/root/system_info_${OP_TIME}.log"

echo "Permanent system log successfully saved to /root/system_info_${OP_TIME}.log"

# ==================== PRE-CHECK LOGIC WITH FORCE MODE ====================
if [ "$FORCE_MODE" = "true" ]; then
    echo "===== [Step 1] Bypassing eMMC fwrev check due to Force Mode ====="
else
    echo "===== [Step 1] Checking eMMC fwrev value ====="
    FWREV_NODE=$(find /sys/ -name fwrev 2>/dev/null | grep mmc0 | head -n 1 || true)

    if [ -z "$FWREV_NODE" ] || [ ! -f "$FWREV_NODE" ]; then
        echo "[FAIL] Error: eMMC fwrev file node not found in /sys/!"
        rm -rf "$BACKUP_DIR"
        rm -f /root/latest_backup_dir.txt /root/permanent_log_name.txt /root/system_info_${OP_TIME}.log
        exit 1
    fi

    CHECK_FWREV=$(cat "$FWREV_NODE" | tr -d '[:space:]')
    echo "Detected eMMC fwrev: $CHECK_FWREV"

    if [ "$CHECK_FWREV" = "0x0000040000000000" ]; then
        echo "================================================================="
        echo "[FAIL] Error: Forbidden fwrev value (0x0000040000000000) matched!"
        echo "Upgrade aborted. Use '-f' argument if you want to force upgrade."
        echo "================================================================="
        rm -rf "$BACKUP_DIR"
        rm -f /root/latest_backup_dir.txt /root/permanent_log_name.txt /root/system_info_${OP_TIME}.log
        exit 1
    fi

    echo "[ OK ] fwrev verification successful. Proceeding to upgrade..."
fi
# =========================================================================

# 4. Start eMMC tool upgrade procedure
echo "===== [Step 1] Start executing eMMC update program ====="
if [ ! -f /root/emmc_tool ] || [ ! -f /root/FFU.pkg ]; then
    echo "Error: Missing /root/emmc_tool or /root/FFU.pkg"
    exit 1
fi
chmod +x /root/emmc_tool

rm -f /root/emmc_tool_output.log

echo "Running emmc_tool... Please wait."
set +e
/root/emmc_tool -d /dev/mmcblk0 -u /root/FFU.pkg 2>&1 | tee /root/tool_output.log
set -e

if grep -q "Please restart to complete the emmc update." /root/tool_output.log; then
    echo "================================================================="
    echo "Key message detected: 'Please restart to complete the emmc update.'"
    echo "eMMC update firmware applied successfully!"
    echo "================================================================="
    rm -f /root/tool_output.log
else
    echo "================================================================="
    echo "[FAIL] Error: eMMC update failed!"
    echo "The required success string was NOT found in the tool output above."
    echo "Upgrade aborted. System will NOT reboot."
    echo "================================================================="
    rm -rf "$BACKUP_DIR"
    rm -f /root/latest_backup_dir.txt /root/permanent_log_name.txt
    mv /root/tool_output.log /root/tool_output-Fail_${OP_TIME}.log
    mv /root/system_info_${OP_TIME}.log /root/system_info_Fail_${OP_TIME}.log
    exit 1
fi

# Set stage 2 flag file for systemd state machine before rebooting
echo "STAGE2" > /root/test_stage.txt
sync

echo "System will reboot in 3 seconds..."
sleep 3
reboot
