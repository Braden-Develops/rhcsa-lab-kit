# RHCSA (EX200) Study Guide: RHEL 10

Based on Red Hat's published EX200 objectives for RHEL 10 (62 objective lines, page last published
2026-09-16, fetched 2026-11-07 from https://www.redhat.com/training/courses/ex200/examobjective).
Every official line appears **verbatim and numbered** in the tables below with the lab task that drills it;
`OBJECTIVES.md` is the same mapping as a checklist. The exam is **hands-on, about 3 hours**, on one or two
systems; you're graded by scripts that inspect the final state of the machines **after a reboot**. No internet;
man pages and `/usr/share/doc` are available. Passing score is 210/300.

**What changed for RHEL 10:** a new *Manage software* section (dnf repositories **and Flatpak**); *Manage
containers* (Podman) was **removed**; Stratis and VDO are not in the objectives. Networking config is keyfile-only
(`/etc/NetworkManager/system-connections/`), no `ifcfg` files.

Each section lists the official objectives, what you must be able to do, the commands, the traps, and the lab.

---

## Exam-day rules of thumb

1. **Read every task first.** Some depend on others (e.g. a repo before installs; `login.defs` before `useradd`).
2. **Everything must survive a reboot.** `systemctl enable --now`, `firewall-cmd --permanent` + `--reload`,
   fstab entries, `setsebool -P`, `semanage` (never `chcon`), `grubby` for kernel args.
3. **Before rebooting** after storage work: `findmnt --verify`, `mount -a`, `swapon -a`. A bad fstab line = emergency mode.
4. **Reboot at least once, mid-exam**, and re-verify everything. Better to find a broken boot with time left.
5. **Never disable SELinux or the firewall** to make something work. Fix the policy/rule.
6. If you lose root access, you know how to reset it (Section 3). That's a task in itself and a safety net.
7. `man -k keyword`, `man 5 fstab`, `man nmcli-examples`, `man semanage-fcontext`, `man systemd.timer`,
   `man 5 crontab`, `/usr/share/doc/*/` are your reference. `--help` and Tab completion are fast.

---

## 1. Understand and use essential tools  → `labs/01-essential-tools`

