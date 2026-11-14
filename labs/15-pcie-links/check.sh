#!/bin/bash
. /opt/labkit/lib/check.sh
. /opt/labkit/lib/hw.sh
. "$LABDIR/fixture.sh"
t=$(mktemp -d); trap 'rm -rf $t' EXIT
LC=/usr/local/bin/pcie-linkcheck
flagged() { awk '/DEGRADED/{sub(/^0000:/, "", $1); print $1}' | sort | paste -sd, -; }

section "Task 1: the AER errors"
check "aer_device = the interface name (or BDF) of the reporting device" 'answer_is aer_device'
check "aer_severity = the AER severity" 'answer_is aer_severity'

section "Task 2: link training (evidence)"
check "width_degraded = the device running with fewer lanes" 'answer_is width_degraded'
check "speed_degraded = the device running at a lower speed" 'answer_is speed_degraded'

section "Task 3: pcie-linkcheck"
check "is executable" '[ -x $LC ]'
check "evidence file: exit 1" '$LC /root/evidence/stor-117-lspci-vvv.txt >/dev/null; [ $? -eq 1 ]'
check "flags exactly the degraded links (another server)" 'server_lspci 17:00.0 b1:00.0 > $t/a; [ "$($LC $t/a | flagged)" = "17:00.0,b1:00.0" ]'
check "a healthy server: nothing flagged, exit 0" 'server_lspci "" "" > $t/ok; out=$($LC $t/ok); [ $? -eq 0 ] && [ -z "$(echo "$out" | flagged)" ]'
check "healthy server: one OK line per device with a link (7)" 'server_lspci "" "" > $t/ok; [ "$($LC $t/ok | grep -c " OK")" -eq 7 ]'
check "only one degradation (width): still caught" 'server_lspci 4b:00.0 "" > $t/w; out=$($LC $t/w); [ $? -eq 1 ] && [ "$(echo "$out" | flagged)" = 4b:00.0 ]'
check "no link information at all: exit 2" 'lspci_host_bridge > $t/none; $LC $t/none >/dev/null 2>&1; [ $? -eq 2 ]'
check "missing file: exit 2" '$LC $t/nope >/dev/null 2>&1; [ $? -eq 2 ]'
check "no argument: checks this machine (prints a verdict or says why it cannot)" 'out=$($LC 2>&1); rc=$?; [ $rc -le 2 ] && [ -n "$out" ]'
summary
