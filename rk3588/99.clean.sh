#!/bin/bash
# Emergency Cleanup & Initialization Script for eMMC Test

echo "===== [RESET] Starting Full System State Initialization ====="

# 1. Read latest backup directory before deletion to clean it up properly
if [ -f /root/latest_backup_dir.txt ]; then
    BACKUP_DIR=$(cat /root/latest_backup_dir.txt)
    if [ -d "$BACKUP_DIR" ] && [ "$BACKUP_DIR" != "/root" ] && [ "$BACKUP_DIR" != "/" ]; then
        rm -rf "$BACKUP_DIR"
        echo "[ OK ] Removed temporary validation folder: $BACKUP_DIR"
    fi
fi

# 2. Blindly clean up any timestamped folders left behind in /root/ just in case
rm -rf /root/backup_20[0-9]*_[0-9]*_* 2>/dev/null || true
echo "[ OK ] Purged any remaining orphaned backup directories."

# 3. Force delete all temporary state machine files and flags
rm -f /root/latest_backup_dir.txt
rm -f /root/permanent_log_name.txt
rm -f /root/test_stage.txt
rm -f /tmp/emmc_tool_output.log
echo "[ OK ] Cleared all operational state files (latest_backup_dir, permanent_log_name, test_stage)."

# 4. Safely restore eMMC boot partitions hardware write protection
if [ -e /sys/block/mmcblk0boot0/force_ro ]; then
    echo 1 > /sys/block/mmcblk0boot0/force_ro
    echo 1 > /sys/block/mmcblk0boot1/force_ro
    echo "[ OK ] Re-enabled eMMC hardware write protection safely."
fi

echo "=========================================================="
echo " SYSTEM STATE INITIALIZATION COMPLETED SUCCESSFULLY! "
echo " Notice: Permanent logs (/root/system_info_*.log) are kept."
echo "=========================================================="
