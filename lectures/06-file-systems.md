# Lecture 6: Create and configure file systems

Lecture 5 got you from a raw disk to a block device: a partition or a logical volume. This lecture puts file
systems on those devices and attaches them to the directory tree, then goes beyond local disks to file systems
served over the network with NFS, mounted on demand by autofs. It explains how to grow a volume and its file
system while it is in use, and finishes with a systematic method for diagnosing permission problems, which ties
together ownership, mode bits, ACLs, mount options and SELinux.

---

## Background: what a file system is

A block device is just a long array of numbered blocks. A **file system** is a data structure written onto those
blocks that turns them into named files and directories with permissions and timestamps. Every Unix file system
has roughly the same parts:

- A **superblock**: the file system's own metadata: type, size, block size, UUID, label, state, and where
  everything else is. (Several backup copies exist on ext4; XFS has one per allocation group.)
- **Inodes**: one per file, holding metadata and pointers to data (Lecture 1, 1.9).
- **Directories**: special files mapping names to inode numbers.
- **Free-space tracking**: bitmaps (ext4) or B+trees (XFS) of free blocks and inodes.
- A **journal** (log): before changing metadata, the file system writes the intended change to the journal. After
  a crash, replaying the journal brings the metadata to a consistent state in seconds, instead of scanning the
  whole disk. That is why modern Linux systems rarely need long `fsck` runs.

`mkfs` ("make file system") writes these structures onto a device. It is **destructive**: whatever was there
before becomes unreachable.

### The Virtual File System

Applications don't talk to XFS or ext4 directly. They call `open()`, `read()`, `write()`, `stat()`, and the
kernel's **VFS** layer dispatches each call to the right file-system driver based on which mount the path falls
in. That is how one directory tree can be stitched together from XFS on an LV, ext4 on a partition, VFAT on a USB
stick, NFS from another machine and virtual file systems like `/proc` (which has no disk at all), while every
program sees just "files".

---

## 6.1 Create, mount, unmount, and use VFAT, ext4, and XFS file systems

### The three file systems compared

| | XFS | ext4 | VFAT (FAT32) |
|---|---|---|---|
| Role on RHEL | **default** for everything, including `/` | fully supported alternative | data exchange, the EFI System Partition |
| Create | `mkfs.xfs` | `mkfs.ext4` | `mkfs.vfat` (package `dosfstools`) |
| Journal | yes (metadata) | yes (metadata by default) | **no** |
| Grow | online, while mounted (`xfs_growfs`) | online or offline (`resize2fs`) | with external tools only |
| **Shrink** | **impossible** | offline only (unmount first) | |
| Max file size | 8 EiB | 16 TiB | 4 GiB − 1 byte |
| Unix owners, permissions, symlinks, ACLs, SELinux labels | yes | yes | **no**: owner, mode and label come from mount options |
| Repair | `xfs_repair` (unmounted) | `e2fsck` / `fsck.ext4` | `fsck.vfat` |
| Label | `xfs_admin -L` (12 chars) | `e2label` (16 chars) | `fatlabel` (11 chars, upper case) |
| Info | `xfs_info /mountpoint` | `tune2fs -l /dev/...`, `dumpe2fs -h` | `fsck.vfat -n` |

XFS was designed for large files and parallel I/O: it divides the device into **allocation groups** that can be
used concurrently, allocates space in extents, and creates inodes dynamically. ext4 descends from ext2/ext3 and is
excellent for general-purpose and smaller volumes; it fixes the number of inodes at creation (`df -i` shows usage,
and running out of inodes is possible with millions of tiny files). VFAT is the lowest common denominator that
every operating system and firmware can read; it has no concept of Unix ownership.

### Creating file systems

```bash
mkfs.xfs /dev/vgdata/lvweb
mkfs.xfs -f -L web /dev/vdb3           # -f: overwrite an existing signature; -L: label
mkfs.ext4 /dev/vdb2
mkfs.ext4 -L DOCS /dev/vgdata/lvdocs
mkfs.vfat /dev/vdb1                    # FAT type chosen by size; -F 32 forces FAT32
mkfs.vfat -n USBDATA /dev/vdb1         # -n: label
mkfs -t xfs /dev/...                   # generic front end, same thing
```

