#!/bin/bash
# Lab 14: a node benchmarks far below its peers. Several real causes are planted (a kernel argument, a cgroup
# quota, a CPU hog that a timer keeps restarting, a power-saving tuned profile), plus MCE and thermal-throttle
# messages in the kernel log and rasdaemon (simulated: a VM has no machine-check banks or thermal sensors).
set -e
. /opt/labkit/lib/hw.sh
need_pkgs tuned kernel-tools rasdaemon sqlite perl-DBD-SQLite stress-ng sysstat
truth_reset
NCPU=$(nproc --all)
[ "$NCPU" -ge 2 ] || { echo "This lab needs a VM with at least 2 vCPUs (it has $NCPU)." >&2; exit 1; }

# --- the benchmark the ticket talks about ---
cat > /usr/local/bin/labbench <<'B'
#!/usr/bin/env python3
"""labbench: fixed CPU workload, one worker per online CPU, prints a score (higher is better)."""
import multiprocessing as mp, os, time
def work(sec, q):
    n, end = 0, time.time() + sec
    while time.time() < end:
        sum(i * i for i in range(2000)); n += 1
    q.put(n)
if __name__ == "__main__":
    cpus = len(os.sched_getaffinity(0)); q = mp.Queue()
    ps = [mp.Process(target=work, args=(5, q)) for _ in range(cpus)]
    [p.start() for p in ps]; [p.join() for p in ps]
    score = sum(q.get() for _ in ps)
    line = f"{time.strftime('%F %T')} cpus={cpus} online={os.cpu_count()} score={score}"
    print(line)
    with open("/var/log/labbench.log", "a") as f: f.write(line + "\n")
B
chmod +x /usr/local/bin/labbench
cat > /etc/systemd/system/labbench.service <<'U'
[Unit]
Description=CPU benchmark used by the burn-in suite
[Service]
Type=oneshot
ExecStart=/usr/local/bin/labbench
U
mkdir -p /etc/systemd/system/labbench.service.d
cat > /etc/systemd/system/labbench.service.d/10-accounting.conf <<'U'
[Service]
CPUAccounting=yes
CPUQuota=25%
U

# --- a "telemetry agent" that burns a CPU, and a timer that brings it back if you just kill it ---
mkdir -p /usr/local/libexec
cat > /usr/local/libexec/telemetry-agent <<'H'
#!/usr/bin/env python3
# collects nothing; spins
while True:
    pass
H
chmod +x /usr/local/libexec/telemetry-agent
cat > /etc/systemd/system/telemetry-agent.service <<'U'
[Unit]
Description=Fleet telemetry agent
[Service]
ExecStart=/usr/local/libexec/telemetry-agent
Nice=-5
U
cat > /etc/systemd/system/telemetry-agent.timer <<'U'
[Unit]
Description=Keep the fleet telemetry agent running
[Timer]
OnBootSec=20s
OnUnitInactiveSec=30s
[Install]
WantedBy=timers.target
U
systemctl daemon-reload
systemctl enable --now telemetry-agent.timer
systemctl start telemetry-agent.service

# --- tuned: someone left the power-saving profile on ---
systemctl enable --now tuned
tuned-adm profile powersave

# --- kernel log and rasdaemon: an MCE and thermal throttling on one CPU ---
MC=$((RANDOM % NCPU)); BANK=$(pick 0 1 2 3 5 6); TC=$(( (MC + 1) % NCPU ))
if [ $((RANDOM % 2)) -eq 0 ]; then ST=0x9000004000010005; TYPE=corrected; else ST=0xb000000000010005; TYPE=uncorrected; fi
truth mce_cpu "$MC"; truth mce_bank "$BANK"; truth mce_type "$TYPE"; truth throttled_cpu "$TC"
systemctl unmask rasdaemon 2>/dev/null || true
systemctl start rasdaemon 2>/dev/null && sleep 3 || true
systemctl stop rasdaemon 2>/dev/null || true
ras_insert mce_record "[{\"timestamp\":\"$(ago 5400)\",\"mcgcap\":3082,\"mcgstatus\":0,\"status\":$((ST)),\"addr\":0,\"misc\":0,\"ip\":0,\"tsc\":0,\"walltime\":$(( $(date +%s) - 5400 )),\"cpu\":$MC,\"cpuid\":525048,\"apicid\":$((MC * 2)),\"socketid\":0,\"cs\":0,\"bank\":$BANK,\"cpuvendor\":0,\"bank_name\":\"bank $BANK\",\"error_msg\":\"Generic CACHE Level-2 Generic Error\",\"mcgstatus_msg\":\"\",\"mcistatus_msg\":\"$( [ $TYPE = corrected ] && echo 'Corrected_error Error_enabled' || echo 'Uncorrected_error Error_enabled')\",\"mcastatus_msg\":\"\",\"user_action\":\"\",\"mc_location\":\"\"}]"
systemctl enable --now rasdaemon 2>/dev/null || true
kmsg 3 "mce: [Hardware Error]: Machine check events logged"
kmsg 3 "mce: [Hardware Error]: CPU $MC: Machine Check: 0 Bank $BANK: ${ST#0x}"
kmsg 3 "mce: [Hardware Error]: TSC 0 MISC 0"
kmsg 3 "mce: [Hardware Error]: PROCESSOR 0:806f8 TIME $(( $(date +%s) - 5400 )) SOCKET 0 APIC $((MC * 2)) microcode 2b000590"
for n in 1 2 3; do
  kmsg 4 "CPU$TC: Core temperature above threshold, cpu clock throttled (total events = $((n * 1371 + RANDOM % 300)))"
  kmsg 4 "CPU$TC: Package temperature above threshold, cpu clock throttled (total events = $((n * 1408 + RANDOM % 300)))"
  kmsg 6 "CPU$TC: Core temperature/speed normal"
done

# --- the persistent cause: a kernel argument that limits the CPUs brought up at boot ---
grubby --update-kernel=ALL --args="maxcpus=1"
for c in /sys/devices/system/cpu/cpu[1-9]*/online; do echo 0 > "$c"; done

systemctl start labbench.service || true
SCORE=$(tail -1 /var/log/labbench.log | sed -n 's/.*score=//p'); SCORE=${SCORE:-100}
mkdir -p /root/evidence
{ echo "labbench results from burn-in, same SKU, same rack build, same firmware"
  echo
  printf '%-12s %5s %8s\n' host cpus score
  for i in 01 02 03 04 05 06; do printf '%-12s %5s %8s\n' rack7-node$i "$NCPU" $(( SCORE * (95 + RANDOM % 11) / 10 )); done
  printf '%-12s %5s %8s   <- this node\n' servera 1 "$SCORE"
} > /root/evidence/peer-bench.txt
answers_template mce_cpu mce_bank mce_type throttled_cpu
echo "Lab 14 ready."
