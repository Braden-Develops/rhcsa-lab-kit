# Lecture 7: Deploy, configure, and maintain systems

This section collects the day-to-day maintenance jobs that keep a system doing the right thing without you:
running jobs on a schedule, making services start at boot, choosing what the system boots into, keeping the clock
correct, keeping software up to date, and controlling the bootloader. The common thread is **persistence**:
every task here is about what the system does next time, not just now, and the exam checks it after a reboot.

---

## 7.1 Schedule tasks using at, cron and systemd timer units

Linux has three schedulers, each suited to different jobs:

| | `at` | cron | systemd timers |
|---|---|---|---|
| Runs a job | **once**, at a future time | **repeatedly**, on a calendar pattern | repeatedly or once, on calendar **or** relative times |
| Defined by | a command typed into `at` | a line in a crontab | a `.timer` unit + a `.service` unit |
| Daemon | `atd` | `crond` | systemd itself (PID 1) |
| Output goes to | mail to the user | mail to the user (or `MAILTO`) | the journal |
| Missed while powered off | runs at next opportunity | lost (except via anacron) | `Persistent=true` catches up |
| Best for | "do this once at 02:00" | classic periodic jobs, per-user jobs | system jobs that need logging, dependencies, resource control |

### at: one-off jobs

`at` reads commands from stdin (or interactively, ending with `Ctrl+D`) and queues them to run at a time:

```bash
at 02:00                       # interactive: type commands, Ctrl+D to finish
at now + 2 hours <<< 'touch /tmp/at-ran'
echo '/usr/local/bin/report.sh' | at 16:00 tomorrow
at -f /root/job.sh teatime     # from a file; "teatime" is 16:00
at 09:30 2026-12-24
at noon + 3 days
atq                            # list pending jobs (as root: everyone's): job number, time, queue, user
at -c 5                        # show job 5 in full: the environment it captured and the commands
atrm 5                         # delete job 5
batch                          # run when the load average drops below 0.8
```

Time specifications are flexible: `HH:MM`, `midnight`, `noon`, `teatime`, `now + N minutes|hours|days|weeks`,
`tomorrow`, dates as `YYYY-MM-DD` or `MM/DD/YY`. A time that has already passed today means tomorrow.

What happens underneath: `at` writes a job file into `/var/spool/at/` containing a shell script that first
**recreates your current environment** (variables, umask and working directory, all visible with `at -c`) and
then runs your commands. The `atd` daemon checks the spool and runs due jobs as the user who submitted them. Output
is mailed to that user if a local mail system exists; otherwise it is lost, so redirect output to a file yourself.

Requirements: the `at` package installed and `atd` running (`systemctl enable --now atd`).

Access is controlled by `/etc/at.allow` and `/etc/at.deny`: if `at.allow` exists, **only** users listed there may
use `at`; otherwise everyone **except** users in `at.deny` may. root is always allowed. A job scheduled for a user
must be created **as** that user: `su - student -c 'echo "touch /tmp/x" | at now + 2 hours'`, or interactively
after `su - student`.

### cron: recurring jobs

The `crond` daemon (package `cronie`, enabled by default) wakes up every minute, checks all crontabs, and runs any
job whose schedule matches the current minute.

**User crontabs** belong to individual users and run as them. Never edit the files directly; use `crontab`:

```bash
crontab -e                     # edit your crontab (opens $EDITOR, vi by default); installed on save
crontab -l                     # list it
crontab -r                     # remove it entirely (careful: no confirmation)
crontab -e -u natasha          # as root: edit natasha's
crontab -l -u natasha
```

They are stored in `/var/spool/cron/USERNAME`. `crontab -e` checks the syntax when you save and refuses a broken
file ("errors in crontab file, can't install"), which is a good reason to use it.

**The five time fields:**

```text
 ┌──────────── minute        0-59
 │ ┌────────── hour          0-23
 │ │ ┌──────── day of month  1-31
 │ │ │ ┌────── month         1-12 (or jan-dec)
 │ │ │ │ ┌──── day of week   0-7 (0 and 7 = Sunday, or sun-sat)
 │ │ │ │ │
 * * * * *  command to run
```

