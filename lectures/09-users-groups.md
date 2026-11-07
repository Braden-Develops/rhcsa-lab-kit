# Lecture 9: Manage users and groups

Every process on a Linux system runs as some user, and every file belongs to some user and group. Accounts are
therefore the foundation of the permission model from Lectures 1 and 6, and of SELinux's user mapping in
Lecture 10. This lecture explains how the system represents identities, what is in the four account databases,
how the account tools fill them in, how passwords and their aging work, and how to give limited administrative
power safely with sudo.

---

## Background: identity on Linux

### Users and groups are numbers

The kernel does not know names. A process carries numeric credentials: a **UID** (user ID), a primary **GID**
(group ID), and a list of **supplementary GIDs**. Files store an owner UID and a group GID. Names like `harry` and
`devops` are translated to numbers (and back) by the C library, using the sources configured in
`/etc/nsswitch.conf` (`passwd:` and `group:` lines): normally the local files described below, and possibly a
directory service via SSSD (FreeIPA/IdM, Active Directory, LDAP).

Consequences worth internalising:

- `ls -l` shows a **number** instead of a name when a file's UID has no account (for example after `userdel`
  without `-r`, or in a tar archive from another system). `find / -nouser` finds such files.
- Two accounts with the same UID **are the same user** to the kernel.
- Copying files between systems (or NFS with `sec=sys`) works by number, so UIDs should match across machines.

`id` shows your credentials: `uid=1000(harry) gid=1000(harry) groups=1000(harry),10(wheel),4000(sysops)
context=unconfined_u:unconfined_r:unconfined_t:s0-s0:c0.c1023`.

### Kinds of account

| UID range | Who | Notes |
|---|---|---|
| 0 | **root** | the superuser: bypasses permission checks. It is the UID, not the name, that matters |
| 1–200 | statically allocated system accounts | `bin`, `daemon`, `adm`, `ftp`, `apache` (48)... |
| 201–999 | dynamically allocated system accounts | created by packages for services (`chrony`, `sssd`, `polkitd`) |
| 1000+ | **regular (human) users** | `UID_MIN 1000` in `/etc/login.defs` |

System accounts exist so each service runs with only its own privileges, not root's. They usually have no password
and a shell of `/sbin/nologin`.

### User private groups

RHEL uses the **user private group** (UPG) scheme: every new user gets a group with the same name (and normally the
same number) as their primary group, of which they are the only member. Because nobody else is in it, the default
umask can safely give the group write permission (Lecture 10, 10.2), which makes shared directories with setgid
(Lecture 1) work smoothly: files you create in a team directory are writable by the team, while files in your home
are still private.

### Primary and supplementary groups

- The **primary group** is stored in the user's `/etc/passwd` line. It becomes the group of files the user creates
  (unless a setgid directory says otherwise).
- **Supplementary groups** are listed in `/etc/group`. They grant access to group-owned resources.

Both are applied **at login** (by `login`, `sshd`, `su`, etc., which call `initgroups()`). A running session does not
see membership changes; the user must log in again, or use `newgrp GROUP` to start a shell with that group as
primary.

---

## The account databases

### /etc/passwd: one line per account, world-readable

```text
harry:x:1001:1001:Harry Potter:/home/harry:/bin/bash
  1   2   3    4       5            6          7
```

1. **Login name**.
2. Password placeholder: `x` means "the hash is in `/etc/shadow`". (Historically the hash lived here.)
3. **UID**.
4. **Primary GID**.
5. **GECOS** (comment): full name, sometimes phone/office, comma-separated.
6. **Home directory**.
7. **Login shell**: `/bin/bash`; or `/sbin/nologin` (prints "This account is currently not available." and exits)
   for accounts that must not log in interactively; `/bin/false` does the same silently.

A `nologin` shell blocks interactive logins (console, ssh shell, `su`), but the account still exists and may
still be usable by services that don't run a shell, such as some SFTP or mail setups. It is the standard way to make
a "user with no interactive shell".

### /etc/shadow: passwords and aging, readable only by root

```text
harry:$6$Q5mF...$Tg0x...:20399:1:90:7:10:20819:
  1          2              3   4  5  6  7    8   9
```

