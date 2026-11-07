#!/bin/bash
set -e
. /opt/labkit/lib/vm.sh
need_disks
for d in $DISK1 $DISK2 $DISK3; do wipe_disk "$d"; done
sed -i '/# lab06/d' /etc/fstab
save_vars DISK1=$DISK1 DISK2=$DISK2 DISK3=$DISK3
echo "Using disks: DISK1=$DISK1 DISK2=$DISK2 DISK3=$DISK3"

# DISK3: an "old" VG holding archive data, and an obsolete VG to be removed
parted -s "$DISK3" mklabel gpt mkpart old 1MiB 1025MiB mkpart temp 1025MiB 1537MiB set 1 lvm on set 2 lvm on
partx -u "$DISK3" 2>/dev/null || true; udevadm settle; P1=$(part "$DISK3" 1); P2=$(part "$DISK3" 2)
pvcreate -y -q "$P1" "$P2"
vgcreate -q vgold "$P1"; vgcreate -q vgtemp "$P2"
lvcreate -q -y -n lvarchive -L 500M vgold; lvcreate -q -y -n lvscratch -L 200M vgtemp
mkfs.xfs -q -f /dev/vgold/lvarchive
mkdir -p /srv/archive && mount /dev/vgold/lvarchive /srv/archive
echo "Archived records. If you can read this after a reboot, task 4 is fixed." > /srv/archive/README
umount /srv/archive
# BROKEN: fstab entry with a UUID that doesn't exist
echo "UUID=$(cat /proc/sys/kernel/random/uuid) /srv/archive xfs defaults,nofail 0 0  # lab06" >> /etc/fstab
systemctl daemon-reload
