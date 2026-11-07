# Lab 06: Configure local storage

Disks for this lab: **DISK1 = {{DISK1}}**, **DISK2 = {{DISK2}}**, **DISK3 = {{DISK3}}**. Don't touch the system disk.
Mount everything persistently; test with `mount -a` / `swapon -a` and `findmnt --verify` **before** you reboot.

1. **Partitions.** Give {{DISK1}} a **GPT** label and create:
   - partition 1: **512 MiB**, used as **swap**, enabled at boot **by UUID** (keep any existing swap too)
   - partition 2: **2 GiB**, type Linux LVM
2. **PVs and VG.** Make partition 2 of {{DISK1}} and the whole of {{DISK2}} physical volumes, and create volume
   group **`vgdata`** from both with a **physical extent size of 8 MiB**.
3. **LVs.**
   - `lvweb`: **600 MiB**, **XFS**, mounted on `/srv/web`, in fstab **by UUID**
   - `lvdocs`: exactly **50 extents**, **ext4** with file system label **`DOCS`**, mounted on `/srv/docs`, in fstab **by LABEL**
   - `lvswap`: **256 MiB** swap space, active at boot (added without disturbing anything else)
4. *Broken:* `/srv/archive` (LV `vgold/lvarchive`) is never mounted after boot. Fix it. Its data must survive.
5. **Remove** the obsolete volume group `vgtemp` completely: its LV, the VG, the PV label, and finally delete
   partition 2 of {{DISK3}}. `vgold` must keep working.
6. **Grow a VG.** Add a third partition of **500 MiB** to {{DISK1}} (non-destructively: partitions 1 and 2 stay
   intact) and **assign** it to the existing volume group `vgold`.
7. Reboot and run `sudo labctl check` again.
