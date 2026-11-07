# Lecture 10: Manage security

The final section is about controlling access in layers. The firewall decides which network connections reach the
machine at all. Default file permissions decide how private new files are. SSH keys replace guessable passwords for
remote logins. And SELinux, the topic most candidates fear, adds a second, mandatory layer of access control that
confines every service to exactly what it needs, even if it runs as root and even if it is compromised.

SELinux is half of this lecture because it is half of the section's objectives and because it is genuinely
different from everything else in Linux. The good news: once the model is clear, the exam tasks reduce to three
fixes (a file label, a port label, a boolean) and one diagnostic loop.

---

## 10.1 Configure firewall settings using firewall-cmd/firewalld

Lecture 8 (8.4) introduced firewalld: zones, services and ports, and the runtime/permanent split. Re-read it if
needed. This objective adds the rest of what you can configure.

### Choosing and assigning zones

```bash
firewall-cmd --get-zones                                   # all zones
firewall-cmd --get-default-zone
firewall-cmd --set-default-zone=internal                   # runtime AND permanent at once (no --permanent needed)
firewall-cmd --get-active-zones                            # which zones have interfaces/sources
firewall-cmd --get-zone-of-interface=enp7s0
firewall-cmd --permanent --zone=internal --change-interface=enp7s0    # move an interface
firewall-cmd --permanent --zone=trusted --add-source=192.168.50.0/24  # traffic FROM this network → trusted
firewall-cmd --permanent --zone=trusted --remove-source=192.168.50.0/24
firewall-cmd --reload
```

Recall the order: **source** match first, then the arrival **interface**, then the **default** zone. Sources make
per-network policies possible on a single interface: "allow everything from the admin network, only web from
elsewhere" is two zones, one with a source.

NetworkManager can also assign a connection's interface to a zone: `nmcli con mod NAME connection.zone internal`.
If both are set, keep them consistent.

### Services, ports, protocols and ICMP

```bash
firewall-cmd --permanent --add-service=nfs
firewall-cmd --permanent --add-port=82/tcp
firewall-cmd --permanent --add-protocol=gre
firewall-cmd --permanent --add-icmp-block=echo-request          # block pings
firewall-cmd --get-icmptypes
firewall-cmd --permanent --new-service=myapp                    # define your own service, then:
firewall-cmd --permanent --service=myapp --add-port=7000/tcp
```

### Rich rules

Services and ports apply to **everyone** reaching the zone. For conditions, such as a specific source address,
logging, rate limits, or explicit rejects, firewalld has **rich rules**, written in a small language
(`man firewalld.richlanguage`):

```text
rule [family="ipv4|ipv6"]
     [source [not] address="ADDR/PREFIX"]  [destination address="..."]
     [service name="NAME" | port port="N" protocol="tcp|udp" | protocol value="..." | icmp-type name="..."]
     [log prefix="TEXT" level="info" limit value="3/m"]
     [audit]
     accept | reject [type="..."] | drop | mark set="..."
```

```bash
# reject everything from one host
firewall-cmd --permanent --add-rich-rule='rule family="ipv4" source address="192.168.50.99" reject'
# allow ssh only from the admin network (and remove the general ssh service)
firewall-cmd --permanent --add-rich-rule='rule family="ipv4" source address="10.0.0.0/24" service name="ssh" accept'
firewall-cmd --permanent --remove-service=ssh
# log and drop http from a range, max 3 log lines per minute
firewall-cmd --permanent --add-rich-rule='rule family="ipv4" source address="203.0.113.0/24" service name="http" log prefix="HTTP-BLOCK " level="info" limit value="3/m" drop'
firewall-cmd --reload
firewall-cmd --list-rich-rules
firewall-cmd --permanent --remove-rich-rule='rule family="ipv4" source address="192.168.50.99" reject'
```

Quote the whole rule in **single quotes**, with double quotes around values inside. To remove a rich rule, repeat
it exactly with `--remove-rich-rule`; copying it from `--list-rich-rules` is the safe way.

**Rule order.** Within a zone, firewalld evaluates in a fixed order: port forwarding and masquerade, then logging
rules, then **deny** rich rules, then **allow** rich rules and the zone's services/ports, then the zone's target. So
a `reject` rich rule for a source wins over a service the zone allows; that's what makes "allow http, but not from
this host" work.

`reject` sends back an ICMP error (the client fails immediately: "Connection refused"/"No route to host"); `drop`
silently discards (the client hangs until it times out). Use what the task says.

### Port forwarding and masquerading (awareness)