| Syntax | Meaning |
|---|---|
| `*` | every value |
| `5` | exactly 5 |
| `1,15,30` | a list |
| `1-5` | a range |
| `*/10` | every 10th value (0, 10, 20...) |
| `0-30/10` | every 10th within a range (0, 10, 20, 30) |

Examples:

```text
23 14 * * *     /usr/bin/logger "rhcsa-cron"          # every day at 14:23
*/5 * * * 1-5   /usr/bin/date >> /var/log/hb.log      # every 5 minutes, Monday-Friday
0 2 1 * *       /usr/local/bin/monthly.sh             # 02:00 on the 1st of each month
30 8 * * mon    /usr/local/bin/weekly.sh              # Mondays 08:30
0 */4 * * *     ...                                    # every 4 hours, on the hour
@reboot         /usr/local/bin/at-boot.sh             # once, when crond starts at boot
@daily          ...                                    # also @hourly, @weekly, @monthly, @yearly
```

Two subtleties:

- If **both** day-of-month and day-of-week are restricted (not `*`), the job runs when **either** matches. `0 0 13
  * 5` runs on every 13th *and* every Friday, not only on Friday the 13th.
- **`%` is special** in the command field: it means newline, and text after the first `%` is fed to the command's
  stdin. `date +%F` in a crontab must be written `date +\%F`.

**The cron environment is minimal**: `SHELL=/bin/sh`, `PATH=/usr/bin:/bin`, `HOME` from passwd. A command that works
in your shell may fail in cron because `/usr/sbin` isn't in the path. Use absolute paths, or set variables at the
top of the crontab: `PATH=/usr/local/bin:/usr/bin:/usr/sbin`, `MAILTO=admin@example.com` (or `MAILTO=""` to stop
mail).

**System cron** jobs are defined by files, and have an extra **user** field:

```text
# /etc/crontab  and  /etc/cron.d/*
SHELL=/bin/bash
PATH=/sbin:/bin:/usr/sbin:/usr/bin
MAILTO=root
# m h dom mon dow user  command
*/5 * * * *       root  /usr/local/bin/check-disk.sh
```

Packages drop files in `/etc/cron.d/`. The directories `/etc/cron.hourly/`, `/etc/cron.daily/`, `/etc/cron.weekly/`
and `/etc/cron.monthly/` hold executable **scripts** (no schedule line) run by `run-parts`. On RHEL, hourly scripts
are run by `/etc/cron.d/0hourly`, and the daily, weekly and monthly ones by **anacron** (`/etc/anacrontab`), which
remembers when each last ran and catches up on jobs missed while the machine was off: well suited to laptops and
servers that are sometimes powered down.

Access control works like at's: `/etc/cron.allow` and `/etc/cron.deny` (RHEL ships an empty `cron.deny`, so
everyone may use cron).

Cron logs each job it starts to `/var/log/cron` (and the journal: `journalctl -u crond`), which is how you confirm a
job ran.

> **Exam angle.** "As user natasha, run X every day at 14:23." Use `crontab -e -u natasha` (or `su - natasha`,
> then `crontab -e`), not `/etc/crontab`, because the job must belong to natasha. Check with `crontab -l -u natasha`.

### systemd timers

A **timer unit** activates another unit (by default, the `.service` with the same name) when its time comes. This
gives scheduled jobs everything services have: logging to the journal, dependencies, resource limits, security
sandboxing, and `systemctl status` to see the last run. RHEL itself uses timers for many housekeeping jobs:
`systemctl list-timers --all` shows them (`dnf-makecache.timer`, `logrotate.timer`, `fstrim.timer`,
`systemd-tmpfiles-clean.timer`...).

A timer job needs **two** unit files, normally in `/etc/systemd/system/`:

```ini
# /etc/systemd/system/cleanup.service
[Unit]
Description=Clean up temporary report files

[Service]
Type=oneshot
ExecStart=/usr/local/bin/cleanup.sh
```

```ini
# /etc/systemd/system/cleanup.timer
[Unit]
Description=Run cleanup every 15 minutes

[Timer]
OnCalendar=*:0/15
Persistent=true

[Install]
WantedBy=timers.target
```

