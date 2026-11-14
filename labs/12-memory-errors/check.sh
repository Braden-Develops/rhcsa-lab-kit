#!/bin/bash
. /opt/labkit/lib/check.sh
. /opt/labkit/lib/hw.sh
t=$(mktemp -d); trap 'rm -rf $t' EXIT
CED=/usr/local/bin/ce-delta

section "Task 1: error recording is back"
check "rasdaemon is not masked" '[ "$(systemctl is-enabled rasdaemon 2>/dev/null)" != masked ]'
check "rasdaemon is enabled at boot" 'systemctl is-enabled -q rasdaemon'
check "rasdaemon is running" 'systemctl is-active -q rasdaemon'

section "Task 2: diagnosis (in /root/answers.txt)"
check "dimm = the silkscreen label of the failing slot" 'answer_is dimm'
check "count = its total correctable errors per rasdaemon" 'answer_is count'
check "action = what the RMA policy says to do" 'answer_is action'

section "Task 3: ce-delta, a telemetry-around-stress wrapper"
mk() { rm -rf $t/mc; mkdir -p $t/mc/mc0 $t/mc/mc1; echo 5 > $t/mc/mc0/ce_count; echo 2 > $t/mc/mc1/ce_count; }
check "is executable" '[ -x $CED ]'
check "clean run: prints CE_DELTA=0, exit 0" 'mk; out=$(EDAC_ROOT=$t/mc $CED true); [ $? -eq 0 ] && echo "$out" | grep -qx "CE_DELTA=0"'
check "errors during the run: CE_DELTA=7, exit 1" 'mk; out=$(EDAC_ROOT=$t/mc $CED sh -c "echo 9 > $t/mc/mc1/ce_count"); [ $? -eq 1 ] && echo "$out" | grep -qx "CE_DELTA=7"'
check "passes the command its arguments" 'mk; EDAC_ROOT=$t/mc $CED touch $t/a $t/b; [ -f $t/a ] && [ -f $t/b ]'
check "command fails, no errors: exit 1" 'mk; EDAC_ROOT=$t/mc $CED false; [ $? -eq 1 ]'
check "no EDAC telemetry: exit 2 (never a pass)" 'mkdir -p $t/none; EDAC_ROOT=$t/none $CED true; [ $? -eq 2 ]'
check "no EDAC telemetry: message on stderr" 'EDAC_ROOT=$t/none $CED true 2>&1 >/dev/null | grep -q .'

section "Task 4: run it for real"
check "vm_exit = the exit code ce-delta gives in this VM" 'answer_is vm_exit'
check "/root/stress.log holds what ce-delta printed" 'grep -Eq "CE_DELTA=|EDAC|telemetry" /root/stress.log'
summary
