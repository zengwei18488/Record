#!/bin/bash

# --- 1. User and Group Initialization ---
# Debian 12 uses 'sudo' as the primary admin group. 
# We also create 'devicegroup' to support the udev rules.
TEST_PASS="AfE-e630@2026"
ENCRYPTED_PASS=$(mkpasswd -m yescrypt $TEST_PASS)

sudo groupadd -f operator
sudo groupadd -f viewer
sudo groupadd -f devicegroup

# Create users with designated roles
sudo useradd -m -s /bin/bash -p "$ENCRYPTED_PASS" user1
sudo useradd -m -s /bin/bash -p "$ENCRYPTED_PASS" user2
sudo useradd -m -s /bin/bash -p "$ENCRYPTED_PASS" user3

# --- 2. Role-Based Access Control (RBAC) Assignment ---
sudo usermod -aG sudo user1           # Admin Role
sudo usermod -aG operator user2       # Operator Role
sudo usermod -aG viewer user3         # Viewer Role
sudo usermod -aG devicegroup user2    # Grant Operator access to hardware (sdb)

# --- 3. File System Level Authorization (Least Privilege) ---
sudo touch /etc/important_file /var/log/operation.log /usr/local/share/view_only

# Admin: Read/Write
sudo chown root:sudo /etc/important_file
sudo chmod 770 /etc/important_file

# Operator: Read Log
sudo chown root:operator /var/log/operation.log
sudo chmod 750 /var/log/operation.log

# Viewer: Read Only
sudo chown root:viewer /usr/local/share/view_only
sudo chmod 740 /usr/local/share/view_only

# --- 4. Command Level Authorization (Sudoers Enforcement) ---
# Note: Debian 12 paths for systemctl/journalctl are in /usr/bin/
sudo tee /etc/sudoers.d/iec_62443_roles > /dev/null << EOT
# User1 (Admin): Full administrative access
%sudo ALL=(ALL:ALL) ALL

# User2 (Operator): Restricted to service restarts
%operator ALL=(ALL) NOPASSWD: /usr/bin/systemctl restart *

# User3 (Viewer): Restricted to log viewing
%viewer ALL=(ALL) NOPASSWD: /usr/bin/journalctl
EOT

# Apply secure permissions (Mandatory for Debian)
sudo chmod 440 /etc/sudoers.d/iec_62443_roles

# --- 5. Hardware Interface Authorization (udev rules) ---
# Enforce access control for block devices (e.g., USB/SATA sda)
# Only Root and 'devicegroup' members (User2) can access /dev/sda
sudo tee /etc/udev/rules.d/99-device.rules > /dev/null << EOT
SUBSYSTEM=="block", KERNEL=="sda", GROUP="devicegroup", MODE="0660"
EOT

# Reload udev rules to apply changes
sudo udevadm control --reload-rules && sudo udevadm trigger

echo "--------------------------------------------------"
echo "CR 2.01 Applied: RBAC and Hardware access enforced."
echo "Admin: user1 | Operator: user2 | Viewer: user3"
echo "--------------------------------------------------"
