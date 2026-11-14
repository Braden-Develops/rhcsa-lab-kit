# Lecture H8: ARM servers: what changes when there's no x86

ARM (aarch64) servers are now common in data centres, built on SoCs from several vendors. Most of Linux looks
the same on them: the same distributions, the same tools, the same `/proc` and `/sys`. But a lot of
**hardware-checking code quietly assumes x86**, and the places it breaks are exactly the places that matter: CPU
identification, error reporting and inventory. The worst failure mode is a check that finds nothing to read on ARM
and reports **pass**.

This lecture covers how ARM servers are standardised, how to identify ARM CPUs, how they report hardware errors
(no MCE: APEI, GHES and CPER instead), what's different about memory errors, inventory and stress, and how to audit
x86 checks for ARM.

Practice: [Lab 18](#/lab/18).

---

## Standards: what makes an ARM machine a "server"

x86 servers are similar because they all descend from the PC. ARM had no such history, so Arm and the industry wrote
standards:

- **SBSA / BSA** (Server Base System Architecture, Base System Architecture): hardware requirements: interrupt
  controller (GIC), timers, PCIe behaviour, a standard UART, and so on.
- **SBBR / BBR** (Base Boot Requirements): firmware requirements: **UEFI** and **ACPI**, the same firmware
  interfaces x86 servers use.
- Arm's **SystemReady** certification checks both.

The result: a SystemReady ARM server boots RHEL with UEFI, describes its hardware with **ACPI** tables (not the
device tree used by embedded ARM boards), and has SMBIOS tables for `dmidecode`. That's why the same OS image can
work on both architectures.

---

## Identifying the CPU

`/proc/cpuinfo` looks completely different:

```text
processor	: 0
BogoMIPS	: 50.00
Features	: fp asimd evtstrm aes pmull sha1 sha2 crc32 atomics fphp asimdhp cpuid asimdrdm lrcpc dcpop asimddp ssbs
CPU implementer	: 0x41
CPU architecture: 8
CPU variant	: 0x3
CPU part	: 0xd0c
CPU revision	: 1
```

There is **no `vendor_id`, no `model name`, no `flags`**. Instead:

- **CPU implementer**: who designed the core, as a code from the `MIDR_EL1` register. Common values: `0x41` Arm
  Ltd, `0x42` Broadcom, `0x43` Cavium, `0x46` Fujitsu, `0x48` HiSilicon, `0x4e` NVIDIA, `0x50` APM, `0x51`
  Qualcomm, `0xc0` Ampere.
- **CPU part**: which core, defined by the implementer. For Arm Ltd: `0xd0c` Neoverse N1, `0xd40` Neoverse V1,
  `0xd49` Neoverse N2, `0xd4f` Neoverse V2. Ampere's own cores use implementer `0xc0` with their own part numbers.
- **Features**: the instruction set extensions, the ARM equivalent of x86 `flags` (`asimd` is NEON, `sve` the
  scalable vector extension, `atomics` the LSE atomics).

```bash
lscpu                      # translates implementer/part into names ("Vendor ID: ARM", "Model name: Neoverse-N1")
cat /sys/devices/system/cpu/cpu0/regs/identification/midr_el1     # the raw ID register
dmidecode -t processor     # the SoC's marketing name, if firmware fills it in
```

Topology differs too: many ARM server CPUs have high core counts and **no SMT** (one thread per core), so
"threads per core: 2" assumptions break. Caches and NUMA layouts vary by SoC.

---

## Error reporting: no MCE

This is the biggest difference. ARM has **no Machine Check Architecture**: no MCE banks, no `mce:` kernel
messages, no `/sys/devices/system/machinecheck/`, no `mcelog`. Errors reach the OS in one of two ways.

### Firmware first: APEI, GHES and CPER

Most ARM servers (and many x86 ones) handle hardware errors **in firmware first**:

1. The hardware signals an error to firmware (on ARM, at the secure monitor / trusted firmware level).
2. Firmware collects the details and writes a **CPER** record (UEFI *Common Platform Error Record*: a standard
   binary format with sections for processor, memory, PCIe and vendor-specific errors) into a memory buffer.
3. Firmware notifies the OS through **ACPI APEI** (ACPI Platform Error Interfaces), specifically a **GHES**
   (Generic Hardware Error Source) described in the **HEST** (Hardware Error Source Table).
4. The kernel's GHES driver reads the record, logs it, and passes memory and PCIe errors on to the EDAC and AER
   code (via `ghes_edac` and the AER handler).

```bash
ls /sys/firmware/acpi/tables/ | grep -E 'HEST|BERT|EINJ|ERST'     # HEST = error sources exist
journalctl -k | grep -iE 'ghes|hest|apei|cper|hardware error'
# {1}[Hardware Error]: Hardware error from APEI Generic Hardware Error Source: 2
# {1}[Hardware Error]: event severity: corrected
# {1}[Hardware Error]:  section_type: memory error
# {1}[Hardware Error]:   node: 0 card: 3 module: 0 rank: 1 bank: 2 ...
ras-mc-ctl --errors        # rasdaemon records ARM/GHES events (arm_event, non_standard_event tables) and memory errors
```

Related tables: **BERT** (Boot Error Record Table) holds errors from **before** this boot (the error that crashed
the last boot is often only here); **ERST** is persistent error storage; **EINJ** lets you **inject** errors for
testing (`/sys/kernel/debug/apei/einj/`, if firmware enables it): useful to prove a check really sees errors.

### The Arm RAS extension

Newer cores (Armv8.2 and later) have an architectural **RAS extension**: error records in the CPU, broadly similar
in spirit to MCA banks. Whether the OS reads them directly ("kernel first") or firmware handles them depends on the
platform. In practice, on current servers, plan on **GHES/CPER** as the main path, and check what each platform
actually delivers.

### Memory errors on ARM

EDAC drivers are **SoC-specific** (or absent); with firmware first, memory errors usually arrive through GHES and
`ghes_edac`, which exposes a generic EDAC view with whatever labels firmware provides. Labels may be less precise
than on x86 (a "card/module" number, a SMBIOS handle). Map them to slots with `dmidecode -t 17` and the vendor's
documentation, once per platform.

---

## Inventory and firmware

- `dmidecode` works, but SMBIOS fields are only as complete as the firmware: some are empty, some vendor-defined.
  Don't assume a field exists because it does on x86.
- `/sys/firmware/acpi/tables/` lists the ACPI tables (`acpidump` and `iasl -d` decode them).
- BMCs on ARM servers are usually the same kind as on x86 (often OpenBMC), so IPMI and Redfish checks
  (lecture H6) carry over well.
- PCIe, NVMe, SAS and SMART tooling is identical.

---

## Stress on ARM

- `stress-ng` and `stressapptest` build and run on aarch64 unchanged.
- x86-specific tools don't apply: Prime95/`mprime` and Intel Linpack binaries are x86 only. Use a BLAS-based HPL
  built for aarch64, or `stress-ng --cpu 0 --cpu-method matrixprod` (or other methods) for heat and power.
- `turbostat` and MSR-based tools are x86 only. Use `perf stat` (ARM PMU events), cpufreq sysfs, and hwmon/BMC
  sensors; SoC vendors often provide their own telemetry tools.
- Silent data corruption testing (lecture H4) matters just as much: run self-checking computations per core.

---

## Auditing an x86 check for ARM

For every check, decide one of three outcomes and make the code say so:

1. **Works unchanged.** fio, SMART, NVMe, PCIe link checks, Redfish/IPMI, most inventory.
2. **Needs an ARM-specific source.** CPU identification (implementer/part instead of vendor_id/model name), hardware
   error telemetry (GHES/CPER and rasdaemon's ARM tables instead of MCE), memory error labels.
3. **Doesn't apply.** MCE, MWAIT/C-state instructions, AVX/AVX-512 feature checks, MSR reads, turbostat. These must
   report **not applicable**, explicitly, never "pass" and never "fail".

Patterns to search for in the code:

| x86 assumption | Symptom on ARM |
|---|---|
| parsing `vendor_id`, `model name`, `flags` from `/proc/cpuinfo` | empty values, or "no AVX2" treated as an old CPU |
| `/sys/devices/system/machinecheck`, `mcelog`, `/dev/mcelog` | missing, and often silently skipped |
| reading MSRs (`/dev/cpu/*/msr`, `rdmsr`) | no such device |
| x86-only instructions or binaries (MWAIT, CPUID, mprime, Linpack) | errors, or skipped |
| `threads per core == 2` | wrong core counts |
| hard-coded EDAC driver names (`skx_edac`) | "driver not loaded" or wrong labels |
| `uname -m` checks that only know `x86_64` | falls into a default branch |

And the rule from lecture H1 matters most here: **a missing telemetry source is never a pass.** Detect the platform
**positively** (cpuinfo has `CPU implementer` → ARM), then require what **that** platform must have (HEST for GHES
error reporting), and fail with "cannot check" when it's missing.

---

## Quick reference

| Task | Command |
|---|---|
| CPU identity | `lscpu`; `grep -m1 -E 'CPU (implementer\|part)' /proc/cpuinfo` |
| Error sources | `ls /sys/firmware/acpi/tables/{HEST,BERT,EINJ}` |
| Error messages | `journalctl -k \| grep -iE 'ghes\|apei\|hardware error'` |
| RAS records | `ras-mc-ctl --errors` |
| Error injection (test) | `/sys/kernel/debug/apei/einj/` (if firmware enables EINJ) |
| Stress | `stress-ng --cpu 0 --cpu-method matrixprod --verify -t 10m`, `stressapptest` |

Reading: Arm BSA/SBSA and BBR specifications and SystemReady (Arm Developer site); UEFI specification, appendix N
(Common Platform Error Record); ACPI specification, APEI chapter; kernel `Documentation/arch/arm64/` and
`Documentation/firmware-guide/acpi/apei/`; the Arm RAS architecture supplement.

---

## Review questions

1. Which `/proc/cpuinfo` fields identify an ARM CPU, and what replaces x86 `flags`?
2. How does a hardware error reach Linux on a typical ARM server?
3. Where do you look for the error that crashed the *previous* boot on an APEI platform?
4. A memory check on ARM finds `/sys/devices/system/edac/mc/` empty. Pass?
5. Should a check print `mce=ok`, `mce=fail` or something else on ARM?
6. Name two x86 stress or telemetry tools that don't exist on ARM, and an alternative for each.
7. How should a check decide it's running on ARM, and why not just "no MCE directory means ARM"?

<details><summary>Answers</summary>

1. `CPU implementer` and `CPU part` (plus variant and revision); `Features` replaces `flags`.
2. Firmware first: firmware writes a CPER record and notifies the OS through an ACPI APEI GHES source (listed in
   HEST); the kernel's GHES driver logs and dispatches it; rasdaemon records it.
3. The BERT (Boot Error Record Table), reported by the kernel at boot and visible in `/sys/firmware/acpi/tables/`.
4. No: memory errors may come through GHES (`ghes_edac`) or the platform may lack EDAC support. If the check can't see
   memory error telemetry from any source, it reports "cannot check", never pass.
5. `mce=not_applicable` (and report the ARM error source, GHES, separately).
6. `mprime`/Linpack (x86 binaries): use `stress-ng --cpu-method matrixprod` or an aarch64 HPL build. `turbostat`/MSRs:
   use `perf stat`, cpufreq sysfs and BMC/hwmon sensors.
7. Positively, from the CPU's identity (`CPU implementer` in cpuinfo, or `uname -m` = `aarch64`). Treating a missing
   directory as "ARM" would also classify a broken x86 machine as ARM and hide the fault.

</details>
