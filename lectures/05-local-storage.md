# Lecture 5: Configure local storage

Storage tasks are worth a lot of marks and are the easiest place to break a system: a wrong partition number
destroys data, a typo in `/etc/fstab` stops the next boot. This lecture explains the layers between a raw disk
and a mounted directory: block devices, partition tables, LVM's physical volumes, volume groups and logical
volumes, the identifiers used to find file systems at boot, and swap. Lecture 6 continues with the file systems
themselves, network storage and growing volumes.

The layers, bottom to top:

```text
 /srv/web  (mount point: a directory in the tree)                   ← fstab, mount   (5.5, Lecture 6)
     │
 XFS / ext4 / vfat file system   or   swap                          ← mkfs, mkswap    (Lecture 6, 5.6)
     │
 logical volume  /dev/vgdata/lvweb                                  ← lvcreate        (5.4)
     │
 volume group  vgdata  (a pool of extents)                          ← vgcreate        (5.3)
     │
 physical volumes  /dev/vdb2, /dev/vdc                              ← pvcreate        (5.2)
     │
 partitions  /dev/vdb1, /dev/vdb2   (or a whole disk)               ← parted / gdisk  (5.1)
     │
 disks  /dev/vdb, /dev/vdc, /dev/nvme0n1                            (block devices)
```

Every layer is optional except the disk and the file system: you can put a file system straight on a partition,
or make a whole unpartitioned disk a physical volume. Real systems mix them, so you must be able to read any
combination.

---

## Background: block devices

### What the kernel shows you

A **block device** is storage accessed in fixed-size blocks at arbitrary positions: a disk, a partition, a logical
volume, a RAID array, a loop device backed by a file. Each appears as a file under `/dev`:

| Name | What it is |
|---|---|
| `/dev/sda`, `/dev/sdb` | SCSI/SATA/SAS/USB disks and many virtual disks (`sd` = SCSI disk); partitions `/dev/sda1`... |
| `/dev/vda`, `/dev/vdb` | virtio paravirtual disks in KVM VMs; partitions `/dev/vdb1`... |
| `/dev/nvme0n1` | NVMe controller 0, namespace 1; partitions add `p`: `/dev/nvme0n1p1` |
| `/dev/xvda` | Xen virtual disks (some cloud VMs) |
| `/dev/sr0` | optical drive |
| `/dev/dm-0`, `/dev/mapper/NAME` | device-mapper devices: LVM logical volumes, LUKS, multipath |
| `/dev/loop0` | loop device: a file presented as a disk |
| `/dev/zram0` | compressed RAM disk (sometimes used for swap) |

Names like `sdb` are assigned in the order the kernel discovers devices, which is **not guaranteed to be stable**
across boots or hardware changes. That is why fstab refers to file systems by UUID or label (5.5), and why udev
creates stable symlinks:

```bash
ls -l /dev/disk/by-id/        # hardware serial numbers / WWNs
ls -l /dev/disk/by-path/      # physical bus location
ls -l /dev/disk/by-uuid/      # file system UUIDs
ls -l /dev/disk/by-label/     # file system labels
ls -l /dev/disk/by-partuuid/  # GPT partition UUIDs
```

### Looking at what you have

```bash
lsblk                  # tree of disks, partitions, LVs, with sizes and mount points
lsblk -f               # add file system type, label, UUID, free space
lsblk -o NAME,SIZE,TYPE,FSTYPE,MOUNTPOINTS,UUID
blkid                  # every block device with a recognised signature, and its UUID/LABEL/TYPE
blkid /dev/vdb1
fdisk -l /dev/vdb      # partition table details
parted /dev/vdb print
cat /proc/partitions   # what the kernel currently knows
df -hT                 # mounted file systems, type and usage
findmnt                # mount tree with options
swapon --show          # active swap
```

**Before you touch any disk on the exam, run `lsblk` and identify the system disk** (the one holding `/`, `/boot`
and the LVM volume group the OS uses). The lab and exam disks are the empty ones. Getting this wrong is the one
mistake you cannot recover from.

---

## 5.1 List, create, and delete partitions on GPT disks

### Why partition at all

A **partition table** divides one disk into independent regions. You partition to: separate data with different
purposes or file systems, create a swap area, make an EFI System Partition, or give LVM a piece of a disk while
keeping the rest for something else. On the exam you will be told to create partitions of particular sizes and
types on a given disk.

### MBR and GPT

