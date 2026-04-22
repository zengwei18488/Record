#!/bin/bash

# =================================================================
# Project: AFE-E630 (Debian 12)
# Purpose: Automated Verification for CR 2.01 (RBAC & Hardware Auth)
# =================================================================

# Ensure the script runs as root
if [ "$EUID" -ne 0 ]; then 
  echo "Error: Please run as root (sudo)."
  exit 1
fi

echo "--------------------------------------------------"
echo "Starting CR 2.01 Full Authorization Enforcement Test"
echo "--------------------------------------------------"

# Function to print test results
print_result() {
    if [ $1 -eq 0 ]; then
        echo -e "\e[32m[ PASS ]\e[0m $2"
    else
        echo -e "\e[31m[ FAIL ]\e[0m $2"
    fi
}

# --- 1. Admin Role Verification (user1) ---
echo "Testing user1 (Admin Role)..."
su - user1 -c "sudo -l" | grep -q "(ALL : ALL) ALL"
print_result $? "user1: Full Sudo management capability verified in policy."

# --- 2. Operator Role Verification (user2) ---
echo -e "\nTesting user2 (Operator Role)..."
# Authorized command: systemctl restart
su - user2 -c "sudo -n /usr/bin/systemctl restart cron" &>/dev/null
print_result $? "user2: Authorized command (systemctl) without password verified."

# Unauthorized command: journalctl
su - user2 -c "sudo -n /usr/bin/journalctl" &>/dev/null
if [ $? -ne 0 ]; then
    print_result 0 "user2: Unauthorized command (journalctl) blocked correctly."
else
    print_result 1 "user2: Unauthorized command (journalctl) WAS PERMITTED (Error)."
fi

# --- 3. Viewer Role Verification (user3) ---
echo -e "\nTesting user3 (Viewer Role)..."
# Authorized command: journalctl
su - user3 -c "sudo -n /usr/bin/journalctl --version" &>/dev/null
print_result $? "user3: Authorized command (journalctl) without password verified."

# Unauthorized command: systemctl
su - user3 -c "sudo -n /usr/bin/systemctl" &>/dev/null
if [ $? -ne 0 ]; then
    print_result 0 "user3: Unauthorized command (systemctl) blocked correctly."
else
    print_result 1 "user3: Unauthorized command (systemctl) WAS PERMITTED (Error)."
fi

# --- 4. File System Isolation Verification ---
echo -e "\nTesting File System Isolation..."
# user3 (Viewer) should not write to operator log
su - user3 -c "echo 'hack' >> /var/log/operation.log" &>/dev/null
if [ $? -ne 0 ]; then
    print_result 0 "FS: Viewer blocked from writing to Operator log."
else
    print_result 1 "FS: Viewer WAS ABLE TO WRITE to Operator log (Error)."
fi

# --- 5. Hardware Interface Verification (udev rules) ---
echo -e "\nTesting Hardware Authorization (udev/devicegroup)..."
# Check if devicegroup exists
getent group devicegroup > /dev/null
if [ $? -eq 0 ]; then
    # Verify user2 is in devicegroup
    groups user2 | grep -q "devicegroup"
    print_result $? "udev: user2 (Operator) is member of 'devicegroup'."

    # Verify user3 is NOT in devicegroup
    groups user3 | grep -q "devicegroup"
    if [ $? -ne 0 ]; then
        print_result 0 "udev: user3 (Viewer) correctly excluded from 'devicegroup'."
    else
        print_result 1 "udev: user3 (Viewer) incorrectly added to 'devicegroup'."
    fi

    # Check /dev/sda permissions if the device exists
    if [ -b "/dev/sda" ]; then
        ls -l /dev/sda | grep -q "devicegroup"
        print_result $? "udev: Physical device /dev/sda group ownership verified."
    else
        echo -e "\e[33m[ INFO ]\e[0m /dev/sda not found. Skipping physical device check."
    fi
else
    print_result 1 "udev: 'devicegroup' does not exist."
fi

echo "--------------------------------------------------"
echo "Verification Complete."
