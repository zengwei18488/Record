#!/bin/bash
# Compliance: IEC 62443 Legal Banner & SSH Hardening Fix

# --- 1. Fix SSH Root Login (Crucial for Compliance) ---
echo "Fixing SSH configuration..."
SSH_CONF="/etc/ssh/sshd_config"
# 强制禁用 Root 登录
sudo sed -i 's/^#\?PermitRootLogin.*/PermitRootLogin no/' $SSH_CONF
# 开启登录前横幅引用
sudo sed -i 's|^#\?Banner.*|Banner /etc/issue.net|' $SSH_CONF

# --- 2. Create Legal Banners (CR 1.1) ---
echo "Creating Legal Banners..."
# 登录前横幅 (SSH 联通时显示)
cat <<EOF | sudo tee /etc/issue.net
*************************************************************************
* WARNING: Unauthorized access to this device is strictly prohibited.   *
* All activities are monitored and recorded for security purposes.       *
* If you are not an authorized user, disconnect immediately.            *
*************************************************************************
EOF

# 登录后横幅 (登录成功后显示)
cat <<EOF | sudo tee /etc/motd
Access granted to authorized engineering personnel only.
Please ensure all security protocols are followed.
EOF

# 備份 UI 檔案
sudo cp /usr/share/lxdm/themes/Industrial/greeter.ui /usr/share/lxdm/themes/Industrial/greeter.ui.bak

# 將 "User:" 替換為 "警告訊息 + User:"
sudo sed -i 's/>User:<\/property>/>                                               User:\n                WARNING\nAuthorized Access Only!\nAll activities are logged.<\/property>/g' /usr/share/lxdm/themes/Industrial/greeter.ui

# 設定系統控制台警告 (實體存取路徑)
echo "WARNING: Authorized Access Only!" | sudo tee -a /etc/issue

# --- 3. Graphics Interface (LXDM/LightDM) Support ---
# 既然你的系统用的是 LXDM/LightDM 而非 GDM3，使用以下配置：
if [ -f /etc/lxdm/lxdm.conf ]; then
    echo "Hardening LXDM GUI (Hiding user list)..."
    
    # 1. 先移除可能存在的旧配置防止冲突
    sudo sed -i '/^disable=/d' /etc/lxdm/lxdm.conf
    
    # 2. 在 [userlist] 标签下面精确插入 disable=1
    # 如果找不到 [userlist] 标签，则在文件末尾添加
    if grep -q "\[userlist\]" /etc/lxdm/lxdm.conf; then
        sudo sed -i '/\[userlist\]/a disable=1' /etc/lxdm/lxdm.conf
    else
        echo -e "\n[userlist]\ndisable=1" | sudo tee -a /etc/lxdm/lxdm.conf
    fi
    
    # 3. 重启 LXDM 生效
    sudo systemctl restart lxdm
fi

# --- 4. Restart Services ---
sudo systemctl restart ssh
echo "SSH Hardening and Banners applied."
