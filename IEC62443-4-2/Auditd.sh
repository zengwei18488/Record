#!/bin/bash
# IEC 62443 Compliance Hardening Script - FINAL REVISED
# Target: RK3568 Debian 12 (AARCH64)
# Coverage: CR 2.08, CR 2.09, CR 2.10, CR 6.01 + Boot Failure Fix

set -e

echo "--- Starting FINAL IEC 62443 Audit Hardening ---"

# 1. 確保必要套件安裝
echo "[Step 1] Ensuring Audit packages..."

# 2. 定義路徑
AUDIT_RULES="/etc/audit/rules.d/audit.rules"
AUDITD_CONF="/etc/audit/auditd.conf"
SERVICE_OVERRIDE_DIR="/etc/systemd/system/auditd.service.d"

# 4. 配置審計規則 (CR 6.01, CR 2.08)
# 修正：開啟 -e 2 鎖定模式
echo "[Step 3] Applying Immutable Audit Rules (CR 6.01)..."
sudo bash -c "cat << 'EOT' > $AUDIT_RULES
-D
-b 8192
-a always,exit -F arch=aarch64 -S execve -k exec_tracking
-w /etc/systemd/ -p wa -k sys_config
-w /etc/audit/ -p wa -k audit_config
-w /var/log/audit/ -p wa -k audit_logs
-w /etc/passwd -p wa -k identity
-w /etc/shadow -p wa -k identity
-w /etc/group -p wa -k identity
-w /etc/sudoers -p wa -k priv_esc
-w /etc/sudoers.d/ -p wa -k priv_esc
-a always,exit -F arch=aarch64 -S connect,accept,bind -F auid>=1000 -F auid!=4294967295 -k net_events
## Monitor USB Device Nodes (CR 3.09)
-w /dev/bus/usb/ -p wa -k usb_device_event
## Monitor Kernel Module Loading (CR 3.09/CR 2.04)
-w /sbin/insmod -p x -k module_insertion
-w /sbin/modprobe -p x -k module_insertion
-w /sbin/rmmod -p x -k module_removal

## CR 6.01: Final lock. Rules cannot be changed until reboot.
-e 2
EOT"

# 5. 配置日誌存儲與報警策略 (CR 2.08, CR 2.09)
echo "[Step 4] Configuring Log Rotation & Alarms..."
sudo sed -i "s|^max_log_file =.*|max_log_file = 100|" $AUDITD_CONF
sudo sed -i "s|^num_logs =.*|num_logs = 10|" $AUDITD_CONF
sudo sed -i "s|^space_left =.*|space_left = 50|" $AUDITD_CONF
sudo sed -i "s|^admin_space_left =.*|admin_space_left = 15|" $AUDITD_CONF
sudo sed -i "s|^admin_space_left_action =.*|admin_space_left_action = SYSLOG|" $AUDITD_CONF
sudo sed -i "s|^disk_full_action =.*|disk_full_action = SYSLOG|" $AUDITD_CONF
sudo sed -i "s|^disk_error_action =.*|disk_error_action = SYSLOG|" $AUDITD_CONF

# 6. 配置服務持續性 (CR 2.10)
# 修正：強制覆蓋 systemd 的 Restart=no 預設值
echo "[Step 5] Forcing Audit Daemon persistence (CR 2.10)..."
sudo mkdir -p "$SERVICE_OVERRIDE_DIR"
sudo bash -c "cat << 'UNIT' > $SERVICE_OVERRIDE_DIR/override.conf
[Service]
Restart=always
RestartSec=5s
UNIT"

# 7. 啟動服務
echo "[Step 6] Reloading and activating..."
sudo systemctl daemon-reload
sudo systemctl restart auditd

# 最終檢查
echo "--- FINAL CHECK ---"
sudo auditctl -s | grep "enabled"
systemctl show auditd.service --property=Restart

echo "Verification Complete. Please REBOOT to apply Immutable Mode (-e 2)."