```bash
systemctl daemon-reload                 # systemd must re-read unit files after you create or edit them
systemctl enable --now cleanup.timer    # enable and start the TIMER, not the service
systemctl list-timers cleanup.timer     # NEXT, LEFT, LAST, PASSED
systemctl status cleanup.timer
journalctl -u cleanup.service           # output of each run
systemctl start cleanup.service         # run the job once now, to test it
```

Note what is and isn't enabled: the **timer** is enabled (it has an `[Install]` section linking it into
`timers.target`); the **service** has no `[Install]` section and is "static": it only runs when the timer
triggers it. `Type=oneshot` tells systemd the service is a job that runs to completion, not a daemon.

**Two kinds of timer:**

| Directive | Fires |
|---|---|
| `OnCalendar=` | at wall-clock times (realtime timer), like cron |
| `OnBootSec=` | this long after boot |
| `OnStartupSec=` | this long after systemd started |
| `OnActiveSec=` | this long after the timer was activated |
| `OnUnitActiveSec=` | this long after the service was last **started** (repeat interval) |
| `OnUnitInactiveSec=` | this long after the service last **finished** |

The relative ("monotonic") ones are combined to express "every N minutes regardless of the clock", e.g.
`OnBootSec=5min` plus `OnUnitActiveSec=15min`.

**Calendar syntax** (`man systemd.time`) has the shape `DayOfWeek Year-Month-Day Hour:Minute:Second`, where any part
may be `*`, a list `a,b`, a range `a..b`, or a repetition `start/step`:

| Expression | Means |
|---|---|
| `daily` / `hourly` / `weekly` / `monthly` | shorthand (`daily` = `*-*-* 00:00:00`) |
| `*-*-* 02:30:00` | every day at 02:30 |
| `Mon..Fri 08:00` | weekdays at 08:00 |
| `Sat,Sun 10:00` | weekends |
| `*:0/15` | every 15 minutes (minute 0, 15, 30, 45 of every hour) |
| `*-*-01 00:00` | the 1st of every month |
| `*-*-* 14:23` | daily at 14:23 |

Always check an expression before trusting it:

```text
$ systemd-analyze calendar 'Mon..Fri 08:00'
  Original form: Mon..Fri 08:00
Normalized form: Mon..Fri *-*-* 08:00:00
    Next elapse: Mon 2026-11-09 08:00:00 UTC
       From now: 1 day 22h left
```

Other useful `[Timer]` options: **`Persistent=true`** (if the machine was off when the timer should have fired,
run once at the next boot, like anacron), `RandomizedDelaySec=` (spread load across many machines),
`AccuracySec=` (systemd may coalesce wake-ups within this window, 1 minute by default; set `1s` if precision
matters), `Unit=` (trigger a differently named unit).

For a quick one-off you can skip writing files: `systemd-run --on-calendar='*:0/10' /usr/local/bin/x.sh` creates
a transient timer, and `systemd-run --on-active=2h touch /tmp/x` is a systemd-flavoured `at`.

User-level timers also exist (`~/.config/systemd/user/`, `systemctl --user`), but need lingering
(`loginctl enable-linger USER`) to run when the user is logged out.

---

## 7.2 Start and stop services and configure services to start automatically at boot

Lecture 4 (4.9) covered starting, stopping and checking services **now**. This objective is about **boot**, and about
how unit files work.

### What "enabled" actually means

Enabling a unit does not start anything. It creates **symlinks** according to the unit's `[Install]` section, so
that the next time the target it belongs to is activated (at boot), the unit is pulled in:

```text
$ systemctl enable httpd
Created symlink /etc/systemd/system/multi-user.target.wants/httpd.service → /usr/lib/systemd/system/httpd.service.
```

`httpd.service` has `WantedBy=multi-user.target`, so enabling it creates a link in that target's `.wants`
directory. Booting into multi-user (or graphical, which includes multi-user) therefore starts httpd. `disable`
removes the link.

```bash
systemctl enable httpd          # start at boot
systemctl enable --now httpd    # start at boot AND start now
systemctl disable httpd         # don't start at boot (doesn't stop it now)
systemctl disable --now httpd   # and stop it now
systemctl is-enabled httpd      # enabled, disabled, static, masked, indirect, alias...
systemctl list-unit-files --type=service
systemctl list-unit-files --state=enabled
```

