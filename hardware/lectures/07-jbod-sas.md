# Lecture H7: JBODs and enclosures: SAS topology, PHY counters, SES and fan-out testing

A JBOD ("just a bunch of disks") is a box of drives with no server inside: drives, backplanes, one or two **SAS
expanders**, power supplies and fans, connected to a server's HBA by external SAS cables. Storage servers often
have several. They multiply every storage problem from lecture H3, and add a new one: **shared components**. One
bad cable or expander port affects many drives at once, and treating each drive's errors separately leads to RMAing
good drives and keeping the bad cable.

This lecture covers SAS topology, wide ports and multipath, how to read SAS PHY counters, SCSI Enclosure
Services (slots, LEDs, fans and PSUs inside the enclosure), how to correlate errors, and fan-out stress testing.

Practice: [Lab 17](#/lab/17).

---

## SAS topology

```text
 server ─ HBA ─ port A ══(4-lane SAS cable)══ expander 0 ─┬─ PHY 4 ── slot 0 (drive)
               │                                          ├─ PHY 5 ── slot 1
               │                                          ├─ ...
               │                                          └─ SES device (the enclosure's own management target)
               └ port B ══(4-lane SAS cable)══ expander 1 ─── slots ... (or the drives' second ports, see below)
```

- A **PHY** is one physical lane: a transmitter/receiver pair. Every connection in SAS is made of PHYs.
- A **wide port** groups several PHYs to the same destination: an external mini-SAS HD cable carries **4 lanes**,
  so an HBA-to-expander link is a 4-wide port (4 × 12 Gb/s = 48 Gb/s for SAS-3). Each drive connects to the
  expander with one PHY (a narrow port).
- An **expander** is a switch: it connects its uplink PHYs to many drive PHYs. Large JBODs cascade expanders.
- Every SAS device and port has a **SAS address** (a WWN like `0x5000c500...`).

### Dual path and multipath

SAS drives have **two ports**. In a dual-path JBOD, each drive connects to **both** expanders (usually through two
IO modules), and the server reaches each expander through a separate cable and HBA port. Linux then sees **every
drive twice** (`sdb` and `sdz` are the same disk), and **device-mapper multipath** combines them:

```bash
multipath -ll                      # each disk: its WWID, and both paths with their state (active/ready, failed/faulty)
lsscsi -t                          # transport addresses: which SAS address each sd device came through
```

Losing one cable or expander then costs bandwidth, not data access. A conformance check confirms every drive has
**both** paths, because a single-path drive in a dual-path design is a hidden single point of failure.

SATA drives in a SAS JBOD have one port (sometimes made dual-path by an *interposer* board).

---

## Linux's view of SAS

```bash
lsscsi -g                          # [H:C:T:L], type (disk, enclosu), model, /dev/sdX, /dev/sgN
ls /sys/class/sas_host/ /sys/class/sas_expander/ /sys/class/sas_phy/ /sys/class/sas_port/
cat /sys/class/sas_phy/phy-1:0:5/{sas_address,negotiated_linkrate,maximum_linkrate}
smp_discover /dev/bsg/expander-1:0          # smp_utils: list every PHY of an expander and what's attached
```

`/sys/class/sas_phy/` holds one directory per PHY (HBA PHYs and expander PHYs), named after the host, expander
and PHY number. Each has:

| File | Meaning |
|---|---|
| `negotiated_linkrate` | the speed this PHY trained to: `12.0 Gbit`, `6.0 Gbit`, `3.0 Gbit`, or a state such as `Phy disabled` |
| `maximum_linkrate`, `minimum_linkrate` | the limits |
| `invalid_dword_count` | received dwords (32-bit words) that failed decoding: corrupted symbols on the wire |
| `running_disparity_error_count` | encoding (DC balance) errors: corrupted signal |
| `loss_of_dword_sync_count` | the receiver lost synchronisation with the stream |
| `phy_reset_problem_count` | the PHY failed to complete a reset (link bring-up problems) |

The first four counters are **link** health, the SAS equivalent of SATA's CRC count. Media errors (bad sectors) don't
show up here at all; they're in the drive's own SMART and in SCSI sense data (lecture H3).

Like every counter, these accumulate from power-on (or since last cleared, `echo 1 > reset_counter` on some
drivers). **Use deltas**: snapshot before a test, snapshot after, and judge the difference. Old large values that
don't move are history (a cable reseated last year), not a current fault.

### Link rate

A drive PHY at `6.0 Gbit` where its neighbours run at `12.0 Gbit` has trained down: a marginal connector, a drive
or interposer that only supports 6G, or a backplane problem. Like a downgraded PCIe link, it works and nothing
reports an error.

---

## Correlate before you blame a drive

The central idea of this lecture: **when errors appear, group them by what the affected components share.**

| Pattern | Likely cause |
|---|---|
| All 4 PHYs of one HBA-to-expander port take errors at the same time | the **cable** (or the HBA port or expander connector at either end) |
| Every drive behind one expander shows timeouts/resets, drives behind the other expander are fine | that expander, its cable, or its IO module |
| One drive PHY with errors and resets, neighbours clean | that drive's link: the drive, its slot connector, the backplane trace. Reseat; if errors follow the drive to another slot, it's the drive |
| One drive with media errors (reallocated/pending sectors, Medium Error sense) | the drive |
| Errors only on drives in a physical region (one row, one side) | backplane section, or temperature (check SES temperatures and fans) |

A field study of storage systems found that interconnect problems (cables, backplanes, HBAs, enclosures)
account for a large share of storage subsystem failures, comparable to disks themselves
(Jiang et al., *Are Disks the Dominant Contributor for Storage Failures?*, 2008). If a check RMAs drives
one at a time, it will replace eight good drives and keep the bad cable.

---

## SCSI Enclosure Services (SES)

The enclosure itself appears as a SCSI device of type *enclosure* (`lsscsi` shows `enclosu`). Through **SES** you
can read the state of everything in the box and control its LEDs:

```bash
sg_ses /dev/sg5                            # supported diagnostic pages
sg_ses --page=cf /dev/sg5                  # configuration: element types (Array device slot, Power supply, Cooling, Temperature sensor, ...)
sg_ses --page=es /dev/sg5                  # enclosure status: every element's status (OK, Critical, Not installed ...)
sg_ses --page=aes /dev/sg5                 # additional element status: which SAS address is in which slot
sg_ses --join /dev/sg5                     # all of that joined, per element: the most useful view
sg_ses --index=7 --set=ident /dev/sg5      # blink slot 7's locate LED (--clear=ident to stop)
sg_ses --index=7 --set=fault /dev/sg5      # light its fault LED
ls /sys/class/enclosure/*/                 # the kernel's view: one directory per slot, with "device" links and LED controls
```

What SES gives you:

- **Slot mapping:** which drive (by SAS address) sits in which numbered slot. Combined with `lsscsi -t` and
  `/dev/disk/by-path`, that turns `sdq` into "enclosure jb-04, slot 7". Always blink the LED before anyone pulls a
  drive.
- **Enclosure health:** status of the enclosure's own PSUs, fans, temperature sensors, and voltage sensors. These
  belong in the check **during stress**, like the server's own (lecture H6).
- **Population:** a slot that should hold a drive and reports *Not installed* while a drive is physically there is a
  seating or backplane problem, not a missing part.

The `/sys/class/enclosure/` tree (from the kernel's `ses` driver) gives the same slot-to-device mapping without
sg3_utils and is handy in scripts.

---

## Fan-out stress testing

Single-drive tests load one drive at a time. A **fan-out** test drives every drive in the enclosure **at the same
time**, which loads what they share:

- the HBA and its PCIe link,
- the expanders and the cables (all four lanes busy),
- the enclosure's power supplies (every drive seeking) and cooling.

A fio job file with one job per drive, no `stonewall` between them, `direct=1`, and time-based runs. Read-only
(`randread`, `read`) on drives with data; write and verify on drives that are being commissioned.

Judge the result in four ways:

1. **fio's own errors:** any job with a non-zero `error` (EIO from a drive) fails.
2. **Peer comparison:** each drive's IOPS, bandwidth and p99 latency against the **median** of drives of the
   same model in the same enclosure. A drive at 30% of its peers is suspect even with no errors (it may be
   retrying internally, or on a degraded link).
3. **Counter deltas:** SAS PHY counters, SMART, kernel log (timeouts, resets) before vs. after. Correlate by
   expander and cable.
4. **Enclosure health during the run:** SES and BMC fans, PSUs and temperatures.

Then name each finding by **enclosure and slot**, not by `sdX`, so a technician can act on it.

### Throughput expectations

Know the bottlenecks to tell a fault from a limit: 24 HDDs at ~250 MB/s each want 6 GB/s, which a single 4-lane
SAS-3 link (~4.4 GB/s usable) can't carry. In a fan-out test, all drives behind a saturated link will be slower
than their standalone numbers, **equally**. Uniform slowness is the topology; one drive slower than its peers is a
fault.

---

## Quick reference

| Task | Command |
|---|---|
| Devices with SCSI addresses | `lsscsi -g`, `lsscsi -t` |
| PHYs | `/sys/class/sas_phy/*/{negotiated_linkrate,invalid_dword_count,running_disparity_error_count,loss_of_dword_sync_count,phy_reset_problem_count}` |
| Expander PHYs | `smp_discover /dev/bsg/expander-H:N` |
| Multipath | `multipath -ll` |
| Enclosure status | `sg_ses --join /dev/sgN`, `/sys/class/enclosure/` |
| Locate LED | `sg_ses --index=SLOT --set=ident /dev/sgN` |
| Fan-out load | fio job file, one job per drive, `--output-format=json` |

Reading: Jiang et al., *Are Disks the Dominant Contributor for Storage Failures?* (FAST 2008); the sg3_utils
`sg_ses` manual; kernel `Documentation/scsi/libsas.rst`; T10 SES drafts (element types).

---

## Review questions

1. What is a wide port, and how many PHYs does an external mini-SAS HD cable carry?
2. All four uplink PHYs of expander 1 gained thousands of invalid dwords during a test; the drives behind it show
   timeouts. What do you replace?
3. One drive PHY shows 900 invalid dwords both before and after a stress run. Problem?
4. How do you find out which slot holds `/dev/sdq`, and make sure the technician pulls the right drive?
5. Why does a fan-out test find faults that single-drive tests miss?
6. In a fan-out run, all 12 drives behind one expander are 20% slower than their standalone results, equally. Fault?
7. A dual-path JBOD: `multipath -ll` shows one disk with only one path. Why does that matter if the disk works?

<details><summary>Answers</summary>

1. Several PHYs grouped into one logical link to the same destination; an external mini-SAS HD cable carries 4.
2. The cable to expander 1 (or reseat it first, and check the HBA port and expander connector): four lanes failing
   together means the thing they share. The drives are victims.
3. No: the count didn't change during the test. It's history; only the delta matters.
4. SES: `sg_ses --join` (or `/sys/class/enclosure/*/`) maps SAS addresses or devices to slots; then blink the slot's
   locate LED with `sg_ses --index=N --set=ident`.
5. It loads the shared parts (HBA, expanders, cables, enclosure power and cooling) at the same time, which is when
   marginal shared components fail.
6. Probably not: equal slowdown across all drives behind one link is the link's bandwidth limit. A fault shows as one
   drive slower than its peers.
7. The design's redundancy is gone for that disk: one cable or expander failure will make it disappear. It's a
   latent single point of failure (cabling, IO module or the drive's second port).

</details>