There are two partition-table formats:

| | MBR (msdos, "DOS") | GPT (GUID Partition Table) |
|---|---|---|
| Where | first 512-byte sector | sector 1 onward, **plus a backup copy at the end of the disk** |
| Max disk size | 2 TiB | 8 ZiB (effectively unlimited) |
| Partitions | 4 primary, or 3 + an extended partition holding "logical" partitions (5, 6...) | 128 by default, all equal |
| Partition type | a 1-byte code (`83` Linux, `82` swap, `8e` LVM) | a 128-bit type **GUID** |
| Identity | 32-bit disk signature | disk GUID and a unique **PARTUUID** per partition, optional partition **names** |
| Integrity | none | CRC32 checksums on header and table |
| Boot | BIOS | UEFI (and BIOS via a small "BIOS boot" partition) |

GPT also writes a **protective MBR** in sector 0, describing one partition covering the whole disk, so old tools
see the disk as "in use" and don't overwrite it. Because GPT keeps a backup table at the **end** of the disk,
when a virtual disk is enlarged, the backup is no longer at the end and tools offer to fix it (`parted` asks; in
`gdisk` use the expert `e` command).

The objective says GPT, so create GPT labels unless told otherwise.

### Partition types on GPT

The type GUID tells the OS what a partition is for. Tools give friendly names or short codes:

| Purpose | `gdisk` code | `fdisk` (GPT) type name | `parted` flag |
|---|---|---|---|
| Linux file system | `8300` | Linux filesystem | (none, default) |
| Linux swap | `8200` | Linux swap | `swap` |
| Linux LVM | `8e00` | Linux LVM | `lvm` |
| Linux RAID | `fd00` | Linux RAID | `raid` |
| EFI System | `ef00` | EFI System | `esp` (or `boot`) |
| BIOS boot | `ef02` | BIOS boot | `bios_grub` |

Linux does not actually require the right type: you can `pvcreate` a partition typed "Linux filesystem". But set
it as asked: graders, and other admins, look at it, and some tools (like the installer and `systemd-gpt-auto-generator`)
use it.

### Sizes and alignment

Disk sizes use two unit systems that are easy to confuse:

- **MiB, GiB** (binary): 1 MiB = 1024² bytes, 1 GiB = 1024³ bytes.
- **MB, GB** (decimal): 1 MB = 1000² bytes, 1 GB = 1000³ bytes.

`parted` takes both and means exactly what you write; `fdisk`/`gdisk` `+512M` and `lvcreate -L 512M` mean MiB.
When a task says "512 MiB", use `MiB` in parted.

Partitions should start on a 1 MiB boundary ("aligned") for performance on SSDs and RAID, which is why the
first partition starts at sector 2048 (1 MiB). All three tools align by default if you let them pick or start at
`1MiB`.

### Three tools: parted, gdisk, fdisk

All three edit GPT. Pick one and know it well; know the others well enough to read.

**parted** applies each command **immediately** (no "write" step), and can run non-interactively, which makes it
precise and scriptable:

```bash
parted /dev/vdb print                         # show the table (and the free space with: print free)
parted /dev/vdb mklabel gpt                   # new, EMPTY GPT table: destroys existing partitions
parted /dev/vdb mkpart swap1 linux-swap 1MiB 513MiB      # name, fs-type hint, start, end
parted /dev/vdb mkpart data 513MiB 2561MiB
parted /dev/vdb set 2 lvm on                  # flag partition 2 as LVM
parted /dev/vdb rm 3                          # delete partition 3
parted /dev/vdb unit MiB print                # print in MiB
parted -s /dev/vdb ...                        # script mode: no questions
```

On GPT, the word after `mkpart` is the partition **name** (on MBR it would be `primary`/`logical`). The
file-system word (`linux-swap`, `xfs`, `ext4`) only sets the type GUID; parted **does not create a file
system**. Note `mkpart` takes **start and end**, not a size: a 512 MiB partition starting at 1 MiB ends at 513 MiB.
Each new partition starts where the previous one ended.

**gdisk** (`gdisk` package) is interactive and only writes when you press `w`:

```text
# gdisk /dev/vdb
Command (? for help): n                    new partition
Partition number (1-128, default 1): ⏎
First sector (...default = 2048): ⏎        accept the aligned default
Last sector (...): +512M                   size relative to the start
Hex code or GUID (L to show codes, Enter = 8300): 8200
Command (? for help): p                    print to check
Command (? for help): w                    write and exit (q quits WITHOUT saving)
```