`mkfs.xfs` refuses to overwrite an existing file system without `-f`; `mkfs.ext4` asks. That pause is your last
chance to notice you typed the wrong device. `wipefs /dev/vdb1` lists signatures on a device without changing
anything.

### Mounting: what it really does

**Mounting** attaches a file system's root directory to an existing directory, the **mount point**, in the tree.
After `mount /dev/vdb1 /mnt/data`, any path under `/mnt/data` is resolved inside that file system. Whatever was
in the `/mnt/data` directory before is **hidden** (not deleted) until you unmount. That is why mount points are
normally empty directories, and why files written to `/mnt/data` when the mount *failed* silently land on the
root file system, a common way to fill up `/`.

```bash
mkdir -p /mnt/xfs
mount /dev/vdb3 /mnt/xfs                       # type auto-detected
mount -t ext4 /dev/vdb2 /mnt/ext4              # explicit type
mount UUID=5c0e6c6a-... /mnt/xfs               # by UUID
mount LABEL=DOCS /srv/docs
mount -o ro,noexec /dev/vdb2 /mnt/ext4         # with options
mount -o remount,rw /                          # change options of an existing mount
mount /srv/docs                                # only a mount point: uses the fstab line
mount -a                                       # everything in fstab not yet mounted
mount                                          # list (long, includes virtual file systems)
findmnt                                        # the mount tree; findmnt /srv/docs; findmnt -t xfs
df -hT                                         # usage per mounted file system
```

Mount options you should recognise:

| Option | Meaning |
|---|---|
| `defaults` | `rw,suid,dev,exec,auto,nouser,async` |
| `ro` / `rw` | read-only / read-write |
| `noexec` | programs on it can't be executed |
| `nosuid` | setuid/setgid bits are ignored |
| `nodev` | device files are ignored |
| `noatime` / `relatime` | don't update / lazily update access times (relatime is the default) |
| `nofail` | don't fail the boot if the device is missing |
| `_netdev` | needs the network; mount after it is up |
| `x-systemd.automount` | mount on first access (systemd automount) |
| `uid=`, `gid=`, `umask=`, `fmask=`, `dmask=` | VFAT: owner and permissions for every file |
| `context="..."` | set one SELinux label for the whole file system (VFAT, NFS) |

**VFAT and permissions.** Because VFAT stores no owners or modes, every file appears owned by the user who
mounted it (root) with permissions derived from `umask`. To let user harry write to a VFAT stick:
`mount -o uid=harry,gid=harry,umask=022 /dev/vdb1 /mnt/usb`. `chmod` and `chown` on a VFAT mount fail or do nothing.

### Unmounting, and "target is busy"

```bash
umount /mnt/xfs          # by mount point (or by device)
```

The kernel refuses to unmount a file system that is **in use**: a process has a file open on it, has its current
directory inside it, or something else is mounted below it.

```text
umount: /mnt/old: target is busy.
```

Find the culprit, deal with it, then unmount:

```bash
fuser -vm /mnt/old       # processes using the file system: USER PID ACCESS COMMAND
                         #   access codes: c = current dir, f = open file, e = executable, m = mmap
lsof /mnt/old            # open files on it (lsof +D /mnt/old for a directory tree, slower)
cd /                     # ...if the "user" is your own shell sitting in it!
kill PID                 # or stop the service cleanly: systemctl stop unit
umount /mnt/old
```

`fuser -km /mnt/old` kills every process using it: effective, but blunt. `umount -l` (lazy) detaches the mount
immediately and cleans up when it is no longer busy; it hides the problem rather than fixing it, so avoid it on
the exam.

To retire a mount **permanently**, unmounting is not enough: remove (or comment out) its fstab line and run
`systemctl daemon-reload`, or it will be back after the next reboot.

### Checking and repairing

File systems are checked automatically when needed (ext4 by fsck pass number, XFS by journal replay at mount).
For manual repair the file system must be **unmounted**:

```bash
umount /srv/ext && e2fsck -f /dev/vgfs/lvext      # ext4
umount /srv/grow && xfs_repair /dev/vgfs/lvgrow    # XFS
```

Never run a repair on a mounted file system.

### Space: df versus du

`df` asks each file system how many blocks are used and free. `du` walks the directory tree adding up file sizes.
They disagree when files are deleted but still open (counted by `df`, invisible to `du`; see `lsof +L1`), or when
files are hidden under a mount point. `du -sh /var/*` finds what is big; `df -h` says how full each file system is;
`df -i` shows inode usage.