**Two separate states, and the exam checks both:** *active* (running now: `start`/`stop`) and *enabled* (starts at
boot: `enable`/`disable`). A service started but not enabled works until the grader reboots. A service enabled but
not started fails any check before the reboot. Use `enable --now` habitually.

`is-enabled` values worth recognising:

| Value | Meaning |
|---|---|
| `enabled` / `disabled` | has an `[Install]` section; links present / absent |
| `static` | no `[Install]` section; can't be enabled, it is started by something else (a timer, socket, or dependency) |
| `masked` | linked to `/dev/null`: cannot be started at all, even manually or as a dependency |
| `indirect` | enabling it is done through another unit (e.g. its socket) |

### Masking

When two services conflict (for example, two firewall managers) or a service must never run, **mask** it:

```bash
systemctl mask iptables         # creates /etc/systemd/system/iptables.service → /dev/null
systemctl start iptables        # "Unit iptables.service is masked."
systemctl unmask iptables
```

Masking is stronger than disabling: a disabled service can still be started by hand or pulled in as a dependency.

### Presets

When a package installs a service, whether it is enabled automatically is decided by **preset** files
(`/usr/lib/systemd/system-preset/*.preset`). On RHEL most network services are preset **disabled**, so after
`dnf install httpd` you must `enable --now` it yourself. `systemctl status` shows the preset on the `Loaded:` line.
`systemctl preset UNIT` resets one to its preset.

### Anatomy of a service unit

```ini
[Unit]
Description=Lab application
After=network-online.target
Wants=network-online.target

[Service]
Type=simple                         # simple / exec / forking / oneshot / notify
User=labapp
ExecStart=/usr/local/bin/labapp --port 8080
ExecReload=/bin/kill -HUP $MAINPID
Restart=on-failure
RestartSec=5
Environment=LOG_LEVEL=info

[Install]
WantedBy=multi-user.target
```

- `[Unit]`: description, documentation, dependencies (`Requires=`, `Wants=`) and ordering (`After=`, `Before=`).
- `[Service]`: how to run it. `ExecStart=` must be an **absolute path**. `Type=simple` means the process started is
  the service; `forking` means it daemonises itself (old-style daemons); `oneshot` means it runs and exits.
- `[Install]`: what `enable` should hook it into.

### Changing units properly: overrides and daemon-reload

Never edit files in `/usr/lib/systemd/system/`: a package update overwrites them. Two correct ways:

```bash
systemctl edit httpd            # creates /etc/systemd/system/httpd.service.d/override.conf
                                # (a drop-in: only the settings you add override the original)
systemctl edit --full httpd     # copies the whole unit to /etc/systemd/system/ for editing
systemctl cat httpd             # shows the unit and all drop-ins as systemd sees them
systemctl revert httpd          # delete your overrides
```

`systemctl edit` reloads systemd automatically. If you create or change unit files any other way (vim, a heredoc),
you **must** run:

```bash
systemctl daemon-reload
```

Otherwise systemd keeps using its cached copy, and warns "unit file changed on disk". To change a list setting such
as `ExecStart=` in a drop-in, first clear it with an empty assignment:

```ini
[Service]
ExecStart=
ExecStart=/usr/local/bin/labapp --port 9090
```

### Diagnosing a service that fails at boot

`systemctl status unit`, `journalctl -u unit -b`, then check the unit itself: a wrong path in `ExecStart=`
(`status=203/EXEC` means "couldn't execute the program": wrong path or not executable), a missing user, a typo in
a directive (`systemd-analyze verify unit.service` reports it), a missing `[Install]` section if it "can't be
enabled".

---

## 7.3 Configure systems to boot into a specific target automatically

The target systemd activates at boot is `default.target`, which is a **symlink** to a real target:

```text
$ ls -l /etc/systemd/system/default.target
lrwxrwxrwx. 1 root root 37 ... /etc/systemd/system/default.target -> /usr/lib/systemd/system/multi-user.target
```