**fdisk** (`util-linux`, always installed) works the same way (`g` creates a new GPT table, `n`, `t` to change
type with a number or alias such as `swap`/`lvm`, `p`, `w`). Use `fdisk -l` for a quick listing of all disks.

### Deleting partitions

Make sure nothing uses it first: not mounted, not active swap, not a PV in a volume group, not in fstab.
Then `parted /dev/vdb rm N`, or `d` in gdisk/fdisk followed by `w`. Deleting a partition only removes the table
entry; the data stays on the disk until overwritten, which is why `wipefs -a /dev/vdb1` (remove file system
signatures) is useful before deleting, to stop old signatures being "rediscovered" if you recreate a partition
in the same place.

### Making the kernel see the change

When the partition table of a disk **not in use** changes, the tools tell the kernel and udev creates the new
`/dev/vdb1` nodes. If the disk has a mounted partition, the kernel may refuse to re-read the table ("Device or
resource busy"); `partprobe /dev/vdb` asks again, and `udevadm settle` waits until udev has finished creating the
device nodes. Always confirm with `lsblk` before using a new partition.

> **Exam angle.** "Create a 512 MiB partition on /dev/vdb and use it as swap" or "a 1 GiB partition for LVM".
> If the disk already has partitions, **add** to the free space without touching existing ones (that's what
> "non-destructively" in 5.6 means). Never run `mklabel` on a disk with partitions you must keep: it wipes the table.

---

## 5.2 Create and remove physical volumes

### Why LVM exists

Partitions are rigid: fixed size, contiguous, on one disk. If `/srv` fills up, growing it means there must be
free space directly after it on the same disk. **LVM** (Logical Volume Manager) adds a layer of indirection:

- You hand LVM pieces of storage, **physical volumes** (PVs), from any disks.
- It pools them into **volume groups** (VGs) divided into equal-size chunks called **physical extents** (PEs).
- From a VG you carve **logical volumes** (LVs) of any size; LVM maps each LV's **logical extents** to whatever
  physical extents are free, on any PV, contiguous or not.

That makes it possible to grow a volume online, add disks to a pool, move data off a failing disk while it is in
use (`pvmove`), and take snapshots. RHEL's installer uses LVM for `/`, `/home` and swap by default.

Under the hood, LVM is a user-space manager that writes **metadata** describing the layout onto every PV, and
configures the kernel's **device-mapper** to present each LV as a block device (`/dev/dm-N`, with friendly
names `/dev/mapper/VG-LV` and `/dev/VG/LV`). The kernel does the actual block remapping; the `pv*`, `vg*` and
`lv*` commands just manage metadata and device-mapper tables.

### Creating PVs

A PV can be a partition (usually typed Linux LVM) or a whole disk:

```bash
pvcreate /dev/vdb2               # initialise: writes an LVM label and metadata area
pvcreate /dev/vdc                # whole disk, no partition table (fine, but be explicit about it)
pvs                              # summary: PV, VG, size, free
pvdisplay /dev/vdb2              # details: PE size, total/free/allocated PEs, PV UUID
pvscan
```

If the device has an old file system or partition-table signature, `pvcreate` asks before overwriting it;
`wipefs -a` clears signatures first.

### The LVM devices file (RHEL 9 and 10)

LVM on RHEL 9 and 10 uses a **devices file**, `/etc/lvm/devices/system.devices`, listing which devices LVM is
allowed to use. `pvcreate` and `vgcreate`/`vgextend` add devices to it automatically, so normally you do not need
to think about it. It matters when disks move between systems, or when you `pvcreate` on another system and attach
the disk: the PV is ignored until added with `lvmdevices --adddev /dev/vdc` or `vgimportdevices VG`.
`lvmdevices` lists the file's contents. If a PV you know exists does not show up in `pvs`, think of this file.

### Removing PVs

A PV can only be removed if no VG uses it:

```bash
vgreduce vgdata /dev/vdc         # take it out of its VG (it must have no allocated extents)
pvmove /dev/vdc                  # if it does have data: move extents to other PVs in the VG first
pvremove /dev/vdc                # wipe the LVM label
```

---

## 5.3 Assign physical volumes to volume groups

### Creating a VG and choosing the extent size

