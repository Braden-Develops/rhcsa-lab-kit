# Lecture H3: Storage: SMART, NVMe health, media vs. link errors, RAID and fio

Drives are the component servers replace most often, and storage is where the most money is wasted on wrong
diagnoses: good drives RMA'd because a cable was bad, bad drives kept because SMART said `PASSED`. This lecture
covers the storage stack from the drive to the kernel, the two very different kinds of error (media and link),
how to read SMART and NVMe health data, how Linux reports I/O errors, how a RAID mirror fails and recovers, and how
to stress storage with fio.

Practice: [Lab 13](#/lab/13) (a failing mirror member and SMART triage) and [Lab 17](#/lab/17) (many drives at once).

---

## The storage stack

```text
 application ── file system (XFS, ext4) ── md RAID / LVM / device-mapper ── block layer ── driver
   ── SATA/SAS: SCSI layer (sd) ── libata or SAS HBA driver (mpt3sas, mpi3mr, megaraid_sas)
         ── HBA ── [cable] ── expander / backplane ── [connector] ── drive
   ── NVMe: nvme driver ── PCIe link ── drive
```

| Interface | Typical drive | Path | Linux name |
|---|---|---|---|
| **SATA** | HDDs, cheaper SSDs | AHCI controller or HBA → (backplane) → drive, one link per drive | `/dev/sdX`, messages from `ataN` |
| **SAS** | enterprise HDDs/SSDs | HBA → expander(s) → drive; dual-ported for two paths | `/dev/sdX`, SCSI messages `sd H:C:T:L` |
| **NVMe** | SSDs | directly on PCIe (sometimes through a PCIe switch) | `/dev/nvme0n1` (controller 0, namespace 1) |

Names like `sdc` are assigned in discovery order and can change between boots. Use stable names for anything
that matters:

```bash
ls -l /dev/disk/by-id/      # model + serial number: identifies the physical drive
ls -l /dev/disk/by-path/    # controller + port/PHY: identifies the physical location
lsblk -o NAME,MODEL,SERIAL,SIZE,TRAN,HCTL
lsscsi -g                   # SCSI address [H:C:T:L], type, model, /dev/sdX, /dev/sgN
nvme list
```

**HCTL** (host:channel:target:LUN) is the SCSI address; the *host* is the HBA. A diagnosis should end with a
serial number (which part to replace) **and** a location (where it is), and by-id plus by-path give you both.

---

## Two kinds of error: media and link

This distinction drives most storage diagnoses.

**Media errors** mean the drive can't read or write its own storage: a bad sector on a platter, a worn-out flash
block. The drive's firmware tries hard (retries, error correction), then remaps the sector to a spare if it can.
Symptoms: reallocated sectors, pending sectors, uncorrectable reads, NVMe `media_errors`, slow I/O while the drive
retries internally.

**Link (transport) errors** mean data was damaged **between** the controller and the drive: a bad cable, a dirty
or damaged connector, a marginal backplane, a failing HBA or expander port. The protocol detects it with a CRC and
retries. Symptoms: SATA `UDMA_CRC_Error_Count`, SAS PHY counters (invalid dwords, disparity errors), link resets,
and kernel messages about interface CRC errors and bus resets.

| | Media | Link |
|---|---|---|
| SATA SMART | 5 Reallocated_Sector_Ct, 197 Current_Pending_Sector, 198 Offline_Uncorrectable, 187 Reported_Uncorrect | **199 UDMA_CRC_Error_Count** |
| SAS | grown defect list, uncorrected errors in the error counter log | PHY counters: invalid dword, running disparity, loss of sync, PHY reset |
| NVMe | `media_errors`, `critical_warning` bits | AER errors on the PCIe link (lecture H5) |
| Kernel log | `Medium Error`, `Unrecovered read error`, `I/O error, dev sdX, sector N` | `ICRC ABRT`, `interface CRC error`, `hard resetting link`, `SError: { ... }` |
| Fix | replace the drive | reseat or replace the **cable, backplane slot or port**; the drive is fine |

The classic mistake: a drive logs errors, the drive is replaced, the new drive logs the same errors because it
sits on the same bad cable. When CRC errors climb while the media attributes stay at zero, the drive is the victim.
When several drives behind the same cable or expander all show link errors at once, it's certainly not the drives
(lecture H7).

---

## SMART

Every SATA and SAS drive keeps **SMART** (Self-Monitoring, Analysis and Reporting Technology) data;
`smartctl` from smartmontools reads it.

```bash
smartctl -i /dev/sda        # identity: model, serial, firmware, capacity, interface speed
smartctl -H /dev/sda        # the overall verdict (see below)
smartctl -A /dev/sda        # attributes
smartctl -x /dev/sda        # everything: attributes, logs, error log, self-test log, device statistics
smartctl -l error /dev/sda  # the drive's own log of the last errors it reported
smartctl -t long /dev/sda   # start an extended self-test (reads every sector); -l selftest shows results
```

### Reading the attribute table

```text
ID# ATTRIBUTE_NAME          FLAGS    VALUE WORST THRESH FAIL RAW_VALUE
  5 Reallocated_Sector_Ct   PO--CK   093   093   010    -    332
197 Current_Pending_Sector  -O--C-   100   100   000    -    27
199 UDMA_CRC_Error_Count    -OSRCK   200   200   000    -    1415
```

- **RAW_VALUE** is the drive's actual counter, in a vendor-defined format.
- **VALUE** is a *normalised* health score (often 100 or 200 when new, falling as things get worse); **WORST** is
  its lowest ever; **THRESH** is the vendor's failure threshold. The attribute "fails" only when VALUE drops to
  THRESH or below.
- **FLAGS** `P` means *pre-failure* (crossing the threshold predicts failure), `O` updated online.

Attributes worth watching, by raw value:

| ID | Name | Meaning |
|---|---|---|
| 5 | Reallocated_Sector_Ct | sectors remapped to spares: the media is wearing or damaged. Growth matters more than the count. |
| 197 | Current_Pending_Sector | sectors that failed to read and are waiting to be rewritten or remapped. Non-zero means unreadable data now. |
| 198 | Offline_Uncorrectable | sectors found unreadable by the drive's own scans |
| 187 | Reported_Uncorrect | errors the drive couldn't correct and reported to the host |
| 199 | UDMA_CRC_Error_Count | **link** errors between drive and controller |
| 9 | Power_On_Hours | age |
| 194 | Temperature_Celsius | current temperature (the raw value's first number) |

Two traps:

- **`PASSED` means very little.** `smartctl -H` fails only when a normalised value crosses its vendor threshold, and
  thresholds are set so that this happens late or never. A drive with hundreds of reallocated sectors and dozens of
  pending sectors routinely reports `PASSED`. The large Google study found that many failed drives had shown no
  SMART warning at all, but that drives with reallocations, pending sectors or scan errors were far more likely to
  fail soon (Pinheiro, Weber and Barroso, *Failure Trends in a Large Disk Drive Population*, 2007). Judge the raw
  values and their growth.
- **Some raw values look terrifying and are normal.** On Seagate drives, `Raw_Read_Error_Rate` and
  `Seek_Error_Rate` raw values pack an operation count together with an error count, so they're huge numbers on
  healthy drives. Judge those by the normalised VALUE.

SAS drives report differently (`smartctl -x` shows the *grown defect list*, read/write/verify error counter logs and
*non-medium errors*). The same media-vs-link logic applies.

---

## NVMe health

NVMe drives keep a standard health log:

```bash
nvme list
nvme smart-log /dev/nvme0        # or smartctl -x /dev/nvme0
nvme error-log /dev/nvme0        # recent errors the controller logged
nvme id-ctrl /dev/nvme0          # model (mn), serial (sn), firmware (fr), capabilities
```

```text
critical_warning        : 0x1
available_spare         : 7%
available_spare_threshold : 10%
percentage_used         : 38%
media_errors            : 0
num_err_log_entries     : 3
```

- **critical_warning** is a bit field: bit 0 *available spare below threshold*, bit 1 *temperature over limit*,
  bit 2 *reliability degraded* (internal errors), bit 3 *read-only mode*, bit 4 *volatile memory backup failed*.
  **Any bit set is a reason to act.**
- **available_spare** is the remaining pool of spare flash blocks. Below the threshold, the drive can no longer
  replace failing blocks.
- **percentage_used** estimates wear against rated endurance; it can exceed 100%. A drive near 100% is near its
  rated end of life, which is a planning issue rather than a fault.
- **media_errors** counts unrecovered data integrity errors: any non-zero value deserves attention.
- **num_err_log_entries** includes harmless entries (some drivers' probing causes "invalid field" errors). Read
  `error-log` before worrying about it.

Flash fails differently from disks: field data shows that flash errors correlate more with age and usage
patterns than with wear alone, and that uncorrectable errors are common even in young drives (Schroeder,
Lagisetty and Merchant, *Flash Reliability in Production*, 2016).

---

## How Linux reports I/O errors

Kernel messages tell you what happened at each layer. Examples, bottom to top:

```text
ata3.00: exception Emask 0x10 SAct 0x0 SErr 0x400000 action 0x6 frozen
ata3.00: irq_stat 0x08000000, interface fatal error
ata3: SError: { Handshk }
ata3.00: failed command: WRITE FPDMA QUEUED
ata3.00: status: { DRDY }  error: { ICRC ABRT }          <- interface CRC: a LINK problem
ata3: hard resetting link

sd 2:0:3:0: [sdd] tag#12 FAILED Result: hostbyte=DID_OK driverbyte=DRIVER_OK
sd 2:0:3:0: [sdd] tag#12 Sense Key : Medium Error [current]
sd 2:0:3:0: [sdd] tag#12 Add. Sense: Unrecovered read error        <- a MEDIA problem (ASC/ASCQ 11/00)
I/O error, dev sdd, sector 1953525160 op 0x0:(READ) flags 0x0 phys_seg 1 prio class 0

nvme nvme0: I/O 345 QID 7 timeout, aborting                        <- the drive stopped answering in time
nvme nvme0: Abort status: 0x0
nvme nvme0: controller is down; will reset

md/raid1:md127: Disk failure on sdd, disabling device.
md/raid1:md127: Operation continuing on 1 devices.
```

- **SCSI sense data** (key / ASC / ASCQ) is the drive explaining itself: *Medium Error* (key 3) is the media,
  *Hardware Error* (key 4) the drive's electronics, *Aborted Command* (key B) often the transport.
- **Timeouts and resets** mean a command didn't complete. A drive retrying a bad sector internally can take
  seconds per command; a link that drops causes resets. Either way, timeouts on one drive under load are a strong
  failure signal.
- The `I/O error, dev ... sector N` line gives the LBA, which you can test directly:
  `dd if=/dev/sdd of=/dev/null bs=512 skip=N count=1 iflag=direct`.

---

## RAID: how a mirror fails and recovers

Linux software RAID (`md`, managed with `mdadm`) is common on servers' boot and data volumes, and LVM can do RAID
too. In a mirror (RAID 1):

- **reads** can come from either half; if a read fails, md reads the other half and tries to **rewrite** the bad
  block on the failing member (which may make the drive remap the sector);
- **writes** go to both halves; if a write fails, md marks that member **faulty** (unless its bad-block log can
  record the bad blocks) and carries on **degraded**;
- a **faulty** member stays listed until you remove it.

```bash
cat /proc/mdstat                       # [UU] healthy, [U_] one half missing, (F) faulty, recovery progress
mdadm --detail /dev/md/data            # State: clean, degraded; member list with "faulty"
mdadm /dev/md/data --fail /dev/sdd     # mark a member failed (if the kernel hasn't)
mdadm /dev/md/data --remove /dev/sdd   # or --remove failed
mdadm /dev/md/data --add /dev/sde      # new member; resync starts
mdadm /dev/md/data --replace /dev/sdd --with /dev/sde   # copy to the new disk *before* removing the old one
mdadm --detail --scan > /etc/mdadm.conf
```

`--replace` is the safer way to swap a drive that still mostly works: the array never loses redundancy during the
copy. For checks, `echo check > /sys/block/mdX/md/sync_action` makes md read and compare both halves;
`/sys/block/mdX/md/mismatch_cnt` afterwards should be 0.

### Layers between the disk and the array

Arrays are often built on top of other block layers: device-mapper multipath (`/dev/mapper/mpatha`), LUKS
encryption, partitions. A failed member may be named `dm-3`. Walk down to the physical disk:

```bash
lsblk -s /dev/dm-3                 # inverse tree: what this device is built on
dmsetup ls; dmsetup deps -o devname NAME; dmsetup table NAME
```

---

## Stressing storage with fio

**fio** is the standard storage load generator. A job file describes the workload:

```ini
[global]
ioengine=libaio        ; asynchronous I/O (io_uring on newer kernels)
direct=1               ; bypass the page cache: measure the device, not RAM
bs=4k
iodepth=32             ; outstanding I/Os per job: drives need depth to reach their limits
time_based
runtime=300
group_reporting=0      ; keep each job's results separate

[sda]
filename=/dev/sda
rw=randread
```

The workload knobs: `rw` (read, write, randread, randwrite, randrw with `rwmixread=70`), `bs`, `iodepth`,
`numjobs`, `size`/`runtime`. Results to look at: bandwidth, IOPS and especially **latency percentiles**
(`clat` p99, p99.9). A drive that's retrying internally often shows normal average latency and terrible tail
latency.

### Verification

fio can write data with checksums and verify it on read:

```ini
[verify]
rw=randwrite
size=4g
verify=crc32c
do_verify=1
verify_fatal=1
```

That catches silent data corruption in the whole path (drive, controller, cable, memory), which an ordinary
throughput test can't. Only write-verify on disks whose data you can destroy, or on files.

### Using fio as a check

- **Read-only on disks with data.** Random and sequential reads with `direct=1` are safe; writes are not.
- **Compare drives with their peers.** Run the same job on every drive of the same model and flag the outliers
  (median-based, lecture H1). Absolute thresholds from a datasheet are optimistic and vary with firmware.
- **Read the health data before and after:** SMART/NVMe logs, kernel log, PHY counters. fio finishing is not the
  verdict.
- **Run drives in parallel** to load the controller, expanders, cables and power together (lecture H7).
- Output JSON (`--output-format=json`) for a program to read.

---

## Quick reference

| Task | Command |
|---|---|
| Inventory | `lsblk -o NAME,MODEL,SERIAL,SIZE,TRAN,HCTL`, `lsscsi -g`, `nvme list` |
| Health, SATA/SAS | `smartctl -x /dev/sdX` |
| Health, NVMe | `nvme smart-log /dev/nvme0`, `nvme error-log /dev/nvme0` |
| Self-test | `smartctl -t long /dev/sdX`, then `smartctl -l selftest /dev/sdX` |
| Kernel errors | `journalctl -k \| grep -Ei 'ata[0-9]\|sd [0-9]\|nvme\|I/O error\|md/'` |
| RAID status | `cat /proc/mdstat`, `mdadm --detail /dev/mdX` |
| Load | `fio jobfile --output-format=json --output=result.json` |

Reading: Pinheiro, Weber, Barroso, *Failure Trends in a Large Disk Drive Population* (FAST 2007); Schroeder and
Gibson, *Disk Failures in the Real World* (FAST 2007); Schroeder, Lagisetty, Merchant, *Flash Reliability in
Production* (FAST 2016); Backblaze's quarterly drive statistics; the fio documentation (`man fio`).

---

## Review questions

1. A SATA drive has `UDMA_CRC_Error_Count` rising, and zero reallocated and pending sectors. Replace the drive?
2. What does `SMART overall-health self-assessment test result: PASSED` actually tell you?
3. An NVMe drive shows `critical_warning: 0x1` and `media_errors: 0`. Healthy?
4. Why should a storage benchmark use `direct=1`?
5. md marks a member faulty after a **write** error but tries to repair after a **read** error. Why the
   difference?
6. A failed md member is named `dm-2`. How do you find the physical disk?
7. Why are latency percentiles more useful than average latency for finding a failing drive?

<details><summary>Answers</summary>

1. No: CRC errors are corruption on the link. Reseat or replace the cable or backplane slot, and watch whether the
   count keeps rising.
2. Only that no normalised attribute has crossed its vendor threshold, which often happens late or never. Judge
   the raw values of the media attributes and their growth.
3. No: bit 0 means available spare is below its threshold. The drive can't replace more failing blocks; replace it.
4. Without it, reads can be served from the page cache and writes absorbed by it, so you measure RAM.
5. After a failed write the two halves differ, and md can't trust that member; after a failed read it can read the
   good half and rewrite the bad block, which may let the drive remap it.
6. `lsblk -s /dev/dm-2` or `dmsetup deps -o devname` on its mapping (`dmsetup ls` lists the names).
7. A drive retrying internally makes a small fraction of I/Os very slow; the average hides them, p99 and p99.9 don't.

</details>
