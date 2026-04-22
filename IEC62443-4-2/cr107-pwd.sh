#!/bin/bash
# Corrected for Debian 12 (Bookworm) - RK3568 Linaro

PWQUALITY_FILE="/etc/security/pwquality.conf"
PASSWORD_FILE="/etc/pam.d/common-password"
LOGIN_DEFS_FILE="/etc/login.defs"
USERNAME="linaro"  # Corrected from 'ubuntu'

# 2. Configure pwquality.conf (Best Practice for Debian 12)
# Using -1 to FORCE at least one of each class
sudo sed -i "
  s/^#\? \?minlen =.*/minlen = 12/;
  s/^#\? \?dcredit =.*/dcredit = -1/;
  s/^#\? \?ucredit =.*/ucredit = -1/;
  s/^#\? \?lcredit =.*/lcredit = -1/;
  s/^#\? \?ocredit =.*/ocredit = -1/;
  s/^#\? \?minclass =.*/minclass = 4/;
" $PWQUALITY_FILE

# 3. Securely update common-password (avoid breaking the PAM stack)
# Check if the line already exists to avoid duplication
if ! grep -q "pam_pwquality.so" "$PASSWORD_FILE"; then
    sudo sed -i '/pam_unix.so/i password requisite pam_pwquality.so retry=3' "$PASSWORD_FILE"
fi

# 4. Apply Aging Policy to the CURRENT user
if id "$USERNAME" &>/dev/null; then
    sudo chage -M 90 -W 7 -m 7 "$USERNAME"
else
    echo "Warning: User $USERNAME not found."
fi

# 5. Set Global Default for FUTURE users
sudo sed -i "
  s/^\(PASS_MAX_DAYS[[:space:]]*\)[[:digit:]]*/\1 90/;
  s/^\(PASS_MIN_DAYS[[:space:]]*\)[[:digit:]]*/\1 7/;
  s/^\(PASS_WARN_AGE[[:space:]]*\)[[:digit:]]*/\1 14/;
" $LOGIN_DEFS_FILE

echo "Configuration applied successfully for Debian 12."