```bash
vgcreate vgdata /dev/vdb2 /dev/vdc           # VG from two PVs (pvcreate is implied if needed)
vgcreate -s 8M vgdata /dev/vdb2              # physical extent size 8 MiB
vgs                                          # VG, #PV, #LV, size, free
vgdisplay vgdata                             # details: "PE Size", "Total PE", "Free  PE / Size"
```

The **physical extent** is LVM's allocation unit. Every LV is a whole number of extents, so its size is rounded
**up** to a multiple of the PE size. The default is **4 MiB**; it must be a power of two. Larger extents mean less
metadata on huge VGs; it has no effect on I/O performance.

The PE size is effectively **fixed when the VG is created** (`-s`), which is why exam tasks that specify it
("with an extent size of 16 MiB") must be done at `vgcreate` time. If you got it wrong and the VG is empty, remove
and recreate it.

### Adding and removing PVs later

```bash
pvcreate /dev/vdb3
vgextend vgold /dev/vdb3          # add a PV to an existing VG: more free extents to allocate
vgreduce vgold /dev/vdb3          # remove an unused PV
vgreduce --removemissing vgold    # after a disk died
vgrename vgold vgarchive
vgremove vgtemp                   # delete a VG (its LVs must be removed first, or it asks)
```

`vgextend` is how you grow the pool when an LV needs more space than the VG has free (Lecture 6, 6.4).

### Reading `vgdisplay`

```text
  --- Volume group ---
  VG Name               vgdata
  Format                lvm2
  VG Access             read/write
  VG Status             resizable
  Cur LV                2
  Open LV               2
  Cur PV                2
  VG Size               <6.99 GiB
  PE Size               8.00 MiB
  Total PE              894
  Alloc PE / Size       125 / 1000.00 MiB
  Free  PE / Size       769 / <6.01 GiB
  VG UUID               Wc8Fm2-...
```

The numbers you use: **PE Size**, **Total PE** and **Free PE**. A VG is always slightly smaller than the sum of
its PVs, because each PV loses some space to metadata and rounding.

---

## 5.4 Create and delete logical volumes

### Creating LVs

```bash
lvcreate -n lvweb -L 600M vgdata          # by size (-L): 600 MiB
lvcreate -n lvdocs -l 50 vgdata           # by extent count (-l): 50 extents (= 400 MiB with 8 MiB PEs)
lvcreate -n lvrest -l 100%FREE vgdata     # all remaining free space
lvcreate -n lvhalf -l 50%VG vgdata        # half the VG's total size
lvcreate -n lvx -L 1G vgdata /dev/vdc     # allocate only from a specific PV
lvs                                       # LV, VG, attributes, size
lvdisplay vgdata/lvweb                    # details, including "Current LE"
```

**`-L` (capital) takes a size; `-l` (lower case) takes a number of extents or a percentage.** This is a classic
trap: `-l 500` with 4 MiB extents is 2 GiB, not 500 MiB. When a task says "exactly 50 extents", use `-l 50`.
When it says "a size between 480 and 520 MiB", any `-L 500M` is fine; a size not divisible by the PE size is
rounded up ("Rounding up size to full physical extent...").

The new LV appears as `/dev/vgdata/lvweb` and `/dev/mapper/vgdata-lvweb` (both symlinks to `/dev/dm-N`). A hyphen
in a VG or LV name is doubled in the mapper name (`vg-data` / `lv-web` → `/dev/mapper/vg--data-lv--web`), which is
one reason to avoid hyphens.

An LV is just an empty block device. Next, put a file system or swap on it (Lecture 6 and 5.6) and mount it (5.5).

### Inspecting the mapping

```bash
lvs -o +devices                 # which PVs each LV lives on
lvs -a -o +seg_pe_ranges
dmsetup ls                      # device-mapper's view
lsblk                           # the LV under its PV(s)
```

### Deleting

Removal goes top-down, the reverse of creation:

```bash
umount /srv/old                       # 1. stop using it (also: swapoff for swap LVs)
vim /etc/fstab                        # 2. remove its line, or the next boot fails
systemctl daemon-reload
lvremove vgtemp/lvold                 # 3. remove the LV (asks to confirm; -y to skip)
vgremove vgtemp                       # 4. remove the VG once it has no LVs
pvremove /dev/vdd2                    # 5. wipe the PV label
parted /dev/vdd rm 2                  # 6. delete the partition if asked
```

Skipping step 2 is the classic way to turn a tidy removal into an emergency-mode boot.

