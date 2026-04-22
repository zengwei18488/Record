#!/bin/bash

# Check root privileges
if [ "$EUID" -ne 0 ]; then 
  echo "Error: Please run as root or using sudo."
  exit 1
fi

echo "--- Disabling Kernel Updates for Debian 12 (Optimized) ---"

# 1. Identify all currently installed kernel-related packages
# This targets image, headers, modules, and kbuild to ensure nothing is missed
INSTALLED_KERNEL_PKGS=$(dpkg -l | grep -E "linux-image|linux-headers|linux-modules|linux-kbuild" | awk '{print $2}')

if [ -n "$INSTALLED_KERNEL_PKGS" ]; then
    echo "Identified installed kernel packages:"
    echo "$INSTALLED_KERNEL_PKGS"
    
    # Apply apt-mark hold
    apt-mark hold $INSTALLED_KERNEL_PKGS
    echo "Success: Packages marked as 'hold'."
else
    echo "Warning: No installed kernel packages found via dpkg."
fi

# 2. Create/Overwrite APT preference to block ALL future kernel installations
# This is a global block using wildcards (*) to ensure no new versions are installed
cat <<EOF > /etc/apt/preferences.d/no-kernel-upgrades
Package: linux-image-* linux-headers-* linux-kbuild-* linux-modules-*
Pin: release *
Pin-Priority: -1
EOF

echo "Success: APT Pinning rules applied to /etc/apt/preferences.d/no-kernel-upgrades"

# 3. Final Verification
echo "--------------------------------------------------"
echo "Verification Results:"
echo "1. Held Packages:"
apt-mark showhold | grep -E "linux-(image|headers|modules|kbuild)" || echo "None (Check Pinning below)"

echo -e "\n2. APT Policy Check (Should show Candidate: none):"
apt-cache policy linux-image-arm64 2>/dev/null | grep "Candidate:" || echo "Package linux-image-arm64 not found, but Pinning is active."

echo "--------------------------------------------------"
echo "Kernel updates are now completely DISABLED."
echo "--------------------------------------------------"