1. Login name.
2. **Password hash**, in the form `$id$salt$hash`. `$6$` is SHA-512, `$y$` is yescrypt (the algorithm for new
   passwords is set by `ENCRYPT_METHOD` in `/etc/login.defs`). The random **salt** means two users with the same
   password have different hashes. Special values: `!` or `!!` (or a `!` prefixed to a hash) = **locked** / no
   password set; `*` = no password login possible; an **empty** field = no password needed (dangerous).
3. **Last change**: date of the last password change, in **days since 1970-01-01**. `0` means "must change at next
   login".
4. **Minimum age**: days before the password may be changed again.
5. **Maximum age**: days after which the password must be changed.
6. **Warning period**: days of warnings before it expires.
7. **Inactivity period**: days after expiry during which the user can still log in, but must change the password
   immediately. After that, the account is locked.
8. **Account expiration date**: days since 1970-01-01 after which the **account** can't be used at all (unrelated to
   password age).
9. Reserved.

Empty fields mean "no limit". `chage -l` displays all of this as real dates, which is easier than doing the
arithmetic (`date -d @$((20399*86400))` if you ever need to).

### /etc/group and /etc/gshadow

```text
sysops:x:4000:natasha,harry
  1    2   3      4
```

Group name, password placeholder, **GID**, and the comma-separated list of **supplementary** members. A user whose
**primary** group is `sysops` is *not* listed here, yet is a member; so to see all members you must check both files,
or use `getent group sysops` plus `id USER`. `/etc/gshadow` holds group passwords (rarely used) and group
**administrators** (who can manage membership with `gpasswd`).

### Never edit them carelessly

Use the commands below. If you must edit by hand, use `vipw` / `vigr` (and `vipw -s` / `vigr -s` for the shadow
files), which lock the files against concurrent changes. `pwck` and `grpck` check consistency. A broken
`/etc/passwd` can prevent everyone, including root, from logging in.

`getent passwd harry` and `getent group sysops` show entries from **all** configured sources, not just the local
files, and are the right way to check whether an account exists.

---

## 9.1 Create, delete, and modify local user accounts

### What useradd does

`useradd harry` does more than add a line:

1. Picks the next free UID ≥ `UID_MIN` (and creates a user private group with a matching GID).
2. Adds lines to `/etc/passwd`, `/etc/shadow` (password locked: `!!`), `/etc/group` and `/etc/gshadow`.
3. Creates the home directory `/home/harry` (mode 0700 on RHEL, from `HOME_MODE` in login.defs) and copies the
   contents of **`/etc/skel/`** into it (default `.bashrc`, `.bash_profile`, `.bash_logout`). Anything you put in
   `/etc/skel` appears in every **new** user's home.
4. Creates a mail spool file `/var/spool/mail/harry` (if `CREATE_MAIL_SPOOL=yes`).

Defaults come from two files:

| File | Controls |
|---|---|
| `/etc/login.defs` | UID/GID ranges (`UID_MIN`, `SYS_UID_MAX`...), password aging defaults (`PASS_MAX_DAYS`, `PASS_MIN_DAYS`, `PASS_WARN_AGE`), `CREATE_HOME`, `HOME_MODE`, `UMASK`, `USERGROUPS_ENAB`, `ENCRYPT_METHOD` |
| `/etc/default/useradd` | default shell (`SHELL=/bin/bash`), home base (`HOME=/home`), `SKEL`, `INACTIVE`, `EXPIRE`, `GROUP` (shown by `useradd -D`) |

These defaults apply only to accounts created **after** you change them. If a task asks for a default (for example a
maximum password age for new users) **and** for users to be created, set the default first.

### useradd options

```bash
useradd harry
useradd -u 3500 -c "John Smith" -G dbadmin john         # UID, comment, supplementary group(s)
useradd -g sysops -G wheel,dbadmin alice                # -g PRIMARY group (must exist), -G supplementary list
useradd -s /sbin/nologin sarah                          # no interactive shell
useradd -d /data/web -m webadm                          # custom home, create it
useradd -M svcuser                                      # don't create a home
useradd -r -s /sbin/nologin myservice                   # system account (UID < 1000, no home by default)
useradd -e 2027-12-31 contractor                        # account expiry date
useradd -k /etc/skel-dev devuser                        # different skeleton directory
useradd -D                                              # show defaults; useradd -D -s /bin/zsh changes one
```

`-g` (lower case) is the **primary** group; `-G` (upper case) is a comma-separated list of **supplementary** groups.
Getting them backwards is a common slip.

### usermod

