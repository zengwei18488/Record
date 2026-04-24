#!/bin/bash

# --- 1. 安裝必要工具 ---
#sudo apt-get update && sudo apt-get install -y secure-delete memtester extundelete

# --- 2. 配置系統自動清理暫存 (防止敏感資訊殘留在 /tmp) ---
# 設定 /tmp 使用 tmpfs (記憶體檔案系統)，重啟即完全消失
if ! grep -q "tmpfs /tmp" /etc/fstab; then
    echo "tmpfs /tmp tmpfs defaults,noatime,nosuid,nodev,mode=1777 0 0" | sudo tee -a /etc/fstab
fi

# --- 3. 配置核心在崩潰時不保留敏感暫存 ---
sudo tee /etc/sysctl.d/54-afe-persistence.conf > /dev/null << EOF
# 減少核心暫存的時間，降低數據殘留風險
vm.dirty_expire_centisecs = 3000
vm.dirty_writeback_centisecs = 500
EOF
sudo sysctl -p /etc/sysctl.d/54-afe-persistence.conf

echo "--- CR 4.02 Information Persistence Hardening Complete ---"
