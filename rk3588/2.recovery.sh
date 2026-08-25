#!/bin/bash
# Step 2: Restore Boot Partitions Script

# ==================== MANUAL STAGE VERIFICATION ====================
if [ ! -f /root/test_stage.txt ]; then
    echo "Error: [test_stage.txt] not found! Did you run step1 successfully first?"
    exit 1
fi

CURRENT_STAGE=$(cat /root/test_stage.txt | tr -d '[:space:]')
if [ "$CURRENT_STAGE" != "STAGE2" ]; then
    echo "Error: Wrong test stage! Current state is [$CURRENT_STAGE], expected [STAGE2]."
    exit 1
fi
echo "[ OK ] Stage verification passed. Preparing to restore boot partitions..."
# ===================================================================

# Get the unique path of the latest backup
if [ ! -f /root/latest_backup_dir.txt ]; then
    echo "Error: Latest backup record file not found!"
    exit 1
fi
BACKUP_DIR=$(cat /root/latest_backup_dir.txt)

# Check if backup files exist in the unique directory
if [ ! -f "${BACKUP_DIR}/mmcblk0boot0.bak" ] || [ ! -f "${BACKUP_DIR}/mmcblk0boot1.bak" ]; then
    echo "Error: Boot backup files not found in [ $BACKUP_DIR ]!"
    exit 1
fi

echo "===== [Step 2] Disabling eMMC write protection ====="
echo 0 > /sys/block/mmcblk0boot0/force_ro
echo 0 > /sys/block/mmcblk0boot1/force_ro

echo "===== [Step 2] Restoring boot partitions from $BACKUP_DIR ====="
dd if="${BACKUP_DIR}/mmcblk0boot0.bak" of=/dev/mmcblk0boot0 bs=4M conv=notrunc,fdatasync 2>/dev/null
dd if="${BACKUP_DIR}/mmcblk0boot1.bak" of=/dev/mmcblk0boot1 bs=4M conv=notrunc,fdatasync 2>/dev/null

# Re-enable write protection for safety
echo 1 > /sys/block/mmcblk0boot0/force_ro
echo 1 > /sys/block/mmcblk0boot1/force_ro
echo "Boot partitions restoration completed successfully."

# ==================== SWITCH TO NEXT STAGE ====================
echo "STAGE3" > /root/test_stage.txt
sync
echo "Test stage advanced to STAGE3."
# ==============================================================

echo "System will reboot in 3 seconds for the final comparison stage..."
sleep 3
reboot

