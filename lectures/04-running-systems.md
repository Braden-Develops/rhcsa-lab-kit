# Lecture 4: Operate running systems

This section is about the life of a running machine: how it gets from power-on to a login prompt, how you
steer and interrupt that process, what processes are and how the kernel schedules them, how the system is tuned,
where every log message goes, how services are controlled, and how files move between machines.

It is the broadest section of the exam and the one where understanding pays off most. The root-password reset
in particular is a sequence many candidates memorise and then botch under pressure; once you understand *why*
each step is there, you cannot get it wrong.

Two labs cover it: [Lab 04](#/lab/04) (processes, tuning, logs, services, transfers; container) and
[Lab 05](#/lab/05) (boot, targets and the password reset; VM).

---

## Background: the boot sequence, end to end

You need this picture for objectives 4.1, 4.2, 4.3, 7.3 and 7.6, so it comes first.

```text
 power on
   │
 1 firmware (UEFI or BIOS): POST, find a boot device
   │
 2 boot loader: GRUB 2 (via shim on UEFI Secure Boot): shows the menu, loads kernel + initramfs
   │
 3 Linux kernel: initialises hardware, mounts the initramfs as a temporary root, starts its /init
   │
 4 initramfs (built by dracut, runs systemd): loads storage drivers, assembles LVM/RAID,
   │  finds the real root file system and mounts it READ-ONLY at /sysroot
   │
 5 switch_root: /sysroot becomes /, and systemd re-executes from the real root (PID 1)
   │
 6 systemd: activates default.target and everything it pulls in: mounts from fstab,
   │  swap, networking, services, getty login prompts...
   │
 7 login prompt (multi-user.target) or graphical login (graphical.target)
```

### 1. Firmware

On power-on the CPU runs firmware stored on the motherboard. Older machines use **BIOS**, which reads the first
sector of the boot disk (the MBR) and jumps to the small boot loader stub there. Modern machines use **UEFI**,
which understands GPT partition tables and FAT file systems, and runs a boot program from the **EFI System
Partition** (ESP), mounted on RHEL at `/boot/efi`. With Secure Boot, UEFI first runs `shimx64.efi` (signed by
Microsoft and Red Hat), which verifies and runs `grubx64.efi`.

### 2. GRUB 2

GRUB reads its configuration, shows a menu (by default for 5 seconds on RHEL, often hidden until you press a
key), and loads the selected **kernel** (`/boot/vmlinuz-VERSION`) and **initramfs**
(`/boot/initramfs-VERSION.img`) into memory, then hands over control, passing a **kernel command line** such as
`root=/dev/mapper/rhel-root ro crashkernel=... rd.lvm.lv=rhel/root rhgb quiet`.

RHEL uses **Boot Loader Specification** (BLS) entries: one small file per installed kernel in
`/boot/loader/entries/`. The menu is built from those. You edit them persistently with `grubby`, and you can
edit the selected entry **temporarily**, for one boot, by pressing `e` at the menu. Both matter on the exam;
the persistent side is Lecture 7, objective 7.6.

### 3–4. Kernel and initramfs

The kernel cannot mount the root file system on its own if that requires drivers or setup that are not built in
(an NVMe or virtio driver, LVM, LUKS encryption, RAID). The **initramfs** ("initial RAM file system") is a
compressed archive containing a minimal Linux userland: systemd, udev, the needed modules, LVM tools and a few
scripts. The kernel unpacks it into memory and runs it. Its job is to find the real root file system, which the
`root=` and `rd.*` arguments describe, and mount it **read-only** at `/sysroot`.

`dracut` builds the initramfs (`dracut -f` rebuilds the current one). A new kernel package builds its own
automatically.

### 5–6. switch_root and systemd

When the real root is ready, the initramfs performs `switch_root`: `/sysroot` becomes `/`, the RAM copy is
discarded, and `/usr/lib/systemd/systemd` from the real root takes over as **PID 1**, the ancestor of every other
process. systemd remounts `/` read-write (as configured in fstab), and starts activating units towards the
**default target**.

### systemd units and targets in one page

systemd manages **units**, each described by a file:

| Unit type | Represents | Example |
|---|---|---|
| `.service` | a daemon or a one-off job | `sshd.service`, `chronyd.service` |
| `.target` | a group of units, a synchronisation point / system state | `multi-user.target` |
| `.mount`, `.swap` | a mount point / swap area (fstab lines are converted into these) | `home.mount` |
| `.socket` | a listening socket that starts a service on demand | `cockpit.socket` |
| `.timer` | a schedule that starts a service | `dnf-makecache.timer` |
| `.path`, `.device`, `.slice`, `.scope` | path watches, devices, cgroup groupings | |

Unit files live in `/usr/lib/systemd/system/` (installed by packages, don't edit), `/etc/systemd/system/`
(yours, and overrides; wins over `/usr/lib`), and `/run/systemd/system/` (runtime).

Units declare **dependencies**: `Wants=` and `Requires=` (pull another unit in), `Before=`/`After=` (ordering
only), and in the `[Install]` section `WantedBy=` (when *enabled*, become a want of that target). A **target** is
just a unit that pulls in a set of others. The important ones:

| Target | State | Old SysV runlevel |
|---|---|---|
| `poweroff.target` | shut down | 0 |
| `rescue.target` | single-user: base system, local file systems mounted, root shell, no network or most services | 1 |
| `multi-user.target` | full system, text logins, network services | 3 |
| `graphical.target` | multi-user plus a graphical login | 5 |
| `reboot.target` | reboot | 6 |
| `emergency.target` | the bare minimum: root file system mounted **read-only**, root shell, nothing else | (none) |

Targets nest: `graphical.target` requires `multi-user.target`, which requires `basic.target`, and so on.
`systemctl list-dependencies graphical.target` shows the tree. `default.target` is a symlink to the one the
system boots into.

---

## 4.1 Boot, reboot, and shut down a system normally

### Shutting down is a process, not an event

When you ask for a shutdown, systemd activates `poweroff.target` (or `reboot.target`). That stops every unit in
reverse dependency order: services are sent `SIGTERM` and given time to exit cleanly (`SIGKILL` after a timeout,
90 seconds by default), file systems are unmounted, buffered data is flushed to disk, and finally the kernel
powers off or restarts the machine. **A normal shutdown is what keeps file systems and databases consistent.**
Pulling the plug (or a hard reset of a VM) skips all of that; XFS and ext4 journals make recovery likely, but
data in flight can be lost.

### The commands

```bash
systemctl poweroff          # halt and power off
systemctl reboot            # restart
systemctl halt              # stop the system but don't power off (rarely wanted)
systemctl suspend           # sleep (laptops)

shutdown -h now             # same as poweroff ("now" is required)
shutdown -r now             # reboot
shutdown -r +10 "Kernel update, back in 5 min"   # in 10 minutes, broadcasting a message
shutdown -r 23:30           # at a time
shutdown -c                 # cancel a pending shutdown

poweroff ; reboot ; halt    # short forms, symlinks to systemctl
```

`shutdown` with a delay warns logged-in users and, in the last five minutes, blocks new logins (by creating
`/run/nologin`).

Ordinary users usually need `sudo`. Locally logged-in desktop users may be allowed by polkit to reboot without
it.

### Booting

There is nothing to *do* to boot normally, but you should know what normal looks like, so you recognise a
problem: the GRUB menu (press an arrow key early if it is hidden), the kernel and systemd messages (press `Esc`
during the graphical splash to see them, or remove `rhgb quiet` from the command line), then a login prompt.

After any boot, these tell you what happened:

```bash
systemctl is-system-running     # running, degraded (some unit failed), maintenance...
systemctl --failed              # which units failed
journalctl -b                   # everything logged during this boot
journalctl -b -1 -p err         # errors from the previous boot (needs a persistent journal, 4.8)
last reboot                     # history of boots
uptime                          # how long since this boot, and load averages
who -b                          # time of last boot
systemd-analyze blame           # which units took longest to start
```

> **Exam angle.** Your work is graded after a reboot. Reboot yourself, mid-exam, after storage and boot
> changes, and check `systemctl --failed` and every mount. Finding a typo with time left is far better than
> the grader finding it.

---

## 4.2 Boot systems into different targets manually

### Switching target on a running system

```bash
systemctl get-default                  # what the system boots into
systemctl isolate multi-user.target    # switch now: stop everything not needed by it
systemctl isolate graphical.target     # start the desktop
systemctl rescue                       # same as isolate rescue.target
systemctl emergency
systemctl default                      # go to the default target (e.g. from rescue)
```

`isolate` starts the named target and its dependencies **and stops all units not required by it**. Only targets
marked `AllowIsolate=yes` can be isolated (all the standard ones are). Changing the default for future boots is
`systemctl set-default`, objective 7.3 in Lecture 7.

### Choosing a target at boot time, from GRUB

To boot into a different target for **one boot** only, edit the kernel command line in GRUB:

1. Reboot. When the GRUB menu appears, use the arrow keys to stop the countdown and highlight the entry.
2. Press **`e`** to edit it. You see the BLS entry's lines; find the one starting with **`linux`** (on some
   systems `linux16` or `linuxefi`). It may wrap; use `End` or `Ctrl+E` to jump to the end of the line.
3. Append a space and **`systemd.unit=rescue.target`** (or `emergency.target`, `multi-user.target`).
4. Press **`Ctrl+X`** to boot with the edited line (`F10` also works). `Esc` discards the edit.

The edit is not saved; the next boot is normal again.

Shortcuts: the words `rescue` (or `single`, `s`, `1`) and `emergency` (`-b`) on the kernel line are also
understood by systemd and select those targets.

### Rescue versus emergency

| | `rescue.target` | `emergency.target` |
|---|---|---|
| Root file system | mounted **read-write** | mounted **read-only** |
| Other fstab file systems | mounted | **not** mounted |
| Services | basic system only (no network) | nothing |
| Asks for | root password | root password |
| Use it when | you need a quiet system to repair something | something in the normal boot (a bad fstab line, a broken unit) prevents even rescue from working |

In emergency mode, before changing files, remount root read-write: `mount -o remount,rw /`. A broken fstab
entry is the classic reason a system drops into emergency mode by itself; you will see "You are in emergency
mode. After logging in, type `journalctl -xb` to view system logs...".

Both require the **root password** (via `sulogin`). If you do not have it, you need 4.3.

---

## 4.3 Interrupt the boot process in order to gain access to a system

### The situation

You have console access but not the root password (or root's account is locked, or the password is wrong).
Rescue and emergency mode ask for it, so they are no help. Instead, you stop the boot **inside the initramfs**,
before the real system's authentication exists, get a root shell there, and change the password in the real
root file system.

Physical (or console) access is the security boundary here: anyone at the console can do this unless GRUB is
password-protected and the disk is encrypted. That is by design for recoverability.

### Method 1: rd.break (the Red Hat method)

`rd.break` is a dracut option meaning "break into a shell at the end of the initramfs, just before
switch_root". At that moment the real root file system is mounted at `/sysroot`, **read-only**.

```text
1. Reboot. At the GRUB menu, highlight the entry and press  e
2. On the line starting with  linux , append:  rd.break
   (on a VM or cloud image with a serial console setting, also remove console=ttyS0... if the
   shell appears on the wrong console)
3. Ctrl+X to boot.  You get a  switch_root:/#  prompt.
```

Then, at that prompt:

```bash
mount -o remount,rw /sysroot     # it is mounted read-only; we need to write
chroot /sysroot                  # make /sysroot appear as / for the following commands
passwd root                      # set the new password (writes /etc/shadow)
touch /.autorelabel              # ask for an SELinux relabel at next boot (see below)
exit                             # leave the chroot
exit                             # leave the initramfs shell: boot continues
```

What each step is for:

- **remount,rw**: the initramfs mounts the real root read-only (systemd remounts it read-write later, during the
  normal boot). Without this, `passwd` fails with "Authentication token manipulation error".
- **chroot /sysroot**: in the initramfs, `/etc/shadow` is the initramfs's own (non-existent) one, and `passwd`
  is not even there. `chroot` starts a shell whose `/` is `/sysroot`, so `passwd` is the real system's binary and
  edits the real system's `/etc/shadow`.
- **passwd**: writes a new hash for root into `/etc/shadow`. It does so by creating a new file and renaming it
  over the old one.
- **touch /.autorelabel**: this is the step people forget, and here is why it is essential. SELinux labels every
  file. The real `/etc/shadow` is labelled `shadow_t`, and the login programs are only allowed to read files of
  that type. But in the initramfs, **SELinux policy is not loaded**, so when `passwd` created the new
  `/etc/shadow`, it got no proper label (it shows as `unlabeled_t`). When the system boots with SELinux
  enforcing, nothing can read the password file, and **every login fails**, including root's, even with the
  right password. `/.autorelabel` makes systemd relabel the whole file system during the next boot (which takes a
  minute or two and then reboots once more by itself), restoring the correct label on `/etc/shadow`.
- **exit, exit**: the first leaves the chroot, the second leaves the dracut shell, and booting continues.

An alternative to the full relabel, which is faster on a big disk: boot with `rd.break enforcing=0`, do the same
steps without `touch /.autorelabel`, and once the system is up and you are logged in as root, run
`restorecon -v /etc/shadow` and `setenforce 1`. The relabel approach is simpler to remember and safe.

### Method 2: init=/bin/bash

Instead of `rd.break`, append `init=/bin/bash` to the `linux` line. The kernel then runs bash as PID 1 from the
**real** root file system (after the initramfs has mounted it read-only), instead of systemd:

```bash
mount -o remount,rw /
passwd root
touch /.autorelabel
exec /sbin/init            # hand over to systemd and continue booting (or: sync; reboot -f)
```

No chroot is needed, because `/` is already the real root. Because systemd is not running, `reboot` the normal way
does not work; `exec /sbin/init` replaces bash with systemd and boots normally.

### Practical problems and how to recognise them

- **"The GRUB menu doesn't appear."** RHEL hides it when the last boot succeeded. Press `Esc`, `Shift` or an
  arrow key repeatedly right after power-on. In a VM, click into the console window first so it gets your keys.
- **The edited line is long and wraps.** It is one logical line; add your argument at the very end, after
  `quiet` or whatever is last, with a space before it.
- **You get no shell, or the shell appears and disappears.** Cloud images often send the console to a serial
  port (`console=ttyS0`). Remove `console=` arguments for the VGA console, or vice versa.
- **The new password does not work after the reboot.** You forgot `/.autorelabel` (SELinux), or you typed the
  password with a different keyboard layout in the initramfs.
- **On UEFI with Secure Boot** everything above works the same.

> **Exam angle.** "Reset the root password of server2 to `redhat`" is a near-certain task, and it may also be
> the precondition for doing anything on that machine at all. Practise until you can do it in three minutes
> without notes. Lab 05 task 1 makes you do it for real.

---

## 4.4 Identify CPU/memory intensive processes and kill processes

### What a process is

A **process** is a running instance of a program: an address space with code and data, one or more threads, a
set of open files, credentials (UID, GID, groups, SELinux context), an environment, a current directory, and a
**PID**. Every process except PID 1 has a parent (**PPID**). New processes are created by **fork** (the parent
clones itself) followed by **exec** (the clone replaces its program with a new one); that is exactly what the
shell does to run each command. When a process exits, it leaves an exit status for its parent to collect.

`pstree -p` shows the family tree rooted at systemd. Process information comes from the kernel's virtual
`/proc` file system: `/proc/PID/status`, `/proc/PID/cmdline`, `/proc/PID/fd/`. Every tool below reads it.

### Process states

| `ps` code | State | Meaning |
|---|---|---|
| `R` | running / runnable | on a CPU or waiting in the run queue |
| `S` | interruptible sleep | waiting for an event (input, a timer); most processes, most of the time |
| `D` | uninterruptible sleep | waiting on I/O inside the kernel; cannot be killed until it returns (stuck NFS, failing disk) |
| `T` | stopped | paused by a signal (`Ctrl+Z`, `SIGSTOP`) |
| `Z` | zombie | has exited, but the parent has not collected its status yet; uses no resources except a table entry |

You cannot kill a zombie (it is already dead); its parent must reap it, or the parent must exit so systemd
adopts and reaps it.

### Load average

`uptime` and `top` show three **load averages**: the average number of processes that are runnable **or in
uninterruptible sleep**, over the last 1, 5 and 15 minutes. Compare it with the number of CPUs (`nproc`): a
load of 4.0 on a 4-CPU machine means it is fully busy; 8.0 means processes are queueing. A high load with idle
CPUs means processes are stuck in `D` state, typically waiting on storage.

### CPU and memory figures

- **%CPU** in `ps` is CPU time used divided by the process's lifetime; in `top` it is the share over the last
  refresh interval. A single-threaded process spinning on one core shows ~100%; multithreaded ones can exceed it.
- **VSZ / VIRT**: virtual memory size, everything mapped, including shared libraries and memory reserved but
  never touched. Usually large and misleading.
- **RSS / RES**: resident set size, the physical RAM actually in use. This is the figure that matters for
  "memory-intensive".
- **%MEM**: RSS as a percentage of total RAM.

System-wide: `free -h` shows total, used, free, and **available**. Linux uses spare RAM as a cache for files
(`buff/cache`), so "free" is often low on a healthy machine; "available" is the honest estimate of what can be
given to programs.

### Finding the heavy hitters

```bash
top                     # interactive. Keys: P sort by CPU, M by memory, k kill, r renice,
                        #   1 per-CPU, u filter by user, c full command, q quit
ps aux --sort=-%cpu | head -5
ps aux --sort=-%mem | head -5
ps -eo pid,ppid,user,ni,%cpu,%mem,rss,stat,cmd --sort=-rss | head
ps -fp 1234             # one PID, full format
ps -u harry             # one user's processes
pgrep -a sshd           # PIDs matching a name, with command lines
pgrep -u harry -l       # by user
pidof httpd
```

`ps aux` (BSD style) and `ps -ef` (System V style) both show every process. `-o` lets you choose columns, and
`--sort=-field` sorts descending.

### Signals and killing

Processes are controlled with **signals**, small numbered messages from the kernel. A process can catch most
signals and decide what to do; two it cannot catch.

| Signal | Number | Default effect | Typical use |
|---|---|---|---|
| `SIGHUP` | 1 | terminate | "reload your config" for many daemons; also sent when a terminal closes |
| `SIGINT` | 2 | terminate | `Ctrl+C` |
| `SIGKILL` | 9 | **terminate immediately, cannot be caught** | last resort |
| `SIGTERM` | 15 | terminate (catchable: the process can clean up) | **the default** for `kill` |
| `SIGCONT` | 18 | continue a stopped process | |
| `SIGSTOP` | 19 | **pause, cannot be caught** | |
| `SIGTSTP` | 20 | pause (catchable) | `Ctrl+Z` |

```bash
kill 1234               # SIGTERM: please exit
kill -9 1234            # SIGKILL: die now (no cleanup: temp files, locks, half-written data remain)
kill -SIGHUP 1234       # or kill -HUP, kill -1
kill -l                 # list signals
pkill -u harry          # by user
pkill -t pts/2          # by terminal (log someone out)
pkill -9 -f 'python3 hog.py'   # match against the full command line
killall httpd           # by exact process name
```

Good practice: try `SIGTERM` first, wait a few seconds, check with `ps`, then use `SIGKILL`. A process in `D`
state ignores even `SIGKILL` until its I/O completes.

**Services are different.** Killing a service's main process may simply make systemd restart it (if
`Restart=` is set), and it leaves the unit in a failed state. Stop services with `systemctl stop` and signal them
with `systemctl kill -s HUP unit`.

> **Exam angle.** "Find the process consuming the most CPU and kill it" or "...terminate all processes of user
> X". Verify afterwards: `ps -p PID` should show nothing.

---

## 4.5 Adjust process scheduling

### How the scheduler shares CPUs

On a busy system, more threads want to run than there are CPUs. The kernel's scheduler decides who runs next and
for how long. For ordinary processes (policy `SCHED_OTHER`) the Linux scheduler aims to give each runnable task
a **fair share** of CPU time, weighted by its **nice value**. (The algorithm changed from CFS to EEVDF in recent
kernels, including RHEL 10's, but the nice semantics are the same.)

**Niceness** ranges from **-20** (highest priority, "least nice to others") to **19** (lowest priority, "very
nice"), default 0. It is not a strict priority: a nice-19 process still runs, but each step in niceness changes a
task's weight by roughly 25%, so a nice-0 process competing with a nice-19 process gets the overwhelming majority
of a CPU. Nice only matters when there is **contention**; on an idle CPU a nice-19 job runs at full speed.

`top` shows `NI` (niceness) and `PR` (the kernel's priority, `20 + NI` for normal tasks). `ps -o pid,ni,cmd`
shows niceness.

### Setting and changing niceness

```bash
nice -n 10 tar -czf /backup/home.tar.gz /home   # start a command with niceness 10
nice tar ...                                    # default increment: 10
nice -n -5 important-job                        # negative: root only

renice -n 5 -p 1234                  # change a running process
renice -n 19 -u harry                # all of harry's processes
renice -n -10 -p 1234                # raise priority: root only
```

Permissions:

- Anyone can make their own processes **nicer** (raise the number).
- Only root (or a process with `CAP_SYS_NICE`) can **lower** niceness below its current value or set it below 0.

Interactive: in `top`, press `r`, type the PID and the new nice value.

`nice` affects a **new** process; `renice` affects one that **already runs**. A child process inherits its
parent's niceness, so a shell started with `nice` runs everything nicely.

For completeness: real-time policies (`SCHED_FIFO`, `SCHED_RR`, set with `chrt`) always run before normal tasks,
and I/O priority is set separately with `ionice`. Neither is in the objective.

> **Exam angle.** "Start command X with a niceness of 15" (`nice -n 15 X &`) or "set the niceness of the running
> process Y to 10" (`renice -n 10 -p $(pgrep Y)`). Read whether the task says *priority* or *niceness*, and
> verify with `ps -o pid,ni,comm -p PID`.

---

## 4.6 Manage tuning profiles

### What tuned does

A Linux system has hundreds of tunables: CPU frequency governors and energy-performance preferences, disk I/O
schedulers and read-ahead, kernel virtual memory settings (`vm.swappiness`, dirty page ratios), network buffer
sizes, transparent huge pages, and so on. The best values depend on the workload: a database server, a
latency-sensitive trading box, a laptop on battery and a VM all want different trade-offs.

**tuned** is a daemon that applies coordinated sets of these settings, called **profiles**, and can adjust some
of them dynamically. Profiles are directories containing `tuned.conf`, which may `include=` another profile and
set values through plug-ins (`[cpu]`, `[disk]`, `[sysctl]`, `[vm]`, `[scheduler]`...).

| Location | Contents |
|---|---|
| `/usr/lib/tuned/profiles/` (or `/usr/lib/tuned/`) | profiles shipped with the package |
| `/etc/tuned/profiles/` (or `/etc/tuned/`) | your custom profiles (same name overrides the shipped one) |
| `/etc/tuned/active_profile` | the profile currently selected |
| `/etc/tuned/tuned-main.conf` | daemon settings (dynamic tuning on/off, etc.) |

Common profiles:

| Profile | For |
|---|---|
| `balanced` | general use: compromise between performance and power (typical default for desktops/laptops) |
| `powersave` | maximum power saving |
| `throughput-performance` | servers: maximum throughput (typical default for bare-metal servers) |
| `latency-performance`, `network-latency` | low latency at the cost of power |
| `network-throughput` | high-bandwidth networking |
| `virtual-guest` | a VM: throughput-performance plus guest-specific tweaks (typical default in VMs) |
| `virtual-host` | a hypervisor running VMs |
| `accelerator-performance`, `hpc-compute`, `desktop`, `optimize-serial-console` | specialised |

### Using it

```bash
dnf install tuned                      # usually already installed
systemctl enable --now tuned           # the daemon must run, and run at boot
tuned-adm list                         # available profiles, and the active one
tuned-adm active                       # current profile
tuned-adm recommend                    # what tuned thinks fits this hardware
tuned-adm profile throughput-performance   # switch (persists across reboots)
tuned-adm profile virtual-guest powersave  # several can be merged
tuned-adm profile_info virtual-guest
tuned-adm verify                       # are the profile's settings actually in effect?
tuned-adm off                          # stop tuning (settings revert)
```

`tuned-adm recommend` bases its answer on rules in `recommend.conf`: virtualisation detected, chassis type and so
on. The active profile is stored in `/etc/tuned/active_profile`, so a profile set with `tuned-adm profile`
survives a reboot **provided the tuned service is enabled**.

On RHEL 10 desktops, `tuned-ppd` can translate the desktop's power-profile switch (power saver / balanced /
performance) into tuned profiles; on servers you use `tuned-adm` directly.

A custom profile is just a directory:

```bash
mkdir /etc/tuned/myprofile
cat > /etc/tuned/myprofile/tuned.conf <<'EOF'
[main]
include=throughput-performance
[sysctl]
vm.swappiness=10
EOF
tuned-adm profile myprofile
```

> **Exam angle.** "Set the recommended tuning profile" means: `tuned-adm recommend`, then `tuned-adm profile`
> with that name, and make sure `tuned` is enabled. Check with `tuned-adm active`.

---

## 4.7 Locate and interpret system log files and journals

### The logging architecture

RHEL has two cooperating logging systems plus a separate audit log:

```text
 kernel (printk) ──────────┐
 programs: syslog() API ───┤
 services' stdout/stderr ──┼──► systemd-journald ──► journal files (binary, indexed)
 sd_journal API ───────────┘          │                /run/log/journal  (volatile)
                                      │                /var/log/journal  (persistent)
                                      ▼
                               rsyslogd (imjournal) ──► /var/log/messages, secure, cron, maillog, boot.log...
                                                         (text, rotated by logrotate)
 kernel audit subsystem ──► auditd ──► /var/log/audit/audit.log   (SELinux denials, logins, audit rules)
```

- **systemd-journald** collects every message on the system. It records each as a structured entry with many
  fields: the message, priority, timestamp, and trusted metadata it adds itself: `_PID`, `_UID`, `_COMM`,
  `_SYSTEMD_UNIT`, `_BOOT_ID`, `_HOSTNAME`, `_SELINUX_CONTEXT`. Because it captures services' stdout and stderr,
  even a program that never heard of syslog gets logged under its unit.
- **rsyslog** reads from the journal and writes traditional text files according to `/etc/rsyslog.conf` and
  `/etc/rsyslog.d/*.conf`. It can also forward logs to a central server.
- **auditd** writes the kernel's audit records, including SELinux AVC denials (Lecture 10), to
  `/var/log/audit/audit.log`.

### Syslog priorities and facilities

Every message has a **priority** (severity), and syslog messages also a **facility** (source category). Both are
used for filtering in rsyslog and journalctl.

| Priority | Number | |
|---|---|---|
| `emerg` | 0 | system unusable |
| `alert` | 1 | act immediately |
| `crit` | 2 | critical |
| `err` | 3 | error |
| `warning` | 4 | warning |
| `notice` | 5 | normal but significant |
| `info` | 6 | informational |
| `debug` | 7 | debugging |

Facilities include `kern`, `user`, `mail`, `daemon`, `auth`, `authpriv`, `cron`, `local0`–`local7`. An rsyslog rule
pairs a selector with a destination:

```text
*.info;mail.none;authpriv.none;cron.none    /var/log/messages
authpriv.*                                  /var/log/secure
mail.*                                      -/var/log/maillog
cron.*                                      /var/log/cron
*.emerg                                     :omusrmsg:*
local7.*                                    /var/log/boot.log
```

`facility.priority` means "this priority **or higher**" (`*.info` includes `err`); `.none` excludes a facility.
So on RHEL: general messages go to `/var/log/messages`, **authentication and sudo to `/var/log/secure`**, cron to
`/var/log/cron`, mail to `/var/log/maillog`. After editing rsyslog's config, `systemctl restart rsyslog`.

`logger` writes a test message: `logger -p local0.err -t mytag "hello"`.

The files are rotated by **logrotate** (a daily timer; config in `/etc/logrotate.conf` and
`/etc/logrotate.d/`), producing `messages-20261101` and so on.

### Reading text logs

```bash
tail -f /var/log/messages            # follow live
less /var/log/secure                 # / to search, G to the end
grep -i 'fail' /var/log/secure
grep sshd /var/log/secure | tail
```

Each line: timestamp, hostname, program[PID], message:
`Nov  7 09:14:02 server1 sshd[1532]: Failed password for harry from 192.168.50.1 port 51234 ssh2`.

### journalctl: querying the journal

```bash
journalctl                       # everything, oldest first, in a pager (G jumps to end)
journalctl -e                    # jump to the end
journalctl -f                    # follow
journalctl -n 50                 # last 50 entries
journalctl -r                    # newest first
journalctl -b                    # this boot; -b -1 previous boot; --list-boots
journalctl -u sshd               # one unit (.service may be omitted)
journalctl -u httpd --since "2026-11-07 09:00" --until "10 min ago"
journalctl --since today         # also: yesterday, "1 hour ago"
journalctl -p err                # priority err and worse (0-3); -p warning..err for a range
journalctl -t payroll-sync       # by syslog identifier (tag)
journalctl -k                    # kernel messages (like dmesg)
journalctl _PID=1234             # by any field
journalctl _UID=1000
journalctl _COMM=sudo
journalctl /usr/sbin/sshd        # by executable
journalctl -o verbose            # every field of each entry
journalctl -o json-pretty
journalctl -xe                   # end of the log, with explanatory text for known messages
journalctl -u sshd -p warning -b --no-pager | grep -i fail
```

Filters combine with AND (different fields) or OR (the same field twice). Tab completion works for field names
and values: type `journalctl _SYSTEMD_UNIT=` and press Tab twice.

Members of the `wheel`, `adm` and `systemd-journal` groups can read the whole journal; other users see only their
own entries.

### Interpreting what you find

Logs are for answering a question, so start from the question. A service won't start: `systemctl status unit`
(which shows the last log lines) then `journalctl -u unit -b`. A login fails: `/var/log/secure` or
`journalctl -t sshd -t sudo`. Something is denied but permissions look right: SELinux,
`ausearch -m AVC -ts recent` (Lecture 10). Boot trouble: `journalctl -b -1 -p err` on the next successful boot
(needs persistence, 4.8).

---

## 4.8 Preserve system journals

### Where the journal is stored, and why it may vanish

journald's storage mode is set by `Storage=` in `/etc/systemd/journald.conf` (or a drop-in in
`/etc/systemd/journald.conf.d/*.conf`):

| `Storage=` | Behaviour |
|---|---|
| `volatile` | only in memory, under `/run/log/journal/` (lost at reboot) |
| `persistent` | on disk under `/var/log/journal/` (creates the directory if needed), falls back to `/run` early in boot |
| `auto` (the default) | persistent **if `/var/log/journal/` exists**, otherwise volatile |
| `none` | keep nothing (still forwards to rsyslog) |

With `auto`, whether a RHEL system keeps its journal across reboots depends on whether `/var/log/journal`
exists. Check: `journalctl --list-boots` shows only one boot if the journal is volatile, and `ls /var/log/journal`
fails. Do not assume; configure it when asked.

### Making it persistent

Either approach works; the second is more explicit:

```bash
# A) rely on Storage=auto: create the directory with the right group and ACLs
mkdir -p /var/log/journal
systemd-tmpfiles --create --prefix /var/log/journal
systemctl restart systemd-journald     # or: journalctl --flush

# B) set it explicitly
mkdir -p /etc/systemd/journald.conf.d
cat > /etc/systemd/journald.conf.d/persistent.conf <<'EOF'
[Journal]
Storage=persistent
EOF
systemctl restart systemd-journald
```

Then confirm: `ls /var/log/journal/` shows a directory named after the machine ID, containing
`system.journal`, and `journalctl --disk-usage` reports space used there. After the next reboot,
`journalctl --list-boots` lists more than one boot and `journalctl -b -1` works.

`journalctl --flush` asks journald to move the in-memory journal from `/run` to `/var` now.

### Size limits and maintenance

Persistent journals are limited by default to 10% of the file system (capped at 4 GiB) and keep 15% free.
Override with `SystemMaxUse=`, `SystemKeepFree=`, `SystemMaxFileSize=`, `MaxRetentionSec=`. Clean up manually with:

```bash
journalctl --disk-usage
journalctl --vacuum-size=500M
journalctl --vacuum-time=2weeks
journalctl --rotate
```

> **Exam angle.** "Configure the journal to be preserved across reboots." Do either method above, restart
> journald, and check `/var/log/journal` has content. It is quick and easy marks.

---

## 4.9 Start, stop, and check the status of network services

### Services are systemd units

A network service such as `sshd`, `httpd`, `chronyd`, `nfs-server` or `named` is a daemon managed by a
`.service` unit. The unit file says how to start it (`ExecStart=`), what kind of process it is (`Type=`),
whether to restart it on failure, and which target it belongs to when enabled.

```bash
systemctl status sshd          # the most useful single command
systemctl start httpd
systemctl stop httpd
systemctl restart httpd        # stop + start (drops connections)
systemctl reload httpd         # re-read config without stopping, if the service supports it
systemctl reload-or-restart httpd
systemctl is-active httpd      # active / inactive / failed (exit status 0 only when active)
systemctl is-failed httpd
systemctl list-units --type=service              # loaded and running
systemctl list-units --type=service --state=failed
systemctl kill -s HUP rsyslog
```

Starting and stopping affects **now** only. Starting at boot (`enable`) is objective 7.2 in Lecture 7;
`systemctl enable --now` does both.

### Reading `systemctl status`

```text
● httpd.service - The Apache HTTP Server
     Loaded: loaded (/usr/lib/systemd/system/httpd.service; enabled; preset: disabled)
     Active: active (running) since Sat 2026-11-07 09:30:12 UTC; 5min ago
       Docs: man:httpd.service(8)
   Main PID: 2210 (httpd)
     Status: "Total requests: 3; Idle/Busy workers 100/0;Requests/sec: 0.01"
      Tasks: 177 (limit: 22952)
     Memory: 21.4M
        CPU: 312ms
     CGroup: /system.slice/httpd.service
             ├─2210 /usr/sbin/httpd -DFOREGROUND
             ├─2211 /usr/sbin/httpd -DFOREGROUND
             ...
Nov 07 09:30:12 server1 systemd[1]: Starting The Apache HTTP Server...
Nov 07 09:30:12 server1 httpd[2210]: Server configured, listening on: port 80
Nov 07 09:30:12 server1 systemd[1]: Started The Apache HTTP Server.
```

- **Loaded**: where the unit file is, whether it is **enabled** at boot, and the vendor preset.
- **Active**: `active (running)`, `inactive (dead)`, `failed` (with a result such as `exit-code`), or
  `activating`.
- **Main PID** and the **CGroup** tree: every process belonging to the service. systemd tracks services by
  control group, so it can stop all their processes reliably.
- The **last log lines**: usually the reason a failed service failed. `journalctl -u httpd -b` shows more.

The coloured dot (●) is green when active, red when failed, white when inactive.

### Diagnosing a service that will not start

A methodical loop:

1. `systemctl status unit` and `journalctl -u unit -b -n 50`: read the actual error.
2. Check the configuration with the service's own tester: `httpd -t` (or `apachectl configtest`), `sshd -t`,
   `named-checkconf`, `nginx -t`, `chronyd -p`.
3. Is the port already in use, or blocked by SELinux? `ss -tlnp | grep :80`;
   `ausearch -m AVC -ts recent` (a non-standard port needs `semanage port`, Lecture 10).
4. Fix, then `systemctl restart unit` and recheck. After editing a **unit file**, run
   `systemctl daemon-reload` first.

A unit that failed repeatedly may hit its start-rate limit ("start request repeated too quickly");
`systemctl reset-failed unit` clears that.

### Seeing what is listening

```bash
ss -tulpn             # TCP and UDP, listening sockets, numeric, with process names (root for -p)
ss -tlnp 'sport = :22'
ss -tn state established
```

`0.0.0.0:80` or `*:80` means "all IPv4/all addresses"; `127.0.0.1:631` means local only; `[::]:22` is IPv6 all.
If a service is running but clients cannot connect, check it listens on the right address and port here, then
check the firewall (Lecture 8) and SELinux.

**Socket activation:** some services are started on demand by a `.socket` unit that listens on their behalf
(for example `cockpit.socket`). The service may look inactive until the first connection arrives; enable and
start the socket rather than the service.

---

## 4.10 Securely transfer files between systems

All three tools below run over SSH, so they use the same authentication (passwords or keys, Lecture 10) and
encryption as `ssh`, and need `sshd` on the remote side.

### scp

`scp` copies like `cp`, with `user@host:` in front of remote paths:

```bash
scp report.txt sally@server2:                  # to sally's home directory (note the trailing colon)
scp report.txt sally@server2:/tmp/             # to a directory
scp sally@server2:/home/sally/data.csv /root/  # download
scp -r /etc/httpd sally@server2:backup/        # recursive (a directory)
scp -p file host:                              # preserve modes and times
scp -P 2222 file host:                         # port: capital P for scp (ssh uses -p)
scp host1:/a host2:/b                          # between two remote hosts
```

Without a trailing `:`, `server2` is just a local file name: `scp file server2` makes a local copy called
`server2`. On RHEL 9 and 10, `scp` uses the SFTP protocol underneath by default (the old SCP protocol had design
flaws); `scp -O` forces the legacy protocol if an old server needs it.

### sftp

`sftp` gives an interactive FTP-like session over SSH:

```text
$ sftp sally@server2
sftp> pwd               remote directory          sftp> lpwd       local directory
sftp> ls                                          sftp> lls
sftp> cd outbox                                   sftp> lcd /root
sftp> get data.csv      download                  sftp> put report.txt     upload
sftp> mget *.log        sftp> mput *.txt          sftp> mkdir new
sftp> bye
```

Commands prefixed with `l` act locally. `sftp host:path/file` downloads directly, and `sftp -b batchfile host`
runs a scripted session.

### rsync

`rsync` synchronises files efficiently: it compares source and destination and transfers only differences, and it
can resume. Over the network it runs over SSH by default:

```bash
rsync -av /var/www/ server2:/var/www/          # archive mode, verbose
rsync -avz --delete src/ host:dst/             # compress; delete files gone from the source
rsync -avn src/ host:dst/                      # dry run: show what would happen
rsync -aAX src/ host:dst/                      # also ACLs and extended attributes (SELinux labels)
```

`-a` preserves permissions, owners, times, symlinks and recurses. **The trailing slash on the source matters**:
`src/` copies the contents of `src`; `src` copies the directory itself into the destination. rsync must be
installed on both ends.

> **Exam angle.** "Copy /root/file to /tmp on serverb as user X", or "retrieve a file from the other server".
> Check the result with `ssh user@host ls -l path`. Remember files you copy keep the remote user's ownership and
> are labelled by SELinux according to the destination.

---

## Putting it together

Imagine the start of an exam where server2 is "broken". You open its console: it drops to emergency mode and
asks for a root password you don't have. You interrupt GRUB, add `rd.break`, remount `/sysroot` read-write,
chroot, `passwd`, `touch /.autorelabel`, and exit twice. The relabel runs and the system reboots, and drops to
emergency mode again; now you can log in. `journalctl -xb -p err` shows a mount unit failing; a bad line in
`/etc/fstab` (Lecture 5). You fix it, `systemctl daemon-reload`, `mount -a`, `systemctl default`. Then you
make the journal persistent so you could investigate the next boot problem from logs, set the recommended tuned
profile, and verify the services the task lists with `systemctl status` and `ss -tlnp`. Every step is an
objective from this lecture.

**Now practise:** [Lab 04](#/lab/04) for processes, priorities, tuned, logs and services, and [Lab 05](#/lab/05)
on the VM for the password reset and targets.

## Review questions

1. List the stages from power-on to a login prompt, and say what the initramfs is for.
2. What is the practical difference between `rescue.target` and `emergency.target`?
3. How do you boot once into `multi-user.target` on a system that defaults to graphical?
4. Explain each step of the `rd.break` password reset, and what goes wrong without `/.autorelabel`.
5. With `init=/bin/bash`, why is `chroot` unnecessary and how do you continue booting?
6. A machine has 2 CPUs and a load average of 6.0, but `top` shows the CPUs 90% idle. What is likely happening?
7. Which memory figure identifies a memory-hungry process, and why is VSZ misleading?
8. What is the difference between `kill PID` and `kill -9 PID`? Why prefer the first?
9. A regular user tries `renice -n -5 -p 4321` on their own process and fails. Why?
10. How do you choose and apply the tuning profile tuned recommends, and make sure it survives a reboot?
11. Where do sudo and SSH login messages go in the text logs?
12. Write a journalctl command for error-or-worse messages from `httpd` during the previous boot. What must be
    configured for it to work?
13. What does `Storage=auto` do, and what are two ways to make the journal persistent?
14. In `systemctl status`, where do you see whether a service starts at boot?
15. `scp file server2` "worked" but nothing arrived on server2. Why?

<details><summary>Answers</summary>

1. Firmware (BIOS/UEFI) → GRUB 2 loads kernel and initramfs → kernel → initramfs mounts the real root at
   `/sysroot` → switch_root → systemd (PID 1) activates the default target → login. The initramfs provides the
   drivers and tools needed to find and mount the root file system.
2. Rescue mounts all local file systems read-write and starts a basic system; emergency mounts only root,
   read-only, and starts nothing else.
3. At GRUB, `e`, append `systemd.unit=multi-user.target` to the `linux` line, `Ctrl+X`. (Or at runtime,
   `systemctl isolate multi-user.target`.)
4. `rd.break` stops in the initramfs; `mount -o remount,rw /sysroot` makes the real root writable; `chroot /sysroot`
   makes the real system's `passwd` and `/etc/shadow` apply; `passwd`; `touch /.autorelabel` because the new
   shadow file has no valid SELinux label (no policy loaded in the initramfs) and every login would be denied;
   `exit` twice to continue.
5. bash runs as PID 1 directly on the real root file system, so `/` is already the right root. Continue with
   `exec /sbin/init`.
6. Processes are in uninterruptible sleep (D state), probably waiting on slow or failing storage or NFS.
7. RSS (resident memory). VSZ counts all mapped virtual memory, including untouched reservations and shared
   libraries.
8. `kill` sends SIGTERM, which the process can catch to clean up; `-9` sends SIGKILL, which cannot be caught
   and leaves no chance to clean up.
9. Only root can lower niceness (raise priority) or set a negative value.
10. `tuned-adm recommend`, then `tuned-adm profile NAME`; ensure `systemctl enable --now tuned`.
11. `/var/log/secure` (the authpriv facility).
12. `journalctl -u httpd -b -1 -p err`. The journal must be persistent, or there is no previous boot to query.
13. It keeps the journal on disk only if `/var/log/journal` exists. Create that directory (then restart or flush
    journald), or set `Storage=persistent` in `journald.conf` or a drop-in and restart journald.
14. The `Loaded:` line, which says `enabled` or `disabled`.
15. Without a trailing colon, `server2` was treated as a local file name; it should be `scp file server2:`.

</details>
