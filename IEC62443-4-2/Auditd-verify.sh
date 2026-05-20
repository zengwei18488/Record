#!/bin/bash
# IEC 62443-4-2 Audit Compliance Test Suite
# Focus: CR 2.08, 2.09, 2.10, 3.09, 6.01

RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m' 

echo -e "--- Starting IEC 62443 Audit Log Compliance Test ---"

# --- 1. CR 6.01 Audit Log Integrity (Immutable Rules) ---
echo -n "[CR 6.01] Checking Audit Immutable State (-e 2)... "
ENABLED_STATE=$(sudo auditctl -s | grep "enabled" | awk '{print $2}')
if [ "$ENABLED_STATE" == "2" ]; then
    echo -e "${GREEN}PASS (Audit rules are locked)${NC}"
else
    echo -e "${RED}FAIL (Current state: $ENABLED_STATE. Please reboot to lock rules)${NC}"
fi

# --- 2. CR 2.08 Audit Storage Capacity ---
echo -n "[CR 2.08] Checking Log Rotation Policy (Max Size/Files)... "
MAX_FILE=$(grep "^max_log_file =" /etc/audit/auditd.conf | awk '{print $3}')
NUM_LOGS=$(grep "^num_logs =" /etc/audit/auditd.conf | awk '{print $3}')
if [ "$MAX_FILE" -ge 100 ] && [ "$NUM_LOGS" -ge 10 ]; then
    echo -e "${GREEN}PASS (Capacity: ${MAX_FILE}MB x ${NUM_LOGS} files)${NC}"
else
    echo -e "${RED}FAIL (Current: ${MAX_FILE}MB, ${NUM_LOGS} files)${NC}"
fi

# --- 3. CR 2.09 Response to Failures ---
echo -n "[CR 2.09] Checking Failure Response (Space Left Action)... "
SPACE_ACTION=$(grep "^admin_space_left_action =" /etc/audit/auditd.conf | awk '{print $3}')
if [ "$SPACE_ACTION" == "SYSLOG" ]; then
    echo -e "${GREEN}PASS (Action: SYSLOG)${NC}"
else
    echo -e "${RED}FAIL (Action: $SPACE_ACTION)${NC}"
fi

# --- 4. CR 2.10 Record Retention (Service Persistence) ---
echo -n "[CR 2.10] Checking Auditd Service Auto-Restart... "
RESTART_CONF=$(systemctl show auditd.service --property=Restart | cut -d= -f2)
if [ "$RESTART_CONF" == "always" ]; then
    echo -e "${GREEN}PASS (Restart: always)${NC}"
else
    echo -e "${RED}FAIL (Restart: $RESTART_CONF)${NC}"
fi

# --- 5. CR 3.09 Input Port Monitoring (USB Event Tracking) ---
echo -n "[CR 3.09] Testing USB Hardware Event Auditing... "
# 模擬 USB 插入事件（即使沒有物理插入，我們檢查是否有核心事件日誌）
USB_LOG=$(sudo ausearch -m KERNEL -i 2>/dev/null | grep -i "usb" | tail -n 1)
if [ ! -z "$USB_LOG" ]; then
    echo -e "${GREEN}PASS (USB events are being tracked)${NC}"
else
    # 如果還沒插過 USB，檢查規則是否存在
    USB_RULE=$(sudo auditctl -l | grep -E "usb|dev")
    if [ ! -z "$USB_RULE" ]; then
        echo -e "${GREEN}PASS (Audit rule for ports is active)${NC}"
    else
        echo -e "${RED}WARN (No USB audit records or rules found)${NC}"
    fi
fi

# --- 6. CR 6.01 Traceability (Sensitive File Change) ---
echo -n "[CR 6.01] Testing Audit Traceability (Shadow File Watch)... "
sudo touch /etc/shadow &> /dev/null
sleep 1
TRACE_LOG=$(sudo ausearch -k identity -i 2>/dev/null | tail -n 20 | grep "shadow")
if [ ! -z "$TRACE_LOG" ]; then
    echo -e "${GREEN}PASS (Shadow file change recorded)${NC}"
else
    echo -e "${RED}FAIL (No audit record for sensitive file change)${NC}"
fi

echo "--- Audit Compliance Test Complete ---"