> **Exam angle.** Read the task for: VG name, PE size, LV name, size *or* extent count, file system type,
> mount point, and whether to mount by UUID or label. Write them down. After creating, verify with `vgdisplay`
> (PE size), `lvs` (size), `lsblk -f` (file system) and `findmnt`.

---

## 5.5 Configure systems to mount file systems at boot by universally unique ID (UUID) or label

### Why not device names

`/dev/vdb1` describes a position, and positions change: add a disk and `sdb` may become `sdc`; NVMe and USB
enumeration order varies between boots. If fstab says `/dev/sdb1`, one day it will mount the wrong file system, or
fail. Instead, refer to the file system by something stored **inside** it:

- **UUID**: a 128-bit identifier written into the file system's superblock by `mkfs` (`mkswap` for swap).
  Unique and stable for the life of that file system. Reformatting creates a **new** UUID.
- **LABEL**: a short human name you choose, also stored in the superblock. Readable, but you must keep it unique
  yourself.
- `PARTUUID`/`PARTLABEL`: GPT partition identifiers (tied to the partition, not the file system).
- LVM paths (`/dev/vgdata/lvweb`, `/dev/mapper/vgdata-lvweb`) are also stable, because the names come from LVM
  metadata, not discovery order. The RHEL installer uses the mapper path for LVM volumes. But when a task says
  "by UUID", use the UUID even for an LV.

Find them with `blkid` or `lsblk -f`:

```text
# blkid /dev/vgdata/lvweb
/dev/vgdata/lvweb: UUID="5c0e6c6a-3b43-4c1c-a9b0-7d2c2c1e8f41" BLOCK_SIZE="512" TYPE="xfs"
```

Setting labels:

| File system | At creation | Later |
|---|---|---|
| ext4 | `mkfs.ext4 -L DOCS /dev/...` | `e2label /dev/... DOCS` or `tune2fs -L DOCS` |
| XFS | `mkfs.xfs -L web /dev/...` (max 12 characters) | `xfs_admin -L web /dev/...` (unmounted) |
| VFAT | `mkfs.vfat -n USB /dev/...` | `fatlabel /dev/... USB` |
| swap | `mkswap -L swap2 /dev/...` | `swaplabel -L swap2 /dev/...` |

### /etc/fstab, field by field

```text
# device                                    mount point  type  options          dump fsck
UUID=5c0e6c6a-3b43-4c1c-a9b0-7d2c2c1e8f41   /srv/web     xfs   defaults         0    0
LABEL=DOCS                                  /srv/docs    ext4  defaults         0    2
/dev/mapper/rhel-root                       /            xfs   defaults         0    0
UUID=9b1f...                                none         swap  defaults         0    0
server1:/exports/data                       /mnt/data    nfs   defaults,_netdev 0    0
```