---

## 6.2 Mount and unmount network file systems using NFS

### How NFS works

**NFS** (Network File System) lets a server **export** directories that clients mount like local file systems.
Programs on the client use ordinary system calls; the client's kernel NFS module turns them into RPC requests over
the network, and the server's kernel NFS server performs them on its local file system.

RHEL defaults to **NFSv4** (v4.2 negotiated when both sides support it). Key properties:

- NFSv4 uses a **single TCP port, 2049**. NFSv3 additionally needed `rpcbind` (port 111) and `mountd`, which
  matters for firewalls and for `showmount` (below).
- NFSv4 servers present their exports under a **pseudo-root**: a virtual tree containing all exports, so a client
  can mount `server:/` and see every export it is allowed to see as subdirectories.
- **Identity**: with the default `sec=sys`, the client simply tells the server the numeric UID and GID of the
  calling user, and the server applies normal permission checks with those numbers. So the same users should have
  the **same UIDs on client and server** (central identity like IdM/LDAP solves this). With `sec=krb5`, Kerberos
  authenticates users properly. NFSv4 also maps user **names** with `idmapd`, using a shared domain.
- **root_squash** (the server default): requests from root on a client are mapped to the anonymous user
  `nobody`, so being root on a client does not make you root on the server's files. That is why `root` on the
  client may get "Permission denied" on an NFS mount where an ordinary user succeeds.

The server side (`/etc/exports`, `exportfs`, `nfs-server.service`) is RHCE material; the RHCSA only asks you to be
a client.

### Client setup

```bash
dnf install nfs-utils                      # client tools and mount helper
showmount -e nfs.lab.example.com           # list exports (uses NFSv3 mountd: may fail on v4-only servers)
mkdir -p /mnt/projects
mount -t nfs nfs.lab.example.com:/exports/projects /mnt/projects
mount -t nfs -o vers=4.2,ro server:/exports/data /mnt/data   # options
mount server:/ /mnt/all                    # NFSv4 pseudo-root: browse all exports
findmnt -t nfs4                            # what's mounted, with negotiated options
nfsstat -m                                 # NFS mounts and their options
umount /mnt/projects
```

If `showmount` fails with an RPC error, the server may be NFSv4-only with `rpcbind` and `mountd` blocked. Mount the
pseudo-root (`server:/`) and `ls` it to discover exports instead.

### Persistent NFS mounts

```text
nfs.lab.example.com:/exports/projects  /mnt/projects  nfs  defaults,_netdev  0 0
```

- The device field is `server:/path`.
- Type `nfs` (NFSv4 is negotiated; `nfs4` also works).
- **`_netdev`** marks it as a network file system so it is mounted after the network is up. systemd also infers
  this from the `nfs` type (placing it under `remote-fs.target`), but writing `_netdev` is explicit and harmless.
- `nofail` is worth adding if the server may be down at boot.
- fsck pass `0`.

Common options: `rw`/`ro`, `vers=4.2`, `sync`, `hard` (default: retry forever if the server disappears, so
programs block rather than see errors) vs `soft`, `timeo=`, `sec=krb5`.

Then `systemctl daemon-reload; mount -a; findmnt /mnt/projects`. Because the server is remote, test that the
mount works **and** that you can read the files (`ls /mnt/projects`).

### Unmounting NFS

`umount /mnt/projects`. Busy mounts behave as for local ones (`fuser -vm`). If the server is gone and processes
hang on a `hard` mount, `umount -f` (force) and as a last resort `umount -l`. To stop it coming back, remove the
fstab line and reload.

---

## 6.3 Configure autofs

### Why automount

Static NFS mounts have drawbacks: every client mounts every share at boot, even ones rarely used; boot may wait or
fail when a server is down; and you cannot pre-list thousands of user home directories. **autofs** mounts a file
system **on demand**, the first time someone accesses its path, and unmounts it again after a period of
inactivity (5 minutes by default, `--timeout` to change).

The mechanism: the `automount` daemon (from the `autofs` package) creates special **autofs mount points** in the
kernel. When a process accesses a path under one, the kernel pauses the process and asks the daemon; the daemon
looks up the path's **key** in a **map**, performs the real mount, and the process continues, unaware anything
happened.

