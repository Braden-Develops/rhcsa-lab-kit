# Lecture H1: Method: how hardware faults reach you, and what makes a good check

Hardware rarely announces "I am broken". It reports a correctable error here, a retried transfer there, a fan
that spins a little slower, a link that trained at half width. Most of the time the machine keeps working.
Your job is to notice, to tell a real fault from noise, to point at the **right** part, and to turn what you
learned into an automated check that catches the next one.

This lecture is the toolkit and the mindset every other lecture in the module uses. It covers how errors travel
from silicon to a log you can read, the three kinds of hardware check, why stress testing works, the rules that
separate a trustworthy check from a flaky one, and a troubleshooting routine that works on any subsystem.

Every lab in this module (12 to 18) uses what's here.

---

## The path of an error: from silicon to your terminal

Almost every component in a server detects some of its own errors. What differs is how the report reaches you.

```text
 component detects an error
   │
   ├── corrects it (ECC, link retry, sector remap)  ──► increments a counter
   │                                                    (EDAC ce_count, SMART attribute, AER status,
   │                                                     SAS PHY counter, NIC error counter)
   │
   └── raises it to the platform
         ├── x86: Machine Check Architecture (MCE banks) ──► kernel MCE handler
         ├── PCIe: AER message to the root port ──────────► kernel AER driver
         ├── ARM/firmware-first: firmware builds a CPER record, tells the OS through ACPI GHES
         └── BMC sensors and events ──────────────────────► System Event Log (SEL), Redfish
                                                         │
 kernel drivers (EDAC, AER, nvme, libata, SCSI, md) print to the kernel ring buffer  ──► dmesg, journalctl -k
 tracepoints (ras:mc_event, mce:mce_record, ras:aer_event ...)  ──► rasdaemon  ──► SQLite database, ras-mc-ctl
```

Three things follow from that picture.

**Counters and logs are different evidence.** A counter (`ce_count`, `UDMA_CRC_Error_Count`,
`invalid_dword_count`) tells you *how many* and lets you compute a **rate**. A log line tells you *when* and
*where* (which DIMM, which PCI address, which sector). You usually need both: the counter to decide whether it
matters, the log to locate it.

**Some of the evidence is outside the OS.** The BMC (baseboard management controller) is a small computer on the
motherboard with its own network port. It watches fans, temperatures, voltages and power supplies whether or not
the OS is running, and keeps its own System Event Log. A server can have a dead fan that Linux never mentions.

**Logs are lossy.** The kernel ring buffer is a fixed size and wraps. Messages are rate limited
(`printk_ratelimit`), so a storm of errors may be summarised as "N callbacks suppressed". That is why
`rasdaemon` exists: it subscribes to the kernel's RAS tracepoints and stores every event in a database that
survives reboots. Make it part of every test image:

```bash
dnf install rasdaemon
systemctl enable --now rasdaemon
ras-mc-ctl --summary            # memory errors per DIMM, plus MCE, AER and disk error summaries
ras-mc-ctl --errors             # every event, with timestamps
```

### Reading the kernel log well

`dmesg` and `journalctl -k` show the same ring buffer, but the journal keeps it across reboots (if the journal is
persistent) and can filter:

```bash
journalctl -k -b                         # this boot's kernel messages
journalctl -k -b -1 -p warning           # last boot, warnings and worse (what happened before that crash?)
journalctl -k --since "2 hours ago" | grep -Ei 'error|fail|mce|edac|aer|i/o'
dmesg -T --level=err,warn                # human timestamps; note -T can drift after suspend
dmesg -w                                 # follow live while you run a test
```

Kernel messages from drivers are prefixed with the driver and the device, for example
`nvme 0000:17:00.0:`, `ata3.00:`, `sd 2:0:0:0: [sdc]`, `EDAC MC1:`, `mce:`. That prefix is how you get from a
message to a physical part, and every subsystem lecture shows how to follow it.

### Persistence: a log you can't read after the crash is no log

Two settings belong on any test or factory image:

- **A persistent journal** (`mkdir -p /var/log/journal`, or `Storage=persistent` in `journald.conf`), so
  `journalctl -b -1` shows what happened before a reboot.
