#!/bin/bash
. /opt/labkit/lib/check.sh
. /opt/labkit/lib/hw.sh
t=$(mktemp -d); trap 'rm -rf $t' EXIT
PO=/usr/local/bin/peer-outliers
J=/root/fanout.json
fiojson() { # fiojson NAME:READ_BW_KiB ... -> minimal fio JSON
  python3 - "$@" <<'P'
import json, sys
jobs = [{"jobname": a.split(":")[0], "error": 0, "job options": {"filename": "/dev/mapper/encl0-" + a.split(":")[0]},
         "read": {"bw": int(a.split(":")[1]), "iops": int(a.split(":")[1]) / 4}, "write": {"bw": 0, "iops": 0}} for a in sys.argv[1:]]
print(json.dumps({"fio version": "fio-3.36", "jobs": jobs}))
P
}
flagged() { awk '/OUTLIER/{print $1}' | sort | paste -sd, -; }

section "Task 1: fan-out fio"
check "/root/fanout.fio has a job for every slot" 'for s in 0 1 2 3 4 5 6 7; do grep -q "encl0-slot$s" /root/fanout.fio || exit 1; done'
check "/root/fanout.fio is read-only, direct I/O, time based" 'grep -Eq "^\s*rw\s*=\s*(rand)?read\s*$" /root/fanout.fio && grep -Eq "^\s*direct\s*=\s*1" /root/fanout.fio && grep -Eq "^\s*time_based" /root/fanout.fio'
check "$J is fio JSON with 8 jobs, one per slot" '[ "$(jq "[.jobs[] | select(.jobname | test(\"^slot[0-7]$\"))] | length" $J)" = 8 ]'
check "the 8 jobs ran at the same time (no stonewall between them)" '! grep -Eq "^\s*(stonewall|wait_for_previous)" /root/fanout.fio'

section "Task 2: peer-outliers"
check "is executable" '[ -x $PO ]'
check "flags the one slow job, exit 1" 'fiojson slot0:100000 slot1:98000 slot2:102000 slot3:20000 slot4:99000 > $t/a; out=$($PO $t/a); [ $? -eq 1 ] && [ "$(echo "$out" | flagged)" = slot3 ]'
check "all within range: exit 0" 'fiojson slot0:100000 slot1:90000 slot2:102000 slot3:85000 > $t/b; $PO $t/b >/dev/null; [ $? -eq 0 ]'
check "uses the median, not the mean (two slow jobs)" 'fiojson slot0:100000 slot1:100000 slot2:100000 slot3:100000 slot4:100000 slot5:5000 slot6:6000 > $t/c; [ "$($PO $t/c | flagged)" = "slot5,slot6" ]'
check "honours a threshold argument (90%)" 'fiojson slot0:100000 slot1:100000 slot2:85000 > $t/d; [ "$($PO $t/d 90 | flagged)" = slot2 ]'
check "flags a job that hit an I/O error" 'fiojson slot0:100000 slot1:100000 slot2:100000 > $t/e; jq ".jobs[1].error=5" $t/e > $t/e2; out=$($PO $t/e2); [ $? -eq 1 ] && echo "$out" | grep -q "^slot1 "'
check "unreadable or empty input: exit 2" '$PO $t/nope >/dev/null 2>&1; a=$?; echo "{\"jobs\":[]}" > $t/f; $PO $t/f >/dev/null 2>&1; b=$?; [ $a -eq 2 ] && [ $b -eq 2 ]'

section "Task 3: diagnosis (answers.txt)"
check "slow_slot" 'answer_is slow_slot'
check "bad_slot (the one returning I/O errors)" 'answer_is bad_slot'

section "Task 4: SAS PHY counters"
check "cable_expander = the expander whose uplink cable is bad" 'answer_is cable_expander'
check "phy_err_slot = the slot whose own link is taking errors" 'answer_is phy_err_slot'
check "slow_link_slot = the slot that negotiated a lower link rate" 'answer_is slow_link_slot'
summary
