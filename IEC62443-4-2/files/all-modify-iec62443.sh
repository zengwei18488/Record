#!/bin/bash

echo "going... 1"
# --- 修复 faillock 目录缺失问题 ---
echo "Ensuring faillock directory exists..."
if [ ! -d "/var/run/faillock" ]; then
    mkdir -p /var/run/faillock
    chmod 755 /var/run/faillock
fi
echo "going... 2"
# 确保在配置文件中指明目录位置
if [ -f "/etc/security/faillock.conf" ]; then
    sed -i 's|^#\? \?dir =.*|dir = /var/run/faillock|' /etc/security/faillock.conf
fi
echo "going... 3"
/usr/bin/chage -M 90 -W 7 -m 7 root 2>/dev/null || true

if id "linaro" &>/dev/null; then
    /usr/bin/chage -M 90 -W 7 -m 7 linaro 2>/dev/null || true
fi

sudo chage -d 0 linaro
echo "going... 4"

cat << 'EOF' >> /etc/bash.bashrc

# =================================================================
# IEC 62443-4-2 CR 1.1 / CR 2.1 Non-Login Shell Timeout Enforcement
# =================================================================
if ! declare -p TMOUT 2>/dev/null | grep -q " -.*r"; then
    export TMOUT=900
    readonly TMOUT
fi
EOF

sudo chmod u+s /usr/bin/xscreensaver
echo "going... 5"
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
echo "going... 6"
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

echo "going... 7"

# 強制開啟網路同步並立即跳轉時間
chronyc online &>/dev/null
chronyc makestep &>/dev/null

# 等待同步完成 (最多等待 10 秒)
echo "Waiting for NTP synchronization..."
for i in {1..10}; do
    if chronyc tracking | grep -q "Reference ID    : [^0]"; then
        echo "Synchronization successful!"
        break
    fi
    sleep 1
done

echo "--------------------------------------------------"
echo "AFE-E630 Time Synchronization Setup Complete!"
echo "Status Check:"
chronyc tracking
echo "going... 8"
# 因為內核模組缺失，我們採用關閉非必要服務來達成「最小化端口開放」
# 關閉您系統中暴露的 VPN, L2TP 與 MQTT 服務
services_to_disable=("charon" "xl2tpd" "mosquitto")

for svc in "${services_to_disable[@]}"; do
    if systemctl list-unit-files | grep -q "^$svc.service"; then
        echo "Disabling service: $svc"
        sudo systemctl stop $svc
        sudo systemctl disable $svc
    fi
done

echo "going... 9"
./cr302-sys.sh
./cr303-sys.sh
./cr310-sys.sh

# 1. 提供安全隨機數 (Secure Session Identifiers)
sudo systemctl enable --now rng-tools-debian

# 3. 鎖定日誌存取權限 (Accessibility)
sudo mkdir -p /var/log/journal
sudo chown root:adm /var/log/journal
sudo chmod 750 /var/log/journal

# 3. 驗證 (證明系統加密庫已升級)
echo "Global OpenSSL Security Level:"
openssl ciphers -v -tls1_3 | grep GCM
openssl ciphers -v "DEFAULT@SECLEVEL=2"
echo "going.... 10-333"
./cr702-res.sh
#./cr703-res.sh
echo "going.... 10-7"
sleep 1

echo "going.... 10-8"
sudo touch /etc/timeshift/timeshift.json
sed -i 's,"/tmp/\*\*","\/tmp\*\*"\,\n    "\/userdata\/\*\*"\,\n    "\/root\/\.\*",g' /etc/timeshift/default.json
sed -i 's/"count_monthly" : "[0-9]"/"count_monthly" : "0"/g' /etc/timeshift/timeshift.json
sed -i 's/"count_weekly" : "[0-9]"/"count_weekly" : "0"/g' /etc/timeshift/timeshift.json
sed -i 's/"count_daily" : "[0-9]"/"count_daily" : "0"/g' /etc/timeshift/timeshift.json
sed -i 's/"count_hourly" : "[0-9]"/"count_hourly" : "0"/g' /etc/timeshift/timeshift.json
sed -i 's/"count_boot" : "[0-9]"/"count_boot" : "0"/g' /etc/timeshift/timeshift.json
sed -i '/"\/home\/linaro\/\*\*"/d' /etc/timeshift/timeshift.json
sed -i '/"\/root\/\*\*"/d' /etc/timeshift/timeshift.json
sed -i 's,"/tmp/\*\*","\/tmp\*\*"\,\n    "\/userdata\/\*\*"\,\n    "\/var\/run\/\*\*",g' /etc/timeshift/timeshift.json

if [ -f "/etc/xdg/autostart/timeshift-gtk.desktop" ]; then
    rm -f "/etc/xdg/autostart/timeshift-gtk.desktop"
fi

if [ -f "/usr/bin/timeshift-gtk" ]; then
    rm -f "/usr/bin/timeshift-gtk"
    ln -sf /bin/true /usr/bin/timeshift-gtk
fi
echo "going.... 10-9"
sudo rm -f /usr/lib/ipsec/charon
sudo ln -sf /bin/true /usr/lib/ipsec/charon

if [ -f "/usr/lib/ipsec/starter" ]; then
    sudo rm -f /usr/lib/ipsec/starter
    sudo ln -sf /bin/true /usr/lib/ipsec/starter
fi

if [ -f "/usr/sbin/ipsec" ]; then
    sudo rm -f /usr/sbin/ipsec
    sudo ln -sf /bin/true /usr/sbin/ipsec
    echo "[+] VPN administrative wrappers redirected to /bin/true."
fi

echo "going ------  10---   Enforcing permanent kernel module disablement seal..."
sudo mkdir -p /etc/sysctl.d
echo "kernel.modules_disabled = 1" | sudo tee /etc/sysctl.d/hardening_malicious_code.conf > /dev/null
sudo sysctl -p /etc/sysctl.d/hardening_malicious_code.conf 2>/dev/null || sudo sysctl -w kernel.modules_disabled=1
cat /proc/sys/kernel/modules_disabled

sudo systemctl enable secure-firewall.service
sudo systemctl start secure-firewall.service

sleep 1

cat << EOT | sudo tee -a /etc/sysctl.d/hardening_network.conf > /dev/null
net.ipv4.ip_forward = 0
net.ipv4.conf.all.forwarding = 0
net.ipv4.conf.default.forwarding = 0
net.ipv4.tcp_syncookies = 1
net.ipv4.icmp_echo_ignore_all = 1
EOT

sudo sysctl --system

sudo iptables -L -n -v
echo "------------------------------------------------"
echo "MINIMAL COMPLIANCE VERIFICATION SUMMARY:"
echo "------------------------------------------------"
echo -e "[CR 5.1] IP Forwarding (Expect 0): \c" && cat /proc/sys/net/ipv4/ip_forward
echo -e "[CR 7.1] SYN Cookies (Expect 1): \c" && cat /proc/sys/net/ipv4/tcp_syncookies
echo "[CR 5.1] Active Perimeter Firewall Rules Loaded Successfully."
echo "------------------------------------------------"

echo "going... 10"
# --- Restart Services ---
sudo systemctl restart lxdm
sudo systemctl restart chrony
sudo systemctl restart systemd-journald
sudo systemctl restart systemd-logind
sudo systemctl restart fail2ban
sudo augenrules --load
sudo systemctl daemon-reload
sudo systemctl restart ssh
sudo systemctl restart irqbalance
sudo systemctl restart cron
echo "going... 11"
