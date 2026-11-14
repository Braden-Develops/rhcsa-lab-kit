# Lab 18: Break-fix: an x86-only check meets an ARM server

**Ticket:** *"We're onboarding aarch64 servers. `/opt/checks/cpu-inventory` passes on them, but its output is
half empty and it claims machine checks are fine on a platform that doesn't have them. Fix it before it ships to
the factory."*

Run the check against a fake file system by setting `ROOT`, for example
`ROOT=/opt/fixtures/arm-ampere /opt/checks/cpu-inventory`. The fixtures in `/opt/fixtures/` are copies of `/proc`
and `/sys` from x86 and ARM servers. Decide the architecture **from the cpuinfo file**, not from `uname`, so the
fixtures work.

Fix **`/opt/checks/cpu-inventory`** so that it prints `key=value` lines and:

1. **x86 keeps working**: `vendor=` from `vendor_id`, `model=` from `model name`, `cpus=`, `avx2=yes|no`.
2. **x86 machine checks:** `mce=ok` if `/sys/devices/system/machinecheck` exists; if it doesn't, print
   `mce=missing` and **exit 2**. (Today it prints `ok` either way. Why is that the worst possible bug for a
   hardware check?)
3. **aarch64** (cpuinfo has `CPU implementer` lines):
   - `vendor=` the implementer's name: at least `0x41` = `ARM` and `0xc0` = `Ampere`; any other code prints
     `unknown(<code>)`, for example `unknown(0x99)`
   - `model=` the `CPU part` value, for example `0xd0c`
   - `cpus=` the number of CPUs
   - `avx2=not_applicable` and `mce=not_applicable`: those are x86 features, so "no" or "ok" would both be wrong
   - `ras=ghes` if the firmware provides the ACPI **HEST** table (`/sys/firmware/acpi/tables/HEST`), which is how
     ARM servers report hardware errors; otherwise `ras=missing` and **exit 2**
4. If the cpuinfo file is missing or unreadable, **exit 2**. Never print an empty value.
5. Otherwise exit 0.
