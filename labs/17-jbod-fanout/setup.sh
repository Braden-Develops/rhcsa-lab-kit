#!/bin/bash
# Lab 17: an 8-slot "enclosure" built from device-mapper devices on DISK1. One slot is slow (dm-delay adds
# latency, like a drive with a weak head or a degraded link), one has a band of unreadable sectors (dm error target).
# Plus SAS PHY counters from a real-layout JBOD to correlate.
set -e
. /opt/labkit/lib/vm.sh
. /opt/labkit/lib/hw.sh
need_pkgs fio jq sg3_utils lsscsi
need_disks
truth_reset
for s in 0 1 2 3 4 5 6 7; do dmsetup remove encl0-slot$s 2>/dev/null || true; done
wipe_disk "$DISK1"
save_vars DISK1=$DISK1
SLOW=$((RANDOM % 8)); while :; do BAD=$((RANDOM % 8)); [ $BAD -ne $SLOW ] && break; done
truth slow_slot "$SLOW" "slot$SLOW" "encl0-slot$SLOW"
truth bad_slot "$BAD" "slot$BAD" "encl0-slot$BAD"
SZ=$((512 * 2048))          # 512 MiB per slot, in 512-byte sectors
modprobe dm-delay 2>/dev/null && DELAY=yes || DELAY=no
for s in 0 1 2 3 4 5 6 7; do
  off=$((s * SZ))
  if [ $s -eq $SLOW ] && [ $DELAY = yes ]; then
    echo "0 $SZ delay $DISK1 $off 25" | dmsetup create encl0-slot$s
  elif [ $s -eq $BAD ]; then
    b=$((SZ / 2 + (RANDOM % 1000) * 64)); l=4096
    dmsetup create encl0-slot$s <<T
0 $b linear $DISK1 $off
$b $l error
$((b + l)) $((SZ - b - l)) linear $DISK1 $((off + b + l))
T
  else
    echo "0 $SZ linear $DISK1 $off" | dmsetup create encl0-slot$s
  fi
done
udevadm settle
if [ $DELAY = no ]; then
  # no dm-delay module: throttle the slot with the block I/O controller instead (works for every login session)
  echo "dm-delay unavailable; throttling slot $SLOW with cgroup io limits"
  for sl in user.slice system.slice; do
    systemctl set-property --runtime $sl "IOReadBandwidthMax=/dev/mapper/encl0-slot$SLOW 4M" \
      "IOWriteBandwidthMax=/dev/mapper/encl0-slot$SLOW 4M" "IOReadIOPSMax=/dev/mapper/encl0-slot$SLOW 40"
  done
fi
# --- SAS evidence ---
CABLE=$((RANDOM % 2)); ES=$((RANDOM % 8)); while :; do LS=$((RANDOM % 8)); [ $LS -ne $ES ] && break; done
truth cable_expander "$CABLE" "expander-$CABLE" "expander$CABLE"
truth phy_err_slot "$ES" "slot$ES"
truth slow_link_slot "$LS" "slot$LS"
rm -rf /root/evidence/jbod; mkdir -p /root/evidence/jbod
python3 "$LABDIR/sasgen.py" /root/evidence/jbod $CABLE $ES $LS
answers_template slow_slot bad_slot cable_expander phy_err_slot slow_link_slot
echo "Lab 17 ready: slots are /dev/mapper/encl0-slot0 .. encl0-slot7"
