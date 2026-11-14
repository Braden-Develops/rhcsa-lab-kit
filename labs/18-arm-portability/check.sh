#!/bin/bash
. /opt/labkit/lib/check.sh
. "$LABDIR/fixtures.sh"
t=$(mktemp -d); trap 'rm -rf $t' EXIT
CI=/opt/checks/cpu-inventory
run() { ROOT=$t/$1 $CI 2>/dev/null; }
mkroot $t/x86 x86 6; mkroot $t/x86nomce x86 2 "" "" nomce
mkroot $t/armA arm 12 0x41 0xd40; mkroot $t/armQ arm 4 0xc0 0xac4; mkroot $t/armG arm 4 0x41 0xd0c noghes
mkroot $t/armU arm 2 0x99 0x123

section "x86 behaviour is unchanged where it was right"
check "x86: vendor, model, cpus, avx2" 'o=$(run x86); echo "$o" | grep -qx vendor=GenuineIntel && echo "$o" | grep -qx "model=Intel(R) Xeon(R) Gold 6430" && echo "$o" | grep -qx cpus=6 && echo "$o" | grep -qx avx2=yes'
check "x86 with machine checks: mce=ok, exit 0" 'o=$(run x86); [ $? -eq 0 ] && echo "$o" | grep -qx mce=ok'
check "x86 without machinecheck in sysfs: mce=missing, exit 2" 'o=$(run x86nomce); [ $? -eq 2 ] && echo "$o" | grep -qx mce=missing'

section "aarch64"
check "ARM implementer 0x41: vendor=ARM" 'run armA | grep -qx vendor=ARM'
check "Ampere implementer 0xc0: vendor=Ampere" 'run armQ | grep -qx vendor=Ampere'
check "unknown implementer: vendor=unknown(0x99), not empty" 'run armU | grep -qx "vendor=unknown(0x99)"'
check "model = the CPU part number" 'run armA | grep -qx model=0xd40 && run armQ | grep -qx model=0xac4'
check "cpus counted" 'run armA | grep -qx cpus=12'
check "avx2=not_applicable (it is an x86 instruction set)" 'run armA | grep -qx avx2=not_applicable'
check "mce=not_applicable" 'run armA | grep -qx mce=not_applicable'
check "with a HEST table: ras=ghes, exit 0" 'o=$(run armA); [ $? -eq 0 ] && echo "$o" | grep -qx ras=ghes'
check "without a HEST table: ras=missing, exit 2" 'o=$(run armG); [ $? -eq 2 ] && echo "$o" | grep -qx ras=missing'
check "no empty values anywhere" '! { run x86; run armA; run armQ; run armG; } | grep -q "=$"'

section "Robustness"
check "missing cpuinfo: exit 2" 'mkdir -p $t/empty; ROOT=$t/empty $CI >/dev/null 2>&1; [ $? -eq 2 ]'
check "the real machine still works (exit 0 or 2, prints cpus=)" 'o=$($CI 2>/dev/null); rc=$?; { [ $rc -eq 0 ] || [ $rc -eq 2 ]; } && echo "$o" | grep -q "^cpus=[1-9]"'
check "script has valid bash syntax" 'bash -n $CI'
summary
