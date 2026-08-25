#!/bin/bash
# Step 3: Compare Information and Cleanup Script

# ==================== MANUAL STAGE VERIFICATION ====================
if [ ! -f /root/test_stage.txt ]; then
    echo "Error: [test_stage.txt] not found! Cannot perform comparison."
    exit 1
fi

CURRENT_STAGE=$(cat /root/test_stage.txt | tr -d '[:space:]')
if [ "$CURRENT_STAGE" != "STAGE3" ]; then
    echo "Error: Wrong test stage! Current state is [$CURRENT_STAGE], expected [STAGE3]."
    exit 1
fi
echo "[ OK ] Stage verification passed. Starting comparison..."
# ===================================================================

echo "===== [Step 3] Start comparing system info before and after update ====="
RESULT="PASS"

# Get the unique path of the latest backup
if [ ! -f /root/latest_backup_dir.txt ]; then
    echo "Error: Latest backup record file not found, cannot compare!"
    exit 1
fi
BACKUP_DIR=$(cat /root/latest_backup_dir.txt)
echo "Comparing current system with backup data in [ $BACKUP_DIR ]..."

# 1. Compare Board Info
if [ -f /proc/board ]; then
    cat /proc/board > "${BACKUP_DIR}/board_info.curr"
else
    echo "none" > "${BACKUP_DIR}/board_info.curr"
fi

if diff -q "${BACKUP_DIR}/board_info.bak" "${BACKUP_DIR}/board_info.curr" >/dev/null; then
    echo "[ OK ] Board information matches."
else
    echo "[FAIL] Board information changed!"
    RESULT="FAIL"
fi

# 2. Compare eth0 MAC
ifconfig eth0 | grep -oE '([0-9a-fA-F]{2}:){5}[0-9a-fA-F]{2}' > "${BACKUP_DIR}/eth0_mac.curr" || echo "none" > "${BACKUP_DIR}/eth0_mac.curr"
if [ "$(cat ${BACKUP_DIR}/eth0_mac.bak)" = "$(cat ${BACKUP_DIR}/eth0_mac.curr)" ]; then
    echo "[ OK ] eth0 MAC address matches: $(cat ${BACKUP_DIR}/eth0_mac.curr)"
else
    echo "[FAIL] eth0 MAC address mismatch! (Before: $(cat ${BACKUP_DIR}/eth0_mac.bak) -> After: $(cat ${BACKUP_DIR}/eth0_mac.curr))"
    RESULT="FAIL"
fi

# 3. Compare eth1 MAC
ifconfig eth1 | grep -oE '([0-9a-fA-F]{2}:){5}[0-9a-fA-F]{2}' > "${BACKUP_DIR}/eth1_mac.curr" || echo "none" > "${BACKUP_DIR}/eth1_mac.curr"
if [ "$(cat ${BACKUP_DIR}/eth1_mac.bak)" = "$(cat ${BACKUP_DIR}/eth1_mac.curr)" ]; then
    echo "[ OK ] eth1 MAC address matches: $(cat ${BACKUP_DIR}/eth1_mac.curr)"
else
    echo "[FAIL] eth1 MAC address mismatch! (Before: $(cat ${BACKUP_DIR}/eth1_mac.bak) -> After: $(cat ${BACKUP_DIR}/eth1_mac.curr))"
    RESULT="FAIL"
fi

echo "=========================================="
echo "Final Test Result: [ ${RESULT} ]"
echo "=========================================="

# ===== Cleanup Environment =====
echo "===== Start cleaning up backup data for this test ====="

# 1. Delete the temporary directory holding individual validation files (.bak/.curr)
if [ -d "$BACKUP_DIR" ] && [ "$BACKUP_DIR" != "/root" ] && [ "$BACKUP_DIR" != "/" ]; then
    rm -rf "$BACKUP_DIR"
    echo "Successfully deleted unique backup directory: $BACKUP_DIR"
fi

# 2. Force delete all temporary state machine files and pointers
rm -f /root/latest_backup_dir.txt
rm -f /root/permanent_log_name.txt
rm -f /root/test_stage.txt
echo "Successfully cleared all configuration files and state pointers (latest_backup_dir, permanent_log_name, test_stage)."

echo "Notice: The permanent file /root/system_info_*.log has been preserved."
echo "Environment cleanup completed. System restored to clean state."
