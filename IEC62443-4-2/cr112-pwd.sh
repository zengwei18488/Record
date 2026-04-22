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

# --- 3. Graphics Interface (LXDM/LightDM) Support ---
# 既然你的系统用的是 LXDM/LightDM 而非 GDM3，使用以下配置：
if [ -f /etc/lxdm/lxdm.conf ]; then
    echo "Hardening LXDM GUI..."
    sudo sed -i 's/^#\?disable_user_list=.*/disable_user_list=1/' /etc/lxdm/lxdm.conf
fi

# --- 4. Restart Services ---
sudo systemctl restart ssh
echo "SSH Hardening and Banners applied."
