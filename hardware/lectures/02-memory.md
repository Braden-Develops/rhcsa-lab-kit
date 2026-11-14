# Lecture H2: Memory: ECC, EDAC, rasdaemon and finding the DIMM

Memory is the best place to start learning hardware validation. Servers carry a lot of it (often 16 to 32 DIMMs),
it fails in the field more than most parts, its error reporting is mature on Linux, and the whole chain from
"error" to "replace the DIMM in slot CPU1_DIMM_E1" is something you can learn completely.

This lecture covers how server memory is organised, how ECC detects and corrects errors, how Linux reports them
(EDAC and rasdaemon), how to turn an error report into a physical slot, how to stress memory, and how to decide
whether a DIMM goes back to the vendor.

Practice: [Lab 12](#/lab/12).

---

## How server memory is organised

```text
 socket (CPU) ─┬─ memory controller 0 ─┬─ channel 0 ─┬─ DIMM slot 0 ── DIMM ─┬─ rank 0 ── chips ── banks ── rows × columns
               │                       │             └─ DIMM slot 1          └─ rank 1
               │                       ├─ channel 1
               │                       └─ channel 2
               └─ memory controller 1 ── channels 0..2
```

- A **socket** has one or more **integrated memory controllers** (IMCs). Each drives several **channels**: an
  independent 64-bit data path (plus ECC bits) to the DIMM slots on it. Modern server CPUs have 6 to 12 channels
  per socket. DDR5 splits each DIMM into two 32-bit subchannels, but EDAC still reports by channel and DIMM.
- Each channel has one or two **DIMM slots**. Populating the first slot of every channel before any second slot
  ("one DIMM per channel") gives the most bandwidth.
- A DIMM has one or more **ranks**: sets of DRAM chips that together provide one channel's width. The chips are
  internally split into **banks** (grouped into bank groups), each a grid of **rows** and **columns**.
- Memory is **interleaved** across channels so consecutive cache lines go to different channels. That's good for
  bandwidth, and it means one bad DIMM can affect data from everywhere in the address space.

`lscpu` and `numactl --hardware` show sockets and NUMA nodes; `dmidecode -t memory` (type 17, *Memory Device*)
lists every slot with its size, speed, part number, serial and its **Locator**, the label printed on the board.

```bash
dmidecode -t 17 | grep -E 'Locator|Size|Speed|Part Number|Serial' | paste - - - - - -
```

An empty slot shows `Size: No Module Installed`. A conformance check compares this list with the build sheet:
right count, right slots, right part numbers, all at the expected speed.

---

## ECC: how memory detects and corrects its own errors

DRAM stores bits as tiny charges that leak and can be disturbed. Bits flip for transient reasons (particle strikes,
electrical noise) and for permanent ones (a failing cell, a bad column or row, a failing chip, a bad connection
between the DIMM and the slot).

Server memory adds extra bits to every word and stores an **error-correcting code** in them:

- **SECDED** (single error correct, double error detect): 8 check bits per 64 data bits. Corrects any single
  flipped bit, detects any two.
- **Chipkill / SDDC / ADDDC** (names vary by vendor): spreads each code word across chips so that the failure of
  an **entire DRAM chip** can be corrected. This is why x4 DIMMs (4 bits per chip, more chips) are preferred in
  servers: one chip's failure costs fewer bits of each word.

Results of an ECC check:

| Result | Meaning | What happens |
|---|---|---|
| **Correctable error (CE)** | the code fixed it | correct data delivered; a counter goes up and an event is logged |
| **Uncorrectable error (UE)** | detected but not fixable | the data is known to be wrong; a machine check is raised |
| Silent corruption | too many bits wrong for the code to notice | wrong data, no error. Rare with good ECC; the reason checksums exist |

What the OS does with a UE depends on the platform and where the bad data was going. If a user process consumed
it, the kernel can kill that process and take the page out of service (*memory failure recovery*). If the
kernel's own data is affected, the machine panics. Either way, a UE on a DIMM means **replace it**.

### Scrubbing, sparing and page offlining

- **Patrol scrub:** the memory controller reads all of memory in the background (typically every 24 hours),
  correcting single-bit errors before a second error in the same word turns them into a UE. Patrol scrub finds
  errors in memory nobody is using, so a quiet server can still log CEs.
- **Demand scrub:** when a read finds a CE, the corrected value is written back.
- **Sparing and rank/bank sparing:** some platforms retire a failing rank or bank and use a spare.
- **Page offlining:** the OS can stop using a 4 KiB page that keeps producing CEs. rasdaemon can do this
  automatically (see `PAGE_CE_THRESHOLD` and `PAGE_CE_ACTION` in `/etc/sysconfig/rasdaemon`), and you can do it
  manually through `/sys/devices/system/memory/soft_offline_page`.

These features hide problems from applications, which is good for production and a reason a test must read the
counters directly.

---

## What the field studies found

Large studies of DRAM in data centres changed how memory errors are treated:

- **Errors are not random.** Most come from a small fraction of DIMMs, and a DIMM that has had correctable errors is
  far more likely to have more, and much more likely to have an uncorrectable one later
  (Schroeder, Pinheiro and Weber, *DRAM Errors in the Wild*, 2009).
- **Hard faults dominate.** Most errors come from permanent faults in a cell, row, column or chip, not from cosmic
  rays (Sridharan and Liberty, *A Study of DRAM Failures in the Field*, 2012).
- **Location matters.** Errors cluster by row, column and bank, which is why a burst of CEs at nearby addresses on
  one DIMM is meaningful and a single CE every few months is not.

The practical rule: **one isolated CE is noise; a pattern of CEs on one DIMM is a failing DIMM.**

---

## EDAC: the kernel's memory error reporting

**EDAC** (Error Detection And Correction) is the kernel subsystem that talks to the memory controller. A
platform-specific driver loads for the memory controller: `skx_edac` and `i10nm_edac` on recent Intel Xeon,
`amd64_edac` on AMD EPYC, various SoC drivers on ARM. Check which:

```bash
lsmod | grep -i edac
journalctl -k -b | grep -i edac | head        # "EDAC MC0: Giving out device to module skx_edac ..."
ls /sys/devices/system/edac/mc/                 # mc0 mc1 ...  (empty: no driver, no telemetry)
```

The sysfs tree:

```text
/sys/devices/system/edac/mc/
  mc0/
    mc_name                 e.g. "Skylake Socket#0 IMC#0"
    ce_count  ue_count      totals for this memory controller since the driver loaded
    ce_noinfo_count         errors the driver couldn't attribute to a DIMM
    dimm0/ dimm1/ ...       (rank*/ on some drivers)
      dimm_label            the label, e.g. "CPU_SrcID#0_MC#0_Chan#1_DIMM#0"
      dimm_location         "channel 1 slot 0"
      dimm_ce_count  dimm_ue_count
      size  dimm_mem_type  dimm_dev_type
```

Counters reset when the driver loads (every boot), and only cover what this boot has seen. Labels come from the
driver; some platforms let you load real silkscreen labels (`ras-mc-ctl --register-labels` with a file in
`/etc/ras/dimm_labels.d/`).

### From an EDAC message to a slot on the board

A typical Intel message:

```text
EDAC MC2: 1 CE memory read error on CPU_SrcID#1_MC#0_Chan#1_DIMM#0 (channel:1 slot:0 page:0x3f1a2
  offset:0x340 grain:32 syndrome:0x0 - err_code:0x0000:0x009f ProcessorSocketId:0x1 MemoryControllerId:0x0
  PhysicalRankId:0 Row:0x2a6c Column:0x1e8 Bank:0x2 BankGroup:0x1)
```

- `EDAC MC2` is the **EDAC** memory controller number, counted across the whole machine.
- `CPU_SrcID#1_MC#0_Chan#1_DIMM#0` is the **location**: socket 1, that socket's memory controller 0, channel 1,
  DIMM 0. Note that `MC#0` here is per socket, which is not the same number as `MC2`. Confusing the two sends a
  technician to the wrong slot.
- The board's silkscreen uses its own names (`CPU1_DIMM_B1`, `P2-DIMMB1`, `DIMM_B1` and so on). The mapping from
  socket/controller/channel/slot to silkscreen is in the **vendor's service manual**, and differs between
  platforms. Write it down once per platform and put it in your check.
- Row, column and bank tell you whether repeated errors come from the same row (a row failure), the same column,
  or are scattered (a chip or connection problem).

Always confirm with the inventory: the `Locator` in `dmidecode -t 17` should match the slot you computed, and the
serial number gives you the exact part to RMA.

---

## rasdaemon: keep every event

EDAC counters reset at boot and the kernel log rotates. **rasdaemon** subscribes to the kernel's RAS tracepoints
(`ras:mc_event`, `mce:mce_record`, `ras:aer_event`, disk errors and others) and stores every event in an SQLite
database, `/var/lib/rasdaemon/ras-mc_event.db`.

```bash
systemctl enable --now rasdaemon
ras-mc-ctl --status          # is EDAC loaded?
ras-mc-ctl --layout          # the memory layout EDAC sees
ras-mc-ctl --summary         # error counts per DIMM label, per error type
ras-mc-ctl --errors          # every event with timestamp, label, address
sqlite3 /var/lib/rasdaemon/ras-mc_event.db \
  "select label, err_type, sum(err_count) from mc_event group by label, err_type;"
```

Each `mc_event` row carries `err_count` (one row can hold several errors), `err_type` (Corrected, Uncorrected,
Fatal), the label, the layers (channel, slot), the address and the driver's detail string. Masking or disabling
rasdaemon "because it's noisy" is how a fleet stops seeing its failing DIMMs: Lab 12 starts from exactly that.

On RHEL 8 and later, rasdaemon replaced `mcelog` as the place where machine checks are logged too.

---

## Stressing memory

| Tool | What it does | Notes |
|---|---|---|
| **stressapptest** | Copies large blocks between memory regions with many threads, verifying everything; also CPU and disk threads | Written by Google to find bad hardware; exercises the memory interconnect and controller harder than simple patterns. `-W` adds more CPU-intensive copies. |
| **memtester** | Classic pattern tests (walking ones, stuck address, random) on a block of memory | Simple, single threaded, slow to cover large memory |
| **stress-ng --vm** | Allocates and exercises memory with many methods; `--verify` checks results | Good for load and for specific methods (`--vm-method`) |
| **memtest86 / memtest86+** | Bootable, tests all memory from outside the OS | The only way to test memory the OS is using, but needs downtime |

A typical run:

```bash
stressapptest -s 600 -M $(( $(awk '/MemAvailable/ {print $2}' /proc/meminfo) * 9 / 10 / 1024 )) -W
```

Leave room for the OS: allocating all available memory triggers the OOM killer, and a test killed by OOM proves
nothing. Report the stress tool's own result (`Status: PASS` or miscompare count) **and** the EDAC delta.

### A memory check that is worth running

```text
1. confirm EDAC is loaded and lists the expected number of DIMMs     (if not: cannot check, exit 2)
2. record ce_count/ue_count per DIMM (and rasdaemon's row count)
3. run stressapptest for the tier's duration, sampling temperatures
4. record counters again
5. fail if: stress tool reported miscompares, any UE, any DIMM's CE delta over the threshold,
   or EDAC disappeared during the run
6. name the slot (silkscreen) and serial of any failing DIMM in the result
```

Heat matters. DIMMs that fail only when warm are common, so a short idle test finds little. Run long enough for
temperatures to stabilise, and read DIMM temperature sensors from the BMC during the run.

---

## Deciding: replace or monitor

Vendors publish RMA criteria. They vary, but typically:

- **any uncorrectable error** attributed to a DIMM: replace;
- **correctable errors above a rate**, for example more than N in 24 hours on one DIMM: replace;
- the platform **retired a rank or exhausted sparing**: replace;
- isolated CEs spread over weeks: monitor.

Two traps:

- **The slot, not the DIMM.** If a replacement DIMM in the same slot shows errors too, suspect the slot, the board
  or the CPU's memory controller (a bent socket pin can produce exactly this). Swap the DIMM with a neighbour to
  tell which.
- **Training failures.** At boot the BIOS *trains* each channel. A DIMM that fails training is often disabled
  silently, and the server boots with less memory. Compare total memory with the build sheet (`free -g`,
  `dmidecode -t 17`) and look for BIOS events in the SEL. That's a conformance check, and a very cheap one.

---

## Row hammer, briefly

Repeatedly activating one DRAM row can flip bits in neighbouring rows (Kim et al., *Flipping Bits in Memory Without
Accessing Them*, 2014). It's a security problem as much as a reliability one. Mitigations live in the DRAM and
memory controller (target row refresh, higher refresh rates). For validation, it explains why some memory tests
use specific access patterns, and why a DIMM can pass simple patterns yet fail under a particular workload.

---

## Quick reference

| Task | Command |
|---|---|
| Which EDAC driver? | `lsmod \| grep edac`, `journalctl -k \| grep -i edac` |
| Counters per DIMM | `grep . /sys/devices/system/edac/mc/mc*/dimm*/{dimm_label,dimm_ce_count,dimm_ue_count}` |
| Error history | `ras-mc-ctl --summary`, `ras-mc-ctl --errors` |
| Slot inventory | `dmidecode -t 17` |
| Stress | `stressapptest -s SECONDS -M MB -W`, `stress-ng --vm N --vm-bytes 80% --verify -t 10m` |
| Offline a bad page | `echo 0xADDR > /sys/devices/system/memory/soft_offline_page` |

Reading: Schroeder, Pinheiro, Weber, *DRAM Errors in the Wild* (2009); Sridharan and Liberty, *A Study of DRAM
Failures in the Field* (SC 2012); Meza et al., *Revisiting Memory Errors in Large-Scale Production Data Centers*
(DSN 2015); Drepper, *What Every Programmer Should Know About Memory*; kernel `Documentation/admin-guide/ras.rst`.

---

## Review questions

1. What's the difference between `EDAC MC2` and `MC#0` in an EDAC message?
2. Why are x4 DIMMs preferred to x8 in servers that use chipkill-style ECC?
3. A quiet server with no workload logs correctable errors overnight. How?
4. Why does rasdaemon matter if the EDAC counters are in sysfs?
5. A replacement DIMM in slot B1 starts logging CEs within a day, like the old one did. What next?
6. A server boots with 480 GiB instead of 512 GiB and logs no memory errors. Where do you look?
7. What should a memory check do if `/sys/devices/system/edac/mc/` is empty?

<details><summary>Answers</summary>

1. `EDAC MC2` is EDAC's machine-wide numbering of memory controllers; `MC#0` in the label is the controller number
   within that socket. Map the label, not the EDAC number, to the slot.
2. With x4 chips, each chip contributes fewer bits to each code word, so the code can correct the loss of a whole
   chip.
3. Patrol scrub reads all memory in the background and corrects (and reports) errors it finds.
4. EDAC counters reset at every boot and kernel messages rotate and are rate limited; rasdaemon keeps every event,
   with timestamps and addresses, across reboots.
5. Suspect the slot, board or memory controller: move the DIMM to another slot (or swap with a neighbour) and see
   whether the errors follow the DIMM or stay with the slot.
6. A DIMM that failed training and was disabled: compare `dmidecode -t 17` with the build sheet, and read the BMC's
   SEL for memory training or configuration events.
7. Report that it cannot check (no memory controller telemetry), exit with an error status, and never pass.

</details>