- **kdump** (`kexec-tools`, `systemctl enable --now kdump`, a `crashkernel=` reservation on the kernel command
  line), so a kernel panic under stress leaves a `vmcore` in `/var/crash` instead of a blank screen. An uncorrected
  machine check usually ends in a panic, and the vmcore's log (`crash` or `makedumpfile --dump-dmesg`) still holds
  the decoded error.

---

## Three kinds of hardware check

Every hardware check you will write is one of three types, and they need different skills.

| Type | Question | Examples | Core skill |
|---|---|---|---|
| **Conformance** | Is this the right hardware, configured correctly? | BIOS and firmware versions, DIMM count and size, disk count, PCIe link width, slot population | Inventory data: SKU specifications, firmware matrices, SMBIOS and FRU data |
| **Passive health** | Does the hardware report itself healthy? | SMART, EDAC counters, sensors, PSU status, AER counters | Knowing which counters matter and where the thresholds belong |
| **Active stress** | Does it still work under load? | memory stress, fio, CPU burn, fan-out I/O, network traffic | Generating load **and** reading telemetry during it; statistics |

Conformance checks are the easiest to write and are often most of a test suite. They catch build mistakes: the
wrong DIMM in a slot, an old firmware, a card in the wrong slot. Passive health checks are cheap and catch parts
that are already failing. Active stress is where marginal parts are found, and it's the hardest to do well.

### The key idea: stress makes the failure, telemetry catches it

A stress tool such as `stressapptest`, `stress-ng` or `fio` has its own pass/fail: did the data come back
correct? That catches some failures. But most of what stress does is push hardware to its **thermal, power and
electrical limits**, and the hardware's *own* error reporting catches the result:

- A memory stress run with zero miscompares can still have produced 400 correctable ECC errors on one DIMM. ECC
  fixed them, so the stress tool saw correct data, and the DIMM is still bad.
- A fio run that completed can have caused a dozen link resets and CRC errors on one drive.
- A CPU burn that finished can have made one socket throttle because its heatsink isn't seated.

So an active check is always three steps:

```text
 1. read every relevant counter           (EDAC, SMART, AER, PHY counters, sensors, SEL)
 2. run the stress for a fixed time        (while sampling sensors and logs)
 3. read the counters again, and judge the DELTA, the stress tool's own verdict, and the readings under load
```

Lab 12 builds exactly this wrapper for memory (`ce-delta`), lab 16 for thermal and power, lab 17 for a JBOD.

---

## The rules of a trustworthy check

A hardware check makes a decision with money attached: a good part pulled wastes a technician's time and the
part; a bad part shipped becomes a production incident. These rules are what make a check worth trusting.

### 1. Missing telemetry is a failure, never a pass

This is the most important rule in the module, and the most common bug in real checks. If a check can't read EDAC
counters, SMART data, sensors or the BMC, it **does not know** whether the hardware is healthy, and it must not
say "pass".

The bug usually looks innocent:

```bash
errors=$(cat /sys/devices/system/edac/mc/mc*/ce_count 2>/dev/null | paste -sd+ | bc)
[ "${errors:-0}" -eq 0 ] && echo PASS          # no EDAC driver loaded -> errors empty -> 0 -> PASS
```

On a machine where the EDAC driver didn't load (a new platform, a missing kernel module, an ARM server, a VM),
that check passes every DIMM forever. Report three outcomes, not two:

| Outcome | Meaning | Typical exit code |
|---|---|---|
| pass | telemetry read, everything within limits | 0 |
| fail | telemetry read, something out of limits | 1 |
| error / cannot check | telemetry missing or unreadable | 2 |

