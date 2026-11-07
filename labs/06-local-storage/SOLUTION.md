# Lab 06 solution  (DISK1={{DISK1}} DISK2={{DISK2}} DISK3={{DISK3}})

```bash
# 1  parted (scriptable) or interactively with gdisk / fdisk ("g" makes a GPT label in fdisk)
parted -s {{DISK1}} mklabel gpt
parted -s {{DISK1}} mkpart swap1 linux-swap 1MiB 513MiB
parted -s {{DISK1}} mkpart data 513MiB 2561MiB set 2 lvm on
udevadm settle; lsblk {{DISK1}}
mkswap {{DISK1}}1                       # nvme disks name partitions ...p1
echo "UUID=$(blkid -s UUID -o value {{DISK1}}1) none swap defaults 0 0" >> /etc/fstab
swapon -a && swapon --show
# 2
pvcreate {{DISK1}}2 {{DISK2}}
vgcreate -s 8M vgdata {{DISK1}}2 {{DISK2}}
# 3
lvcreate -n lvweb -L 600M vgdata
mkfs.xfs /dev/vgdata/lvweb
lvcreate -n lvdocs -l 50 vgdata          # -l = extents, -L = size
mkfs.ext4 -L DOCS /dev/vgdata/lvdocs     # or later: e2label /dev/vgdata/lvdocs DOCS  (xfs: xfs_admin -L)
mkdir -p /srv/web /srv/docs
echo "UUID=$(blkid -s UUID -o value /dev/vgdata/lvweb) /srv/web xfs defaults 0 0" >> /etc/fstab
echo "LABEL=DOCS /srv/docs ext4 defaults 0 0" >> /etc/fstab
lvcreate -n lvswap -L 256M vgdata
mkswap /dev/vgdata/lvswap
echo "/dev/vgdata/lvswap none swap defaults 0 0" >> /etc/fstab
systemctl daemon-reload; mount -a; swapon -a
# 4  the fstab UUID is wrong; nofail hid the failure at boot
blkid /dev/vgold/lvarchive
sed -i '/\/srv\/archive/d' /etc/fstab
echo "UUID=$(blkid -s UUID -o value /dev/vgold/lvarchive) /srv/archive xfs defaults 0 0" >> /etc/fstab
systemctl daemon-reload; mount -a; cat /srv/archive/README
# 5
lvremove -y vgtemp/lvscratch
vgremove vgtemp
pvremove {{DISK3}}2
parted -s {{DISK3}} rm 2
# 6  add a partition in the free space after partition 2, then vgextend
parted -s {{DISK1}} mkpart extra 2561MiB 3073MiB set 3 lvm on
udevadm settle
pvcreate {{DISK1}}3
vgextend vgold {{DISK1}}3          # (vgcreate assigns PVs to a new VG; vgextend to an existing one)
vgs vgold; pvs
# verify, then reboot
findmnt --verify
```

**Notes.** Always run `findmnt --verify` and `mount -a` before rebooting: a bad fstab line without `nofail` drops
the system into emergency mode (lab 05 shows you how to get out). `lsblk -f` and `blkid` show UUIDs and labels.
After editing fstab on RHEL 9/10, `systemctl daemon-reload` stops systemd from warning about a stale fstab.
"Non-destructively" means: add new partitions in free space, never re-create existing ones; add swap with
`mkswap` + fstab + `swapon -a` without touching existing swap.