```bash
firewall-cmd --permanent --add-forward-port=port=8080:proto=tcp:toport=80                 # local redirect
firewall-cmd --permanent --add-forward-port=port=2222:proto=tcp:toport=22:toaddr=10.0.0.5
firewall-cmd --permanent --add-masquerade          # NAT for traffic routed through this host
```

These belong to routers and gateways and are more RHCE than RHCSA, but recognise them in `--list-all`.

### Where it is stored, and emergencies

Permanent zone configuration: `/etc/firewalld/zones/ZONE.xml` (only zones you changed; defaults stay in
`/usr/lib/firewalld/zones/`). Global settings: `/etc/firewalld/firewalld.conf` (e.g. `DefaultZone=`).
`firewall-cmd --check-config` validates. `firewall-cmd --panic-on` drops all traffic (and would cut your SSH
session); `--panic-off` restores.

> **Exam angle.** Read the task for: zone (default unless stated), services vs ports, permanent (always, given the
> reboot), sources or rich rules. Confirm with both `--list-all` and `--list-all --permanent`; they should match.

---

## 10.2 Manage default file permissions

### What umask does

When a program creates a file, it asks for a mode, typically **0666** for files (programs don't ask for execute) and
**0777** for directories. The kernel then **removes** the bits set in the process's **umask**:

```text
requested  0666  rw-rw-rw-          0777  rwxrwxrwx
umask      0022  ----w--w-          0022  ----w--w-
result     0644  rw-r--r--          0755  rwxr-xr-x
```

The umask is a mask of bits to **take away**, not a mode to set, and it is not subtraction (subtracting gives wrong
answers for odd masks like 0033 applied to 0666; think "turn these bits off"). Useful values:

| umask | New files | New directories | Use |
|---|---|---|---|
| 0022 | 644 `rw-r--r--` | 755 `rwxr-xr-x` | readable by everyone (traditional root default) |
| 0002 | 664 `rw-rw-r--` | 775 `rwxrwxr-x` | group-writable (user private groups) |
| 0027 | 640 `rw-r-----` | 750 `rwxr-x---` | group can read, others nothing |
| 0077 | 600 `rw-------` | 700 `rwx------` | private |
| 0007 | 660 `rw-rw----` | 770 `rwxrwx---` | team-shared, others nothing |

The umask never **adds** permissions: a file is never created executable by umask alone. Default ACLs on a directory
(Lecture 6), when present, take precedence over the umask for files created in it.

### Seeing and setting it

```bash
umask            # 0022 (octal)
umask -S         # u=rwx,g=rx,o=rx (symbolic: what is KEPT)
umask 027        # for this shell and its children, until it exits
```

The umask is a **per-process** attribute, inherited by children. Setting it in a shell affects only that shell, so
making it permanent means setting it wherever new sessions start:

| Scope | Where | Notes |
|---|---|---|
| One user | `~/.bashrc` and/or `~/.bash_profile`: add `umask 027` | `.bash_profile` runs for login shells (and on RHEL sources `.bashrc`); `.bashrc` for interactive non-login shells |
| All users, shell sessions | a script in `/etc/profile.d/`, e.g. `/etc/profile.d/umask.sh` containing `umask 027` | read by `/etc/profile` for login shells |
| All users, every login (incl. non-shell) | `UMASK` in `/etc/login.defs`, applied at login by **pam_umask** | |

How RHEL decides the default: `UMASK 022` in `/etc/login.defs` is applied at login, and with
`USERGROUPS_ENAB yes`, regular users whose primary group is their own private group get the group bits matching
the owner bits, which yields an effective **0002** for normal users and **0022** for root. Check with `su - harry -c
umask` rather than trusting the file; distribution defaults have shifted between releases.

Services started by systemd don't run a login shell; their umask comes from the unit (`UMask=` in `[Service]`),
default 0022.

> **Exam angle.** "User X must have a umask of 027" → add `umask 027` to `~X/.bashrc` (owned by X), then verify
> as the user: `su - X -c umask` should print `0027`, and a test file should be `rw-r-----`.

---

## 10.3 Configure key-based authentication for SSH

### Why keys

Password authentication sends a secret the server can check, which means it can be guessed, phished or reused.
**Public-key authentication** uses an asymmetric key pair:

- The **private key** stays on the client, ideally protected by a **passphrase**. It never leaves the machine.
- The **public key** is copied to every server you want to log in to, into `~/.ssh/authorized_keys` of the target
  account. It can be shared freely.

At login, the server sends a challenge that only the holder of the matching private key can sign; the client signs
it, the server verifies the signature with the public key. Nothing secret crosses the network, nothing reusable is
stored on the server, and brute-forcing is pointless. It also enables automation (scripts, Ansible) without storing
passwords.

### Generating a key pair

```bash
ssh-keygen -t ed25519                        # modern default choice; RSA (-t rsa -b 4096) for old systems
# Enter file in which to save the key (/home/student/.ssh/id_ed25519): ⏎
# Enter passphrase (empty for no passphrase):  ← a passphrase encrypts the private key on disk
ssh-keygen -t ed25519 -N '' -f ~/.ssh/lab_key    # non-interactive, no passphrase, custom file
```

This creates `~/.ssh/id_ed25519` (private, mode 600) and `~/.ssh/id_ed25519.pub` (public, one line:
`ssh-ed25519 AAAAC3Nz... student@servera`). `ssh-keygen -lf key.pub` shows a key's fingerprint.

### Installing the public key on the server

```bash
ssh-copy-id sally@serverb                    # appends your default public key to ~sally/.ssh/authorized_keys
ssh-copy-id -i ~/.ssh/lab_key.pub sally@serverb
ssh sally@serverb                            # should not ask for sally's password now
```

`ssh-copy-id` asks for the password once (to log in and install the key), creates `~/.ssh` and `authorized_keys`
with the correct permissions if needed, and avoids duplicates. To do it by hand:

```bash
# on the server, as (or for) sally
mkdir -p ~sally/.ssh
cat student_key.pub >> ~sally/.ssh/authorized_keys
chown -R sally:sally ~sally/.ssh
chmod 700 ~sally/.ssh
chmod 600 ~sally/.ssh/authorized_keys
restorecon -Rv ~sally/.ssh                   # SELinux label ssh_home_t
```

### Why permissions matter so much here

sshd's `StrictModes yes` (the default) **ignores** `authorized_keys` if the file, the `.ssh` directory, or the home
directory is writable by anyone other than the owner (or root), because then someone else could add their key. The
login silently falls back to password authentication. The rules:

| Path | Must not be | Typical mode |
|---|---|---|
| `~` | group/other writable | 700 or 755 |
| `~/.ssh` | group/other writable | **700** |
| `~/.ssh/authorized_keys` | group/other writable | **600** |
| `~/.ssh/id_*` (private keys, on the client) | readable by others (ssh refuses to use it: "UNPROTECTED PRIVATE KEY FILE") | **600** |

And SELinux: sshd may only read `authorized_keys` labelled `ssh_home_t`. Files created in place inherit it, but a key
file **moved** from elsewhere keeps its old label. `restorecon -Rv ~/.ssh` fixes that.

When a key login falls back to a password prompt, run `ssh -v user@host` on the client (it shows which keys are
offered and the server's response) and read `/var/log/secure` or `journalctl -u sshd` on the server, which usually
says "Authentication refused: bad ownership or modes".

### ssh-agent

With a passphrase-protected key you'd type the passphrase at every connection. **ssh-agent** holds decrypted keys
in memory for your session:

```bash
eval $(ssh-agent)       # start an agent for this shell (desktop sessions usually have one already)
ssh-add                 # add default keys (asks for the passphrase once)
ssh-add -l              # list loaded keys
```

### Server configuration

sshd reads `/etc/ssh/sshd_config`, which on RHEL begins by including `/etc/ssh/sshd_config.d/*.conf`. For most
keywords **the first value found wins**, so a setting in a drop-in (read first) overrides the main file. Put your
changes in a drop-in such as `/etc/ssh/sshd_config.d/50-local.conf`, or edit the main file and check no drop-in
contradicts it (`grep -r PasswordAuthentication /etc/ssh/sshd_config*`).

| Setting | Meaning |
|---|---|
| `PubkeyAuthentication yes` | allow key logins (default) |
| `PasswordAuthentication no` | disable password logins (do this only after keys work!) |
| `PermitRootLogin prohibit-password` | root may log in with keys only (RHEL 9/10 default); `no` = never; `yes` = also with password |
| `AllowUsers alice bob` / `AllowGroups sshusers` | only these may log in |
| `DenyUsers`, `DenyGroups` | these may not |
| `Port 2222` | listen port (also needs `semanage port` and firewall changes) |
| `ClientAliveInterval 300` | keepalives |

```bash
sshd -t                         # test the configuration (no output = OK)
sshd -T | grep -i passwordauth  # the effective value of every setting
systemctl reload sshd           # apply (existing sessions stay connected)
```

**Keep a session open while changing sshd**, and test with a new connection, so a mistake doesn't lock you out.

> **Exam angle.** "Configure user X on servera to log in to serverb as Y without a password": as X,
> `ssh-keygen` (empty passphrase unless told otherwise) and `ssh-copy-id Y@serverb`; test `ssh Y@serverb hostname`.
> Don't disable password authentication unless asked.

---

## SELinux: the model

### Discretionary versus mandatory access control

Everything so far (owners, mode bits, ACLs) is **discretionary access control** (DAC): the owner of a file decides
who may access it, and root bypasses it all. That has two weaknesses. A user can carelessly `chmod 777` their files.
And any program, if compromised, can do anything its user can do; a hijacked web server running as `apache` can read
every world-readable file on the system, and one running as root can do anything at all.

**SELinux** (Security-Enhanced Linux) adds **mandatory access control** (MAC): a system-wide **policy**, written by
the distribution and loaded into the kernel, defines exactly which **process types** may access which **object types**
and how. Neither users nor root can override the policy by changing permissions. Every access must pass **both**
DAC and SELinux; SELinux can only further restrict, never grant what DAC denies.

The result is **confinement**: the web server can read web content, write its logs, bind to web ports, and nothing
else, even if it is root and even if an attacker controls it.

### Labels (contexts)

SELinux works on **labels**, called **security contexts**, attached to everything: processes, files, directories,
ports, users. A context has four fields:

```text
system_u : object_r : httpd_sys_content_t : s0
  user       role          type             level
```

- **user**: SELinux user (not the Linux user), e.g. `system_u`, `unconfined_u`, `staff_u`.
- **role**: `object_r` for files, `system_r` for services, `unconfined_r` for normal users.
- **type**: the important one. Processes have a type (also called their **domain**), such as `httpd_t`, `sshd_t`,
  `init_t`, or `unconfined_t` for normal user sessions. Files and ports have types such as `httpd_sys_content_t`,
  `shadow_t`, `user_home_t`, `http_port_t`.
- **level**: MLS/MCS sensitivity (`s0`, `s0:c0.c1023`), used by container isolation and MLS systems. Ignore it for
  the RHCSA.

The **targeted** policy (RHEL's default, `SELINUXTYPE=targeted`) confines network-facing and system services and
leaves ordinary logged-in users mostly **unconfined** (`unconfined_t`), so day-to-day user work rarely meets SELinux.

### Type enforcement

The core of the policy is **type enforcement** rules of the form "a process of domain X may perform operations Y on
objects of type Z":

```text
allow httpd_t httpd_sys_content_t : file { read getattr open };
allow httpd_t http_port_t : tcp_socket name_bind;
```

Everything not explicitly allowed is **denied**. So `httpd_t` can read files labelled `httpd_sys_content_t` and bind
to ports labelled `http_port_t`, but cannot read `user_home_t` or `shadow_t` files, or bind to port 82 unless 82 is
labelled `http_port_t`. When a process is denied, the kernel logs an **AVC denial** (Access Vector Cache) to the audit
log.

This is why the typical SELinux problem is a **wrong label**, not a wrong rule: the policy already allows web servers
to read web content; you just put content in a directory that isn't labelled as web content.

### How processes get their types

A process normally inherits its parent's domain. **Domain transitions** in the policy change it when a particular
program is executed: when `init_t` (systemd) runs `/usr/sbin/httpd`, which is labelled `httpd_exec_t`, the new process
enters `httpd_t`. That is why a service started by systemd is confined, while the same binary run by hand from an
unconfined shell may behave differently. Labels on executables matter.

---

## 10.4 Set enforcing and permissive modes for SELinux

### The three modes

| Mode | Policy loaded | Denials | Use |
|---|---|---|---|
| **enforcing** | yes | **enforced** and logged | normal operation (the exam's required state) |
| **permissive** | yes | **allowed**, but logged as if denied | troubleshooting: "would SELinux block this?" |
| **disabled** | no | nothing; files created meanwhile get no labels | avoid |

Permissive is a diagnostic tool: it lets you check whether SELinux is the cause of a problem (if it works in
permissive and fails in enforcing, it is), and collect all the denials an application would trigger. It is not a
fix.

### Checking and switching

```bash
getenforce                 # Enforcing / Permissive / Disabled
sestatus                   # mode, config file mode, policy name, MLS, policy version
setenforce 0               # permissive NOW (until reboot)
setenforce 1               # enforcing NOW
```

`setenforce` only works when SELinux is enabled (enforcing or permissive). It switches immediately but **does not
persist**.

### Persistent configuration

```bash
vim /etc/selinux/config
SELINUX=enforcing          # enforcing | permissive | disabled: the mode at boot
SELINUXTYPE=targeted
```

The file is read at boot. For a change to be both immediate and persistent, edit the file **and** run `setenforce`.

Kernel arguments override the file for a boot: `enforcing=0` (permissive), `enforcing=1`, and `selinux=0` (disable
SELinux entirely). On RHEL 9 and 10, `SELINUX=disabled` in the config file no longer fully disables SELinux in the
kernel; the supported way to disable it is the `selinux=0` kernel argument (`grubby --update-kernel ALL
--args selinux=0`). You should not need to on the exam: never disable SELinux there.

### Coming back from disabled

While SELinux is disabled, new and changed files receive no labels. Re-enabling requires a full **relabel**, or
services break: set `SELINUX=permissive` first, `touch /.autorelabel`, reboot (the relabel runs), check for denials,
then switch to enforcing. Going straight from disabled to enforcing risks an unbootable system.

### Per-domain permissive (awareness)

`semanage permissive -a httpd_t` makes only that domain permissive while the rest stays enforcing: a precise
troubleshooting tool. `semanage permissive -d httpd_t` undoes it. Don't leave it in place.

> **Exam angle.** "SELinux must be in enforcing mode" → `SELINUX=enforcing` in `/etc/selinux/config` **and**
> `setenforce 1`; verify `getenforce` and the file. If you found the system disabled, you also need a relabel and a
> reboot. Check this early: other SELinux tasks assume enforcing.

---

## 10.5 List and identify SELinux file and process context

Most familiar commands accept `-Z` to show contexts:

```bash
ls -Z /var/www/html/index.html           # file context
ls -dZ /var/www/html                     # a directory itself
ls -lZ /etc/shadow
ps -eZ                                   # every process with its context
ps -eZ | grep sshd                       # or: ps -Z -C sshd
ps auxZ
id -Z                                    # your own context (unconfined_u:unconfined_r:unconfined_t:...)
ss -Ztlnp                                # sockets with process contexts
stat -c %C /etc/shadow                   # just the context
```

```text
$ ls -Z /etc/shadow /var/www/html/index.html
system_u:object_r:shadow_t:s0 /etc/shadow
unconfined_u:object_r:httpd_sys_content_t:s0 /var/www/html/index.html

$ ps -eZ | grep -E 'sshd|httpd' | head -3
system_u:system_r:sshd_t:s0-s0:c0.c1023   1021 ?  00:00:00 sshd
system_u:system_r:httpd_t:s0              2210 ?  00:00:00 httpd
```

To extract only the type, for example to answer a question: `ls -Z FILE | cut -d: -f3`, or
`ps -eZ | awk '/sshd$/{split($1,a,":"); print a[3]; exit}'`.

Types you will meet constantly:

| Type | What |
|---|---|
| `httpd_sys_content_t` | web content httpd may read (`/var/www/html`) |
| `httpd_sys_rw_content_t` | web content httpd may write |
| `httpd_log_t`, `var_log_t` | logs |
| `user_home_t`, `user_home_dir_t` | users' files and home directories |
| `admin_home_t` | root's home |
| `ssh_home_t` | `~/.ssh` and its files |
| `etc_t`, `shadow_t`, `passwd_file_t` | config, the shadow and passwd files |
| `tmp_t` | `/tmp` |
| `default_t` | a file in a location the policy has no rule for (e.g. a new top-level directory): nothing confined may read it |
| `unlabeled_t` | a file with no label at all |
| `http_port_t`, `ssh_port_t` | port types |

File labels are stored on disk as an extended attribute (`security.selinux`), which is why they survive reboots, why
`cp -a`/`tar --selinux`/`rsync -X` can preserve them, and why file systems without xattrs (VFAT, NFS by default) get a
single label for everything via the `context=` mount option.

---

## 10.6 Restore default file contexts

### Where a file's label comes from

When a file is **created**, it normally inherits the type of its **parent directory** (unless a policy rule says
otherwise for that combination). So a file created in `/var/www/html` gets `httpd_sys_content_t`.

The policy also contains a database of **default contexts** by path, as regular expressions: the **file-context
rules**. They say what each path *should* be labelled, and are what relabeling tools apply:

```bash
semanage fcontext -l | grep '/var/www'         # rules from the policy and local customisations
# /var/www(/.*)?          all files    system_u:object_r:httpd_sys_content_t:s0
matchpathcon /var/www/html/x.html              # what the rules say this path should be
```

### Why labels go wrong

- **`mv` keeps the label.** A file created in `/root` (`admin_home_t`) and moved into `/var/www/html` is still
  `admin_home_t`, and httpd gets "403 Forbidden". `cp` creates a new file, which inherits the destination directory's
  label (unless `cp -a`/`--preserve=context`).
- **Content in a non-standard place.** `/srv/www` has no specific rule, so files there are `var_t` or `default_t`.
- **Files written while SELinux was disabled**, or by the initramfs (the `rd.break` password reset).
- **`chcon`** set a temporary label that a relabel later reverts.

### restorecon

`restorecon` resets files to the label the file-context rules specify:

```bash
restorecon -v /var/www/html/moved.html         # one file, show changes
restorecon -Rv /var/www/                        # recursively
restorecon -Rvn /srv/www                        # -n: dry run (show what would change)
touch /.autorelabel ; reboot                    # relabel the ENTIRE file system at next boot
fixfiles -F onboot                              # same, another way
```

`restorecon` only knows the rules. If the rules don't cover your path, it "restores" the wrong label. That is what
`semanage fcontext` is for.

### Defining new default contexts: semanage fcontext

To serve web content from `/srv/www`, tell the policy that path should be web content, **then** apply it:

```bash
semanage fcontext -a -t httpd_sys_content_t '/srv/www(/.*)?'
restorecon -Rv /srv/www
ls -Zd /srv/www ; ls -Z /srv/www
```

- `-a` add a rule, `-m` modify, `-d` delete; `-t` the type.
- The path is a **regular expression**, quoted. `'/srv/www(/.*)?'` means "`/srv/www` itself, and optionally a slash
  followed by anything", so the directory and everything under it. Forgetting `(/.*)?` labels only the directory.
- **`semanage fcontext` changes the rules but not the files.** Always follow it with `restorecon`.
- Local rules are stored in `/etc/selinux/targeted/contexts/files/file_contexts.local`; `semanage fcontext -l -C`
  lists only your customisations.
- An **equivalence** rule copies all labelling for one tree from another: `semanage fcontext -a -e /var/www /srv/www`.

The package `policycoreutils-python-utils` provides `semanage`. If it's missing: `dnf install
policycoreutils-python-utils` (or `dnf provides semanage`).

### chcon: temporary, avoid

`chcon -t httpd_sys_content_t /srv/www/index.html` changes a file's label directly, without touching the rules. It
works until the next `restorecon` or relabel, which silently undoes it. That makes it useful for a quick experiment
and wrong as a fix. Exam tasks often say "don't use chcon"; the grader may run a relabel.

> **Exam angle.** "The web server returns 403 for X" → check `ls -Z`, compare with `matchpathcon`, then
> `restorecon -v` (if the path is standard) or `semanage fcontext -a ... && restorecon -Rv` (if not).

---

## 10.7 Manage SELinux port labels

Ports have types too. The policy allows each confined domain to bind (listen) and connect to ports of particular
types: `httpd_t` may bind `http_port_t`, which by default includes 80, 81, 443, 488, 8008, 8009, 8443 and 9000.
Configuring httpd to `Listen 82` makes it fail to start in enforcing mode with
`(13)Permission denied: AH00072: make_sock: could not bind to address [::]:82`, because port 82 isn't
`http_port_t`.

```bash
semanage port -l | grep -w http_port_t          # which ports have the type
semanage port -l | grep -w 82                   # does 82 have any type?
semanage port -a -t http_port_t -p tcp 82       # add
semanage port -m -t http_port_t -p tcp 82       # modify (if 82 already has another type)
semanage port -d -t http_port_t -p tcp 82       # delete a local definition
semanage port -l -C                             # your customisations only
```

Use `-a` for a port with no type; if `-a` complains the port "is already defined", it belongs to another type, so use
`-m` to change it. The change is immediate and persistent. Ranges work: `-p tcp 8100-8110`.

The same principle applies to other services: sshd on port 2222 needs `semanage port -a -t ssh_port_t -p tcp 2222`.
The policy man pages tell you the port type each service uses (`man httpd_selinux`, `man sshd_selinux`, from the
`selinux-policy-doc` package).

A service on a new port usually needs **three** changes, and missing any of them looks like the same failure: the
service config (`Listen 82`), the SELinux port type, and the firewall (`firewall-cmd --permanent --add-port=82/tcp`).

---

## 10.8 Use Boolean settings to modify system SELinux settings

Some behaviours are legitimate for some sites and risky for others: should the web server be allowed to make outgoing
network connections (to a database or an API)? Serve users' `~/public_html`? Should FTP allow anonymous writes?
Rather than forcing everyone to write policy, the policy includes **booleans**: on/off switches that enable optional
sets of rules.

```bash
getsebool -a                                    # every boolean and its current value
getsebool -a | grep httpd
getsebool httpd_enable_homedirs
semanage boolean -l | grep httpd_enable_homedirs   # current, default, and a description
semanage boolean -l -C                          # booleans changed from their defaults
setsebool httpd_enable_homedirs on              # NOW only: lost at reboot
setsebool -P httpd_enable_homedirs on           # now AND persistently (-P writes the policy; takes a few seconds)
```

**`-P` is the persistence switch**, and forgetting it is the most common SELinux mistake on the exam. The value shown
by `getsebool` is the runtime value; `semanage boolean -l` shows both current and default, so you can confirm a
change survives.

Commonly used booleans:

| Boolean | Allows |
|---|---|
| `httpd_enable_homedirs` | httpd to serve `~user/public_html` |
| `httpd_can_network_connect` | httpd (e.g. PHP, a reverse proxy) to make outbound network connections |
| `httpd_can_network_connect_db` | httpd to connect to database ports |
| `httpd_use_nfs` | httpd to serve content from NFS |
| `use_nfs_home_dirs` | logins with NFS-mounted home directories |
| `ftpd_anon_write`, `ftpd_full_access` | FTP writes |
| `samba_enable_home_dirs`, `samba_export_all_rw` | Samba sharing |

Descriptions in `semanage boolean -l` and the `*_selinux` man pages tell you which boolean you need.

---

## SELinux troubleshooting: the loop

When something fails with "Permission denied" (or a 403, or a service that can't bind) and DAC permissions look
right:

```text
1. Reproduce the failure.
2. Confirm SELinux is involved:   ausearch -m AVC -ts recent      (or: setenforce 0, retry, setenforce 1)
3. Read the denial: who (scontext), did what (perms, class), to what (tcontext, path/port).
4. Pick the fix:  wrong file label → restorecon / semanage fcontext
                  port            → semanage port
                  optional behaviour → setsebool -P
5. Apply it, keep enforcing, retest.
```

### Reading an AVC denial

```text
type=AVC msg=audit(1762508123.442:812): avc:  denied  { read } for  pid=2210 comm="httpd"
  name="index.html" dev="dm-0" ino=1835
  scontext=system_u:system_r:httpd_t:s0
  tcontext=unconfined_u:object_r:admin_home_t:s0 tclass=file permissive=0
```

The process `httpd` in domain **`httpd_t`** was denied **`read`** on a **file** named `index.html` labelled
**`admin_home_t`**. httpd is allowed to read `httpd_sys_content_t`, not `admin_home_t`: this file was moved from root's
home. Fix: `restorecon -v` on it. `permissive=0` means it was actually blocked (enforcing).

Tools that read the logs for you:

```bash
ausearch -m AVC -ts recent                     # raw AVCs from the last 10 minutes (-ts today, -ts boot)
ausearch -m AVC -c httpd                        # for one command
grep AVC /var/log/audit/audit.log | tail
journalctl -t setroubleshoot                    # setroubleshoot's analysis, if setroubleshoot-server is installed
sealert -a /var/log/audit/audit.log             # explanations and suggested fixes for every denial
sealert -l ID                                   # the full report for one alert ID from the journal
ausearch -m AVC -ts recent | audit2why           # explains why: missing label? boolean? (policycoreutils-python-utils)
```

`sealert` is extremely helpful: it typically suggests the exact `semanage fcontext`/`restorecon`/`setsebool` command
with a confidence rating. Read its suggestions critically; one of them is often "generate a local policy module
with audit2allow", which you should **not** use on the exam unless told to: it writes new allow rules and widens the
policy instead of fixing a label.

Not every denial is logged: some are deliberately silenced with **dontaudit** rules. If you suspect SELinux but see no
AVCs, `semodule -DB` disables dontaudit temporarily (`semodule -B` restores it).

---

## Putting it together

A classic combined exam task: *"httpd must serve content from /srv/www on port 82. SELinux must stay enforcing."*

```bash
getenforce                                              # Enforcing (if not: fix 10.4 first)
dnf install -y httpd policycoreutils-python-utils
# (httpd config: Listen 82, DocumentRoot "/srv/www" with a <Directory> block granting access)
semanage fcontext -a -t httpd_sys_content_t '/srv/www(/.*)?'
restorecon -Rv /srv/www
semanage port -a -t http_port_t -p tcp 82
firewall-cmd --permanent --add-port=82/tcp && firewall-cmd --reload
systemctl enable --now httpd
curl -s http://localhost:82/ | head -3
ausearch -m AVC -ts recent                              # should be quiet now
```

Every layer from this lecture is in there: the firewall lets port 82 in, SELinux lets httpd bind it and read the
content, DAC lets the `apache` user read the files, and the service starts at boot.

**Now practise:** [Lab 11](#/lab/11) on the VM: SELinux modes, contexts, a non-standard web root and port, a moved
file, a boolean, firewall rich rules, a umask, and SSH keys.

## Review questions

1. In what order does firewalld choose a zone for an incoming packet? How do you send all traffic from
   10.0.0.0/24 to the `trusted` zone?
2. Write a rich rule rejecting all IPv4 traffic from 192.168.50.99, permanently.
3. Why does a reject rich rule win over a service the zone allows?
4. With umask 0027, what modes do new files and directories get? Why is no file created executable?
5. Where would you set a umask for one user, and for all users' login shells?
6. Why does sshd ignore `authorized_keys` if `~/.ssh` is mode 775?
7. Your key login falls back to a password prompt. List three things to check.
8. In `/etc/ssh/sshd_config.d/` and `sshd_config` both set `PasswordAuthentication`. Which wins?
9. What does SELinux add to standard Linux permissions? Can it grant access DAC denies?
10. Name the four fields of an SELinux context. Which one matters for the targeted policy?
11. Explain the difference between enforcing, permissive and disabled, and how to make enforcing persistent.
12. A file moved from `/root` into `/var/www/html` gives 403. Why, and what is the fix?
13. Why must `semanage fcontext` be followed by `restorecon`? What does `'(/.*)?'` do?
14. Why should you not use `chcon` as a fix?
15. httpd fails to bind to port 8888. What SELinux command fixes it, and what else might be needed?
16. What is a boolean, and what does `-P` do in `setsebool -P`?
17. Read this: `avc: denied { name_bind } for comm="sshd" src=2222 scontext=...:sshd_t tcontext=...:unreserved_port_t
    tclass=tcp_socket`. What's the fix?

<details><summary>Answers</summary>

1. Source address match, then interface, then default zone.
   `firewall-cmd --permanent --zone=trusted --add-source=10.0.0.0/24; firewall-cmd --reload`.
2. `firewall-cmd --permanent --add-rich-rule='rule family="ipv4" source address="192.168.50.99" reject'` then
   `firewall-cmd --reload`.
3. firewalld evaluates deny rich rules before allow rules and services.
4. Files 640, directories 750. Programs request 0666 for files, and umask only removes bits.
5. One user: `~/.bashrc` (or `~/.bash_profile`). All users: a script in `/etc/profile.d/` (or `UMASK` in
   `/etc/login.defs`).
6. `StrictModes` refuses keys when the directory or file is writable by others, since anyone could add a key.
7. Permissions/ownership of `~`, `~/.ssh` (700) and `authorized_keys` (600); the key actually in `authorized_keys`
   for the right user; SELinux label (`restorecon -Rv ~/.ssh`); sshd settings (`PubkeyAuthentication`,
   `AllowUsers`); `ssh -v` and `/var/log/secure`.
8. The drop-in, because it is included first and the first value wins.
9. Mandatory access control: a system-wide policy confining processes by type. No: both must allow access.
10. user, role, type, level. The type.
11. Enforcing blocks and logs; permissive logs but allows; disabled loads no policy. `SELINUX=enforcing` in
    `/etc/selinux/config` plus `setenforce 1`.
12. `mv` kept the `admin_home_t` label, which httpd can't read. `restorecon -v FILE`.
13. `semanage fcontext` only changes the rules; `restorecon` applies them to files. `(/.*)?` makes the rule match
    everything below the directory as well as the directory.
14. Its change isn't recorded in the policy, so the next restorecon or relabel reverts it.
15. `semanage port -a -t http_port_t -p tcp 8888`; also the firewall port and the httpd `Listen` directive.
16. An on/off switch for optional policy rules; `-P` makes the change persist across reboots.
17. sshd may not bind 2222 because it isn't `ssh_port_t`: `semanage port -a -t ssh_port_t -p tcp 2222`.

</details>