```bash
usermod -aG sysops harry          # ADD to a supplementary group (keep the others)
usermod -G sysops harry           # REPLACE all supplementary groups with just sysops (!)
usermod -g devops harry           # change primary group
usermod -s /sbin/nologin harry    # change shell
usermod -c "Harry P" harry        # comment
usermod -u 1500 harry             # change UID (files in his home are re-owned; others elsewhere are not)
usermod -l harryp harry           # rename the login (home directory and group keep their old names)
usermod -d /home/dbadmin/john -m john    # new home directory, and MOVE the contents (-m)
usermod -L harry ; usermod -U harry      # lock / unlock the password
usermod -e 2027-12-31 john        # account expiry; usermod -e "" (or -e -1) removes it
```

**`-G` without `-a` replaces** the user's supplementary groups. Always type `-aG` when adding. And `-d` without `-m`
only changes the passwd field: the user's files stay in the old place and their new home doesn't exist.

Changing a user's UID or name while they are logged in or running processes is refused (`usermod: user harry is
currently used by process 1234`). Kill or wait for those processes.

### userdel

```bash
userdel tempuser       # remove the account; home directory and mail spool are LEFT behind
userdel -r tempuser    # also remove the home directory and mail spool
```

Files the user owned elsewhere (in `/tmp`, shared directories) are never removed. They now show a bare UID, and if a
new user later receives the same UID, **they inherit those files**. Find them first (`find / -user tempuser`) if it
matters, or remove them afterwards with `find / -nouser`.

### Why a user cannot log in: a checklist

When "dave can't log in", the cause is almost always one of these. Check each:

| Check | How | Fix |
|---|---|---|
| Account exists | `getent passwd dave` | `useradd` |
| Shell is valid | 7th field: `/sbin/nologin`, `/bin/false`, or a non-existent path | `usermod -s /bin/bash dave` |
| Password locked | `passwd -S dave` (`LK`), `!` at the start of the shadow hash | `usermod -U dave` / `passwd -u dave` |
| Account expired | `chage -l dave` "Account expires" in the past | `chage -E -1 dave` (or a future date) |
| Password expired + inactive | `chage -l dave` | `chage -d` / `passwd dave` / adjust `-I` |
| Home directory missing or wrong owner | `ls -ld ~dave` | create / `chown -R dave:dave` |
| SSH-specific | `AllowUsers`, `DenyUsers`, `PermitRootLogin` in sshd config; key permissions | Lecture 10 |
| SELinux / PAM | `/var/log/secure`, `journalctl -t sshd -t login` | read the message |

`/var/log/secure` usually tells you exactly which one it is.

---

## 9.2 Change passwords and adjust password aging for local user accounts

### Setting passwords

```bash
passwd                        # change your own (asks for the current one)
passwd harry                  # as root: set harry's, no old password needed
echo 'Rhcsa@2026' | passwd --stdin harry          # non-interactive (RHEL's passwd supports --stdin)
echo 'harry:Rhcsa@2026' | chpasswd                # one or many "user:password" lines
passwd -S harry               # status: PS (set), LK (locked), NP (no password), plus aging values
passwd -l harry ; passwd -u harry                 # lock / unlock
passwd -d harry               # delete the password (passwordless login!): avoid
passwd -e harry               # expire now: must change at next login
```

`passwd` checks new passwords against **pwquality** rules (`/etc/security/pwquality.conf` and
`/etc/security/pwquality.conf.d/`: `minlen`, `dcredit`, `dictcheck`...). For ordinary users a weak password is
rejected; for root it only warns ("BAD PASSWORD: ...") and accepts it. On the exam you set the password the task
gives you, even if it is weak.

Never put real passwords on command lines in production (they end up in shell history and are visible in `ps`);
on the exam it's fine.

### How password aging works

The aging fields in `/etc/shadow` describe a timeline relative to the **last change** date:

```text
 last change          min                                  max      max+inactive
     │◄──── can't change ────►│                              │◄─ grace ─►│
─────┼────────────────────────┼─────────────────────┬────────┼───────────┼──────────►
     │                                              │ warn   │ expired:  │ account locked
     │                                              │ period │ must      │ (inactive)
     │                                              │        │ change at │
     │                                              │        │ login     │