```bash
systemctl get-default                          # graphical.target or multi-user.target
systemctl set-default multi-user.target        # text mode for future boots (rewrites the symlink)
systemctl set-default graphical.target         # desktop for future boots
```

`set-default` changes **future boots only**; to switch now as well, `systemctl isolate multi-user.target`
(Lecture 4, 4.2). A one-time override at the GRUB menu (`systemd.unit=...`) takes precedence for that boot.

`graphical.target` only produces a desktop if a display manager (GDM) and desktop are installed. A server installed
with "Server with GUI" defaults to graphical; "Server" or "Minimal" to multi-user.

> **Exam angle.** "Configure the system to boot into a text-based multi-user target by default." One command,
> `systemctl set-default multi-user.target`, verified with `get-default`.

---

## 7.4 Configure time service clients

### Why time matters

Accurate, agreed time is not cosmetic. Kerberos authentication (used by IdM/Active Directory and NFS with
`sec=krb5`) rejects requests if clocks differ by more than five minutes. TLS certificates have validity windows.
Logs from several systems are useless for investigating an incident if their timestamps disagree. Cron and timers
fire at the wrong moment. Distributed databases and clusters can corrupt data.

### Clocks in a Linux system

- The **hardware clock** (RTC): a battery-backed clock on the motherboard that keeps time while the machine is
  off. On Linux servers it is normally kept in **UTC**.
- The **system clock**: maintained by the kernel while running, initialised from the RTC at boot. Everything
  uses this one.
- **Time zones** are only a display matter: the kernel counts seconds since 1970-01-01 UTC, and the time zone
  setting converts that for humans. `/etc/localtime` is a symlink to a zone file under `/usr/share/zoneinfo/`.

Clocks drift: a typical crystal gains or loses seconds per day. **NTP** (Network Time Protocol, UDP port 123)
corrects that by comparing with time servers arranged in **strata**: stratum 0 is a reference clock (GPS, atomic),
stratum 1 servers are directly attached to one, stratum 2 servers sync from stratum 1, and so on. A client polls
several servers, estimates network delay, discards outliers, and steers its clock.

### chrony

RHEL's NTP implementation is **chrony**: the daemon `chronyd` and the control tool `chronyc`. chronyd adjusts the
clock gradually (**slewing**: running the clock slightly fast or slow) so time never jumps backwards under running
programs; it only **steps** the clock (jumps) in limited cases, such as at startup, when allowed by `makestep`.

Configuration is `/etc/chrony.conf`. The default looks like:

```text
pool 2.rhel.pool.ntp.org iburst      # a pool name resolving to several servers
sourcedir /run/chrony-dhcp           # servers learned from DHCP
driftfile /var/lib/chrony/drift      # remembers this clock's drift rate between restarts
makestep 1.0 3                       # step if off by >1 s, but only during the first 3 updates
rtcsync                              # let the kernel copy system time to the RTC periodically
keyfile /etc/chrony.keys
ntsdumpdir /var/lib/chrony
leapseclist /usr/share/zoneinfo/leap-seconds.list
logdir /var/log/chrony
```

- `server HOST [options]`: use one specific server. `pool NAME`: a DNS name that resolves to several servers,
  using several of them.
- **`iburst`**: send a burst of requests at startup so synchronisation happens in seconds rather than minutes. Use
  it on every server line.
- `prefer` marks a preferred source. `allow 192.168.50.0/24` would make this machine an NTP **server** for that
  network (not needed for a client).

### Configuring a client

```bash
dnf install chrony                              # normally installed
vim /etc/chrony.conf                            # comment out "pool ..." and add:
#   server classroom.lab.example.com iburst
systemctl enable --now chronyd
systemctl restart chronyd                       # after editing the file
chronyc sources -v                              # sources and their state
chronyc tracking                                # this system's offset and stratum
timedatectl                                     # summary
```

If the task says "use **only** server X", remove or comment out the default `pool` line and any other `server` lines.

Reading `chronyc sources`:

```text
MS Name/IP address         Stratum Poll Reach LastRx Last sample
===============================================================================
^* classroom.lab.example.com     2   6   377    12   +245us[ +310us] +/-   18ms
```

