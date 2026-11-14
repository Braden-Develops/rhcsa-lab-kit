#!/bin/bash
# Lab 13: a mirrored data volume loses a disk to real I/O errors, plus SMART reports from four drives to triage.
# The failing disk is DISK2 seen through a device-mapper table with an "error" segment: every read or write that
# touches that 16 MiB region fails inside the kernel, exactly like unreadable sectors on a dying drive.
set -e
. /opt/labkit/lib/vm.sh
. /opt/labkit/lib/hw.sh
need_pkgs mdadm smartmontools nvme-cli fio xfsprogs
need_disks
truth_reset
mdadm --stop --scan 2>/dev/null || true
dmsetup remove jbod-bay2 2>/dev/null || true
for d in $DISK1 $DISK2 $DISK3; do mdadm --zero-superblock --force "$d" 2>/dev/null || true; wipe_disk "$d"; done
sed -i '/\/srv\/data/d' /etc/fstab
rm -f /etc/mdadm.conf
save_vars DISK1=$DISK1 DISK2=$DISK2 DISK3=$DISK3
truth failed_disk "$DISK2" "${DISK2#/dev/}"

# --- the bad drive: DISK2 with a band of unreadable/unwritable sectors at 60% of its LBA range ---
SZ=$(blockdev --getsz "$DISK2"); BS=$((SZ * 3 / 5)); BL=32768
dmsetup create jbod-bay2 <<T
0 $BS linear $DISK2 0
$BS $BL error
$((BS + BL)) $((SZ - BS - BL)) linear $DISK2 $((BS + BL))
T
udevadm settle

# --- a RAID 1 data volume across bay 1 (DISK1) and bay 2 ---
yes | mdadm --create /dev/md/data --level=1 --raid-devices=2 --metadata=1.2 --assume-clean --run --name=data \
  "$DISK1" /dev/mapper/jbod-bay2
udevadm settle
# the nightly scrub writes the whole array; the bad band makes md kick bay 2 out
dd if=/dev/zero of=/dev/md/data bs=4M oflag=direct status=none 2>/dev/null || true
sleep 2
# md's bad-block log can absorb a few bad sectors and keep the member. Real drives in this state usually stop
# answering soon after, so make the drive drop off the bus: every sector now fails, and md fails the member.
if ! mdadm --detail /dev/md/data | grep -q faulty; then
  dmsetup suspend jbod-bay2
  echo "0 $SZ error" | dmsetup load jbod-bay2
  dmsetup resume jbod-bay2
  dd if=/dev/zero of=/dev/md/data bs=1M count=64 oflag=direct,sync status=none 2>/dev/null || true
  mdadm --detail /dev/md/data | grep -q faulty || mdadm /dev/md/data --fail /dev/mapper/jbod-bay2
