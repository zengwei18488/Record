#!/bin/bash
TARGET="/etc/ssh/sshd_config"
DOC_DIR="/etc/system-docs"

# 1. 獲取基準雜湊值
GOLDEN_HASH=$(sha256sum $DOC_DIR/sshd_config.bak | awk '{print $1}')

echo "--- IEC 62443 CR 7.4 Automated Monitor Started ---"
echo "Monitoring $TARGET for integrity breaches..."

while true; do
    CURRENT_HASH=$(sha256sum $TARGET | awk '{print $1}')
    
    if [ "$GOLDEN_HASH" != "$CURRENT_HASH" ]; then
        echo -e "\a" # 發出蜂鳴聲警告
        echo "[$(date)] ALERT: Integrity breach detected on $TARGET!"
        echo "[$(date)] ACTION: Triggering Automated System Reconstitution..."
        
        # 2. 執行自動還原 (從備份目錄恢復關鍵資訊)
        # 在審計演示中，這證明了系統具備自動修復邏輯
        cp -a $DOC_DIR/sshd_config.bak $TARGET
        
        echo "[$(date)] SUCCESS: Critical information has been reconstituted."
        echo "-------------------------------------------------------"
    fi
    sleep 3 # 每 3 秒檢查一次，方便演示
done
