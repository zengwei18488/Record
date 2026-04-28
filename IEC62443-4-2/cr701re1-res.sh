#!/bin/bash

# =================================================================
# Script Name: IEC62443_CR7_01_RE1_with_Validation.sh
# Purpose: Resource Priority Setup and Cross-Item Validation (CR 2.05/7.01RE1)
# Target: Debian 12 (Linaro/Rockchip)
# =================================================================

echo "Starting CR 7.1 RE(1) Configuration and Cross-Validation..."

# --- 1. Resource Priority & Quotas (CR 7.1 RE1 specific) ---
echo "[1/3] Applying Systemd Resource Hardening for SSH..."
sudo mkdir -p /etc/systemd/system/ssh.service.d/
sudo tee /etc/systemd/system/ssh.service.d/override.conf << EOT
[Service]
Nice=-5
TasksMax=10
MemoryMax=150M
Restart=always
EOT

sudo systemctl daemon-reload
sudo systemctl restart ssh

# --- 2. Essential Function Documentation ---
echo "[2/3] Generating Essential Function Priority Document..."
sudo mkdir -p /etc/security
sudo tee /etc/security/essential-functions.txt << EOT
[IEC 62443-4-2 CR 7.1 RE(1) Compliance]
- Identified Essential Function: SSH (Port 22) for remote management.
- Priority: Nice=-5 (Elevated CPU scheduling priority).
- Resource Quotas: 150MB MemoryLimit and 10 TasksLimit enforced via Systemd.
- Load Management: Inherited from CR 2.05 (MaxSessions limit).
EOT

# --- 3. Compliance Validation (The Check Phase) ---
echo "[3/3] Running Compliance Validation..."
echo "------------------------------------------------"
echo "IEC 62443 CR 7.1 RE(1) AUDIT CHECKLIST:"
echo "------------------------------------------------"

# 3.1 Validate Systemd Nice Value (CR 7.1 RE1)
NICE_VAL=$(systemctl show ssh -p Nice --value)
if [ "$NICE_VAL" == "-5" ]; then
    echo "[PASS] SSH Priority: Nice=$NICE_VAL (Elevated)"
else
    echo "[FAIL] SSH Priority: Nice=$NICE_VAL (Expected -5)"
fi

# 3.2 Validate Resource Quotas (CR 7.1 RE1)
MEM_LIMIT=$(systemctl show ssh -p MemoryMax --value)
TASK_LIMIT=$(systemctl show ssh -p TasksMax --value)
if [ "$TASK_LIMIT" == "10" ]; then
    echo "[PASS] SSH Resource: TasksLimit=$TASK_LIMIT"
else
    echo "[FAIL] SSH Resource: TasksLimit=$TASK_LIMIT (Expected 10)"
fi

# 3.3 Cross-check MaxSessions from CR 2.05 (Inherited Requirement)
MAX_SESS=$(grep "^MaxSessions" /etc/ssh/sshd_config | awk '{print $2}')
if [ -n "$MAX_SESS" ] && [ "$MAX_SESS" -le 5 ]; then
    echo "[PASS] Cross-Check (CR 2.05): MaxSessions=$MAX_SESS (Compliant)"
else
    echo "[FAIL] Cross-Check (CR 2.05): MaxSessions not found or > 5"
    echo "       (Please ensure CR 2.05 script has been executed)"
fi

# 3.4 Validate Evidence Document
if [ -f /etc/security/essential-functions.txt ]; then
    echo "[PASS] Evidence Document: essential-functions.txt exists."
else
    echo "[FAIL] Evidence Document: Missing."
fi

echo "------------------------------------------------"
echo "Validation Complete."
