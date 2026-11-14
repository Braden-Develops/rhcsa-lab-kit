#!/bin/bash
. /opt/labkit/lib/check.sh
. /opt/labkit/lib/hw.sh
t=$(mktemp -d); pids=()
trap 'kill ${pids[@]} 2>/dev/null; rm -rf $t' EXIT
TC=/usr/local/bin/thermal-check
SIM=/opt/bmc-sim/bmc-sim.py
sim() { # sim PORT healthy|faulty : start a private BMC on PORT
  python3 $SIM --generate $2 --out $t/$1.json
  printf 'port=%s\nstate=%s\nuser=admin\npassword=labpass\n' $1 $t/$1.json > $t/$1.conf
  python3 $SIM --config $t/$1.conf >/dev/null 2>&1 & pids+=($!)
  for _ in $(seq 1 30); do curl -s -o /dev/null http://127.0.0.1:$1/redfish/v1 && return 0; sleep 0.2; done
}
section "Task 1: the BMC service"
check "bmc-sim.service is running" 'systemctl is-active -q bmc-sim.service'
check "bmc-sim.service is enabled" 'systemctl is-enabled -q bmc-sim.service'
check "it still runs as the bmcsim user" '[ "$(systemctl show -p User --value bmc-sim.service)" = bmcsim ]'
check "Redfish answers on 127.0.0.1:8000 with authentication" 'curl -sf -u admin:labpass http://127.0.0.1:8000/redfish/v1/Chassis/1 | grep -q Thermal'
check "the state file is not world-readable" '[ $(( 0$(stat -c %a /var/lib/bmc-sim/state.json) & 4 )) -eq 0 ]'

section "Task 2: what the BMC says (answers.txt)"
check "fan = the failed fan" 'answer_is fan'
check "psu = the power supply that lost input" 'answer_is psu'
check "redundancy = ok or lost" 'answer_is redundancy'
check "hot_sensor = the temperature sensor in warning" 'answer_is hot_sensor'

section "Task 3: node B, from the ipmitool capture"
check "nodeb_fan" 'answer_is nodeb_fan'
check "nodeb_psu" 'answer_is nodeb_psu'

section "Task 4: thermal-check"
sim 18001 healthy; sim 18002 faulty
check "is executable" '[ -x $TC ]'
check "healthy server: exit 0" 'REDFISH_URL=http://127.0.0.1:18001 $TC >/dev/null 2>&1'
check "faulty server: exit 1" 'REDFISH_URL=http://127.0.0.1:18002 $TC >/dev/null 2>&1; [ $? -eq 1 ]'
check "faulty server: names the failed fan and PSU" 'out=$(REDFISH_URL=http://127.0.0.1:18002 $TC 2>&1); f=$(jq -r .truth.fan $t/18002.json); p=$(jq -r .truth.psu $t/18002.json); echo "$out" | grep -q "$f" && echo "$out" | grep -q "$p"'
check "BMC unreachable: exit 2" 'REDFISH_URL=http://127.0.0.1:1 $TC >/dev/null 2>&1; [ $? -eq 2 ]'
check "wrong password: exit 2" 'REDFISH_URL=http://127.0.0.1:18001 REDFISH_PASSWORD=nope $TC >/dev/null 2>&1; [ $? -eq 2 ]'
check "defaults to this server's BMC: exit 1" '$TC >/dev/null 2>&1; [ $? -eq 1 ]'
summary
