#!/bin/bash

AUTH_FILE="/etc/pam.d/common-auth"
ACCOUNT_FILE="/etc/pam.d/common-account"
FAILLOCK_CONF="/etc/security/faillock.conf"

# 1. 配置 faillock.conf (参数集中管理，最稳妥)
# 直接修改配置文件，避免在 PAM 行写一堆参数
sudo sed -i "s/^#\? \?deny =.*/deny = 5/" $FAILLOCK_CONF
sudo sed -i "s/^#\? \?fail_interval =.*/fail_interval = 900/" $FAILLOCK_CONF
sudo sed -i "s/^#\? \?unlock_time =.*/unlock_time = 1800/" $FAILLOCK_CONF
# 确保开启审计和静默模式
sudo sed -i "s/^#\? \?audit.*/audit/" $FAILLOCK_CONF
sudo sed -i "s/^#\? \?silent.*/silent/" $FAILLOCK_CONF

# 2. 修改 common-auth (精确匹配 Debian 12 结构)
# 先备份
sudo cp $AUTH_FILE ${AUTH_FILE}.bak

# 清理旧的 faillock 行（防止重复运行脚本导致冲突）
sudo sed -i '/pam_faillock.so/d' $AUTH_FILE

# 在 pam_unix.so 之前插入 preauth (必须要放在 auth 栈顶层，仅次于 pam_env)
sudo sed -i '/pam_unix.so/i auth    required    pam_faillock.so preauth' $AUTH_FILE

# 在 pam_unix.so 之后插入 authfail 和 authsucc
# Debian 12 的 pam_unix 行通常包含 [success=1 default=ignore]
sudo sed -i '/pam_unix.so/a auth    [default=die]    pam_faillock.so authfail\nauth    sufficient    pam_faillock.so authsucc' $AUTH_FILE

# 3. 修改 common-account
sudo sed -i '/pam_unix.so/i account    required    pam_faillock.so' $ACCOUNT_FILE

# 4. 重置状态
sudo faillock --reset

echo "Debian 12 faillock configuration updated."
