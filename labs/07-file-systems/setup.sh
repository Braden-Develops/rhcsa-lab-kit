#!/bin/bash
set -e
. /opt/labkit/lib/vm.sh
need_disks
for d in $DISK1 $DISK2; do wipe_disk "$d"; done
sed -i '/# lab07/d' /etc/fstab
save_vars DISK1=$DISK1 DISK2=$DISK2
echo "Using disks: DISK1=$DISK1 DISK2=$DISK2"

# Two LVs that are running out of space
pvcreate -y -q "$DISK2"; vgcreate -q vgfs "$DISK2"
lvcreate -q -y -n lvgrow -L 300M vgfs; mkfs.xfs -q -f /dev/vgfs/lvgrow
lvcreate -q -y -n lvext -L 200M vgfs;  mkfs.ext4 -q -F /dev/vgfs/lvext
mkdir -p /srv/grow /srv/ext
echo "/dev/vgfs/lvgrow /srv/grow xfs defaults 0 0  # lab07" >> /etc/fstab
echo "/dev/vgfs/lvext /srv/ext ext4 defaults 0 0  # lab07" >> /etc/fstab
systemctl daemon-reload; mount -a
dd if=/dev/zero of=/srv/grow/fill bs=1M count=200 status=none
dd if=/dev/zero of=/srv/ext/fill bs=1M count=150 status=none

# An NFS server on this same machine, reachable as nfs.lab.example.com
grep -q nfs.lab.example.com /etc/hosts || echo "127.0.0.1 nfs.lab.example.com nfs" >> /etc/hosts
mkdir -p /exports/projects /exports/homes/alice /exports/homes/bob
echo "project plan v1" > /exports/projects/plan.txt
for u in alice bob carol; do id $u &>/dev/null || useradd $u; echo "$u:password" | chpasswd; done
echo "alice's remote home" > /exports/homes/alice/welcome.txt
echo "bob's remote home" > /exports/homes/bob/welcome.txt
chown alice: /exports/homes/alice -R; chown bob: /exports/homes/bob -R
chmod 1777 /exports/projects
cat > /etc/exports.d/lab07.exports <<'X'
/exports/projects *(rw,sync)
/exports/homes    *(rw,sync)
X
systemctl enable --now nfs-server >/dev/null 2>&1
exportfs -ra
systemctl disable --now autofs >/dev/null 2>&1 || true

# Obsolete mounts to retire: a local ext4 LV (kept busy by a process) and an old NFS share
lvcreate -q -y -n lvold -L 100M vgfs; mkfs.ext4 -q -F /dev/vgfs/lvold
mkdir -p /mnt/old /mnt/legacy /exports/legacy
echo "legacy data" > /exports/legacy/old.txt
echo "/exports/legacy   *(ro,sync)" >> /etc/exports.d/lab07.exports
exportfs -ra
echo "/dev/vgfs/lvold /mnt/old ext4 defaults 0 0  # lab07" >> /etc/fstab
echo "nfs.lab.example.com:/exports/legacy /mnt/legacy nfs defaults,_netdev 0 0  # lab07" >> /etc/fstab
systemctl daemon-reload; mount -a
systemd-run --unit=lab-oldreader -p WorkingDirectory=/mnt/old /usr/bin/sleep infinity >/dev/null

# BROKEN permissions on a team directory
groupadd -f team
usermod -aG team alice; usermod -aG team bob
mkdir -p /srv/team
chown root:root /srv/team; chmod 755 /srv/team
echo "Q4 goals" > /srv/team/plan.txt
chown root:team /srv/team/plan.txt; chmod 664 /srv/team/plan.txt
setfacl -m u:bob:r /srv/team/plan.txt