```

- **Minimum age** (`-m`) stops users cycling through passwords to get back to their old favourite.
- **Maximum age** (`-M`) forces a change after N days. `99999` effectively means "never".
- **Warning** (`-W`) days before expiry, the user is warned at login.
- **Inactive** (`-I`) days after expiry, the user may still log in but must set a new password; after that, the
  account is disabled until an admin intervenes.
- **Account expiry** (`-E`) is a separate, absolute date on which the **account** stops working, regardless of the
  password, used for contractors and temporary staff.
- **Last change = 0** (`-d 0`) forces a change at the next login.

### chage

```bash
chage -l natasha                          # human-readable summary
chage -M 90 -W 7 natasha                  # max 90 days, warn 7 days before
chage -m 1 -M 90 -W 7 -I 10 natasha       # with min and inactive
chage -d 0 harry                          # force change at next login (same as passwd -e)
chage -E 2027-12-31 john                  # account expiry date (YYYY-MM-DD)
chage -E -1 john                          # never expires
chage natasha                             # interactive: prompts for each value
```

`chage -l` output:

```text
Last password change                                    : Nov 07, 2026
Password expires                                        : Feb 05, 2027
Password inactive                                       : never
Account expires                                         : never
Minimum number of days between password change          : 0
Maximum number of days between password change          : 90
Number of days of warning before password expires       : 7
```

About account expiry dates: the shadow field stores a day number, and the account is unusable **from** that day.
`chage -E 2027-12-31` and `usermod -e 2027-12-31` set the same value; graders check the stored date, so use exactly
the date the task gives.

### Defaults for new users

`PASS_MAX_DAYS`, `PASS_MIN_DAYS` and `PASS_WARN_AGE` in `/etc/login.defs` set the aging values given to accounts
created afterwards. They do **not** change existing users (use `chage` for those). `INACTIVE` and `EXPIRE` defaults
live in `/etc/default/useradd` (`useradd -D -f 10`, `useradd -D -e 2027-12-31`).

> **Exam angle.** "All new users must change their password every 60 days" → `PASS_MAX_DAYS 60` in login.defs
> (before creating users). "User X must change password every 90 days" → `chage -M 90 X`. "User Y must change
> their password at first login" → `chage -d 0 Y`. Verify each with `chage -l`.

---

## 9.3 Create, delete, and modify local groups and group memberships

```bash
groupadd sysops                     # next free GID ≥ GID_MIN (1000)
groupadd -g 4000 sysops             # specific GID
groupadd -r appsvc                  # system group (GID < 1000)
groupmod -n operators sysops        # rename
groupmod -g 4500 operators          # change GID (files owned by the old GID are NOT updated)
groupdel operators                  # delete (refused if it's any user's PRIMARY group)

gpasswd -a harry sysops             # add one member
gpasswd -d harry sysops             # remove one member
gpasswd -M natasha,harry sysops     # set the complete member list
gpasswd -A natasha sysops           # make natasha a group administrator (she can then use gpasswd -a/-d)
usermod -aG sysops harry            # the same addition, from the user's side

