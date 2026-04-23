#!/bin/bash

# =================================================================
# Project: AFE-E630 (Debian 12)
# Purpose: Cleanup Script to Remove IEC 62443 Test Configurations
# =================================================================

# Check root privileges
if [ "$EUID" -ne 0 ]; then 
  echo "Error: Please run as root (sudo)."
  exit 1
fi

echo "--------------------------------------------------"
echo "Starting Cleanup: Removing Users, Groups, and Files"
echo "--------------------------------------------------"

# 1. Remove Users and their Home Directories
echo "Removing users: user1, user2, user3..."
for username in user1 user2 user3 admin_user op_user view_user; do
    if id "$username" &>/dev/null; then
        sudo deluser --remove-home "$username" &>/dev/null
        echo "Deleted user: $username"
    fi
done

# 2. Remove Custom Groups
echo "Removing custom groups..."
for groupname in operator viewer devicegroup; do
    if getent group "$groupname" &>/dev/null; then
        sudo groupdel "$groupname" &>/dev/null
        echo "Deleted group: $groupname"
    fi
done

# 3. Remove Sudoers Configuration
echo "Removing sudoers roles..."
sudo rm -f /etc/sudoers.d/iec_62443_roles
sudo rm -f /etc/sudoers.d/groups
echo "Deleted: /etc/sudoers.d/ entries"

# 4. Remove Test Files and Logs
echo "Removing test assets and log files..."
sudo rm -f /etc/important_file
sudo rm -f /etc/important_config
sudo rm -f /var/log/operation.log
sudo rm -f /var/log/custom_audit.log
sudo rm -f /usr/local/share/view_only
sudo rm -f /usr/local/share/read_only_data
echo "Deleted: Test files in /etc, /var, and /usr"

# 5. Remove Hardware Rules (udev)
echo "Removing udev rules..."
sudo rm -f /etc/udev/rules.d/99-device.rules
sudo udevadm control --reload-rules
sudo udevadm trigger
echo "Deleted: /etc/udev/rules.d/99-device.rules"

# 6. Reset Login Banners (Optional but recommended)
echo "Resetting /etc/issue and SSH banners..."
echo "Debian GNU/Linux 12 \n \l" | sudo tee /etc/issue > /dev/null
sudo rm -f /etc/ssh/banner_message
sudo sed -i 's|^Banner /etc/ssh/banner_message|#Banner none|' /etc/ssh/sshd_config
sudo systemctl restart ssh &>/dev/null

echo "--------------------------------------------------"
echo "Cleanup Complete! The system is ready for re-test."
echo "--------------------------------------------------"
