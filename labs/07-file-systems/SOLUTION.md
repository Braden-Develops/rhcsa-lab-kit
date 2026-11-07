# Lab 07 solution  (DISK1={{DISK1}} DISK2={{DISK2}})

```bash
# 1
parted -s {{DISK1}} mklabel gpt \
  mkpart fat fat32 1MiB 301MiB mkpart e4 ext4 301MiB 601MiB mkpart x xfs 601MiB 901MiB
udevadm settle
mkfs.vfat {{DISK1}}1; mkfs.ext4 {{DISK1}}2; mkfs.xfs {{DISK1}}3
mkdir -p /mnt/vfat /mnt/ext4 /mnt/xfs
for spec in "1 /mnt/vfat vfat" "2 /mnt/ext4 ext4" "3 /mnt/xfs xfs"; do
  set -- $spec
  echo "UUID=$(blkid -s UUID -o value {{DISK1}}$1) $2 $3 defaults 0 0" >> /etc/fstab
done
systemctl daemon-reload; mount -a
# 2  -r resizes the file system too (xfs_growfs / resize2fs under the hood)
lvextend -r -L 800M vgfs/lvgrow
lvextend -r -L 400M vgfs/lvext
# 3
showmount -e nfs.lab.example.com          # NFSv3 only; with v4-only servers just try mounting
mkdir -p /mnt/projects
echo "nfs.lab.example.com:/exports/projects /mnt/projects nfs defaults,_netdev 0 0" >> /etc/fstab
systemctl daemon-reload; mount -a
# 4
dnf -y install autofs nfs-utils
echo "/remote/homes /etc/auto.homes" > /etc/auto.master.d/homes.autofs
echo "* -rw,sync nfs.lab.example.com:/exports/homes/&" > /etc/auto.homes
systemctl enable --now autofs
ls /remote/homes/alice                    # triggers the mount
# 5
chgrp team /srv/team
chmod 2770 /srv/team                      # setgid: new files inherit group team; others get nothing
getfacl /srv/team/plan.txt                # an ACL entry user:bob:r-- overrides his group rights
setfacl -x u:bob /srv/team/plan.txt       # or: setfacl -m u:bob:rw ...
# 6
umount /mnt/old                           # "target is busy"
fuser -vm /mnt/old                        # or: lsof /mnt/old  -> a sleep process (unit lab-oldreader)
systemctl stop lab-oldreader              # (or kill the PID)
umount /mnt/old
umount /mnt/legacy
sed -i -E '/\s\/mnt\/(old|legacy)\s/d' /etc/fstab
systemctl daemon-reload
lvremove -y vgfs/lvold
```

**Notes.** XFS can only grow, never shrink; ext4 can shrink but only unmounted. `lvextend -r` handles both kinds.
In autofs maps `*` is the key wildcard and `&` substitutes it. Direct maps use `/-` in the master map and absolute
paths in the map file. When permissions look right but access fails, check in this order: the path's parent
directories (`namei -l /path`), ACLs (`getfacl`; a `+` at the end of `ls -l` modes means one exists), group
membership of the *current login* (`id`, re-login after `usermod`), then SELinux.