### Maps

Configuration has two levels:

1. The **master map**, `/etc/auto.master`, plus any `*.autofs` files in `/etc/auto.master.d/`. Each line says
   "this base directory is managed by that map file".
2. **Map files**, each mapping keys (names under the base directory) to what should be mounted there.

```bash
dnf install autofs nfs-utils
```

**An indirect map** manages the entries *under* a base directory:

```text
# /etc/auto.master.d/projects.autofs
/shares   /etc/auto.shares

# /etc/auto.shares
#key      options           location
projects  -rw,sync          nfs.lab.example.com:/exports/projects
docs      -ro               nfs.lab.example.com:/exports/docs
```

Accessing `/shares/projects` mounts the export there. `autofs` creates and owns `/shares` itself: **do not create
the subdirectories** `projects` and `docs`; they appear on access. (`ls /shares` shows nothing until something is
mounted, unless you enable `browse_mode` or put `--ghost` on the master map line.)

**Wildcard maps** handle many similar entries, such as home directories:

```text
# /etc/auto.master.d/homes.autofs
/remote/homes   /etc/auto.homes

# /etc/auto.homes
*   -rw,sync   nfs.lab.example.com:/exports/homes/&
```

`*` matches any key, and `&` is replaced by the key that matched. Accessing `/remote/homes/alice` mounts
`server:/exports/homes/alice` there. This is the classic exam task: NFS home directories for network users,
mounted on login. A user whose home in `/etc/passwd` (or LDAP) is `/remote/homes/alice` gets it mounted
automatically when they log in.

**A direct map** mounts at absolute paths anywhere in the tree; the master map uses the special base `/-`:

```text
# /etc/auto.master.d/direct.autofs
/-   /etc/auto.direct

# /etc/auto.direct
/mnt/reports   -ro   nfs.lab.example.com:/exports/reports
```

Use direct maps when the mount point must be a specific existing path that you cannot dedicate a whole parent
directory to.

Map options use the same names as `mount -o`, prefixed with `-`. Non-NFS mounts specify the type:
`data -fstype=xfs :/dev/vgdata/lvdata`.

### Starting it

```bash
systemctl enable --now autofs
ls /remote/homes/alice          # triggers the mount
findmnt /remote/homes/alice     # confirm: an nfs4 mount under an autofs mount
```

After changing **maps**, autofs usually picks up indirect map changes on the next lookup, but changing the
**master map** requires `systemctl reload autofs` (or restart). When in doubt, restart.

### Troubleshooting autofs

- Nothing mounts: is `autofs` running and enabled? Is the master map file name ending in `.autofs` inside
  `/etc/auto.master.d/`? Is `nfs-utils` installed? Can you mount the export manually?
- `ls /remote/homes` is empty: normal for indirect maps; access a full path.
- The base directory already contains real files: autofs mounts over it and hides them. Use an empty or
  non-existent base.
- `journalctl -u autofs`, and for detail set `logging = debug` in `/etc/autofs.conf` and restart.
- `automount -m` dumps the maps as autofs understands them.

> **Exam angle.** Expect "configure autofs so that user X's home from server:/path/X is mounted at
> /path/X". Make the master-map entry and a wildcard map, enable autofs, then `su - X` (or `ls /path/X`) and
> check `findmnt`. Don't pre-create the per-user directories.

systemd offers a lighter alternative for single mounts: the fstab option `x-systemd.automount` (with
`x-systemd.idle-timeout=`) creates an automount unit, so the file system is mounted on first access. If a task
says "autofs", use autofs.

---

## 6.4 Extend existing logical volumes

### Two layers must grow

Growing storage is always a two-step operation: first the **block device** (the LV) gets bigger, then the **file
system** on it is told to use the new space. Until the second step, `lvs` shows the new size but `df` shows the
old one.

### Growing the LV

```bash
vgs vgfs                                   # is there enough free space in the VG?
lvextend -L 800M vgfs/lvgrow               # to an absolute size
lvextend -L +200M vgfs/lvgrow              # by an amount
lvextend -l +50 vgfs/lvgrow                # by 50 extents
lvextend -l +100%FREE vgfs/lvgrow          # take all free space in the VG
lvextend -r -L 800M vgfs/lvgrow            # ... and resize the file system too (-r = --resizefs)
```

