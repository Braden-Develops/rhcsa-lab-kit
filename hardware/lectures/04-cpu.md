# Lecture H4: CPU: topology, frequency, throttling, machine checks and silent corruption

CPUs fail less often than drives or DIMMs, but when they do it's often in the worst way: a core that computes
wrong answers without raising any error. CPUs also make performance problems look like hardware faults, and the
reverse: a "slow" server is more often a kernel argument, a cgroup limit, a power profile or a cooling problem
than a bad processor.

This lecture covers how Linux sees CPU topology, how frequency and power states work, what throttling is and how
to spot it, the Machine Check Architecture and how to decode it, silent data corruption, and how to stress CPUs
usefully.

Practice: [Lab 14](#/lab/14).

---

## Topology: sockets, cores, threads and NUMA

```bash
lscpu                          # sockets, cores per socket, threads per core, NUMA nodes, caches, flags
lscpu -e                       # one line per logical CPU: node, socket, core, online, max/min MHz
nproc; nproc --all             # online CPUs vs. all CPUs the kernel knows
cat /sys/devices/system/cpu/{present,online,offline}
numactl --hardware             # NUMA nodes, their CPUs and memory, distances
```

- A **socket** holds a CPU package; it has many **cores**; with SMT (Hyper-Threading) each core runs two hardware
  **threads**, and Linux calls each thread a CPU.
- Each socket has its own memory: a **NUMA node**. Memory on the other socket is slower to reach.
- `lscpu` reports `On-line CPU(s) list` and `Off-line CPU(s) list`. CPUs can be offline because someone wrote
  `0` to `/sys/devices/system/cpu/cpuN/online`, because the kernel was booted with `maxcpus=` or `nr_cpus=`, or
  because the BIOS disabled cores or SMT.

A conformance check confirms the CPU model, socket count, core count, SMT state and total online CPUs match the
build sheet. It's cheap and catches a lot: a CPU that isn't fully seated can come up with fewer cores or memory
channels, and a BIOS setting can silently disable cores.

### Kernel arguments that limit CPUs

| Argument | Effect |
|---|---|
| `maxcpus=N` | bring up only N CPUs at boot; the rest can be brought online later via sysfs |
| `nr_cpus=N` | the kernel supports at most N CPUs; the rest can't be onlined at all |
| `nosmt` / `mitigations=auto,nosmt` | disable SMT siblings |
| `isolcpus=`, `nohz_full=` | reserve CPUs away from the general scheduler (legitimate for some workloads) |

```bash
cat /proc/cmdline                       # what this boot used
grubby --info=ALL | grep -E '^(kernel|args)'
grubby --update-kernel=ALL --remove-args="maxcpus"
```

---

## Frequency and power states

A modern CPU constantly changes speed and sleeps to save power:

- **P-states** (performance states) are frequency/voltage levels while running. Turbo (Intel Turbo Boost, AMD
  Precision Boost) runs above base frequency when power and temperature allow.
- **C-states** (idle states) are sleep levels when a core has nothing to do: C1 halts the core, deeper states
  (C6 and beyond) power parts of it down. Deeper means more saving and longer wake-up latency.
- The **cpufreq governor** (`performance`, `powersave`, `schedutil`) and the platform's own controller
  (Intel HWP, AMD CPPC) decide the P-state; `intel_idle` or `acpi_idle` decides the C-state.

```bash
cpupower frequency-info                 # driver, governor, limits
cpupower idle-info                      # available C-states
turbostat --quiet --interval 5          # per-CPU: Busy%, Bzy_MHz, C-state residency, package temp, power (needs MSRs)
grep MHz /proc/cpuinfo
```

On RHEL, **tuned** applies coordinated settings: `throughput-performance` favours speed, `powersave` saves
energy, `latency-performance` disables deep C-states, `virtual-guest` suits VMs. The same hardware benchmarks
differently under each, so **record the active profile with every result**, and make sure test hosts run the
profile your thresholds were set with.

```bash
tuned-adm active; tuned-adm recommend; tuned-adm profile throughput-performance
```

---

## Throttling

When a CPU gets too hot, or draws more power or current than its limits allow, it slows itself down. That's
**throttling**, and on a server it nearly always means something is wrong with cooling or power delivery: a
heatsink not seated, dried thermal paste, a failed fan, blocked airflow, a missing air baffle or blank panel, or a
power limit set too low.

How it shows up:

```text
CPU12: Core temperature above threshold, cpu clock throttled (total events = 4182)
CPU12: Package temperature above threshold, cpu clock throttled (total events = 4210)
CPU12: Core temperature/speed normal
```

```bash
journalctl -k | grep -i throttl
grep . /sys/devices/system/cpu/cpu*/thermal_throttle/*_throttle_count     # Intel: per-core and package counts
turbostat --show Core,CPU,Busy%,Bzy_MHz,CoreTmp,PkgTmp,PkgWatt --interval 5
```

A throttling CPU still works, so nothing fails, but it runs slower than its peers. That's why thermal checks
belong **during** stress: at idle, a badly seated heatsink is invisible. Compare package temperature and
sustained frequency under the same load across identical servers; a socket that runs 15 °C hotter than its twin
in the same chassis has a cooling problem.

---

## Software causes that look like slow hardware

Before blaming the CPU, rule these out (Lab 14 plants all of them):

- **Offline CPUs** (`maxcpus=`, sysfs, BIOS).
- **cgroup limits.** systemd's `CPUQuota=` caps a service's CPU time regardless of how idle the machine is;
  `AllowedCPUs=` / `CPUAffinity=` pin it to a subset. `systemctl show -p CPUQuotaPerSecUSec,AllowedCPUs UNIT`,
  `systemd-cgtop`, `systemctl cat UNIT` (look for drop-ins).
- **Another process** using the CPU: `top` (press `1` for per-CPU), `ps -eo pid,ni,pcpu,cmd --sort=-pcpu`. Ask
  what starts it (`systemctl status PID` names the unit; timers can restart a killed service).
- **The power profile** (tuned, BIOS power settings).
- **Frequency limits** set in sysfs (`scaling_max_freq`) or by the BMC's power capping.

---

## Machine Check Architecture (x86)

x86 CPUs report hardware errors through the **Machine Check Architecture** (MCA). The CPU has a set of
**banks**, each covering a unit (a cache level, the memory controller, the interconnect, the instruction fetch
unit...). When a unit detects an error, it records it in its bank's registers:

| Register | Holds |
|---|---|
| `MCi_STATUS` | what happened: valid, corrected or not, error code |
| `MCi_ADDR` | the physical address involved (if `ADDRV`) |
| `MCi_MISC` | extra detail (if `MISCV`) |

Corrected errors are logged and the CPU carries on (the kernel polls banks periodically, or gets an interrupt).
Uncorrected errors raise a **machine-check exception**; the kernel decides whether it can recover (kill a process,
offline a page) or must panic.

### Decoding MCi_STATUS

The kernel prints the raw values:

```text
mce: [Hardware Error]: CPU 12: Machine Check: 0 Bank 5: be00000000800400
mce: [Hardware Error]: TSC 0 ADDR 3f1a2340 MISC 86
mce: [Hardware Error]: PROCESSOR 0:806f8 TIME 1731577920 SOCKET 1 APIC 18 microcode 2b000590
```

The top bits of the status value are the same on all x86 CPUs (Intel SDM Vol. 3, *Machine-Check Architecture*;
AMD's are equivalent for these bits):

| Bit | Name | Meaning when set |
|---|---|---|
| 63 | VAL | the register holds a valid error |
| 62 | OVER | another error was lost because this one was still there |
| 61 | UC | the error was **not corrected** |
| 60 | EN | reporting was enabled for it |
| 59 | MISCV | `MCi_MISC` is valid |
| 58 | ADDRV | `MCi_ADDR` is valid |
| 57 | PCC | processor context corrupt: execution can't safely continue |

Read the first hex digit as bits 63 to 60 and the second as 59 to 56:

- `9...` = 1001 = VAL + EN: a **corrected** error.
- `b...` = 1011 = VAL + UC + EN: **uncorrected**.
- `be...` = 1011 1110 = VAL, UC, EN, MISCV, ADDRV, **PCC**: uncorrected with corrupt context, usually a panic.
- `fe...`: the same plus OVER.

The low 16 bits are the **MCA error code**, which says what kind of error (for example a cache, memory or bus
error, and the cache level). Which bank number means which unit is model-specific; rasdaemon and the kernel decode
it for known CPUs.

```bash
ras-mc-ctl --errors                     # MCE section: cpu, bank, status, decoded message
journalctl -k | grep -i 'hardware error'
```

**Interpreting machine checks:**

- A *memory controller* bank with an address points at memory: map it to a DIMM (lecture H2).
- Repeated corrected errors from a *cache* bank on the **same core** point at that CPU. A few over years are
  normal; a burst under stress is a reason to pull the CPU.
- *Interconnect* (UPI/Infinity Fabric) errors point at the socket, its seating, or the board.
- An uncorrected error that ended in a panic leaves its record in the kdump vmcore's log, and on many platforms
  in the BMC's SEL too.

**MCE is x86 only.** ARM servers report the same kinds of error through firmware (lecture H8).

---

## Silent data corruption

The most dangerous CPU failure raises **no error at all**: a core computes a wrong result. Large operators have
found this at a rate of roughly one in a thousand servers, usually in specific instructions on specific cores,
often only at certain temperatures or frequencies, and sometimes appearing only after months in service
(Hochschild et al., *Cores That Don't Count*, 2021; Dixit et al., *Silent Data Corruptions at Scale*, 2021).

Consequences for checks:

- **Telemetry can't catch it.** There's no counter. The only way is to run computations whose correct answer is
  known and compare.
- Good SDC tests run **many different instruction mixes** (integer, floating point, vector/AVX-512, crypto,
  compression) on **every core individually** (pin with `taskset`), at different frequencies and temperatures.
- Tools with built-in verification help: `stress-ng` methods with `--verify`, Prime95/`mprime` torture tests
  (which check results against known values), and vendor tools (Intel's DCDIAG/IFS on supported CPUs, OpenDCDiag).
- A core that fails can be taken offline (`echo 0 > /sys/devices/system/cpu/cpuN/online`) as a stopgap, but the
  CPU should be replaced.

---

## Stressing CPUs

| Goal | Tool |
|---|---|
| Maximum heat and power | `mprime` / Prime95 torture (large FFTs), Linpack/HPL, `stress-ng --cpu 0 --cpu-method matrixprod` |
| Correctness | `mprime` torture (self-checking), `stress-ng --cpu 0 --verify`, vendor SDC tools |
| Specific units | `stress-ng --cpu-method` (float, int, fft, crc, ...), `--cache`, `--avx` methods |

```bash
stress-ng --cpu 0 --cpu-method matrixprod --verify --metrics-brief -t 10m    # 0 = one worker per CPU
```

During the run, sample: per-core frequency (`turbostat`), package temperature and power, throttle counters, MCE
records. After it: the stress tool's errors, the MCE delta, throttle event deltas, and a comparison of sustained
frequency and score with peers.

---

## Quick reference

| Task | Command |
|---|---|
| Topology | `lscpu`, `lscpu -e`, `numactl --hardware` |
| Online CPUs | `nproc`, `/sys/devices/system/cpu/online`, `/proc/cmdline` |
| Frequency and idle | `cpupower frequency-info`, `turbostat` |
| Profile | `tuned-adm active`, `tuned-adm recommend` |
| Throttling | `journalctl -k \| grep -i throttl`, `/sys/devices/system/cpu/cpu*/thermal_throttle/` |
| Machine checks | `ras-mc-ctl --errors`, `journalctl -k \| grep -i 'hardware error'` |
| cgroup limits | `systemctl show -p CPUQuotaPerSecUSec UNIT`, `systemd-cgtop` |
| Stress | `stress-ng --cpu 0 --verify -t 10m`, `mprime -t` |

Reading: Hochschild et al., *Cores That Don't Count* (HotOS 2021); Dixit et al., *Silent Data Corruptions at
Scale* (2021) and *Detecting Silent Data Corruptions in the Wild* (2022); Intel SDM Vol. 3, Machine-Check
Architecture; Gregg, *Systems Performance*, chapter on CPUs.

---

## Review questions

1. `nproc` prints 1 on a two-socket server. List three places to look.
2. What's the difference between `maxcpus=` and `nr_cpus=`?
3. Decode `MCi_STATUS = 0x9000004000010005` and `0xbe00000000800400`: corrected or not? Can execution continue?
4. Why must thermal checks run during stress rather than before it?
5. A service is slow, the machine is 90% idle, and `top` shows the service at exactly 25% of one CPU. Likely cause?
6. Why can't EDAC, MCE or any other telemetry catch silent data corruption, and what can?
7. You kill a process eating a CPU; 30 seconds later it's back. What do you check?

<details><summary>Answers</summary>

1. `/proc/cmdline` (for `maxcpus=`/`nr_cpus=`), `/sys/devices/system/cpu/online` and `offline` (CPUs offlined at
   runtime), and the BIOS/firmware (cores or SMT disabled, or a CPU not detected: check `lscpu` sockets and the SEL).
2. With `maxcpus=` the other CPUs can be onlined later through sysfs; with `nr_cpus=` the kernel won't support them
   at all until reboot.
3. `0x9000...`: VAL + EN, corrected, execution continues. `0xbe00...`: VAL, UC, EN, MISCV, ADDRV and PCC: uncorrected
   with corrupt context, the system can't safely continue (normally a panic).
4. Cooling problems only show when the CPU produces full heat; at idle a badly seated heatsink looks normal.
5. A cgroup CPU quota (`CPUQuota=25%`), probably in a systemd drop-in.
6. Nothing in the hardware detected an error, so nothing is counted. Only computing known answers (self-checking
   tests on each core) and comparing can find it.
7. What starts it: `systemctl status PID` for the owning unit, then `systemctl list-timers` and the unit's
   `Restart=` setting. Disable the timer or unit, don't just kill the process.

</details>
