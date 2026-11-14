# Lab 13 solution  (DISK1={{DISK1}} DISK2={{DISK2}} DISK3={{DISK3}})

## 1. Find it

```bash
cat /proc/mdstat                      # [U_] = one half missing; (F) marks the faulty member
mdadm --detail /dev/md/data           # "faulty  /dev/dm-0"
journalctl -k | grep -E 'md/raid1|I/O error|dm-'
# md/raid1:md127: Disk failure on dm-0, disabling device.
# md/raid1:md127: Operation continuing on 1 devices.
# I/O error, dev dm-0, sector 6291456 op 0x1:(WRITE) ...
dmsetup ls                            # jbod-bay2 (253:0)
dmsetup deps -o devname jbod-bay2     # (vdc)  <- the physical disk
lsblk -s /dev/mapper/jbod-bay2        # the same, as a tree
dmsetup table jbod-bay2               # the "error" segment is the simulated bad band
```

`failed_disk={{DISK2}}`. The kernel saw **write** errors on a band of sectors. md RAID 1 kicks a member out when a
write to it fails, because the two halves would otherwise differ.

## 2. Replace it

```bash
mdadm /dev/md/data --fail /dev/mapper/jbod-bay2 2>/dev/null   # already failed; harmless
mdadm /dev/md/data --remove failed                            # or --remove /dev/dm-0
dmsetup remove jbod-bay2                                      # "pull" the drive
mdadm /dev/md/data --add {{DISK3}}
watch cat /proc/mdstat                                        # wait for recovery to reach 100%
mdadm --wait /dev/md/data
mdadm --detail --scan > /etc/mdadm.conf                       # ARRAY /dev/md/data metadata=1.2 UUID=...
cd /srv/data && sha256sum -c MANIFEST.sha256
```

With an `/etc/mdadm.conf` the array always assembles under its name. Without it, assembly falls back to whatever
udev and the metadata suggest, which is how arrays come back as `/dev/md127` with the wrong name after a rebuild.

## 3. SMART triage

- **Cable:** `199 UDMA_CRC_Error_Count` is high and climbing (it was much lower 24 hours ago) while
  `5 Reallocated_Sector_Ct`, `197 Current_Pending_Sector` and `198 Offline_Uncorrectable` are all 0. CRC errors
  are counted when a frame is corrupted *on the wire* between the controller and the drive: the media is fine. Reseat
  or replace the cable or backplane slot. RMAing the drive puts a new drive on the same bad link.
- **Replace:** the SATA drive with **reallocated, pending and offline-uncorrectable sectors** (the media is
  failing), and the **NVMe drive** with `critical_warning: 0x1`: bit 0 means *available spare has dropped below
  its threshold* (7% < 10%). It has used up its spare blocks, and the next failing block can't be remapped.
- **Not a problem:** the drive with huge `Raw_Read_Error_Rate` and `Seek_Error_Rate` raw values. On Seagate drives
  those raw numbers pack an operation count with an error count; the normalised `VALUE` (well above `THRESH`) is
  what matters. Every report says `PASSED`, including the failing drives: the overall verdict trips only when a
  normalised value crosses its threshold, which is usually far too late.

## 4. fio verify

```ini
; /root/verify.fio
[global]
directory=/srv/data
direct=1
ioengine=libaio
bs=64k
iodepth=16

[mirror-verify]
rw=randwrite
size=256m
verify=crc32c
do_verify=1
verify_fatal=1
```

```bash
fio /root/verify.fio | tee /root/fio-verify.log
grep 'err=' /root/fio-verify.log      # err= 0
rm -f /srv/data/mirror-verify.*       # tidy up the test file
```

fio writes each block with a checksum header, then reads everything back and checks it. `direct=1` bypasses the
page cache, so the reads really go to the disks rather than being served from RAM.
