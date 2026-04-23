#!/bin/bash

# =================================================================
# Project: AFE-E630 (RK3568 / Debian 12)
# Purpose: Direct Modification of GRUB for IMA/EVM
# Usage: sudo bash setup_ima_direct.sh [fix|enforce]
# =================================================================

MODE=$1
if [[ "$MODE" != "fix" && "$MODE" != "enforce" ]]; then
    echo "Usage: $0 [fix|enforce]"
    echo "  fix:     Calculate hashes without blocking (Initial Setup)"
    echo "  enforce: Stop execution if hash mismatch (Production)"
    exit 1
fi

TARGET_CFG="/boot/grub/grub.cfg"
IMA_PARAMS="ima_policy=tcb ima_appraise=$MODE ima_hash=sha256"

if [ ! -f "$TARGET_CFG" ]; then
    echo "Error: $TARGET_CFG not found."
    exit 1
fi

echo "--- Configuring IMA/EVM to mode: $MODE ---"

# 1. 備份原始檔案
sudo cp "$TARGET_CFG" "${TARGET_CFG}.bak"

# 2. 清除可能存在的舊參數（避免重複疊加）
sudo sed -i "s/ima_policy=tcb ima_appraise=[a-z]* ima_hash=sha256//g" "$TARGET_CFG"

# 3. 將新參數加入到 linux 開頭的那一行末尾
# 注意：在 RK3568 上這行通常包含 vmlinuz 或 Image
sudo sed -i "/^[[:space:]]*linux/ s/$/ $IMA_PARAMS/" "$TARGET_CFG"

echo "Done. Parameters injected into $TARGET_CFG"
echo "Current boot line:"
grep "^[[:space:]]*linux" "$TARGET_CFG"

echo "--------------------------------------------------"
echo "Please REBOOT now."
echo "After reboot, verify with: cat /proc/cmdline"
echo "--------------------------------------------------"