Mind the `+`: `-L 800M` means "make it 800 MiB"; `-L +800M` means "add 800 MiB". If the target is smaller than
the current size, `lvextend` refuses, which protects you from accidentally shrinking.

`lvresize` can grow or shrink and takes the same options; `lvextend` is safer because it only grows.

### Growing the file system

**`-r` does it for you**: it calls `fsadm`, which runs the right tool for the file system type. Use it. If you
forgot, grow the file system afterwards:

```bash
xfs_growfs /srv/grow              # XFS: takes the MOUNT POINT, works only while mounted
resize2fs /dev/vgfs/lvext         # ext4: takes the DEVICE, works mounted or unmounted
```

Both default to growing to fill the device. Both work **online**: users keep working while it grows. Confirm with
`df -h /srv/grow`.

### When the VG is full

Add space to the pool first (Lecture 5): new partition or disk → `pvcreate` → `vgextend vgfs /dev/vdc1` →
`lvextend -r`.

### Shrinking

XFS **cannot be shrunk**, ever. To make an XFS volume smaller: back up (`xfsdump` or `tar`), recreate it smaller,
restore. ext4 can be shrunk, but **only unmounted**, and the file system must be shrunk **before** the LV:
`lvreduce -r -L 400M vg/lv` does it in the right order (after asking to unmount). Shrinking the LV first destroys
the end of the file system. Shrinking is not in the objectives, but knowing why it is dangerous helps you avoid
typing `lvreduce` by accident.

> **Exam angle.** "Resize the logical volume lvdata and its file system to between 750 MiB and 850 MiB."
> `lvextend -r -L 800M vg/lvdata`, then `lvs` and `df -h` to confirm both changed. A size *range* exists because
> extents round sizes; aim for the middle.

---

## 6.5 Diagnose and correct file permission problems

"User X can't do Y" is one of the most common administrative tickets, and the exam includes it in disguise
("make sure members of group Z can create files in D"). Access to a file depends on **several independent
layers**, and the request is denied if **any** one of them says no. Check them in order.

### Step 1: who is actually asking?

```bash
id alice            # uid, primary gid, ALL groups, as the system sees them now for a new login
id                  # your current process's identity
groups alice
```

**Group membership is read at login.** If alice was added to `team` five minutes ago, her existing shells (and
any processes started from them) still do not have `team`. She must log out and in, or run `newgrp team`, or you
test with a fresh `su - alice`. Many "I'm in the group but it still says denied" problems are just this.

Also check the account itself: is it locked, expired, using `nologin` as shell (Lecture 9)? Those cause login
failures, not file permission errors, but the symptom can look similar.

### Step 2: can they get to it? Every directory on the path.

To open `/srv/team/plan.txt`, a process needs **execute (search)** permission on `/`, `/srv` and `/srv/team`, and
then the appropriate permission on `plan.txt`. To create or delete in `/srv/team`, it needs **write and execute on
`/srv/team`** (not on the file). `namei` shows the whole chain in one go:

```text
$ namei -l /srv/team/plan.txt
f: /srv/team/plan.txt
dr-xr-xr-x root root  /
drwxr-xr-x root root  srv
drwxrws--- root team  team
-rw-r--r-- alice team plan.txt
```

Reading this: everyone can traverse `/` and `/srv`; only root and group `team` can enter `/srv/team` (setgid is
set, so new files get group `team`); `plan.txt` is writable only by alice. So bob, in `team`, can read it but not
edit it. Fix: `chmod g+w /srv/team/plan.txt` (and think about why: alice's **umask** created it without group write,
see objective 10.2).

### Step 3: owner, group and mode bits

Remember the kernel picks exactly **one** class: owner, else group, else other (Lecture 1, 1.10). An owner with
`r--` cannot write even if "other" has `rw-`. Check with `ls -l` (or `stat`), and fix with `chown`, `chgrp` and
`chmod`. For shared directories the standard shape is:

```bash
chgrp team /srv/team
chmod 2770 /srv/team        # rwxrws---: group can create; setgid makes new files group team; others nothing
```

If members must not delete each other's files, add the sticky bit: `chmod 3770`.

### Step 4: ACLs

