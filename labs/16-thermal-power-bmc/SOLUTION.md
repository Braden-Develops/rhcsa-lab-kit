# Lab 16 solution

## 1. The BMC service (two faults, one after the other)

```bash
systemctl status bmc-sim                     # failed / activating (auto-restart)
journalctl -u bmc-sim -n 20 --no-pager
# bmc-sim: invalid port '80000' in config (must be 1-65535)
sed -i 's/^port = 80000/port = 8000/' /etc/bmc-sim/bmc-sim.conf
systemctl reset-failed bmc-sim; systemctl restart bmc-sim
journalctl -u bmc-sim -n 5 --no-pager
# bmc-sim: cannot read state file: [Errno 13] Permission denied: '/var/lib/bmc-sim/state.json'
ls -l /var/lib/bmc-sim/state.json            # -rw------- root root
chown bmcsim: /var/lib/bmc-sim/state.json    # keep mode 600: only its owner reads it
systemctl restart bmc-sim
curl -s -u admin:labpass http://127.0.0.1:8000/redfish/v1/ | jq .
```

This is the RH342 rhythm: read the log, fix exactly what it says, restart, read the log again. Fixing a start
failure often uncovers the next one. `reset-failed` clears the start-rate limit after several quick failures.

## 2. Redfish

```bash
R='curl -s -u admin:labpass http://127.0.0.1:8000'
$R/redfish/v1/Chassis/1 | jq '.Status, .Thermal, .Power'
$R/redfish/v1/Chassis/1/Thermal | jq -r '.Fans[] | "\(.Name) \(.Reading) \(.ReadingUnits) \(.Status.Health)"'
$R/redfish/v1/Chassis/1/Thermal | jq -r '.Temperatures[] | "\(.Name) \(.ReadingCelsius)C warn=\(.UpperThresholdNonCritical) crit=\(.UpperThresholdCritical) \(.Status.Health)"'
$R/redfish/v1/Chassis/1/Power | jq '.PowerSupplies[] | {Name, LineInputVoltage, Status}, .Redundancy'
$R/redfish/v1/Managers/1/LogServices/SEL/Entries | jq -r '.Members[] | "\(.Created) \(.Severity) \(.SensorName): \(.Message)"'
```

The SEL tells the story: one PSU lost AC first (so the server runs on a single supply and redundancy is lost),
later a fan failed, and the remaining fans could no longer cool one zone, which crossed its warning threshold.
On a real server, fix the cause rather than the symptom: restore AC to the PSU (check the PDU and cord before
RMAing the supply), replace the fan, then confirm the temperature drops back.

## 3. Node B

```bash
grep -E ' cr | nc |0x0b00' /root/evidence/node-b-ipmitool.txt       # sensors in critical / non-critical state
grep -E 'AC lost|Lower Critical' /root/evidence/node-b-ipmitool.txt
```

In `ipmitool sensor` the 4th column is the state: `ok`, `nc` (non-critical), `cr` (critical), `nr`
(non-recoverable). The six thresholds after it are lower nr/cr/nc and upper nc/cr/nr. A PSU's status is a
*discrete* sensor: the value is a bit field (bit 0 = presence detected, bit 1 = failure, bit 3 = AC lost).

## 4. thermal-check

```bash
cat > /usr/local/bin/thermal-check <<'S'
#!/bin/bash
# thermal-check: health of fans, temperatures and PSUs from the BMC, over Redfish
URL=${REDFISH_URL:-http://127.0.0.1:8000}
AUTH="${REDFISH_USER:-admin}:${REDFISH_PASSWORD:-labpass}"
get() { curl -sf --max-time 10 -u "$AUTH" "$URL$1"; }
thermal=$(get /redfish/v1/Chassis/1/Thermal) && power=$(get /redfish/v1/Chassis/1/Power) || {
  echo "thermal-check: cannot read telemetry from the BMC at $URL" >&2; exit 2; }
problems=$( { echo "$thermal" | jq -r '.Fans[], .Temperatures[] | select(.Status.Health != "OK")
                | "\(.Name) \(.Status.Health) \(.Reading // .ReadingCelsius) \(.ReadingUnits // "C")"'
              echo "$power"   | jq -r '.PowerSupplies[], .Redundancy[] | select(.Status.Health != "OK")
                | "\(.Name) \(.Status.Health) \(.Status.State // "")"'; } ) || {
  echo "thermal-check: unexpected data from the BMC" >&2; exit 2; }
[ -z "$problems" ] && { echo "thermal-check: all fans, temperatures and power supplies OK"; exit 0; }
echo "$problems"; exit 1
S
chmod +x /usr/local/bin/thermal-check
thermal-check; echo $?
```

`curl -f` turns HTTP errors (401 bad credentials, 404) into a non-zero exit, so a BMC that refuses you is
"no telemetry" (exit 2), not "no problems". A real check should also compare readings against thresholds itself
and against peers, because BMC health flags are only as good as the thresholds the vendor set, and should run
**during** a stress test, when fans and PSUs are working hardest.

## What was simulated

bmc-sim serves a subset of the DMTF Redfish schema (`Thermal` and `Power` resources; newer BMCs also offer
`ThermalSubsystem` and `PowerSubsystem`). Real BMCs use HTTPS (`curl -k` against self-signed certificates) and
usually sessions (`POST /redfish/v1/SessionService/Sessions`, then the `X-Auth-Token` header) as well as basic auth.
