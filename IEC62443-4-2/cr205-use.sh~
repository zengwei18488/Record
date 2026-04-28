#!/bin/bash

# =================================================================
# Project: AFE-E630 (Linaro/Debian 12)
# Purpose: Comprehensive Session Termination (CR 2.05) - Standard Blank Mode
# Includes: SSH Timeout, XScreenSaver (Standard), PAM Fix, Shortcut
# =================================================================

# 檢查 root 權限
if [ "$EUID" -ne 0 ]; then 
  echo "Error: Please run as root (sudo)."
  exit 1
fi

echo "--- 1. Configuring SSH & CLI Timeout (SUPER ENFORCED) ---"

SSHD_CONFIG="/etc/ssh/sshd_config"

# 確保檔案權限，防止因權限過大導致 SSH 忽略設定
sudo chown root:root $SSHD_CONFIG
sudo chmod 644 $SSHD_CONFIG

# [超級強化 A]：清除所有重複項目，確保設定唯一且生效
sudo sed -i '/ClientAliveInterval/d' $SSHD_CONFIG
sudo sed -i '/ClientAliveCountMax/d' $SSHD_CONFIG
sudo sed -i '/TCPKeepAlive/d' $SSHD_CONFIG
sudo sed -i '/MaxStartups/d' $SSHD_CONFIG
sudo sed -i '/MaxSessions/d' $SSHD_CONFIG

# [超級強化 B]：寫入強制斷開邏輯
sudo tee -a $SSHD_CONFIG > /dev/null << EOF
# --- IEC 62443 CR 2.05 Hardening ---
ClientAliveInterval 300
ClientAliveCountMax 0
TCPKeepAlive no
MaxSessions 5
MaxStartups 10:30:60
EOF

# 註：ClientAliveCountMax 設為 0 代表只要一次 300 秒沒回應就「立即」踢掉
# 這是最嚴格的設定，不給客戶端任何緩衝機會。

echo "session required pam_limits.so" | sudo tee -a /etc/pam.d/sshd

sudo systemctl restart ssh

LIMITS_CONF="/etc/security/limits.conf"

# 清除舊的 maxlogins 設定
sudo sed -i '/maxlogins/d' $LIMITS_CONF

# 寫入強制限制 (Hard Limits)
sudo tee -a $LIMITS_CONF > /dev/null << EOF
*               hard    maxlogins       10
root            hard    maxlogins       10
EOF

# 本地 Shell (CLI) 超時設定
sudo tee /etc/profile.d/session_timeout.sh > /dev/null << EOF
# IEC 62443 CR 2.05: Global Session Timeout
readonly TMOUT=900
export TMOUT
EOF

sudo chmod 644 /etc/profile.d/session_timeout.sh

echo "--- 2. Installing and Patching XScreenSaver (Standard Mode) ---"
# 移除先前可能殘留的自定義全域配置，恢復原樣
sudo rm -f /etc/X11/app-defaults/XScreenSaver

# 安裝套件
#sudo apt-get update && sudo apt-get install -y xscreensaver xscreensaver-data-extra dbus-x11

# 修復 PAM 驗證與權限 (確保能輸入密碼正常解鎖)
if [ ! -f /etc/pam.d/xscreensaver ]; then
    sudo cp /etc/pam.d/common-auth /etc/pam.d/xscreensaver
fi
sudo chmod u+s /usr/bin/xscreensaver

# 為所有使用者設定「普通黑屏模式」
for user_home in /home/*; do
    if [ -d "$user_home" ]; then
        USERNAME=$(basename "$user_home")
        # mode: blank (黑屏不跑動畫), timeout: 15分鐘, lock: True
        cat <<EOF > "$user_home/.xscreensaver"
mode: blank
timeout: 0:15:00
lock: True
lockTimeout: 0:00:00
EOF
        chown "$USERNAME":"$USERNAME" "$user_home/.xscreensaver"
        
        # 建立個人自啟動目錄與檔案
        mkdir -p "$user_home/.config/autostart"
        cat <<EOF > "$user_home/.config/autostart/xscreensaver.desktop"
[Desktop Entry]
Type=Application
Name=XScreenSaver
Exec=xscreensaver -nosplash
EOF
        chown -R "$USERNAME":"$USERNAME" "$user_home/.config"
    fi
done

echo "--- 3. Configuring Manual Lock Shortcut (Ctrl+Alt+L) ---"
# 針對 Openbox 設定檔添加快捷鍵
CONFIG_PATHS=("/etc/xdg/openbox/rc.xml" "/usr/share/lxde/openbox/rc.xml" "$HOME/.config/openbox/rc.xml")
SHORTCUT_XML='  <keybind key="C-A-l"> \
    <action name="Execute"> \
      <command>xscreensaver-command -lock</command> \
    </action> \
  </keybind>'

for RC_XML in "${CONFIG_PATHS[@]}"; do
    if [ -f "$RC_XML" ]; then
        sudo cp "$RC_XML" "${RC_XML}.bak"
        if ! grep -q "xscreensaver-command -lock" "$RC_XML"; then
            sudo sed -i "/<\/keyboard>/i $SHORTCUT_XML" "$RC_XML"
            echo "Shortcut added to $RC_XML"
        fi
    fi
done

echo "--------------------------------------------------"
echo "Setup Complete for AFE-E630!"
echo "Standard Mode: Lock screen will show username for reliability."
echo "[CR 2.05] Remote: 5m Timeout | Local: 15m Timeout"
echo "[CR 2.06] Max SSH Sessions: 5 | Max Total Logins: 10"
echo "Please REBOOT the device to apply all changes."
echo "--------------------------------------------------"
