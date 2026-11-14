#!/bin/bash
# Fake root file systems for cpu-inventory: mkroot DIR x86|arm CPUS [IMPLEMENTER PART] [nomce|noghes]
mkroot() {
  local d=$1 arch=$2 n=$3 impl=${4:-0xc0} part=${5:-0xac3} opt=${6:-} i
  rm -rf "$d"; mkdir -p "$d/proc" "$d/sys/devices/system/cpu" "$d/sys/firmware/acpi/tables"
  for ((i = 0; i < n; i++)); do
    if [ "$arch" = x86 ]; then cat <<C
processor	: $i
vendor_id	: GenuineIntel
cpu family	: 6
model		: 143
model name	: Intel(R) Xeon(R) Gold 6430
stepping	: 8
microcode	: 0x2b000590
cpu MHz		: 2100.000
cache size	: 61440 KB
physical id	: $((i * 2 / n))
siblings	: $n
core id		: $i
cpu cores	: $n
flags		: fpu vme de pse tsc msr pae mce cx8 apic sep mtrr pge mca cmov pat pse36 clflush dts acpi mmx fxsr sse sse2 ss ht tm pbe syscall nx pdpe1gb rdtscp lm constant_tsc art arch_perfmon pebs bts rep_good nopl xtopology nonstop_tsc cpuid aperfmperf tsc_known_freq pni pclmulqdq dtes64 monitor ds_cpl vmx smx est tm2 ssse3 sdbg fma cx16 xtpr pdcm pcid dca sse4_1 sse4_2 x2apic movbe popcnt tsc_deadline_timer aes xsave avx f16c rdrand lahf_lm abm 3dnowprefetch cpuid_fault epb cat_l3 cat_l2 cdp_l3 invpcid_single cdp_l2 ssbd mba ibrs ibpb stibp ibrs_enhanced tpr_shadow flexpriority ept vpid ept_ad fsgsbase tsc_adjust bmi1 avx2 smep bmi2 erms invpcid cqm rdt_a avx512f avx512dq rdseed adx smap avx512ifma clflushopt clwb intel_pt avx512cd sha_ni avx512bw avx512vl xsaveopt xsavec xgetbv1 xsaves
bogomips	: 4200.00
address sizes	: 46 bits physical, 57 bits virtual

C
    else cat <<C
processor	: $i
BogoMIPS	: 50.00
Features	: fp asimd evtstrm aes pmull sha1 sha2 crc32 atomics fphp asimdhp cpuid asimdrdm jscvt fcma lrcpc dcpop sha3 sm3 sm4 asimddp sha512 asimdfhm dit uscat ilrcpc flagm ssbs sb paca pacg dcpodp flagm2 frint
CPU implementer	: $impl
CPU architecture: 8
CPU variant	: 0x1
CPU part	: $part
CPU revision	: 1

C
    fi
  done > "$d/proc/cpuinfo"
  if [ "$arch" = x86 ]; then
    [ "$opt" = nomce ] || { mkdir -p "$d/sys/devices/system/machinecheck/machinecheck0"; echo 0 > "$d/sys/devices/system/machinecheck/machinecheck0/check_interval"; }
  else
    [ "$opt" = noghes ] || printf 'HEST' > "$d/sys/firmware/acpi/tables/HEST"
  fi
}