and a fourth where it applies: **not applicable** (the check doesn't apply to this platform, such as MCE on ARM),
which must be stated explicitly so nobody reads it as a pass. Labs 12, 15, 16 and 18 all grade this.

### 2. Compare to peers, not just to magic numbers

Servers of the same model, built from the same parts list, in the same rack, should behave alike. That makes the
**peer group** the best reference you have:

- a drive whose fio bandwidth is 30% below its siblings is suspect even if it clears an absolute threshold;
- a server whose benchmark is 10% below the median of its rack has something wrong (lab 14);
- one DIMM with 400 correctable errors while its 23 neighbours have zero is a bad DIMM, not "a bit of noise".

Use the **median** of the peers, not the mean: a couple of very bad units drag the mean down until they no longer
look bad. Lab 17 builds a peer-outlier detector.

### 3. Judge rates and deltas, not totals

Counters accumulate for the life of a component. A PHY with 900 invalid dwords might have had them all during
cabling two years ago. What matters is the change during the test window, or the rate per hour. Always capture
**before and after**.

### 4. False positives cost more than they seem

A check that's 99% accurate, run on 10,000 servers, makes 100 wrong calls. Each one pulls a good part, costs a
technician an hour, and teaches people to ignore the check. Then they ignore it the time it's right. Before
shipping a check, find out its false-positive rate on known-good hardware.

### 5. False negatives cost more still

A bad part that passes becomes a production outage, an RMA and a site visit. The most valuable data you can get
is **escape analysis**: units that passed screening and failed soon after deployment. Group them by component and
by failure mode, and you have a ranked list of the checks that are missing.

### 6. Thresholds come from somewhere

Every threshold should have a written reason: a vendor's RMA criteria ("replace a DIMM after N correctable errors
in M hours"), a specification limit (a sensor's critical threshold), or data from qualification testing. A
threshold stricter than the vendor's RMA criteria fails parts the vendor won't take back, which creates an
inventory problem instead of solving one.

---

## Lab, factory and fleet

The same hardware gets tested at three points in its life, and "good" means something different at each.

| | Lab (qualification) | Factory (screening) | Fleet (monitoring) |
|---|---|---|---|
| **When** | New model, platform, firmware or vendor | Every unit, at build | After deployment, and on returns |
| **Question** | Is the *design* sound, and where are its limits? | Is *this unit* built right and free of early-life defects? | Is this unit *still* healthy? Is it about to fail? |
| **Finds** | Firmware bugs, thermal limits, compatibility problems, bad batches | Seating, cabling, dead-on-arrival parts, infant mortality | Wear-out, degradation, drift, silent corruption |
| **Time** | Days to weeks, few units | Minutes per unit, times every unit | Continuous, in small slices |
| **Disruption** | Anything, including destructive tests | The host is yours until it ships | Must not hurt production |

They feed each other. Qualification **sets the thresholds** the factory uses. If many units of one batch fail the
same factory check, that's a design or supplier problem to escalate, not a pile of individual RMAs. Fleet
escapes show where factory coverage has gaps.

### The time budget

In a factory, burn-in time is the scarce resource: each extra minute multiplies across every unit. Early-life
failures follow a decreasing curve (the left side of the classic "bathtub curve"): most of them appear in the first
part of a stress run, and each additional hour catches fewer. Knowing that curve from your own data lets you
justify the duration of each test tier, or cut it.

---

## A troubleshooting routine that works on anything

RH342 teaches a general method; for hardware it looks like this.

1. **Define the symptom precisely.** "Slow" is not a symptom; "labbench scores 10% of its peers" is. Get the
   exact error, the time it started, and what changed.
2. **Collect before you change anything.** `sos report` captures logs, configuration and hardware inventory in
   one archive (`sos report --batch`, output in `/var/tmp`). Diffing the sos reports of a failing and a passing
   machine of the same model is one of the fastest ways to find a configuration difference.
3. **Read the evidence from the bottom up.** BMC (SEL, sensors) → firmware (CPER records) → kernel log → RAS
   database → application. Hardware problems usually show up lower in the stack first.
4. **Locate it physically.** Every subsystem has a translation from a Linux name to a physical location: EDAC label
   to DIMM slot, PCI address to slot, SCSI address to enclosure bay. A diagnosis that doesn't name a slot isn't
   finished.
5. **Form one hypothesis and test it.** Change one thing at a time. Swap the suspect part with a known-good
   neighbour: if the error follows the part, it's the part; if it stays with the slot, it's the slot, cable or
   backplane.
6. **Fix, then verify under the same load that exposed it.**
7. **Ask what check would have caught it,** and write it.

### Quick reference: where each kind of evidence lives

| Evidence | Command or path |
|---|---|
| Kernel log | `journalctl -k`, `dmesg -T` |
| RAS event database | `ras-mc-ctl --summary` / `--errors`, `/var/lib/rasdaemon/ras-mc_event.db` |
| Memory controller counters | `/sys/devices/system/edac/mc/mc*/` |
| Hardware inventory | `dmidecode`, `lshw -short`, `lscpu`, `lsblk`, `lspci`, `lsscsi` |
| Disk health | `smartctl -x /dev/sdX`, `nvme smart-log /dev/nvme0` |
| PCIe errors | `lspci -vvv`, `/sys/bus/pci/devices/*/aer_dev_*` |
| SAS links | `/sys/class/sas_phy/*/` |
| BMC sensors and events | `ipmitool sensor`, `ipmitool sel elist`, Redfish `/redfish/v1/Chassis/...` |
| Full snapshot | `sos report` |
| Crash dumps | `/var/crash/` (kdump) |

---

## How the labs in this module simulate faults

The labs run in containers or a small VM, which have no physical parts to break. Each lab uses the most realistic
mechanism available, and says which in its solution:

- **Real kernel behaviour** where a VM allows it: device-mapper `error` targets make real I/O errors, `delay`
  targets make real latency, md RAID really ejects a failing member, and CPU onlining, cgroup quotas, systemd units
  and tuned profiles are all real.
- **Kernel log lines** written through `/dev/kmsg`. They show up in `dmesg` and `journalctl -k` like driver
  messages. One tell: `dmesg -x` shows their facility as `user` instead of `kern`.
- **rasdaemon records** inserted into its SQLite database, so `ras-mc-ctl` reports them like real events.
- **A simulated BMC** (a small Redfish service) and **captured output** from `lspci`, `smartctl`, `ipmitool` and
  sysfs, generated in exactly the format the real tools print.

---

## Review questions

1. A memory stress test finishes with zero miscompares. Name two reasons the server could still have a bad DIMM,
   and what you'd look at.
2. A check reads `/sys/devices/system/edac/mc/mc*/ce_count` and fails the host if the sum is above 0. What happens
   on a machine where the EDAC driver isn't loaded, and how should the check behave instead?
3. Why compare a drive's throughput with its siblings' median rather than with an absolute threshold, and why the
   median rather than the mean?
4. A SAS PHY shows 850 invalid dwords. Is that a problem?
5. Why does a factory care so much about the time each test takes, and what data lets you justify cutting it?
6. What do a persistent journal and kdump each give you after a server crashes under stress?
7. You suspect a DIMM. What swap test tells you whether the fault is the DIMM or the slot?

<details><summary>Answers</summary>

1. ECC corrected the errors, so the stress tool saw correct data: check the EDAC/rasdaemon correctable-error delta
   across the run. Or the fault needs heat or a specific access pattern the run didn't reach: check temperatures
   during the run and use a tool that exercises the interconnect (stressapptest).
2. The glob matches nothing, the sum is empty or 0, and the check passes every host. It should detect that no
   memory controllers are present and report "cannot check" (exit 2), never pass.
3. Peers share the same model, parts and environment, so a unit that differs from them is suspicious even if it
   clears a generic limit. The median isn't dragged down by the bad units themselves.
4. Not by itself: it's a lifetime total. Compare snapshots before and after a test; only a delta (or a rate)
   says whether the link is bad now.
5. Every minute is multiplied by every unit built. Historical data on *when* during burn-in failures are detected
   shows how much time catches how many failures.
6. The journal keeps the kernel log from before the reboot (`journalctl -b -1`); kdump keeps a memory image of the
   crashed kernel, including its log and the decoded machine check.
7. Swap the suspect DIMM with a known-good one in another slot. If the errors move with the DIMM, replace the DIMM;
   if they stay with the slot, the problem is the slot, the board or the memory controller.

</details>