**Access Control Lists** extend the owner/group/other model with entries for **additional named users and
groups**, for cases like "the team owns it, but auditor bob needs read access too". They are supported on XFS and
ext4 (and NFSv4 has its own ACL model). A file with an ACL shows a `+` after its mode in `ls -l`:
`-rw-rw-r--+`.

```bash
getfacl /srv/team/plan.txt
# file: srv/team/plan.txt
# owner: alice
# group: team
user::rw-          ← owner
user:bob:rw-       ← named user entry
group::r--         ← owning group
group:audit:r--    ← named group entry
mask::rw-          ← upper limit for named users, named groups and the owning group
other::---

setfacl -m u:bob:rw /srv/team/plan.txt       # add/modify an entry
setfacl -m g:audit:rx /srv/team              # for a group
setfacl -x u:bob /srv/team/plan.txt          # remove one entry
setfacl -b /srv/team/plan.txt                # remove all ACL entries
setfacl -R -m g:team:rwX /srv/team           # recursively (X: x only for dirs and already-executable files)
setfacl -m d:g:team:rwx /srv/team            # DEFAULT ACL on a directory: inherited by new files/dirs
getfacl -R /srv/team > acl-backup.txt; setfacl --restore=acl-backup.txt
```

Two ACL concepts cause confusion:

- **The mask.** The `mask` entry caps the permissions of every named user, named group and the owning group. An
  entry `user:bob:rw-` with `mask::r--` gives bob only `r--` (getfacl shows `#effective:r--`). The mask is
  recalculated when you `setfacl -m`, but **`chmod g=...` on a file with an ACL changes the mask**, not the owning
  group's entry. So a careless `chmod 640` can silently remove named users' write access. When `ls -l` shows a `+`,
  the "group" bits it displays are the mask.
- **Default ACLs** exist only on directories. They do not affect the directory's own access; they are the ACL that
  new files and subdirectories created inside will **inherit**. To give a team lasting access to everything created
  in a directory, you need both an access ACL (for existing content) and a default ACL (for future content).

The algorithm: owner entry if you are the owner; else a matching named user entry (masked); else any matching
group entries, owning or named (masked); else other.

ACLs are preserved by `cp -a`, `tar --acls`, `rsync -A`, and lost by plain `cp`.

### Step 5: default permissions (umask)

If a team member's new files are not writable by the others, look at how they were created: the **umask**
removes permission bits from new files (Lecture 10, 10.2). A default ACL on the directory, or a different umask,
fixes it going forward; `chmod` fixes existing files.

### Step 6: the file system and mount options

- Mounted **read-only** (`ro`), or remounted read-only by the kernel after errors: everything fails with
  "Read-only file system". `findmnt -no OPTIONS /path`, and `dmesg` for errors.
- `noexec`: scripts and programs fail with "Permission denied" even with `x` set. Running `bash script.sh`
  works, which is the tell.
- VFAT: ownership and modes come from mount options; `chmod` doesn't help.
- NFS: `root_squash` makes root `nobody` on the server; UIDs must match between client and server; the server's
  export options (`ro`) apply.

### Step 7: file attributes

ext4 and XFS support extra attribute flags. The **immutable** attribute (`i`) prevents any change, even by root;
**append-only** (`a`) allows only appending. They are rare but baffling if you don't know them:

```bash
lsattr /srv/team/plan.txt     # ----i----------- means immutable
chattr -i /srv/team/plan.txt
```

### Step 8: SELinux

If every traditional permission allows access and it is still denied, and especially if the user is a **service**
(httpd, sshd, vsftpd) rather than a person, suspect SELinux. Its labels are shown by `ls -Z`, and every denial is
logged:

```bash
ausearch -m AVC -ts recent
journalctl -t setroubleshoot
```

Lecture 10 explains how to read and fix those. `getenforce` and a quick `setenforce 0` test (then **`setenforce 1`
again**) tells you whether SELinux is the cause; the fix is a label, a port type or a boolean, never leaving it
permissive.

### A worked diagnosis

*"bob is in group team but cannot edit `/srv/team/plan.txt`, and carol (not in team) can read files there."*

```bash
id bob                         # is team listed? (if just added: needs a new login)
namei -l /srv/team/plan.txt    # path: /srv/team is 0775 → others can enter and read: carol's access
ls -l /srv/team/plan.txt       # -rw-r--r--. alice team → group has no write: bob's problem
chmod 2770 /srv/team           # others: no access; setgid for group inheritance
chmod g+w /srv/team/plan.txt
su - bob -c 'echo test >> /srv/team/plan.txt'   # verify as the user
su - carol -c 'ls /srv/team'                    # should now be denied
```

