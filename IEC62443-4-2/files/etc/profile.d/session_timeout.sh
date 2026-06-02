# IEC 62443 CR 2.05: Global Session Timeout
# =================================================================
# IEC 62443-4-2 CR 1.1 / CR 2.1 Global Session Timeout (15 Mins)
# =================================================================
if ! declare -p TMOUT 2>/dev/null | grep -q " -.*r"; then
    export TMOUT=900
    readonly TMOUT
fi