getent group sysops                 # supplementary members
id harry ; groups harry             # groups for a NEW login of harry
lid -g sysops                       # all members (if libuser is installed)
```

Removing a user from a group: `gpasswd -d harry sysops` is the precise tool. (`usermod -G` with a list that omits
the group also works, but you must list every group to keep.)

Remember that membership changes apply to **new** logins. Test with `su - harry -c id`, not with a shell harry
already had open.

### Groups in practice: a shared team directory

Users, groups, permissions and setgid come together in the standard pattern:

```bash
groupadd -g 4000 sysops
usermod -aG sysops natasha ; usermod -aG sysops harry
mkdir -p /srv/sysops
chgrp sysops /srv/sysops
chmod 2770 /srv/sysops             # group rwx, setgid: new files belong to sysops, others have no access
su - natasha -c 'touch /srv/sysops/test && ls -l /srv/sysops/test'
```

---

## 9.4 Configure privileged access

### Why not just share the root password

Everyone logging in as root means no accountability (the logs show "root" did it), no way to revoke one person's
access without changing the password for everyone, and every task run with full power. Privileged access is better
**delegated**: individuals log in as themselves and elevate specific commands, with each use logged.

RHEL's tools for this:

- **`su`**: become another user with **their** password (Lecture 1). Needs the root password to become root.
- **`sudo`**: run commands as root (or another user) with **your own** password, according to a policy in
  `/etc/sudoers`. Every command is logged to the journal and `/var/log/secure`.
- **polkit**: fine-grained authorisation for desktop and system services (what lets a desktop user reboot or change
  network settings). Not examined, but it's why some actions prompt for a password without sudo.

### The wheel group

RHEL's default `/etc/sudoers` contains:

```text
%wheel  ALL=(ALL)       ALL
```

so **members of the `wheel` group can run any command as any user** with sudo, after entering their own password.
`usermod -aG wheel harry` is the quickest way to make someone a full administrator. The installer's "Make this user
administrator" checkbox does exactly that.

### sudoers syntax

A rule has the form:

```text
WHO   WHERE = (AS_WHOM)  [TAG:]  WHAT
harry ALL   = (ALL)              ALL
```

| Part | Meaning | Examples |
|---|---|---|
| WHO | a user, `%group`, or an alias | `harry`, `%sysops`, `ADMINS` |
| WHERE | hosts the rule applies on (for shared sudoers files) | `ALL`, `servera` |
| AS_WHOM | users (and optionally `:groups`) the command may run as | `(ALL)`, `(root)`, `(ALL:ALL)`, `(postgres)` |
| TAG | modifiers | `NOPASSWD:` (no password prompt), `PASSWD:` |
| WHAT | commands, **with absolute paths**, comma-separated; arguments may be specified | `ALL`, `/usr/bin/systemctl restart httpd`, `/usr/sbin/useradd, /usr/sbin/usermod` |

Examples:

```text
%sysops   ALL=(ALL)       NOPASSWD: ALL                       # group: everything, no password
sarah     ALL=(root)      /usr/bin/systemctl restart httpd    # exactly this command (and arguments)
operator  ALL=(root)      /usr/bin/systemctl * httpd          # wildcard in arguments (use carefully)
dba       ALL=(postgres)  ALL                                 # anything, but only as postgres
helpdesk  ALL=(root)      /usr/bin/passwd *, !/usr/bin/passwd root   # reset passwords, but not root's

User_Alias   WEBTEAM = alice, bob
Cmnd_Alias   WEBCMDS = /usr/bin/systemctl restart httpd, /usr/bin/systemctl reload httpd
WEBTEAM      ALL=(root) WEBCMDS

Defaults     timestamp_timeout=10     # minutes before sudo asks for the password again (default 5)
Defaults:sarah  !lecture
```

If a command is listed **without** arguments, any arguments are allowed; with arguments, exactly those are allowed;
`""` as the argument list means "no arguments".

Be careful what you delegate: allowing an editor (`vim`), a pager (`less`), a shell, `find`, `tar`, or a command
like `systemctl edit` effectively grants a root shell, because those programs can run other commands.

### Where to put rules: /etc/sudoers.d

The main `/etc/sudoers` ends with `#includedir /etc/sudoers.d` (shown as `@includedir` in newer versions; the `#` is
part of the directive, not a comment). Every file in that directory is read, **except** names containing a `.` or
ending in `~`. Put your rules in a drop-in file instead of editing the main file: it survives package updates
untouched, is easy to remove, and keeps each policy separate.

**Always edit with `visudo`**, which locks the file, opens it in an editor, and **checks the syntax before saving**.
A syntax error in any sudoers file breaks sudo for everyone, and if root has no password, that can lock you out of
administration entirely.

```bash
visudo                                   # edit /etc/sudoers
visudo -f /etc/sudoers.d/sysops          # create/edit a drop-in safely
visudo -c                                # check all sudoers files
echo '%sysops ALL=(ALL) NOPASSWD: ALL' > /etc/sudoers.d/sysops && chmod 0440 /etc/sudoers.d/sysops && visudo -c
```

Files in `sudoers.d` should be mode `0440` and owned by root (visudo does this; the `echo` method needs the `chmod`).
If `visudo -c` reports an error, fix it before doing anything else.

### Checking what someone may do

```bash
sudo -l                    # as the user: my privileges
sudo -l -U sarah           # as root: sarah's privileges
su - sarah -c 'sudo -n systemctl restart httpd'   # -n: fail instead of prompting (tests NOPASSWD)
journalctl _COMM=sudo      # who ran what
grep sudo /var/log/secure
```

### Protecting root itself

Common hardening once sudo is set up: lock root's password (`passwd -l root`, so only sudo and the console rescue
methods work), and keep `PermitRootLogin` restricted in sshd (Lecture 10, 10.3). On the exam, never lock root unless
asked: graders may need it.

