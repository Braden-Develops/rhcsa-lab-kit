#!/bin/bash
# Lab 18: a CPU inventory check written for x86 servers is about to run on ARM servers. Fixture file systems
# (fake /proc and /sys from real x86 and aarch64 machines) let you test it without ARM hardware.
set -e
. "$LABDIR/fixtures.sh"
mkdir -p /opt/checks /opt/fixtures
mkroot /opt/fixtures/x86-server x86 8
mkroot /opt/fixtures/x86-nomce x86 4 "" "" nomce
mkroot /opt/fixtures/arm-ampere arm 16 0xc0 0xac3
mkroot /opt/fixtures/arm-neoverse arm 8 0x41 0xd0c
mkroot /opt/fixtures/arm-noghes arm 4 0x41 0xd40 noghes
cat > /opt/checks/cpu-inventory <<'S'
#!/bin/bash
# cpu-inventory: CPU vendor, model, count, AVX2 support and machine-check health, as key=value lines.
# ROOT points at a fake file system (fixtures); unset, it reads this machine.
ROOT=${ROOT:-}
CPUINFO=$ROOT/proc/cpuinfo

vendor=$(grep -m1 '^vendor_id' $CPUINFO | cut -d: -f2 | sed 's/^ //')
model=$(grep -m1 '^model name' $CPUINFO | cut -d: -f2 | sed 's/^ //')
cpus=$(grep -c '^processor' $CPUINFO)
echo "vendor=$vendor"
echo "model=$model"
echo "cpus=$cpus"
if grep -m1 '^flags' $CPUINFO | grep -qw avx2; then echo "avx2=yes"; else echo "avx2=no"; fi

# machine checks: the kernel exposes machinecheck devices when MCE is set up
if [ -d $ROOT/sys/devices/system/machinecheck ]; then
  echo "mce=ok"
else
  echo "mce=ok"      # nothing to check
fi
exit 0
S
chmod +x /opt/checks/cpu-inventory
echo "Lab 18 ready."
