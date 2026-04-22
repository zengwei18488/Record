#!/bin/bash
# =================================================================
# Target: Debian 12 (Bookworm) on RK3568
# Compliance: IEC 62443-4-2 (Identification & Authentication)
# Description: Hardening Password Policy, Account Lockout, and Auditing
# =================================================================

# Ensure the script is run as root
if [[ $EUID -ne 0 ]]; then
   echo "Error: This script must be run as root/sudo."
   exit 1
fi

echo "Starting IEC 62443 Hardening for Debian 12..."

# 1. Install Necessary Modules
# libpam-pwquality: For password strength
# rsyslog: For security auditing logs
echo "[1/5] Installing security modules..."
apt update && apt install -y libpam-pwquality rsyslog cracklib-runtime wamerican
update-cracklib

# 2. Configure Password Complexity (Min 12 chars, 4 classes)
echo "[2/5] Configuring Password Complexity Policy..."
CONF_PW="/etc/security/pwquality.conf"
# Ensure the file is clean before modifying
sed -i 's/^#\? \?minlen =.*/minlen = 12/' $CONF_PW
sed -i 's/^#\? \?minclass =.*/minclass = 4/' $CONF_PW
sed -i 's/^#\? \?retry =.*/retry = 3/' $CONF_PW
sed -i 's/^#\? \?dictcheck =.*/dictcheck = 0/' $CONF_PW # Avoid dict errors on lean images

# 3. Configure Account Lockout (FAILLOCK)
# 5 failed attempts = 30 mins lockout
echo "[3/5] Configuring Account Lockout (5 attempts / 30 mins)..."
AUTH_PAM="/etc/pam.d/common-auth"

# Backup original
cp $AUTH_PAM ${AUTH_PAM}.bak

# Clean up any previous faillock lines to avoid duplicates
sed -i '/pam_faillock.so/d' $AUTH_PAM

# Correct PAM sequence for Debian 12:
# We use 'tee' to ensure the order is correct: preauth -> unix -> authfail -> authsucc
cat <<EOF > $AUTH_PAM
auth    required                    pam_env.so
auth    required                    pam_faillock.so preauth silent audit deny=5 unlock_time=1800
auth    [success=1 default=ignore]  pam_unix.so nullok
auth    [default=die]               pam_faillock.so authfail audit deny=5 unlock_time=1800
auth    sufficient                  pam_faillock.so authsucc audit deny=5 unlock_time=1800
auth    required                    pam_deny.so
auth    required                    pam_permit.so
auth    optional                    pam_cap.so
EOF

# 4. Clean up faulty modules (Fix for LXDM/GUI login loop)
echo "[4/5] Cleaning up legacy/missing PAM modules..."
# Disable gnome-keyring if it's causing login loop
if [ -f /etc/pam.d/lxdm ]; then
    sed -i 's/.*pam_gnome_keyring.so.*/#&/g' /etc/pam.d/lxdm
fi

# 5. Enable Security Auditing
echo "[5/5] Enabling Security Auditing Logs..."
systemctl enable --now rsyslog
echo "auth,authpriv.*    /var/log/auth.log" > /etc/rsyslog.d/audit.conf
systemctl restart rsyslog

# Reset any accidental lockouts during setup
faillock --reset

echo "================================================================="
echo "SUCCESS: Debian 12 Hardening Complete."
echo "SYSTEM POLICY:"
echo "- Minimum Password Length: 12"
echo "- Character Classes Required: 4 (Upper, Lower, Digit, Special)"
echo "- Account Lockout: 5 attempts / 30 minutes"
echo "- Security Logs: /var/log/auth.log"
echo "================================================================="
echo "IMPORTANT: Please set a strong password now: 'passwd linaro'"