> **Exam angle.** "Members of group X may run any command without a password" → a drop-in with
> `%X ALL=(ALL) NOPASSWD: ALL` via `visudo -f`. "User Y may only run command Z as root" →
> `Y ALL=(root) /full/path/to/Z args`. Use `which` to get the absolute path. Verify with `sudo -l -U`.

---

## Putting it together

A typical cluster of exam tasks: *"Set the default maximum password age to 60 days. Create group sysops (GID 4000).
Create natasha and harry with sysops as a supplementary group, and sarah with no interactive shell; all with
password X. natasha's password expires every 90 days. harry must change his at first login. Members of sysops get
passwordless sudo."*

```bash
sed -i 's/^PASS_MAX_DAYS.*/PASS_MAX_DAYS\t60/' /etc/login.defs      # defaults first
groupadd -g 4000 sysops
useradd -G sysops natasha
useradd -G sysops harry
useradd -s /sbin/nologin sarah
for u in natasha harry sarah; do echo 'X' | passwd --stdin "$u"; done
chage -M 90 natasha
chage -d 0 harry
visudo -f /etc/sudoers.d/sysops          # %sysops ALL=(ALL) NOPASSWD: ALL
id natasha; chage -l natasha; chage -l harry; getent passwd sarah; sudo -l -U harry; visudo -c
```

Note the order: login.defs first so natasha, harry and sarah get the 60-day default, then natasha's explicit 90
overrides it.

**Now practise:** [Lab 10](#/lab/10), including a user who can't log in for three different reasons.

## Review questions

1. Why do UIDs, not names, determine file ownership, and what does `ls -l` show for a deleted user's files?
2. What is a user private group, and why does RHEL use them?
3. Describe the seven fields of `/etc/passwd`.
4. What do `!!` and `*` mean in the password field of `/etc/shadow`?
5. Where do `useradd`'s defaults come from, and when do they apply?
6. What is the difference between `useradd -g` and `useradd -G`?
7. What happens if you run `usermod -G wheel harry` when harry is in sysops and dbadmin?
8. How do you move a user's home directory with its contents?
9. A user's account works, but `/sbin/nologin` is their shell. What can and can't they do?
10. List five reasons a user may be unable to log in, with the command that reveals each.
11. Explain the difference between password maximum age, inactivity and account expiry.
12. How do you force a password change at next login?
13. You set `PASS_MAX_DAYS 60` but `chage -l harry` still shows 99999. Why?
14. Why must you use `visudo` (or `visudo -f`) to edit sudo rules?
15. Write a sudoers rule letting group `web` restart httpd as root without a password, and nothing else.
16. Why is `alice ALL=(root) /usr/bin/vim` effectively full root access?

<details><summary>Answers</summary>

1. The kernel stores and checks numeric IDs; names are a lookup. A deleted user's files show the bare UID number.
2. A group per user, with the same name and only that user as member. It lets the default umask grant group write
   safely, which makes setgid team directories work.
3. Name, password placeholder (`x`), UID, primary GID, GECOS comment, home directory, login shell.
4. `!!` (or a `!` prefix) means locked or never set; `*` means password login is impossible.
5. `/etc/login.defs` and `/etc/default/useradd`; only for accounts created after the change.
6. `-g` sets the primary group; `-G` sets supplementary groups.
7. His supplementary groups are replaced: he ends up only in wheel (plus his primary group). Use `-aG`.
8. `usermod -d NEWHOME -m USER`.
9. They can't get an interactive shell (console, ssh, su), but the account exists, owns files, and may be used by
   services that don't need a shell.
10. Non-existent account (`getent passwd`), nologin/invalid shell (`getent passwd`), locked password
    (`passwd -S`), expired account (`chage -l`), expired password past inactivity (`chage -l`), missing home
    (`ls -ld`), sshd restrictions (`/var/log/secure`).
11. Maximum age forces a password change after N days; inactivity is a grace period after the password expires
    before the account is locked; account expiry disables the account on a fixed date regardless of passwords.
12. `chage -d 0 USER` (or `passwd -e USER`).
13. login.defs defaults apply only to accounts created after the change; use `chage -M 60 harry` for existing ones.
14. It checks the syntax before saving; a broken sudoers file breaks sudo for everyone.
15. `%web ALL=(root) NOPASSWD: /usr/bin/systemctl restart httpd`.
16. vim can run shell commands (`:!bash`) and edit any file as root.

</details>