| Official objective (verbatim) and lab | Must-know |
|---|---|
| **1.1** Access a shell prompt and issue commands with correct syntax<br>*Lab: all labs; 05 task 8 (console)* | `cmd -opts args`; quoting `'literal'` vs `"$expanded"`; `\` escapes; `;` `&&` `\|\|` |
| **1.2** Use input-output redirection (>, >>, \|, 2>, etc.)<br>*Lab 01 task 2* | `>` overwrite, `>>` append, `2>` stderr, `2>&1` / `&>` both, `<` input, `\|` pipe, `tee file`, `/dev/null` |
| **1.3** Use grep and regular expressions to analyze text<br>*Lab 01 task 1* | `grep -i -v -n -c -r -E -w -o`; anchors `^` `$`; `.` `*` `+` `?` `[abc]` `[^0-9]` `{n,m}` `\b`; `grep -E 'a\|b'` |
| **1.4** Access remote systems using SSH<br>*Lab 01 task 6* | `ssh user@host`, `ssh host cmd`, `-p port`, `~/.ssh/known_hosts`, `ssh -i key` |
| **1.5** Log in and switch users in multi-user targets<br>*Lab 01 task 8; 05 task 8* | `su - user` (login shell), `su -c 'cmd' user`, `sudo -i`, `sudo -u user cmd`, `whoami`, `id`, multi-user target logins on ttys (`Ctrl+Alt+F2`) |
| **1.6** Archive, compress, unpack, and uncompress files using tar, gzip, and bzip2<br>*Lab 01 task 3* | `tar -czf a.tar.gz dir` (gzip), `-cjf` (bzip2), `-cJf` (xz), `-tf` list, `-xf a.tar.gz -C /dest`; `gzip/gunzip`, `bzip2/bunzip2`, `zcat`/`bzcat`; `tar` auto-detects compression on extract |
| **1.7** Create and edit text files<br>*Lab 01 task 9* | `vim` (i, Esc, `:wq`, `:q!`, `/search`, `dd`, `yy`, `p`, `u`), `nano`, `cat > f <<'EOF'` |
| **1.8** Create, delete, copy, and move files and directories<br>*Lab 01 task 10* | `mkdir -p`, `cp -a`/`-r`, `mv`, `rm -r`, `rmdir`, `touch`; `find / -name x -user y -size +10M -mtime -1 -type f -exec … {} \;` |
| **1.9** Create hard and soft links<br>*Lab 01 task 4* | `ln target link` (same inode, same file system, files only); `ln -s target link` (path, can dangle, can cross FS); `ls -li`, `readlink -f` |
| **1.10** List, set, and change standard ugo/rwx permissions<br>*Lab 01 task 5* | `chmod u+x,g-w,o= f`; octal `chmod 750`; `chown user:group`; `chgrp`; special bits: setuid `4`, setgid `2` (dirs: inherit group), sticky `1` (dirs: only owner deletes) |
| **1.11** Locate, read, and use system documentation including man, info, and files in /usr/share/doc<br>*Lab 01 task 7* | `man`, `man -k`/`apropos` (run `mandb` if empty), `man 5 passwd` (sections: 1 cmds, 5 files, 8 admin), `info grep` (Enter follows a link, `n`/`p` next/prev node, `u` up, `/` search, `q` quit), `/usr/share/doc/pkg/`, `rpm -qd pkg` (a package's docs) |

**Traps:** `find` errors go to stderr: redirect `2>/dev/null` (or to a file if asked). `grep -w` = whole word.
Symlinks are resolved relative to the *link's* directory if relative. Directories need `x` to be entered.
Lab drills: grep to file, find+redirect, tar/bzip2, gzip, hard/soft links, fixing a dangling symlink, permission fixes,
setgid dir, ssh as another user, man sections.

---

## 2. Manage software  → `labs/02-software`

| Official objective (verbatim) and lab | Must-know |
|---|---|
| **2.1** Configure access to RPM repositories<br>*Lab 02 tasks 1–3* | `/etc/yum.repos.d/*.repo`: `[id]`, `name=`, `baseurl=`, `enabled=1`, `gpgcheck=0/1`, `gpgkey=`. Or `dnf config-manager --add-repo URL`, then fix gpgcheck. `rpm --import KEY` |
| **2.2** Install and remove RPM software packages<br>*Lab 02 tasks 2–6* | `dnf install/remove/update/reinstall`, `dnf search`, `dnf info`, `dnf provides /path`, `dnf list installed`, `dnf history` (+ `undo`), `dnf group list/install`, `dnf module list` (few modules left in RHEL 10), `rpm -qa`, `rpm -qi`, `rpm -ql`, `rpm -qf /file`, `rpm -qc` (config files) |
| ↳ supporting: installing from the local file system (see 7.5)<br>*Lab 02 task 4* | `dnf install ./pkg.rpm` (resolves deps; plain `rpm -ivh` doesn't) |
| **2.3** Configure access to Flatpak repositories<br>*Lab 02 task 7* | `flatpak remote-add --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo`; `flatpak remotes`; `remote-delete`; `--system` (default as root) vs `--user` |
| **2.4** Install and remove Flatpak software packages<br>*Lab 02 task 8* | `flatpak search X`, `flatpak install REMOTE APP-ID`, `flatpak list [--app]`, `flatpak info`, `flatpak run APP-ID`, `flatpak uninstall APP-ID`, `flatpak update`, `flatpak uninstall --unused`, `flatpak history` |

**Typical exam task:** "Configure your system to use `http://content.example.com/rhel10.0/x86_64/dvd/BaseOS` and
`.../AppStream` as repositories." → two repo files, `gpgcheck=0` unless a key URL is given; then `dnf repolist`.
**Traps:** a typo in `baseurl` breaks *every* dnf command; `dnf clean all` after fixing. Remote names are case-sensitive
for Flatpak. Lab drills: disable a broken repo, fix a repo file, create a repo, local RPM install, provides, Flatpak remote.

---

## 3. Create simple shell scripts  → `labs/03-shell-scripts`

| Official objective (verbatim) and lab | Must-know |
|---|---|
| **3.1** Conditionally execute code (use of: if, test, [], etc.)<br>*Lab 03 tasks 1, 3, 4* | `if cmd; then …; elif …; else …; fi`; `test` / `[ ]` / `[[ ]]`: `-f -d -e -r -w -x -s -z -n`, `=` `!=` strings, `-eq -ne -lt -le -gt -ge` numbers; `&&` / `\|\|`; `case $x in a) …;; *) …;; esac` |
| **3.2** Use Looping constructs (for, etc.) to process file, command line input<br>*Lab 03 tasks 2, 4* | `for f in *.log; do …; done`, `for i in $(seq 1 5)`, `for u in "$@"`, `while read -r line; do …; done < file`, `until`, `break`/`continue` |
| **3.3** Process script inputs ($1, $2, etc.)<br>*Lab 03 tasks 1–4* | `$1 $2 … ${10}`, `$#` count, `"$@"` all args, `$0` name, `shift`, `read -p "prompt" var` |
| **3.4** Processing output of shell commands within a script<br>*Lab 03 tasks 1, 3* | `var=$(cmd)`, `$?` exit status, `exit N`, pipes into loops, `>&2` to stderr |

Skeleton you should be able to type from memory:
```bash
#!/bin/bash
if [ $# -ne 1 ]; then echo "Usage: $0 FILE" >&2; exit 2; fi
while read -r line; do
  [ -z "$line" ] && continue
  echo "processing $line"
done < "$1"
```
**Traps:** forgetting `chmod +x`; unquoted variables breaking on spaces/empty values (`[ -z $x ]` errors when x is
empty-ish); `[` needs spaces around brackets; `bash -n` to syntax-check, `bash -x` to trace.

---

## 4. Operate running systems  → `labs/04-running-systems` (container) + `labs/05-boot` (VM)

| Official objective (verbatim) and lab | Must-know |
|---|---|
| **4.1** Boot, reboot, and shut down a system normally<br>*Lab 05 tasks 1, 7, 9* | `systemctl reboot`, `systemctl poweroff`, `shutdown -r +5`, `shutdown -c` |
| **4.2** Boot systems into different targets manually<br>*Lab 05 task 6* | at GRUB: `e`, append `systemd.unit=rescue.target` (or `emergency.target`, `multi-user.target`), Ctrl+x; at runtime: `systemctl isolate multi-user.target` |
| **4.3** Interrupt the boot process in order to gain access to a system<br>*Lab 05 task 1* | GRUB `e` → append `rd.break` → `mount -o remount,rw /sysroot` → `chroot /sysroot` → `passwd` → `touch /.autorelabel` → `exit`×2. Alternative `init=/bin/bash` → `mount -o remount,rw /` → `passwd` → `touch /.autorelabel` → `exec /sbin/init` |
| **4.4** Identify CPU/memory intensive processes and kill processes<br>*Lab 04 task 1* | `top` (P, M, k, r), `ps aux --sort=-%cpu \| head`, `ps -eo pid,user,%cpu,%mem,cmd --sort=-%mem`, `pgrep -a`, `kill PID`, `kill -9`, `pkill -u user`, `killall name`, `uptime`/load average, `free -h` |
| **4.5** Adjust process scheduling<br>*Lab 04 task 2* | niceness -20 (high) … 19 (low): `nice -n 10 cmd`, `renice -n 5 -p PID`, `ps -o pid,ni,cmd`; only root can lower it |
| **4.6** Manage tuning profiles<br>*Lab 04 task 3* | `dnf install tuned; systemctl enable --now tuned`, `tuned-adm list/active/recommend`, `tuned-adm profile NAME` |
| **4.7** Locate and interpret system log files and journals<br>*Lab 04 task 4* | `/var/log/messages`, `secure`, `cron`, `maillog`, `audit/audit.log`; `journalctl -u unit -p err -b -1 --since today -f -t tag -o verbose`, `journalctl _PID=`, `logger -p user.err -t tag msg` |
| **4.8** Preserve system journals<br>*Lab 04 task 5* | `mkdir -p /var/log/journal` *or* `Storage=persistent` in `/etc/systemd/journald.conf` (or a `.conf.d` drop-in), then `systemctl restart systemd-journald` (+ `journalctl --flush`) |
| **4.9** Start, stop, and check the status of network services<br>*Lab 04 task 6* | `systemctl start/stop/restart/reload/status sshd`, `systemctl is-active`, `ss -tulpn` to see listeners |
| **4.10** Securely transfer files between systems<br>*Lab 04 task 7* | `scp file user@host:/path`, `scp user@host:/path .`, `scp -r`, `sftp user@host` (get/put), `rsync -av -e ssh src user@host:dst` |

**Traps:** after `rd.break`, without `/.autorelabel` (or `restorecon /etc/shadow`) nobody can log in with SELinux
enforcing. `renice` changes running processes; `nice` starts new ones. The RHEL 10 journal is volatile by default.

---

## 5. Configure local storage  → `labs/06-local-storage` (VM)

| Official objective (verbatim) and lab | Must-know |
|---|---|
| **5.1** List, create, and delete partitions on GPT disks<br>*Lab 06 tasks 1, 5, 6* | `lsblk`, `lsblk -f`, `blkid`, `parted DISK print`; `parted -s DISK mklabel gpt mkpart NAME [fs] 1MiB 513MiB set 2 lvm on`; `gdisk`/`fdisk` interactively (n, t, w; type 8e00/8200 in gdisk, "Linux LVM"/"Linux swap" in fdisk); `parted rm N`; `udevadm settle` / `partprobe` |
| **5.2** Create and remove physical volumes<br>*Lab 06 tasks 2, 5* | `pvcreate /dev/vdb1`, `pvs`, `pvdisplay`, `pvremove` |
| **5.3** Assign physical volumes to volume groups<br>*Lab 06 tasks 2, 6* | `vgcreate [-s 8M] vg pv…`, `vgextend vg pv`, `vgreduce`, `vgs`, `vgdisplay`, `vgremove` |
| **5.4** Create and delete logical volumes<br>*Lab 06 tasks 3, 5* | `lvcreate -n lv -L 500M vg` (size) or `-l 50` (extents) or `-l 100%FREE`; `lvs`, `lvdisplay`, `lvremove vg/lv` |
| **5.5** Configure systems to mount file systems at boot by universally unique ID (UUID) or label<br>*Lab 06 tasks 1, 3, 4* | fstab: `UUID=… /mnt/x xfs defaults 0 0`; `LABEL=DOCS …`; labels: `mkfs.ext4 -L`, `e2label`, `xfs_admin -L`, `mkfs.xfs -L`; then `systemctl daemon-reload; mount -a` |
| **5.6** Add new partitions and logical volumes, and swap to a system non-destructively<br>*Lab 06 tasks 1, 3, 6* | new partitions in free space only; swap: `mkswap DEV`, fstab `UUID=… none swap defaults 0 0`, `swapon -a`, `swapon --show`, `free -h` |

**Traps:** `-L` vs `-l`. PE size can only be set at `vgcreate`. Leave 1 MiB alignment (`1MiB` start). NVMe partitions are
`nvme0n1p1`. Swap in fstab uses `none`/`swap` mount point. Removing: unmount → remove fstab line → `lvremove` →
`vgremove` → `pvremove` → delete partition.

---

## 6. Create and configure file systems  → `labs/07-file-systems` (VM)

| Official objective (verbatim) and lab | Must-know |
|---|---|
| **6.1** Create, mount, unmount, and use VFAT, ext4, and XFS file systems<br>*Lab 07 tasks 1, 6* | `mkfs.vfat` (`dosfstools`), `mkfs.ext4`, `mkfs.xfs`; `mount DEV DIR`, `umount DIR` ("target is busy": `fuser -vm DIR` / `lsof DIR`, stop the process, then umount; remove the fstab line so it stays unmounted); `findmnt`, `df -hT` |
| **6.2** Mount and unmount network file systems using NFS<br>*Lab 07 tasks 3, 6* | `dnf install nfs-utils`; `showmount -e server` (v3) or just mount; `mount -t nfs server:/export /mnt`; fstab: `server:/export /mnt nfs defaults,_netdev 0 0` |
| **6.3** Configure autofs<br>*Lab 07 task 4* | `dnf install autofs`; master map `/etc/auto.master.d/x.autofs`: `/remote /etc/auto.remote`; map: `key -rw,sync server:/path` or wildcard `* -rw server:/homes/&`; direct map: `/- /etc/auto.direct` with absolute keys; `systemctl enable --now autofs` |
| **6.4** Extend existing logical volumes<br>*Lab 07 task 2* | `lvextend -r -L 800M vg/lv` (or `-L +200M`, `-l +100%FREE`); without `-r`: `xfs_growfs /mountpoint` / `resize2fs /dev/vg/lv`; add space first with `vgextend` if needed |
| **6.5** Diagnose and correct file permission problems<br>*Lab 07 task 5; 01 tasks 4–5* | `ls -ld`, `namei -l /full/path` (every parent dir), `getfacl`/`setfacl -m u:x:rw`/`-x`/`-b`, `id user` (and re-login after group change), setgid dirs, umask, SELinux (`ls -Z`, AVCs) |

**Traps:** XFS can't shrink. A home dir automount needs the *parent* (`/remote/homes`) to NOT exist as a real dir
with content. Users added to a group must log in again to get it. A `+` after `ls -l` mode bits means an ACL is set,
and the ACL mask can silently limit group/named entries.

---

## 7. Deploy, configure, and maintain systems  → `labs/08-scheduling-services-time` (container), `labs/05-boot` (VM), `labs/02-software`

| Official objective (verbatim) and lab | Must-know |
|---|---|
| **7.1** Schedule tasks using at, cron and systemd timer units<br>*Lab 08 tasks 1–3* | `at now + 2 hours`, `at 16:00 tomorrow`, `atq`, `atrm N`, `at -c N`; `/etc/at.allow`/`at.deny`; `atd` running |
| ↳ cron<br>*Lab 08 task 1* | `crontab -e [-u user]`, `crontab -l`; fields `min hour dom month dow`: `*/5 * * * 1-5`, `0 2 1 * *`; system: `/etc/cron.d/file` (has a user field), `/etc/cron.{daily,hourly}/`; `man 5 crontab` |
| ↳ systemd timer units<br>*Lab 08 task 3* | `x.service` (Type=oneshot, ExecStart=) + `x.timer` with `[Timer] OnCalendar=*:0/15` or `OnBootSec=`/`OnUnitActiveSec=`, `Persistent=true`, `[Install] WantedBy=timers.target`; `systemctl enable --now x.timer`; `systemctl list-timers`; `systemd-analyze calendar 'Mon *-*-* 02:00'` |
| **7.2** Start and stop services and configure services to start automatically at boot<br>*Lab 08 task 4; 04 task 6* | `systemctl enable --now x`, `disable`, `mask`/`unmask`, `is-enabled`, `list-unit-files --type=service`, `systemctl daemon-reload` after editing units; `systemctl edit x` for drop-ins |
| **7.3** Configure systems to boot into a specific target automatically<br>*Lab 08 task 5; 05 task 5* | `systemctl get-default`, `systemctl set-default multi-user.target` |
| **7.4** Configure time service clients<br>*Lab 08 task 6* | `/etc/chrony.conf`: `server host iburst` (or `pool`), `systemctl enable --now chronyd`, `chronyc sources -v`, `chronyc tracking`, `timedatectl`, `timedatectl set-timezone Region/City`, `timedatectl set-ntp true` |
| **7.5** Install and update software packages from Red Hat Content Delivery Network, a remote repository, or from the local file system<br>*Lab 02 tasks 2–4, 9 (CDN: guide only, needs a subscription)* | from CDN (`subscription-manager register`, `dnf update`), a remote repo (Section 2), or local files (`dnf install ./x.rpm`) |
| **7.6** Modify the system bootloader<br>*Lab 05 tasks 2–4* | `grubby --info=ALL`, `grubby --update-kernel=ALL --args="x=y"`/`--remove-args=`, `grubby --set-default=/boot/vmlinuz-…`, `grubby --default-kernel`; `/etc/default/grub` (GRUB_TIMEOUT) → `grub2-mkconfig -o /boot/grub2/grub.cfg` |

**Traps:** cron's `%` must be escaped as `\%`. A unit file edit needs `daemon-reload`. A timer is enabled, not its
service. `set-default` doesn't change the current target.

---

## 8. Manage basic networking  → `labs/09-networking` (VM)

| Official objective (verbatim) and lab | Must-know |
|---|---|
| **8.1** Configure IPv4 and IPv6 addresses<br>*Lab 09 task 1* | `nmcli dev status`, `nmcli con show`; `nmcli con add type ethernet con-name X ifname eth1 ipv4.method manual ipv4.addresses 192.168.1.10/24 ipv4.gateway 192.168.1.1 ipv4.dns 192.168.1.1 ipv6.method manual ipv6.addresses 2001:db8::10/64`; `nmcli con mod X +ipv4.addresses …`; `nmcli con up X`; `nmtui`; `ip -br addr`, `ip route`, `ip -6 route` |
| **8.2** Configure hostname resolution<br>*Lab 09 tasks 3–4* | `hostnamectl set-hostname host.domain`; `/etc/hosts`; DNS via `ipv4.dns`/`ipv4.dns-search`; `/etc/nsswitch.conf`; check with `getent hosts name` (not `dig`, which skips /etc/hosts) |
| **8.3** Configure network services to start automatically at boot<br>*Lab 09 task 5* | `systemctl enable --now httpd/sshd/...`; NM profile `connection.autoconnect yes` |
| **8.4** Restrict network access using firewalld and firewall-cmd<br>*Lab 09 task 6; 11 task 6* | `firewall-cmd --get-default-zone`, `--list-all`, `--permanent --add-service=http`, `--add-port=8080/tcp`, `--remove-service=`, `--reload`, `--runtime-to-permanent`, `--get-services`, `--zone=X --add-source=10.0.0.0/24`, rich rules |

**Traps:** `nmcli con mod` doesn't apply until `con up` or reboot. Two profiles for one device: the wrong one may win at
boot (delete the old one). Keyfiles live in `/etc/NetworkManager/system-connections/` (mode 600). The address goes
on the *connection*, not the device.

---

## 9. Manage users and groups  → `labs/10-users-groups` (container)

| Official objective (verbatim) and lab | Must-know |
|---|---|
| **9.1** Create, delete, and modify local user accounts<br>*Lab 10 tasks 2, 5–7* | `useradd [-u UID] [-g primary] [-G sup1,sup2] [-c comment] [-s shell] [-d home] [-m] name`; `usermod -aG grp user` (‑a!), `usermod -s`, `-d NEW -m` (move home), `-l newname`, `-L`/`-U` lock/unlock, `-e YYYY-MM-DD`; `userdel -r`; `/etc/passwd`, `/etc/shadow`; defaults in `/etc/login.defs` and `/etc/default/useradd` |
| **9.2** Change passwords and adjust password aging for local user accounts<br>*Lab 10 tasks 2–3* | `passwd user`, `echo 'user:pw' \| chpasswd`, `passwd --stdin`; `chage -l`, `chage -M 90 -m 1 -W 7 -I 10 -E 2027-12-31 user`, `chage -d 0 user` (force change), `passwd -e`; `PASS_MAX_DAYS`/`PASS_MIN_DAYS`/`PASS_WARN_AGE` in login.defs (new users only) |
| **9.3** Create, delete, and modify local groups and group memberships<br>*Lab 10 tasks 1–2* | `groupadd [-g GID] g`, `groupmod -n new old`, `groupdel`, `gpasswd -a user g` / `-d user g`, `id user`, `groups user`, `/etc/group`, `/etc/gshadow`, `newgrp` |
| **9.4** Configure privileged access<br>*Lab 10 task 4* | `visudo` / `visudo -f /etc/sudoers.d/x`: `user ALL=(ALL) ALL`, `%group ALL=(ALL) NOPASSWD: ALL`, `user ALL=(root) /usr/bin/systemctl restart httpd`; `wheel` group has sudo by default; `sudo -l -U user`; `visudo -c` |

**Traps:** `-G` without `-a` *replaces* groups. `nologin` users can't log in but still exist (sftp etc.). Set login.defs
before creating users when both are asked.

---

## 10. Manage security  → `labs/11-security` (VM)

| Official objective (verbatim) and lab | Must-know |
|---|---|
| **10.1** Configure firewall settings using firewall-cmd/firewalld<br>*Lab 11 task 6; 09 task 6* | as in Section 8; plus services vs ports, zones (`--get-active-zones`, `--set-default-zone`), rich rules: `firewall-cmd --permanent --add-rich-rule='rule family="ipv4" source address="1.2.3.4" service name="ssh" reject'` |
| **10.2** Manage default file permissions<br>*Lab 11 task 7* | `umask` (027 → files 640, dirs 750); per user in `~/.bashrc`/`~/.bash_profile`; system-wide `UMASK` in `/etc/login.defs` + `/etc/profile.d/*.sh` |
| **10.3** Configure key-based authentication for SSH<br>*Lab 11 task 8* | `ssh-keygen -t ed25519`, `ssh-copy-id user@host`, `~/.ssh` 700, `authorized_keys` 600; `/etc/ssh/sshd_config(.d/)`: `PermitRootLogin`, `PasswordAuthentication` → `systemctl reload sshd` |
| **10.4** Set enforcing and permissive modes for SELinux<br>*Lab 11 task 1* | `getenforce`, `setenforce 0/1`, `sestatus`; `/etc/selinux/config` `SELINUX=enforcing` (needs reboot from disabled; disabled→enforcing requires relabel); kernel arg `enforcing=0` for one boot |
| **10.5** List and identify SELinux file and process context<br>*Lab 11 task 2* | `ls -Z`, `ps -eZ`, `ps -Z -C httpd`, `id -Z`; `user:role:type:level`; the **type** (`httpd_t`, `httpd_sys_content_t`) is what matters |
| **10.6** Restore default file contexts<br>*Lab 11 task 4; 05 task 1* | `restorecon -Rv /path`; `touch /.autorelabel` for everything at next boot; `mv` keeps labels, `cp` creates new ones |
| **10.7** Manage SELinux port labels<br>*Lab 11 task 3* | `semanage port -l \| grep http`, `semanage port -a -t http_port_t -p tcp 82`, `-m` modify, `-d` delete |
| **10.8** Use Boolean settings to modify system SELinux settings<br>*Lab 11 task 5* | `getsebool -a \| grep httpd`, `setsebool -P name on`, `semanage boolean -l [-C]` |

**Persistent file contexts:** `semanage fcontext -a -t httpd_sys_content_t '/srv/www(/.*)?'` then `restorecon -Rv /srv/www`.
**Troubleshooting loop:** reproduce → `ausearch -m AVC -ts recent` / `journalctl -t setroubleshoot` / `sealert -a /var/log/audit/audit.log`
→ apply the fcontext/port/boolean fix it suggests (never `audit2allow` on the exam unless told). `man httpd_selinux` (from `selinux-policy-doc`).

---

## Mapping: objective sections → labs

| Exam section | Lab(s) |
|---|---|
| 1 Essential tools | 01 |
| 2 Manage software | 02 |
| 3 Shell scripts | 03 |
| 4 Operate running systems | 04, 05 |
| 5 Local storage | 06 |
| 6 File systems | 07 |
| 7 Deploy, configure, maintain | 08, 05 (bootloader, default target), 02 (installing software) |
| 8 Basic networking | 09 |
| 9 Users and groups | 10 |
| 10 Security | 11, plus firewall in 09 |

## Final-week checklist

- [ ] Reset root's password via `rd.break` in under 3 minutes, with SELinux relabel
- [ ] Partition → PV → VG (custom PE) → LV → mkfs → fstab by UUID → `mount -a`, without looking anything up
- [ ] Extend an XFS and an ext4 LV online
- [ ] autofs wildcard map for NFS home directories
- [ ] nmcli static IPv4 + IPv6 profile, hostname, /etc/hosts
- [ ] firewalld service + port + rich rule, permanent and runtime
- [ ] semanage fcontext + restorecon, semanage port, setsebool -P
- [ ] cron line, at job, and a systemd timer from scratch
- [ ] users with UID/groups/shell, chage aging, sudoers drop-in
- [ ] dnf repo file from a URL, local RPM install, Flatpak remote + install
- [ ] tuned profile, persistent journal, renice/kill a hog
- [ ] a short script with args, if/test, a loop and command substitution
- [ ] Reboot. Everything still works.