fi
mkfs.xfs -q -f -L data /dev/md/data
mkdir -p /srv/data && mount /dev/md/data /srv/data
mkdir -p /srv/data/records
for i in $(seq 1 8); do head -c $((4 * 1048576)) /dev/urandom > /srv/data/records/batch$i.bin; done
(cd /srv/data && sha256sum records/*.bin > MANIFEST.sha256)
echo "UUID=$(blkid -s UUID -o value /dev/md/data) /srv/data xfs defaults,nofail 0 0" >> /etc/fstab
systemctl daemon-reload
# BROKEN on purpose: no /etc/mdadm.conf, so nothing records what the array should look like

# --- SMART triage: four drives from another server, one report each ---
mkdir -p /root/evidence/smart
ser() { printf '%s%06X' "$1" $(( (RANDOM << 8 | RANDOM) & 0xFFFFFF )); }
SC=$(ser ZA1); SM=$(ser ZA1); SH=$(ser ZA1); SN=$(ser S6EUNA0)
truth cable "$SC"
truth replace "$SM,$SN"
hours=$((8000 + RANDOM % 9000))
sata() { # serial realloc pending offline crc rawread seek
cat <<R
smartctl 7.4 2023-08-01 r5530 [x86_64-linux-6.12.0-55.el10.x86_64] (local build)
Copyright (C) 2002-23, Bruce Allen, Christian Franke, www.smartmontools.org

=== START OF INFORMATION SECTION ===
Model Family:     Seagate Exos 7E10
Device Model:     ST8000NM017B-2TJ103
Serial Number:    $1
Firmware Version: SN05
User Capacity:    8,001,563,222,016 bytes [8.00 TB]
Sector Sizes:     512 bytes logical, 4096 bytes physical
Rotation Rate:    7200 rpm
SATA Version is:  SATA 3.3, 6.0 Gb/s (current: 6.0 Gb/s)
SMART support is: Available - device has SMART capability.

=== START OF READ SMART DATA SECTION ===
SMART overall-health self-assessment test result: PASSED

SMART Attributes Data Structure revision number: 10
Vendor Specific SMART Attributes with Thresholds:
ID# ATTRIBUTE_NAME          FLAGS    VALUE WORST THRESH FAIL RAW_VALUE
  1 Raw_Read_Error_Rate     POSR--   0$((70 + RANDOM % 15))   064   044    -    $6
  3 Spin_Up_Time            PO----   091   091   000    -    0
  4 Start_Stop_Count        -O--CK   100   100   020    -    $((20 + RANDOM % 30))
  5 Reallocated_Sector_Ct   PO--CK   $( [ $2 -gt 0 ] && echo 093 || echo 100)   $( [ $2 -gt 0 ] && echo 093 || echo 100)   010    -    $2
  7 Seek_Error_Rate         POSR--   0$((80 + RANDOM % 9))   060   045    -    $7
  9 Power_On_Hours          -O--CK   0$((90 - hours / 1000))   0$((90 - hours / 1000))   000    -    $hours
 10 Spin_Retry_Count        PO--C-   100   100   097    -    0
 12 Power_Cycle_Count       -O--CK   100   100   020    -    $((20 + RANDOM % 30))
187 Reported_Uncorrect      -O--CK   $( [ $4 -gt 0 ] && echo 076 || echo 100)   $( [ $4 -gt 0 ] && echo 076 || echo 100)   000    -    $4
188 Command_Timeout         -O--CK   100   100   000    -    0
190 Airflow_Temperature_Cel -O---K   065   048   040    -    35 (Min/Max 27/41)
194 Temperature_Celsius     -O---K   035   052   000    -    35 (0 21 0 0 0)
197 Current_Pending_Sector  -O--C-   100   100   000    -    $3
198 Offline_Uncorrectable   ----C-   100   100   000    -    $4
199 UDMA_CRC_Error_Count    -OSRCK   200   200   000    -    $5
                            ||||||_ K auto-keep
                            |||||__ C event count
                            ||||___ R error rate
                            |||____ S speed/performance
                            ||_____ O updated online
                            |______ P prefailure warning
R
}
CRC=$((900 + RANDOM % 1500)); PEND=$((8 + RANDOM % 40))
sata "$SC" 0 0 0 "$CRC" $((RANDOM * 5000)) $((RANDOM * 9000)) > /tmp/c.txt
printf '\n# Same drive, previous report 24 hours earlier: 199 UDMA_CRC_Error_Count raw value was %d\n' $((CRC / 9)) >> /tmp/c.txt
sata "$SM" $((200 + RANDOM % 300)) "$PEND" "$PEND" 0 $((RANDOM * 7000)) $((RANDOM * 8000)) > /tmp/m.txt
sata "$SH" 0 0 0 0 $((RANDOM * 9000 + 120000000)) $((RANDOM * 30000 + 900000000)) > /tmp/h.txt
cat > /tmp/n.txt <<R
# nvme smart-log /dev/nvme0n1
# nvme id-ctrl /dev/nvme0n1 | grep -E '^(mn|sn|fr) ': mn = SAMSUNG MZQL23T8HCLS-00A07, sn = $SN, fr = GDC5602Q
Smart Log for NVME device:nvme0n1 namespace-id:ffffffff
critical_warning			: 0x1
temperature				: 41 °C (314 K)
available_spare				: 7%
available_spare_threshold		: 10%
percentage_used				: 38%
endurance group critical warning summary: 0
Data Units Read				: 1,804,113,927 (923.71 TB)
Data Units Written			: 2,203,550,316 (1.13 PB)
host_read_commands			: 9,330,551,904
host_write_commands			: 14,980,221,630
controller_busy_time			: 31,092
power_cycles				: 61
power_on_hours				: $hours
unsafe_shutdowns			: 19
media_errors				: 0
num_err_log_entries			: 3
Warning Temperature Time		: 0
Critical Composite Temperature Time	: 0
R
order=(c m h n); for i in 0 1 2 3; do j=$((RANDOM % 4)); x=${order[i]}; order[i]=${order[j]}; order[j]=$x; done
for i in 0 1 2 3; do mv /tmp/${order[i]}.txt /root/evidence/smart/bay$((i + 1)).txt; done
cat > /root/evidence/smart/README.txt <<'R'
SMART reports from the four data drives of storage server stor-117, collected by the nightly health job.
A tech wants to know which drives to RMA and whether anything else needs fixing.
R
answers_template failed_disk cable replace
echo "Lab 13 ready."