The first characters: `^` a server, `=` a peer, `#` a local reference clock. The second: **`*` the source currently
synchronised to**, `+` an acceptable source combined with it, `-` acceptable but not used, `?` unreachable or not
yet assessed, `x` a falseticker (disagrees with others), `~` too variable. **Reach** is an octal bitmap of the last
eight polls: `377` means all eight succeeded; `0` means never reached. If you see `^?` and Reach `0`, check the name
resolves, the server is up, and UDP 123 isn't blocked.

### timedatectl

`timedatectl` (systemd-timedated) shows and sets clock settings:

```bash
timedatectl                                     # local time, UTC, RTC, time zone, "System clock synchronized", "NTP service"
timedatectl list-timezones | grep -i chicago
timedatectl set-timezone America/Chicago        # rewrites the /etc/localtime symlink
timedatectl set-ntp true                        # enable and start chronyd (false: disable and stop)
timedatectl set-time '2026-11-07 10:00:00'      # only possible with NTP off
timedatectl set-local-rtc 0                     # keep the RTC in UTC (the right choice)
```

`date` prints the time; `hwclock` reads or sets the RTC (`hwclock --systohc`).

> **Exam angle.** "Configure the system as an NTP client of classroom.example.com." Edit `chrony.conf`
> (`server ... iburst`, remove the pool), restart and enable chronyd, then check `chronyc sources` shows `^*` next
> to it after a few seconds. Set a time zone if asked with `timedatectl set-timezone`.

---

## 7.5 Install and update software packages from Red Hat Content Delivery Network, a remote repository, or from the local file system

