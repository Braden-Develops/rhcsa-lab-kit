# Lab 14 solution

## Survey first

```bash
nproc; nproc --all; lscpu | grep -i 'on-line\|off-line'     # e.g. 1 of 2 online
cat /sys/devices/system/cpu/{present,online,offline}
cat /proc/cmdline                                           # ... maxcpus=1
top                                                         # press 1 for per-CPU; a python3 at ~100%
systemctl status labbench.service                           # Drop-In: 10-accounting.conf
systemctl cat labbench.service                              # CPUQuota=25%
tuned-adm active                                            # powersave
```

`maxcpus=1` tells the kernel to bring up only one CPU at boot. The others stay present but offline, so you can bring
them online later through sysfs. `nr_cpus=` is the harsher cousin: CPUs beyond it can't be onlined at all.

## 1. CPUs

```bash
for c in /sys/devices/system/cpu/cpu[1-9]*/online; do echo 1 > $c; done
grubby --update-kernel=ALL --remove-args="maxcpus"
grubby --info=ALL | grep ^args
```

## 2. Quota

```bash
rm /etc/systemd/system/labbench.service.d/10-accounting.conf
systemctl daemon-reload
systemctl show -p CPUQuotaPerSecUSec labbench          # infinity
```

`CPUQuota=25%` puts the service in a cgroup that gets at most a quarter of one CPU's time per period, however many
CPUs are idle. `systemd-cgtop` shows cgroup CPU use live.

## 3. The hog

```bash
ps -eo pid,ni,pcpu,cmd --sort=-pcpu | head -3          # /usr/local/libexec/telemetry-agent
systemctl status <PID>                                 # systemd tells you which unit owns a PID
systemctl list-timers | grep telemetry                 # telemetry-agent.timer restarts it 30 s after it stops
systemctl disable --now telemetry-agent.timer
systemctl stop telemetry-agent.service
# optional, and stronger: systemctl mask telemetry-agent.service telemetry-agent.timer
```

Killing the PID alone "works" for 30 seconds. Always ask what starts a process before you kill it.

## 4. Tuning

```bash
tuned-adm recommend          # virtual-guest in a VM, throughput-performance on most bare-metal servers
tuned-adm profile "$(tuned-adm recommend)"
```

On bare metal, `powersave` lets the CPUs sit in deep C-states and at low clocks. Record the active tuned profile
with every benchmark result, because the same hardware scores differently under different profiles.

## 5. Prove it

```bash
labbench                     # cpus=2 ... score roughly 10x the first run
```

## 6. Hardware events

```bash
journalctl -k | grep -E 'mce|Hardware Error|throttled'
ras-mc-ctl --errors          # the MCE section lists cpu, bank and status
```

```text
mce: [Hardware Error]: CPU 1: Machine Check: 0 Bank 5: b000000000010005
```

Decode the top bits of `MCi_STATUS` (Intel SDM Vol. 3, Machine-Check Architecture):

| bit | name | meaning |
|---|---|---|
| 63 | VAL | the register holds a valid error |
| 62 | OVER | an earlier error was overwritten |
| 61 | UC | **uncorrected** error |
| 60 | EN | error reporting was enabled |
| 59 | MISCV | MCi_MISC is valid |
| 58 | ADDRV | MCi_ADDR is valid |
| 57 | PCC | processor context corrupt: the system can't safely continue |

The first hex digit covers bits 63 to 60: `9` = 1001 = VAL + EN, so **corrected**; `b` = 1011 = VAL + UC + EN, so
**uncorrected** (but with PCC clear, the kernel could contain it). `throttled_cpu` is the CPU in the
"temperature above threshold, cpu clock throttled" lines.

On real hardware these matter more than anything else here: a CPU that throttles under load is a cooling problem
(heatsink seating, thermal paste, fan or airflow), and repeated corrected MCEs from the same bank on the same core
are a reason to pull that CPU, even though nothing has crashed.

## What was simulated

The MCE and throttle lines were written through `/dev/kmsg` and the MCE record was inserted into rasdaemon's
database. The CPU, cgroup, systemd and tuned problems are all real.
