This module is about **finding bad hardware with Linux**: how servers report their own faults, which counters
mean something, how to stress a machine so marginal parts show themselves, and how to turn all of that into
checks that catch a bad part before it ships, without failing good ones. It goes beyond the RHCSA and lines up with
the hardware and diagnostics parts of Red Hat's RH342 (diagnostics and troubleshooting) and RH442 (performance).

**How it's organised.** Eight lectures, one per subsystem, each followed by a **break-fix lab**: the lab breaks
a machine (or hands you evidence from a broken one) and you work out what is wrong, fix what can be fixed, and
write the check that would have caught it.

| | Lecture | Lab |
|---|---|---|
| H1 | Method: how hardware faults reach you, and what makes a good check | all of them |
| H2 | Memory: ECC, EDAC, rasdaemon, finding the DIMM | 12, VM |
| H3 | Storage: SMART, NVMe health, media vs. link errors, md RAID, fio | 13, VM |
| H4 | CPU: topology, frequency and throttling, machine checks, silent corruption | 14, VM |
| H5 | PCIe: link training, LnkCap vs. LnkSta, AER | 15, VM |
| H6 | Thermal, power and the BMC: IPMI, SEL, Redfish | 16, container |
| H7 | JBODs and enclosures: SAS topology, PHY counters, SES, fan-out testing | 17, VM |
| H8 | ARM servers: what changes when there's no x86 | 18, container |

**What the labs can and can't fake.** A virtual machine has no DIMMs, fans or PCIe lanes to break, so each lab says
exactly what it simulates. Where the kernel offers a real mechanism, the labs use it: device-mapper *error* and
*delay* targets produce genuine I/O errors and latency, md RAID really fails a member, systemd, cgroups, tuned and
kernel arguments are all real. Where nothing real exists, the lab produces the **evidence** in the exact form you'd
see it on a server: lines written into the kernel log through `/dev/kmsg`, records in rasdaemon's database,
a small Redfish service standing in for a BMC, and `lspci`, `smartctl`, `ipmitool` and sysfs captures. The skill
being practised, reading that evidence and acting on it, is the same.

Answers go in `/root/answers.txt` as `key=value` lines; the grader stores the expected answers hashed, and most
labs randomise the fault each time you reset them, so you can redo a lab without remembering the answer.

**Run them** exactly like the RHCSA labs: `./lab start 12`, `./lab shell 12`, `./lab check 12`, or from the lab
host panel on each lab page. VM labs install the extra packages they need (rasdaemon, fio, mdadm, smartmontools,
pciutils, stress-ng and so on) on first start; to save that time on every reset, refresh the VM's clean snapshot
once: `cd vm && vagrant up && vagrant provision --provision-with packages && vagrant snapshot save clean`.