> **Exam angle.** Always verify as the affected user with `su - USER -c '...'`. Root bypasses permission checks,
> so testing as root proves nothing.

---

## Putting it together

The life cycle of a file system on an exam machine: an LV from Lecture 5 gets `mkfs.xfs -L web`, a mount point,
an fstab line by UUID, `daemon-reload` and `mount -a`. Later the task asks for it to be 300 MiB larger:
`lvextend -r -L +300M`. A team needs a shared directory on it: `chgrp`, `chmod 2770`, and perhaps a default ACL
for an extra group. Network data lives on an NFS server: a static fstab entry with `_netdev` for a share everyone
needs, and an autofs wildcard map for home directories. At the end of the exam, an obsolete mount is retired:
`fuser -vm`, stop the process, `umount`, delete the fstab line, `lvremove`.

**Now practise:** [Lab 07](#/lab/07) on the VM covers all of it, including a busy mount and a broken team
directory.

## Review questions

1. What does `mkfs` write, and why is a journal useful?
2. Name two things XFS cannot do that ext4 can, and one advantage of XFS.
3. Why can't you `chown` a file on a VFAT file system, and how do you give a user write access to one?
4. `umount /mnt/old` says "target is busy". How do you find out why?
5. What happens to files that were in a directory before you mounted a file system on it?
6. Why might root get "Permission denied" on an NFS mount where ordinary users don't?
7. What does `_netdev` do in fstab?
8. `showmount -e server` fails, but the server works. Why might that be, and how else can you list exports?
9. Explain the master map and a map file, and write a wildcard map for `server:/homes/USER` at `/rhome/USER`.
10. Why should you not create `/rhome/alice` yourself?
11. After `lvextend -L 800M vg/lv`, `df` still shows the old size. What did you forget, and how do you fix it for
    XFS and for ext4?
12. What is the difference between `-L 800M` and `-L +800M`?
13. A user was added to a group but still can't access a group-owned directory. What's the most likely reason?
14. `getfacl` shows `user:bob:rw-  #effective:r--`. Explain.
15. What is a default ACL, and where can it be set?
16. A script on a mounted file system fails with "Permission denied" despite `rwx`, but `bash script.sh` works.
    What's going on?

<details><summary>Answers</summary>

1. The superblock, inode tables, free-space structures, root directory and journal. The journal lets the file
   system return to a consistent state after a crash by replaying recent metadata changes instead of a full scan.
2. XFS can't shrink, and can't be resized while unmounted (it must be mounted to grow). It scales better for large
   files and parallel I/O.
3. VFAT has no Unix ownership or permissions; they come from mount options. Mount with
   `uid=USER,gid=GROUP,umask=...`.
4. `fuser -vm /mnt/old` or `lsof /mnt/old` (and check your own shell isn't in it).
5. They are hidden, not deleted, until the file system is unmounted.
6. `root_squash` maps the client's root to `nobody` on the server.
7. Marks the mount as needing the network, so it is mounted after the network is up (under `remote-fs.target`).
8. `showmount` uses NFSv3's mountd and rpcbind, which an NFSv4-only server or a firewall may not offer. Mount the
   NFSv4 pseudo-root (`server:/`) and list it.
9. The master map (`/etc/auto.master` and `/etc/auto.master.d/*.autofs`) binds a base directory to a map file;
   the map file maps keys to locations. `/rhome /etc/auto.rhome` in `rhome.autofs`, and `* -rw,sync server:/homes/&`
   in `/etc/auto.rhome`.
10. autofs manages the base directory and creates entries on access; a real directory there conflicts with that.
11. Growing the file system. `xfs_growfs /mountpoint` or `resize2fs /dev/vg/lv` (or use `lvextend -r` next time).
12. `-L 800M` sets the size to 800 MiB; `-L +800M` adds 800 MiB.
13. Group membership is applied at login: they need a new login session (or `newgrp`).
14. The mask (`mask::r--`) limits bob's named entry to read.
15. An ACL on a directory that new files and subdirectories inherit; only on directories (`setfacl -m d:...`).
16. The file system is mounted `noexec`.

</details>