1. **Device**: `UUID=...`, `LABEL=...`, a device path, or for network file systems `server:/path`.
2. **Mount point**: an existing directory (create it with `mkdir -p`). For swap, `none` (or `swap`).
3. **Type**: `xfs`, `ext4`, `vfat`, `swap`, `nfs`, ... (`auto` lets the kernel guess; be explicit).
4. **Options**, comma-separated. `defaults` means `rw,suid,dev,exec,auto,nouser,async`. Others you will meet:
   `ro`, `noexec`, `nosuid`, `nodev`, `noatime`, **`nofail`** (don't fail the boot if the device is missing),
   **`_netdev`** (needs the network), `x-systemd.automount`, `uid=`/`gid=`/`umask=` for VFAT.
5. **dump**: legacy backup flag, `0`.
6. **fsck pass**: order in which `fsck` checks at boot. `0` = never (use this for XFS, which has no boot-time
   fsck, and for swap and network mounts); `1` for the root file system if ext4; `2` for other ext4 file systems.

Lines starting with `#` are comments. Whitespace (spaces or tabs) separates fields.

### How fstab is used at boot

systemd does not read fstab line by line at boot. Early on, `systemd-fstab-generator` **converts every fstab line
into a unit** (`srv-web.mount`, `dev-disk-by\x2duuid-....swap`) under `/run/systemd/generator/`. Those units are
ordered and started like any other, as dependencies of `local-fs.target` (or `remote-fs.target` for network
file systems).

Two consequences:

1. **A failing mount fails `local-fs.target`, and the system drops to emergency mode.** That is what a typo in a
   UUID, a missing mount point, or a wrong file-system type does. `nofail` prevents that for non-essential mounts.
2. **After editing fstab, run `systemctl daemon-reload`** so the generator recreates the units. Otherwise
   `mount -a` may complain that the units are out of date, and `mount /point` may use the old definition.

### The safe workflow

```bash
mkdir -p /srv/web
blkid /dev/vgdata/lvweb               # copy the UUID (or: blkid -s UUID -o value /dev/vgdata/lvweb >> /etc/fstab, then edit)
vim /etc/fstab                        # add the line
systemctl daemon-reload
mount -a                              # mount everything in fstab not yet mounted: errors show NOW
findmnt --verify                      # syntax and sanity check of fstab (add --verbose)
findmnt /srv/web                      # confirm it mounted from the right device
df -hT /srv/web
```

`mount -a` is your boot simulation: if it succeeds silently, the boot will very probably be fine. **Never reboot
after editing fstab without running it.** If you are stuck in emergency mode because of fstab: log in with the
root password, `mount -o remount,rw /`, fix the file, `systemctl daemon-reload`, `mount -a`, then
`systemctl default` or reboot.

A handy trick to avoid copying 36-character UUIDs by hand is to append and then edit:

```bash
echo "UUID=$(blkid -s UUID -o value /dev/vgdata/lvweb) /srv/web xfs defaults 0 0" >> /etc/fstab
```

Use `>>`, never `>`, unless you want to lose your entire fstab.

---

## 5.6 Add new partitions and logical volumes, and swap to a system non-destructively

### "Non-destructively"

The word means: **existing partitions, volumes, file systems and swap keep working and keep their data**. In
practice:

- Create new partitions in **free space** only. Check with `parted /dev/vdb print free` or `lsblk`. Never
  `mklabel` a disk that has partitions you must keep, and never resize or recreate existing ones.
- Add new LVs from free extents, or `vgextend` the VG with a new PV first.
- Add swap **in addition to** existing swap, not instead of it.
- Edit `/etc/fstab` by appending; do not break existing lines.
- On a disk in use, run `partprobe` and check `lsblk` so the kernel sees the new partition without a reboot.

### What swap is

Physical RAM is finite. **Swap** is disk space the kernel uses to hold memory pages that have not been used
recently, freeing RAM for active work and for the file cache. It is not a substitute for enough RAM (disk is
thousands of times slower), but it gives breathing room, and without any swap the kernel's only answer to memory
exhaustion is the **OOM killer**, which kills processes. The kernel balances swapping out application memory
against dropping file cache using `vm.swappiness` (default 60 on RHEL; tuned profiles adjust it).

Swap can live on a partition, an LV, or a file. Multiple swap areas can be active; ones with higher
**priority** (`pri=`) are used first, and equal priorities are used round-robin.

### Creating swap

```bash
# on a partition (type Linux swap) or an LV
mkswap /dev/vdb1                      # writes a swap signature with a UUID
swapon /dev/vdb1                      # enable now
swapon --show                         # NAME TYPE SIZE USED PRIO
free -h                               # Swap: total grows

# make it permanent: fstab line, mount point "none", type "swap"
echo "UUID=$(blkid -s UUID -o value /dev/vdb1) none swap defaults 0 0" >> /etc/fstab
systemctl daemon-reload
swapon -a                             # enable everything in fstab: tests your line
swapon --show
```

An LV for swap: `lvcreate -n lvswap -L 256M vgdata`, then `mkswap /dev/vgdata/lvswap` and the same steps.
A swap file (not usually asked): `dd if=/dev/zero of=/swapfile bs=1M count=512; chmod 600 /swapfile;
mkswap /swapfile; swapon /swapfile`, and fstab `/swapfile none swap defaults 0 0`.

To remove swap: `swapoff /dev/vdb1`, remove the fstab line, `systemctl daemon-reload`, then reuse the device.

`swapon -a` is to swap what `mount -a` is to file systems: it activates every swap line in fstab, so it proves
your line works. Note that `mount -a` does **not** test swap lines.

Options worth knowing: `pri=10` (priority), `nofail`, and `discard` (for SSDs).

> **Exam angle.** "Add 512 MiB of swap, keep the existing swap, active at boot." Check before (`swapon --show`)
> and after: the new area must be listed **in addition to** the old one, and must survive a reboot.

---

## Putting it together

A full sequence for a typical exam task, *"On /dev/vdb create a 2 GiB LVM partition. Create volume group vgdata
with 8 MiB extents on it. Create a 50-extent LV lvdocs with ext4, label DOCS, mounted at /srv/docs by label.
Add 512 MiB of swap from a new partition, active at boot."*:

```bash
lsblk                                         # identify vdb: empty? which disk is the system disk?
parted -s /dev/vdb mklabel gpt                # only because vdb is new and empty
parted -s /dev/vdb mkpart lvm1 1MiB 2049MiB set 1 lvm on
parted -s /dev/vdb mkpart swap1 linux-swap 2049MiB 2561MiB
udevadm settle; lsblk /dev/vdb

pvcreate /dev/vdb1
vgcreate -s 8M vgdata /dev/vdb1
lvcreate -n lvdocs -l 50 vgdata
mkfs.ext4 -L DOCS /dev/vgdata/lvdocs
mkdir -p /srv/docs
mkswap /dev/vdb2

cat >> /etc/fstab <<EOF
LABEL=DOCS   /srv/docs  ext4  defaults  0 2
UUID=$(blkid -s UUID -o value /dev/vdb2)  none  swap  defaults  0 0
EOF
systemctl daemon-reload
mount -a && swapon -a && findmnt --verify
vgdisplay vgdata | grep 'PE Size'; lvs vgdata; findmnt /srv/docs; swapon --show
```

Then reboot at a convenient point and check it all again.

**Now practise:** [Lab 06](#/lab/06) on the VM: GPT partitions, PVs, a VG with a custom extent size, LVs by size
and by extent count, mounts by UUID and label, swap, a broken mount to diagnose, a VG to remove cleanly, and a
non-destructive extension.

## Review questions

1. Why should fstab not refer to `/dev/sdb1`? Name three better identifiers.
2. List four differences between MBR and GPT.
3. With `parted`, how do you create a 1 GiB partition immediately after one that ends at 513 MiB?
4. Does `parted mkpart data xfs 1MiB 1GiB` create an XFS file system?
5. Explain PV, VG, LV, PE and LE in one sentence each.
6. When can you choose a VG's extent size, and how?
7. What is the difference between `lvcreate -L 100` and `lvcreate -l 100`?
8. A PV you created on another machine is not listed by `pvs`. What RHEL 9/10 feature is probably responsible?
9. Give the correct order to remove an LV, its VG, PV and partition, starting from a mounted file system.
10. What does the sixth fstab field mean, and what value should XFS use?
11. Why run `systemctl daemon-reload` and `mount -a` after editing fstab?
12. What happens at boot if an fstab line refers to a UUID that doesn't exist, and how do you avoid that for a
    non-essential disk?
13. Write the fstab line for a swap partition with UUID `abcd-...`.
14. Which command tests fstab swap lines, given that `mount -a` doesn't?

<details><summary>Answers</summary>

1. Device names depend on discovery order and can change. Use `UUID=`, `LABEL=`, or a stable LVM path
   (or `PARTUUID=`).
2. GPT supports disks over 2 TiB, 128 partitions without extended/logical tricks, GUID types and per-partition
   UUIDs and names, a backup table at the end of the disk, and CRC checksums. MBR is a single sector with four
   primary entries.
3. `parted /dev/vdb mkpart NAME 513MiB 1537MiB`.
4. No. It only sets the partition type; you still run `mkfs.xfs`.
5. A PV is a device initialised for LVM; a VG is a pool of PVs divided into extents; an LV is a block device
   allocated from a VG; a PE is the VG's allocation unit; an LE is the corresponding unit of an LV, mapped to a PE.
6. At creation: `vgcreate -s SIZE`.
7. `-L 100` is 100 MiB; `-l 100` is 100 extents.
8. The LVM devices file (`/etc/lvm/devices/system.devices`); add it with `lvmdevices --adddev` or
   `vgimportdevices`.
9. `umount`, remove the fstab line (and `daemon-reload`), `lvremove`, `vgremove`, `pvremove`, then delete the
   partition.
10. The fsck pass order at boot; `0` for XFS.
11. `daemon-reload` regenerates the mount units from fstab; `mount -a` mounts everything now, exposing errors
    before a reboot does.
12. The mount unit fails, `local-fs.target` fails, and the system enters emergency mode. Use the `nofail` option.
13. `UUID=abcd-... none swap defaults 0 0`.
14. `swapon -a` (then `swapon --show`).

</details>
