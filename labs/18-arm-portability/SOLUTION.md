# Lab 18 solution

## What was wrong

```bash
for f in /opt/fixtures/*; do echo "== $f"; ROOT=$f /opt/checks/cpu-inventory; echo "exit $?"; done
diff <(grep -m1 -A20 '^processor' /opt/fixtures/x86-server/proc/cpuinfo | cut -d: -f1 | sort -u) \
     <(grep -m1 -A20 '^processor' /opt/fixtures/arm-ampere/proc/cpuinfo | cut -d: -f1 | sort -u)
```

aarch64 `/proc/cpuinfo` has no `vendor_id`, `model name` or `flags`. It has `CPU implementer` (who designed the
core, as a code), `CPU part` (which core), and `Features`. So on ARM the check printed `vendor=` and `model=`
empty, `avx2=no` (as if it were an old x86 CPU), and `mce=ok` (because a missing directory fell through to "ok").
That last one is the dangerous bug: **a check that can't see its telemetry must fail, not pass**. ARM has no MCE at
all; its hardware errors arrive through ACPI APEI/GHES as CPER records, announced by the firmware's HEST table.

## Fixed script

```bash
#!/bin/bash
# cpu-inventory: CPU vendor, model, count, AVX2 support and hardware-error reporting, as key=value lines.
# ROOT points at a fake file system (fixtures); unset, it reads this machine.
ROOT=${ROOT:-}
CPUINFO=$ROOT/proc/cpuinfo
[ -r "$CPUINFO" ] || { echo "cpu-inventory: cannot read $CPUINFO" >&2; exit 2; }
field() { grep -m1 "^$1[[:space:]]*:" "$CPUINFO" | cut -d: -f2- | sed 's/^[[:space:]]*//'; }
rc=0
echo "cpus=$(grep -c '^processor' "$CPUINFO")"

if grep -q '^CPU implementer' "$CPUINFO"; then          # aarch64
  impl=$(field 'CPU implementer')
  case $impl in
    0x41) vendor=ARM ;;       0x42) vendor=Broadcom ;;  0x43) vendor=Cavium ;;   0x46) vendor=Fujitsu ;;
    0x48) vendor=HiSilicon ;; 0x4e) vendor=NVIDIA ;;    0x50) vendor=APM ;;      0x51) vendor=Qualcomm ;;
    0xc0) vendor=Ampere ;;    *) vendor="unknown($impl)" ;;
  esac
  echo "vendor=$vendor"
  echo "model=$(field 'CPU part')"
  echo "avx2=not_applicable"
  echo "mce=not_applicable"
  if [ -e "$ROOT/sys/firmware/acpi/tables/HEST" ]; then echo "ras=ghes"; else echo "ras=missing"; rc=2; fi
else                                                    # x86
  echo "vendor=$(field vendor_id)"
  echo "model=$(field 'model name')"
  if field flags | grep -qw avx2; then echo "avx2=yes"; else echo "avx2=no"; fi
  if [ -d "$ROOT/sys/devices/system/machinecheck" ]; then echo "mce=ok"; else echo "mce=missing"; rc=2; fi
fi
exit $rc
```

(Moving `cpus=` to the top is fine: the order of `key=value` lines shouldn't matter to whatever reads them. If
it does in your codebase, keep the original order.)

## Lessons for porting checks

- Decide per check: works unchanged, needs an ARM-specific source, or **doesn't apply** (and says
  `not_applicable` so nobody mistakes it for a pass).
- Never infer the platform from a missing file: detect it positively, then require the files that platform must have.
- Real ARM servers vary: `dmidecode` fields can be sparse, EDAC drivers are SoC-specific or absent, and `lscpu`
  translates implementer/part codes to names (`Neoverse-N1` for 0x41/0xd0c).