This objective is covered in depth in [Lecture 2](#/lecture/2); here is the map of the three sources:

| Source | Set up | Install / update |
|---|---|---|
| **Red Hat CDN** | `subscription-manager register` (or `rhc connect`); repos appear in the managed `/etc/yum.repos.d/redhat.repo` (`rhel-10-for-x86_64-baseos-rpms`, `...-appstream-rpms`); enable more with `subscription-manager repos --enable=ID` | `dnf install PKG`, `dnf upgrade` |
| **A remote repository** | a `.repo` file in `/etc/yum.repos.d/` with `baseurl=http://...`, or `dnf config-manager --add-repo URL`; `gpgcheck` and `gpgkey` as appropriate | `dnf install PKG`, `dnf upgrade` |
| **The local file system** | nothing, or a `file:///` repository created with `createrepo_c` (e.g. from a mounted ISO) | `dnf install ./pkg.rpm` (resolves dependencies from configured repos) |

Updating is `dnf upgrade` (everything) or `dnf upgrade PKG`. `dnf check-update` lists what is available; `dnf
updateinfo list --security` (with CDN errata metadata) lists security fixes; `dnf upgrade --security` applies
only those. A new kernel is installed alongside the old ones, and becomes the default at the next boot (7.6).

`needs-restarting -r` (from `dnf-utils`/`yum-utils`) tells you whether updates since boot require a reboot, and
`needs-restarting -s` which services should be restarted.

---

## 7.6 Modify the system bootloader

### How GRUB's configuration is put together on RHEL

Several files cooperate, and knowing which does what avoids most mistakes:

| File | Role | Edit? |
|---|---|---|
| `/etc/default/grub` | settings for generating the config: `GRUB_TIMEOUT`, `GRUB_CMDLINE_LINUX`, `GRUB_DEFAULT`... | yes, then regenerate |
| `/boot/grub2/grub.cfg` | the generated main configuration GRUB reads | **no**: generated by `grub2-mkconfig` |
| `/boot/efi/EFI/redhat/grub.cfg` | on UEFI: a small stub that points to `/boot/grub2/grub.cfg` | no |
| `/boot/loader/entries/*.conf` | **BLS entries**: one per kernel, with its `linux`, `initrd` and `options` (the kernel command line) | via `grubby` |
| `/boot/grub2/grubenv` | GRUB environment block: the saved default entry, `menu_auto_hide`, etc. | via `grub2-editenv` / `grubby` |

A BLS entry looks like:

```text
title Red Hat Enterprise Linux (6.12.0-55.el10.x86_64) 10.0 (Coughlan)
version 6.12.0-55.el10.x86_64
linux /vmlinuz-6.12.0-55.el10.x86_64
initrd /initramfs-6.12.0-55.el10.x86_64.img
options root=/dev/mapper/rhel-root ro crashkernel=... resume=/dev/mapper/rhel-swap rd.lvm.lv=rhel/root rd.lvm.lv=rhel/swap rhgb quiet
grub_users $grub_users
grub_arg --unrestricted
grub_class rhel
```

Since RHEL 9 (UEFI and BIOS alike), `/boot/grub2/grub.cfg` is the one real config file, and
`grub2-mkconfig -o /boot/grub2/grub.cfg` is the command to regenerate it on either firmware.

### Kernel arguments with grubby

`grubby` edits BLS entries directly and is the Red Hat-recommended tool for kernel command-line changes:

```bash
grubby --info=ALL                                     # every entry: index, kernel, args, root, initrd
grubby --info=DEFAULT
grubby --default-kernel                               # path of the default kernel
grubby --default-index
grubby --update-kernel=ALL --args="audit_backlog_limit=8192"     # add to every entry
grubby --update-kernel=ALL --remove-args="rhgb quiet"            # remove from every entry
grubby --update-kernel=DEFAULT --args="debug"                    # only the default entry
grubby --update-kernel=/boot/vmlinuz-6.12.0-55.el10.x86_64 --args="..."   # one specific kernel
cat /proc/cmdline                                     # what the RUNNING kernel was booted with
```

Changes take effect at the **next boot**; `/proc/cmdline` confirms after rebooting. Newly installed kernels
inherit the arguments of the current default entry, so a change made with `--update-kernel=ALL` survives kernel
updates.

`/etc/default/grub`'s `GRUB_CMDLINE_LINUX` holds the base arguments used when the config is regenerated. If you
change kernel arguments there instead of with grubby, regenerate with
`grub2-mkconfig -o /boot/grub2/grub.cfg --update-bls-cmdline` so existing BLS entries pick them up as well (without
`--update-bls-cmdline`, current RHEL versions leave the existing entries' options alone).

Common reasons to change kernel arguments: removing `rhgb quiet` to see boot messages, adding
`audit=1`/`audit_backlog_limit=`, `crashkernel=`, `console=ttyS0,115200` for a serial console, `selinux=0`
(don't), `systemd.unit=` (better done with `set-default`), or removing something someone planted, such as
`systemd.unit=emergency.target`.

### Menu timeout and visibility

```bash
vim /etc/default/grub                       # GRUB_TIMEOUT=10
grub2-mkconfig -o /boot/grub2/grub.cfg      # regenerate (required for /etc/default/grub changes)
```

RHEL also **hides** the menu after a successful boot (`menu_auto_hide` in grubenv), so the timeout appears not to
work. To always show it: `grub2-editenv - unset menu_auto_hide`, or set `GRUB_TIMEOUT_STYLE=menu` in
`/etc/default/grub` and regenerate. `grub2-editenv list` shows the environment block.

### Choosing the default kernel

```bash
grubby --info=ALL | grep -E '^(index|kernel)'
grubby --set-default=/boot/vmlinuz-6.12.0-50.el10.x86_64     # by path
grubby --set-default-index=1                                 # by index (0 = first, newest)
grubby --default-kernel                                      # confirm
```

By default a newly installed kernel becomes the default (`UPDATEDEFAULT=yes` in `/etc/sysconfig/kernel`). To boot an
older kernel just **once**, pick it at the menu, or `grub2-reboot INDEX` then reboot.

### Protecting GRUB (bonus)

`grub2-setpassword` sets a password needed to **edit** entries at the menu (normal booting is still allowed). That
blocks the `rd.break` trick for anyone without the password, which is why physical security matters. Not in the
objectives, but useful to understand Lecture 4's password reset in context.

### If you break it

A typo in a BLS entry or a bad kernel argument can stop a boot. At the GRUB menu press `e`, fix the line for one
boot, `Ctrl+X`, log in, and correct it persistently with grubby. If the default kernel itself fails, choose an
older entry from the menu. This is why the old kernels are kept.

> **Exam angle.** "Add kernel argument X to all kernels" → `grubby --update-kernel=ALL --args=X`. "Set the GRUB
> timeout to N seconds" → `/etc/default/grub`, then `grub2-mkconfig -o /boot/grub2/grub.cfg`. Reboot and check
> `/proc/cmdline` and the menu.

---

## Putting it together

On a newly built server you might: point it at the repositories and `dnf upgrade` (7.5); `grubby` a console argument
and set a 10-second menu (7.6); `set-default multi-user.target` (7.3); configure chrony against the site's NTP
server (7.4); `enable --now` the services it will run, and mask one that conflicts (7.2); add a crontab entry for a
user's report, an `at` job for a one-off maintenance step, and a systemd timer for a cleanup job that logs to the
journal (7.1). Then reboot, and check: `systemctl get-default`, `cat /proc/cmdline`, `chronyc sources`,
`systemctl is-enabled`, `systemctl list-timers`, `crontab -l -u USER`, `atq`.

**Now practise:** [Lab 08](#/lab/08) (scheduling, services, default target, chrony; container) and tasks 2–5 of
[Lab 05](#/lab/05) (bootloader and default target; VM).

## Review questions

1. When would you choose `at`, cron, or a systemd timer?
2. Where are `at` jobs stored, and why does `at -c N` show lots of environment variables?
3. Write a crontab line for 06:45 on weekdays, and one for every 10 minutes between 08:00 and 17:59.
4. Why does `date +%F > /tmp/d` misbehave in a crontab, and what is the fix?
5. How does a line in `/etc/cron.d/` differ from a line in a user crontab?
6. A cron job works in your shell but fails from cron with "command not found". Why?
7. Which unit do you enable for a timer job, the timer or the service? Why?
8. Write an `OnCalendar` value for every day at 02:30, and how you'd check it.
9. What does `Persistent=true` do?
10. What does `systemctl enable` actually do on disk?
11. Explain the difference between disabled, static and masked.
12. You edited a unit file with vim and `systemctl restart` uses the old settings. What did you forget?
13. Where is the default target stored, and how do you change it?
14. What does `iburst` do, and how do you see which NTP source chrony is synchronised to?
15. Give the command to add a kernel argument to every installed kernel, and how to confirm it after reboot.
16. You set `GRUB_TIMEOUT=10` but the menu doesn't appear. Name two possible reasons.

<details><summary>Answers</summary>

1. `at` for a one-time job; cron for simple recurring jobs, especially per user; timers for system jobs that
   benefit from journald logging, dependencies, catching up after downtime, or monotonic intervals.
2. In `/var/spool/at/`. `at` captures the submitting shell's environment (and umask, directory) so the job runs
   in the same context.
3. `45 6 * * 1-5 cmd` and `*/10 8-17 * * * cmd`.
4. `%` is a newline in crontab commands. Escape it: `date +\%F`.
5. It has an extra user field after the five time fields.
6. cron's `PATH` is minimal (`/usr/bin:/bin`). Use absolute paths or set `PATH` in the crontab.
7. The timer. It has the `[Install]` section; the service is static and started by the timer.
8. `OnCalendar=*-*-* 02:30:00` (or `02:30`); check with `systemd-analyze calendar '02:30'`.
9. If the machine was off when the timer should have fired, the job runs once soon after the next boot.
10. Creates symlinks named in the unit's `[Install]` section, e.g. in `multi-user.target.wants/`.
11. Disabled: can be enabled, links absent. Static: no `[Install]` section; started only by other units.
    Masked: linked to `/dev/null`; can't be started at all.
12. `systemctl daemon-reload`.
13. `/etc/systemd/system/default.target` (a symlink). `systemctl set-default TARGET`.
14. It sends a quick burst of requests at startup for fast initial sync. `chronyc sources` and look for `^*`.
15. `grubby --update-kernel=ALL --args="ARG"`; after reboot, `cat /proc/cmdline`.
16. You didn't regenerate with `grub2-mkconfig -o /boot/grub2/grub.cfg`; or the menu is auto-hidden
    (`menu_auto_hide`); fix with `grub2-editenv - unset menu_auto_hide` or `GRUB_TIMEOUT_STYLE=menu`.

</details>
