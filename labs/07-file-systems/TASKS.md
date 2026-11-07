# Lab 07: Create and configure file systems

Disks: **DISK1 = {{DISK1}}** (empty), **DISK2 = {{DISK2}}** (holds VG `vgfs`). All mounts must persist across reboots.

1. **Three file systems.** On {{DISK1}} (GPT) create three 300 MiB partitions and put:
   **VFAT** on the first, mounted on `/mnt/vfat`; **ext4** on the second on `/mnt/ext4`; **XFS** on the third on
   `/mnt/xfs`. All three in `/etc/fstab` **by UUID**.
2. **Extend logical volumes** (without unmounting or losing data):
   - `vgfs/lvgrow` (XFS on `/srv/grow`) to **800 MiB**, and the file system with it
   - `vgfs/lvext` (ext4 on `/srv/ext`) to **400 MiB**, and the file system with it
3. **NFS.** Mount the export `nfs.lab.example.com:/exports/projects` on `/mnt/projects`, persistently.
4. **autofs.** Configure autofs so that any user's home on the NFS server, `nfs.lab.example.com:/exports/homes/<user>`,
   appears automatically as `/remote/homes/<user>` (read-write) when accessed. autofs must start at boot.
5. *Broken:* `/srv/team` is the shared directory for group `team` (alice and bob).
   - alice and bob must be able to create files in it; other users (e.g. `carol`) must have **no** access
   - new files created there must automatically belong to group `team`
   - bob says he can't edit `/srv/team/plan.txt` even though he's in `team`. Fix that too.
6. **Unmount and retire.** `/mnt/old` (LV `vgfs/lvold`) and the NFS share on `/mnt/legacy` are obsolete.
   Unmount both (something is keeping `/mnt/old` busy: find it and stop it), make sure they are **not** mounted
   again at boot, and delete the logical volume `vgfs/lvold`.
