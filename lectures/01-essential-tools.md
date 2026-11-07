# Lecture 1: Understand and use essential tools

Everything else on the RHCSA sits on top of this section. Storage, networking, SELinux and users are all
"just" files, processes and commands, and the exam gives you nothing but a shell to reach them with. This
lecture explains what the shell actually does with the line you type, how data flows between programs, how
files are really stored on disk (which is what makes links and permissions make sense), and where to find
help when your memory fails you in the exam room.

Read it once straight through. The objective numbers (1.1, 1.2, ...) match the official list and the
quick reference, so you can jump back to a single topic later.

---

## 1.1 Access a shell prompt and issue commands with correct syntax

### What a shell is, and what it is not

When you log in on a text console or over SSH, the system starts a program for you: your **login shell**,
named in the last field of your line in `/etc/passwd` (usually `/bin/bash` on RHEL). The shell is an
ordinary user-space program. It is not the kernel and it is not "the terminal". It does three jobs in a loop:

1. Print a prompt and read a line of text.
2. Turn that line into a list of words, expanding variables, wildcards and so on.
3. Find the program named by the first word and ask the kernel to run it with the remaining words as
   arguments, wiring up its input and output first.

The **terminal** (a physical console, a virtual console like `tty2`, or a pseudo-terminal `pts/0` created for
an SSH session) is the device the shell reads keystrokes from and writes text to. That distinction matters
later: `who` and `w` list terminals, `ps` shows which terminal a process is attached to, and when you
"log in on tty3" you are asking `systemd-logind`/`getty` to start a login on that virtual console.

The prompt itself tells you who and where you are. RHEL's default looks like `[harry@server1 ~]$`: user,
short hostname, current directory (`~` means your home), and the final character, `$` for an ordinary user
and `#` for root. Glance at that last character before every destructive command.

### The anatomy of a command line

```text
ls  -l  -a  --sort=size  /etc  /var/log
│   └────── options ─────┘ └─ arguments ─┘
command
```

The shell does not know what `-l` means; it simply splits the line on whitespace and hands every word to
`ls`. Conventions, not rules, decide the rest:

- **Short options** are a dash and one letter, and can usually be bundled: `ls -la` is `ls -l -a`.
- **Long options** are two dashes and a word: `--all`. Some take a value with `=` or a space:
  `--sort=size`, `--sort size`.
- **Arguments** are what the command acts on: files, users, package names.
- A lone `--` means "end of options": `rm -- -weird-file` deletes a file whose name begins with a dash.

Because options are conventions, some old commands break them. `tar` accepts `tar czf` without a dash,
`find` uses single-dash long words like `-name` and `-mtime`, and `dd` uses `if=` and `of=`. You learn these
by using them, and `--help` or the man page settles any doubt.

### How the shell finds the program

If the first word contains a slash (`./script.sh`, `/usr/sbin/ip`), the shell runs exactly that file.
Otherwise it checks, in order:

1. **Aliases** (`alias ll='ls -l'`; RHEL sets `rm='rm -i'`, `cp='cp -i'`, `mv='mv -i'` for root in `~/.bashrc`).
2. **Shell functions**.
3. **Builtins**: commands implemented inside bash itself, such as `cd`, `echo`, `export`, `read`, `umask`
   and `test`. `cd` *has* to be a builtin: a separate program could change only its own directory, not yours.
4. **Programs found by searching `$PATH`**, a colon-separated list of directories, left to right.

`type cmd` tells you which of these a word resolves to, and `which cmd` shows the path found in `$PATH`.
Root's `PATH` includes `/usr/sbin`, which is why administrative commands such as `useradd` or `parted` may
appear "not found" for an ordinary user but work under `sudo`. The current directory is deliberately **not**
in `PATH`, which is why you must type `./myscript.sh` rather than `myscript.sh`.

### What the shell does to your line before running it

This is the part most people never learn, and it explains a huge number of "why did that do something weird"
moments. Bash processes a line in a fixed order:

1. **Brace expansion**: `mkdir -p /srv/{a,b,c}/data` becomes three paths; `{1..5}` becomes `1 2 3 4 5`.
2. **Tilde expansion**: `~` becomes your home directory, `~harry` becomes harry's.
3. **Parameter and variable expansion**: `$HOME`, `${USER}`, `$1`.
4. **Command substitution**: `$(hostname)` is replaced by that command's output.
5. **Arithmetic expansion**: `$((3 * 4))` becomes `12`.
6. **Word splitting**: the *results* of steps 3–5, if unquoted, are split on spaces, tabs and newlines.
7. **Pathname expansion (globbing)**: words containing `*`, `?` or `[...]` are replaced by matching file
   names, sorted. If nothing matches, bash leaves the pattern as-is.
8. **Quote removal**, then the command runs.

The command never sees `*.log`; it sees the list of file names the shell produced. That is why
`rm *.log` and `ls *.log` "agree", and why `find / -name *.conf` is a bug: if the current directory contains
`a.conf`, the shell expands the pattern before `find` ever sees it, and you get `find / -name a.conf`.
Quote patterns meant for another program: `find / -name '*.conf'`.

### Quoting: the three kinds

| Syntax | What it protects | Example |
|---|---|---|
| `'single'` | everything; nothing inside is special | `echo '$HOME is *'` prints `$HOME is *` |
| `"double"` | spaces and globs, but `$var`, `$(cmd)` and `` ` `` still expand | `echo "home is $HOME"` |
| `\` | the next single character | `echo cost: \$5` |

Rule of thumb: **put variables in double quotes** (`"$file"`) so a name with a space stays one word, and use
**single quotes** for text you want passed through untouched, such as regular expressions, `awk` programs,
or firewall rich rules.

### Chaining commands

- `cmd1 ; cmd2`: run one after the other, regardless of success.
- `cmd1 && cmd2`: run `cmd2` only if `cmd1` **succeeded** (exit status 0).
- `cmd1 || cmd2`: run `cmd2` only if `cmd1` **failed** (non-zero status).
- `cmd &`: run in the background; `jobs`, `fg`, `bg` and `Ctrl+Z` manage it.

Every program returns an **exit status**, a number from 0 to 255; 0 means success and anything else means
some kind of failure. `echo $?` shows the status of the last command. This one idea powers `&&`, `||`, `if`
in scripts (Lecture 3), and the graders that will score your exam.

### Editing the command line quickly

Speed matters on a timed exam. Bash uses Emacs-style line editing by default:

| Keys | Action |
|---|---|
| Tab, Tab Tab | complete a command, path, or (with `bash-completion`) an option, unit name or package |
| ↑ / ↓, `Ctrl+R` | walk history; reverse-search history by typing a fragment |
| `Ctrl+A` / `Ctrl+E` | jump to start / end of line |
| `Ctrl+W`, `Ctrl+U`, `Ctrl+K` | delete previous word / to start / to end |
| `Alt+.` | insert the last argument of the previous command |
| `Ctrl+C` / `Ctrl+D` | interrupt the running command / end of input (logs out of an empty prompt) |
| `!!`, `!$` | previous whole command (`sudo !!`), previous last argument |

`history` lists past commands; `!123` reruns number 123. Tab completion is not only faster but safer: if a
path does not complete, it does not exist, and you have just caught a typo.

> **Exam angle.** Tab-complete systemd unit names, `nmcli` arguments, `firewall-cmd` service names and SELinux
> types. If completion does not work for `firewall-cmd --add-service=`, check `bash-completion` is installed.

---

## 1.2 Use input-output redirection (>, >>, |, 2>, etc.)

### File descriptors: the idea underneath

Every process has a small table of open files, and the entries are numbered. These numbers are
**file descriptors**. By convention, every program starts with three already open:

| fd | Name | Default |
|---|---|---|
| 0 | standard input (stdin) | the keyboard / terminal |
| 1 | standard output (stdout) | the terminal |
| 2 | standard error (stderr) | the terminal |

A well-behaved program writes its normal results to fd 1 and its complaints to fd 2. Both appear on your
screen, so they look like one stream, but they are separate, and redirection lets you send them to different
places. The program does not know or care where they go; the shell sets up the descriptors **before** it
starts the program. That is the whole trick behind redirection.

### The operators

| Syntax | Meaning |
|---|---|
| `cmd > file` | stdout to `file`, **truncating** it first (creating it if needed) |
| `cmd >> file` | stdout appended to `file` |
| `cmd 2> file` | stderr to `file` |
| `cmd 2>> file` | stderr appended |
| `cmd > out 2> err` | each stream to its own file |
| `cmd > file 2>&1` | stdout to `file`, then stderr to "wherever fd 1 now points" (the same file) |
| `cmd &> file` | bash shorthand for the line above |
| `cmd < file` | stdin read from `file` |
| `cmd <<'EOF'` ... `EOF` | a **here-document**: the following lines become stdin |
| `cmd <<< "text"` | a **here-string** |
| `cmd1 \| cmd2` | stdout of `cmd1` becomes stdin of `cmd2` |
| `cmd \| tee file` | copy stdin to `file` *and* to stdout |
| `cmd 2>/dev/null` | discard errors |

### Order matters with 2>&1

`2>&1` means "make fd 2 a copy of whatever fd 1 is **right now**". Redirections are applied left to right, so:

```bash
find / -name passwd > /root/out.txt 2>&1   # both streams into the file
find / -name passwd 2>&1 > /root/out.txt   # errors still on screen!
```

In the second line, at the moment `2>&1` is applied, fd 1 is still the terminal, so stderr is pointed at the
terminal; only afterwards is fd 1 moved to the file. When in doubt, use `&>` or put `2>&1` last.

### `>` is destructive and happens first

The shell truncates the target file **before** the command runs. So `sort names.txt > names.txt` leaves you
with an empty file: by the time `sort` opens `names.txt` to read it, the shell has already emptied it.
Write to a temporary file and move it, or use a tool's own in-place option (`sort -o names.txt names.txt`,
`sed -i`). Bash's `set -o noclobber` makes `>` refuse to overwrite existing files (`>|` overrides it).

### Pipes

A pipe connects two processes running **at the same time**: the kernel provides a small buffer, the left side
writes into it, the right side reads from it. Nothing is written to disk. Pipelines are how Unix builds big
tools out of small ones:

```bash
# the five users with the most processes
ps -eo user= | sort | uniq -c | sort -rn | head -5
```

Only stdout goes down a pipe; stderr still goes to the terminal. To pipe both, use `2>&1 |` or bash's `|&`.

Useful filters to know: `sort` (`-n` numeric, `-r` reverse, `-k2` by field, `-t:` separator), `uniq` (needs
sorted input; `-c` counts), `wc -l` (lines), `head`/`tail` (`tail -f` follows a growing file), `cut -d: -f1`,
`tr`, `awk '{print $1}'`, `sed 's/old/new/g'`, and `tee`.

### tee and sudo

`sudo echo "x" > /etc/file` fails with "Permission denied" even for a sudoer. The redirection is done by
**your** shell, which is not root; only `echo` runs as root. The idiom is to let a root process open the file:

```bash
echo "nameserver 10.0.0.1" | sudo tee -a /etc/resolv.conf > /dev/null
```

### /dev/null and friends

`/dev/null` is a device that discards everything written to it and returns end-of-file when read.
`/dev/zero` returns endless zero bytes (handy with `dd` to make test files), and `/dev/urandom` returns random
bytes.

> **Exam angle.** Tasks are phrased like "save the list of files to X and the errors to Y" or "find all files
> owned by user Z and copy them / list them into a file". Read carefully whether errors should go to a file,
> be discarded, or are irrelevant. Graders check the file contents exactly, so an error message mixed into a
> result file fails the task.

---

## 1.3 Use grep and regular expressions to analyze text

### What grep does

`grep PATTERN [FILE...]` reads input line by line and prints the lines that match the pattern. Without files,
it reads stdin, which is why it is so often at the end of a pipe. Its exit status is 0 if anything matched,
1 if nothing did, and 2 on error, which makes it useful in scripts (`if grep -q root /etc/passwd; then`).

The options you will actually use:

| Option | Effect |
|---|---|
| `-i` | ignore case |
| `-v` | invert: print lines that do **not** match |
| `-n` | prefix line numbers |
| `-c` | print only a count of matching lines |
| `-l` / `-L` | print only names of files that match / don't |
| `-r` / `-R` | recurse into directories (`-R` follows symlinks) |
| `-w` | match whole words only |
| `-x` | match whole lines only |
| `-o` | print only the matched part |
| `-E` | extended regular expressions (same as `egrep`) |
| `-F` | fixed string, no regex at all |
| `-A n`, `-B n`, `-C n` | n lines of context after / before / around |
| `-q` | quiet, only the exit status |
| `-e PAT` | give a pattern explicitly (repeatable, or for patterns starting with `-`) |

### Regular expressions from the ground up

A regular expression is a small language for describing text. Most characters match themselves; a handful
are special. grep speaks two dialects: **basic** (BRE, the default) and **extended** (ERE, with `-E`). The
difference is only which characters need a backslash to be special.

| Pattern | Matches |
|---|---|
| `.` | any single character |
| `[abc]`, `[a-z]`, `[0-9]` | one character from the set or range |
| `[^0-9]` | one character **not** in the set |
| `[[:digit:]]`, `[[:space:]]`, `[[:alpha:]]`, `[[:upper:]]` | POSIX classes (locale-safe) |
| `^` | start of line (an anchor, matches no character) |
| `$` | end of line |
| `*` | **zero or more** of the previous item |
| `+` | one or more (ERE; BRE `\+`) |
| `?` | zero or one (ERE; BRE `\?`) |
| `{n}`, `{n,}`, `{n,m}` | exactly n, at least n, n to m (ERE; BRE `\{n,m\}`) |
| `a\|b` (BRE) / `a|b` (ERE) | alternation |
| `( )` (ERE) / `\( \)` (BRE) | grouping |
| `\b`, `\<`, `\>` | word boundary, start of word, end of word |
| `\.` | a literal dot (any special character can be escaped) |

Two things trip up newcomers:

- **`*` is not a wildcard.** In a shell glob, `*` means "anything". In a regex, `*` modifies the item before
  it. The regex equivalent of the glob `*` is `.*`. So `grep 'a*'` matches every line (zero `a`s is fine).
- **Regexes match anywhere in the line** unless anchored. `grep 'root'` matches `chroot` too. Use `^root:`
  to match the start of the `/etc/passwd` line, `-w root` for the whole word, or `-x` for the whole line.

Worked examples:

```bash
grep '^#' /etc/ssh/sshd_config            # comment lines
grep -v -E '^(#|$)' /etc/ssh/sshd_config  # everything that is not a comment or blank: the "real" settings
grep -E '^[0-9]{4}-[0-9]{2}-[0-9]{2}' app.log   # lines starting with a date
grep -E ':/bin/(ba)?sh$' /etc/passwd     # users whose shell is /bin/sh or /bin/bash
grep -c processor /proc/cpuinfo          # number of CPUs
grep -rl 'PermitRootLogin' /etc/ssh/     # which files mention it
ip -4 addr | grep -oE '([0-9]{1,3}\.){3}[0-9]{1,3}/[0-9]+'   # just the addresses
```

Always single-quote a regex, so the shell leaves `*`, `$`, `|` and `\` alone.

### Beyond grep: just enough of the rest

You are only examined on grep, but two companions often finish the job. `cut -d: -f1,7 /etc/passwd` picks
fields from delimited text, and `awk -F: '$3 >= 1000 {print $1}' /etc/passwd` prints usernames with a UID
of at least 1000. `sed -n '5,10p' file` prints lines 5 to 10, and `sed -i 's/^PORT=.*/PORT=9090/' file`
edits a file in place.

> **Exam angle.** "Find all lines in /usr/share/dict/words containing 'seismic' and save them to /root/lines,
> in original order, with no blank lines." That is `grep seismic /usr/share/dict/words > /root/lines`. Do not
> sort; do not add `-n`. Read for "starts with", "whole word", "case-insensitive" and similar qualifiers.

---

## 1.4 Access remote systems using SSH

### What SSH is doing

SSH (Secure Shell) gives you a shell on another machine over an encrypted connection. On RHEL, the server is
`sshd` (package `openssh-server`, unit `sshd.service`, listening on TCP port 22) and the client is `ssh`
(package `openssh-clients`).

When you run `ssh harry@server2`, roughly this happens:

1. The client opens TCP to port 22 and both sides agree on algorithms.
2. They perform a key exchange to create session keys. From here on, everything is encrypted.
3. The **server proves its identity** by signing with its **host key** (`/etc/ssh/ssh_host_*_key`). The client
   compares the server's public key against `~/.ssh/known_hosts`.
4. The **user authenticates**: by public key (Lecture 10, objective 10.3), or by password, which the server
   checks through PAM against `/etc/shadow`.
5. `sshd` starts your login shell on a new pseudo-terminal, and you get a prompt.

### Host keys and known_hosts

The first time you connect, the client has no record of the host and asks:

```text
The authenticity of host 'server2 (192.168.50.11)' can't be established.
ED25519 key fingerprint is SHA256:Xq0...
Are you sure you want to continue connecting (yes/no/[fingerprint])?
```

Answering `yes` stores the key in `~/.ssh/known_hosts`. Next time, if the key differs, ssh refuses with a loud
`REMOTE HOST IDENTIFICATION HAS CHANGED` warning, because that is exactly what a man-in-the-middle attack looks
like. In a lab it usually just means the machine was rebuilt; remove the stale entry with
`ssh-keygen -R server2` and connect again.

### Everyday usage

```bash
ssh server2                  # same username as you are locally
ssh harry@server2            # as harry
ssh -p 2222 harry@server2    # non-default port
ssh harry@server2 'df -h /'  # run one command and come back
ssh -i ~/.ssh/lab_key root@server2   # use a specific private key
ssh -X server2               # forward X11 (graphical programs)
exit                         # or Ctrl+D, to log out
```

`~/.ssh/config` lets you save per-host settings (`Host`, `HostName`, `User`, `Port`, `IdentityFile`).

> **Exam angle.** You may be asked to do work on a second system, or the first task may be to get to a
> console. Remember that on RHEL 9 and 10, `sshd` by default does **not** accept root logins with a password
> (`PermitRootLogin prohibit-password`); log in as a regular user and use `sudo`, or use keys. Lecture 10
> covers the server-side configuration.

---

## 1.5 Log in and switch users in multi-user targets

### Targets and where logins come from

A **target** is systemd's name for a system state (Lecture 4 explains them fully). The two you meet day to day
are `multi-user.target` (all services, text consoles, no graphical desktop: a typical server and probably
your exam machine) and `graphical.target` (everything in multi-user plus a display manager such as GDM).

In multi-user mode you can log in in several ways:

- **Virtual consoles.** The kernel provides several text terminals, `tty1` to `tty6`. systemd starts a
  `getty@ttyN.service` on demand when you switch to one with `Ctrl+Alt+F2` (or `Alt+F2` on a text console, or
  `chvt 2`). `getty` prints `login:`, the `login` program checks your password through PAM, and starts your
  shell. On a graphical system, the desktop usually lives on `tty1` or `tty2` and the others are text.
- **Serial console**, often what an exam or cloud environment exposes in a browser window.
- **SSH**, which allocates a pseudo-terminal (`/dev/pts/N`).

`who`, `w`, and `loginctl list-sessions` show who is logged in where. `tty` prints your own terminal.

### Becoming another user

There are two families of tools, and the difference is about **whose password** and **whose rules**.

**`su` (substitute user)** starts a shell as another user, after you give **that user's** password (root can
`su` to anyone without a password).

```bash
su - harry          # login shell as harry: full environment, starts in ~harry
su harry            # non-login: keeps much of YOUR environment and current directory
su -                # login shell as root
su - harry -c 'id'  # run one command as harry
exit                # back to the previous user
```

The dash matters. A **login shell** reads `/etc/profile`, `~/.bash_profile` and friends: it resets `PATH`,
sets `HOME`, `USER`, `MAIL` and changes to the home directory. Without the dash you are harry, but in your
old directory with your old `PATH`, which leads to confusing "command not found" errors for root tools.
On the exam, always use `su -`.

**`sudo`** runs a command as another user (root by default) after you give **your own** password, if the
sudoers policy allows it (objective 9.4). Every use is logged to the journal and `/var/log/secure`.

```bash
sudo dnf install httpd   # one command as root
sudo -i                  # a root login shell (like su -, but authorised by sudoers)
sudo -u harry whoami     # one command as harry
sudo -l                  # what am I allowed to run?
```

`whoami` prints your effective user; `id` shows UID, GID and all groups (and the SELinux context); `logname`
prints who originally logged in. These help you keep track after a few levels of `su`.

### Exiting cleanly, and shutting down from a session

Each `su` or `sudo -i` nests a new shell. `exit` returns one level. If you have nested several deep, `exit`
repeatedly until the prompt shows who you expect. Rebooting from a regular user requires privileges
(`sudo systemctl reboot`); Lecture 4 covers the shutdown commands.

> **Exam angle.** Some tasks ask you to verify something "as user X" (for example, that harry can write in a
> shared directory). `su - harry` then try it. Note that group membership changes only take effect in **new**
> logins, so `su - harry` after `usermod -aG` sees the new group, but an existing harry session does not.

---

## 1.6 Archive, compress, unpack, and uncompress files using tar, gzip, and bzip2

### Archiving and compressing are two different things

An **archive** bundles many files and directories, with their names, permissions, owners and timestamps, into
one file. **Compression** makes a single stream of bytes smaller. Unix tools keep these jobs separate:

- `tar` (tape archiver) archives. By itself, a `.tar` is the same size as its contents.
- `gzip` (`.gz`), `bzip2` (`.bz2`) and `xz` (`.xz`) compress one file each.

`tar` can call the compressors for you, which gives the familiar `.tar.gz` (`.tgz`), `.tar.bz2` and
`.tar.xz`. gzip is fastest with the least compression; bzip2 is slower and smaller; xz is slowest and
smallest. On the exam, use whichever the task names.

### tar

`tar` takes exactly one **mode** letter plus modifiers:

| Mode | Meaning |
|---|---|
| `c` | create |
| `x` | extract |
| `t` | list contents |
| `r` / `u` | append / update (uncompressed archives only) |

| Modifier | Meaning |
|---|---|
| `f FILE` | the archive file (always use it; without it tar talks to a tape device) |
| `v` | verbose: list files as processed |
| `z` / `j` / `J` | gzip / bzip2 / xz |
| `C DIR` | change to DIR first (where to extract, or where to archive from) |
| `p` | preserve permissions (default for root) |
| `--xattrs --selinux --acls` | include extended attributes, SELinux labels and ACLs |

```bash
tar -czf /root/etc-backup.tar.gz /etc        # create, gzip
tar -cjf /root/ssh.tar.bz2 /etc/ssh          # create, bzip2
tar -cJf /root/logs.tar.xz -C /var/log .     # archive the contents of /var/log, not the path itself
tar -tf /root/etc-backup.tar.gz              # list
tar -xf /root/etc-backup.tar.gz -C /tmp/restore   # extract elsewhere (tar auto-detects compression)
tar -xf backup.tar.gz etc/hosts              # extract a single member
```

Note the `f` must be followed by the file name, so `-czf name` works but `-cfz name` makes `z` the archive name.

**Leading slashes.** When you archive `/etc`, tar prints `Removing leading '/' from member names` and stores
`etc/...`. That is a safety feature: on extraction, files land **relative to the current directory** (or
`-C`), so restoring an old backup cannot silently overwrite the live `/etc`. If you really want to restore
in place, `cd /` (or `-C /`) first.

### gzip, bzip2, xz on their own

These replace the original file with the compressed one, and back:

```bash
gzip notes.txt        # -> notes.txt.gz, notes.txt is gone
gunzip notes.txt.gz   # or gzip -d
gzip -k notes.txt     # keep the original
gzip -c notes.txt > /root/notes.txt.gz   # write to stdout, original untouched
bzip2 file; bunzip2 file.bz2; bzip2 -k file
xz file; unxz file.xz
zcat file.gz; bzcat file.bz2; xzcat file.xz   # read without decompressing to disk
```

`zip`/`unzip` exist too but are not part of the objective.

> **Exam angle.** "Create a bzip2-compressed tar archive of /usr/local named /root/local.tar.bz2." Check your
> work with `tar -tjf /root/local.tar.bz2 | head` and `file /root/local.tar.bz2`. When asked to compress a
> file but keep the original, reach for `-k` or `-c`.

---

## 1.7 Create and edit text files

Almost all Linux configuration is text, so on the exam you will edit dozens of files. You need to be fast
and accurate in at least one editor that is guaranteed to exist. That is `vi`/`vim`. `nano` is often
installed too, and it is fine to use it if it is there, but do not depend on it.

### Creating files without an editor

```bash
touch empty.txt                    # create empty (or update the timestamp)
echo "Authorized use only" > /etc/motd
printf 'line1\nline2\n' > file
cat > /etc/yum.repos.d/local.repo <<'EOF'
[baseos]
name=BaseOS
baseurl=http://repo.example.com/BaseOS
gpgcheck=0
EOF
```

The quoted `'EOF'` stops the shell from expanding `$` inside the heredoc; leave it quoted unless you want
expansion.

### vim: the mental model

vim is **modal**. Keys mean different things depending on the mode, and this is the source of every new user's
pain. Once the model clicks, it is fast.

- **Normal mode** (where you start, and where `Esc` always returns you): keys are commands: move, delete,
  copy, paste.
- **Insert mode** (`i`, `a`, `o`, ...): keys type text. The bottom line shows `-- INSERT --`.
- **Command-line mode** (`:` from normal mode): commands such as save and quit.
- **Visual mode** (`v`, `V`): select text, then act on it.

The minimum you must be able to do without thinking:

| Keys (normal mode) | Action |
|---|---|
| `i` / `a` | insert before / after the cursor |
| `o` / `O` | open a new line below / above and insert |
| `Esc` | back to normal mode |
| `h j k l` or arrows | move |
| `gg` / `G` / `:42` | first line / last line / line 42 |
| `0` / `$` / `w` / `b` | start / end of line, next / previous word |
| `x` | delete a character |
| `dd`, `3dd` | delete (cut) a line, three lines |
| `dw`, `D` | delete word, delete to end of line |
| `cw`, `cc` | change word, change line (delete and insert) |
| `yy`, `p` / `P` | copy a line, paste after / before |
| `u` / `Ctrl+R` | undo / redo |
| `/text`, `n`, `N` | search forward, next, previous |
| `:%s/old/new/g` | replace every `old` with `new` in the file |
| `:w`, `:wq` or `ZZ`, `:q!` | save, save and quit, quit discarding changes |
| `:set nu` | show line numbers |

If you ever end up somewhere confusing, press `Esc` twice and type `:q!` to escape without saving.
`vimtutor` (from the `vim-enhanced` package) is a 30-minute interactive lesson; it is the best half-hour of
practice you can do for this objective.

vim leaves a swap file (`.file.swp`) while editing. If vim warns that one exists, another vim may have the
file open, or an earlier session crashed. Choose `(R)ecover` or `(D)elete it` accordingly.

### Editing safely

Before changing a critical file, make a copy: `cp -a /etc/fstab /etc/fstab.bak`. Many config files have a
checker you should run after editing: `visudo -c`, `sshd -t`, `findmnt --verify`, `named-checkconf`,
`systemd-analyze verify unit`. Use them; a typo in `fstab` or `sudoers` can lock you out.

---

## 1.8 Create, delete, copy, and move files and directories

### The file-system tree

Linux has a single tree rooted at `/`. Other disks and partitions are **mounted** onto directories in that
tree (Lecture 6). The standard layout, the Filesystem Hierarchy Standard, is worth knowing because the exam
assumes it:

| Path | Contents |
|---|---|
| `/etc` | system configuration (text) |
| `/usr` | installed software: `/usr/bin`, `/usr/sbin`, `/usr/lib`, `/usr/share` (on RHEL, `/bin`, `/sbin`, `/lib` are symlinks into `/usr`) |
| `/var` | variable data: logs (`/var/log`), spools, caches, databases, web content (`/var/www`) |
| `/home`, `/root` | user home directories, and root's |
| `/tmp`, `/var/tmp` | temporary files; `/tmp` may be cleaned at boot, `/var/tmp` survives longer |
| `/boot` | kernels, initramfs images, bootloader files |
| `/dev` | device files (`/dev/sda`, `/dev/null`) |
| `/proc`, `/sys` | virtual file systems exposing kernel state |
| `/run` | runtime data, cleared at boot |
| `/srv`, `/opt` | data served by this system, add-on software |
| `/mnt`, `/media` | temporary mount points |

A path starting with `/` is **absolute**. Anything else is **relative** to the current directory (`pwd`).
`.` is the current directory, `..` its parent, `~` your home, and `cd -` returns to the previous directory.

### The commands

```bash
mkdir dir; mkdir -p /srv/a/b/c          # -p: create parents, no error if it exists
touch file                              # create empty / update mtime
cp src dst; cp -r srcdir dstdir         # copy file / directory tree
cp -a src dst                           # archive mode: recursive, keep mode, owner, timestamps, links, context
cp -p src dst                           # keep mode, owner, timestamps
mv src dst                              # move or rename
rm file; rm -r dir; rm -rf dir          # remove (no recycle bin!)
rmdir dir                               # remove an EMPTY directory only
ls -l, -a, -d, -h, -R, -t, -r, -i, -Z   # long, hidden, the dir itself, human sizes, recursive, by time, reverse, inode, SELinux
```

A few behaviours worth understanding rather than memorising:

- **`cp` creates a new file**, so the copy gets a new inode, the copier as owner, the default mode and
  SELinux label of the destination, and the current time, unless you use `-p` or `-a`. **`mv` within the same
  file system only renames**: the inode, owner, mode, timestamps and SELinux label all stay the same. This
  matters a lot for SELinux (objective 10.6).
- `cp src dir/` puts `src` *inside* `dir`; `cp -r srcdir existingdir` puts `srcdir` inside `existingdir`.
  With a trailing `/.`, `cp -a srcdir/. dstdir` copies the *contents*.
- Root's `rm`, `cp` and `mv` are aliased with `-i` (interactive), so they ask before overwriting or deleting.
  `\rm` or `command rm` bypasses the alias; `-f` overrides prompts.

### find: searching by any property

`find` walks a directory tree and tests every entry. The syntax is `find START... TESTS... ACTION`.

```bash
find /etc -name '*.conf'                     # by name (glob, quoted!)  -iname = case-insensitive
find / -user harry -type f                   # owned by harry, regular files only
find / -group devops                         # by group
find /var -size +10M                         # bigger than 10 MiB (-size -1k: smaller than 1 KiB)
find /home -mtime -1                         # modified less than 24h ago (+7: more than 7 days)
find /tmp -mmin -30                          # in the last 30 minutes
find / -perm -4000                           # setuid set (-perm /6000: setuid OR setgid; -perm 644: exactly)
find /srv -empty                             # empty files and directories
find / -nouser                               # files whose owner UID has no account
find / -user harry -exec cp -a {} /root/harry/ \;    # run a command per match
find /tmp -name '*.tmp' -delete
find / -user harry 2>/dev/null > /root/harry-files.txt
```

Tests are ANDed by default. Use `-o` for OR and `\( \)` to group:
`find / \( -name '*.log' -o -name '*.txt' \) -size +1M`. `-maxdepth 1` stops recursion.

In `-exec cmd {} \;`, `{}` is replaced by each path and `\;` ends the command (escaped so the shell does not
eat the semicolon). `-exec cmd {} +` passes many paths to one command, which is faster.

`locate name` (package `plocate`) searches a prebuilt database and is much faster, but only knows files that
existed at the last `updatedb`.

> **Exam angle.** "Find all files owned by user jack and copy them to /root/found, keeping their structure"
> or "list them into /root/jackfiles". Watch for `-type f` (files only, not directories) and for the
> difference between copying into a flat directory and preserving paths (`cp --parents`).

---

## 1.9 Create hard and soft links

To understand links you need to know how a file is actually stored. This also pays off in permissions,
`df` vs `du`, and why deleting an open file does not free space.

### Inodes and directory entries

On a Linux file system (XFS, ext4), a file has two parts:

- An **inode**: a numbered on-disk record holding the file's **metadata** (type, permissions, owner, group,
  size, timestamps, link count, and where the data blocks are). The inode does **not** contain the file name.
- **Data blocks** holding the content.

A **directory** is itself just a special file whose content is a table of `name → inode number` pairs. So a
file name is only an entry in some directory, pointing at an inode. `ls -i` shows inode numbers, and `stat`
shows the full inode:

```text
$ stat /etc/hosts
  File: /etc/hosts
  Size: 158        Blocks: 8          IO Block: 4096   regular file
Device: fd00h/64768d    Inode: 33595531    Links: 1
Access: (0644/-rw-r--r--)  Uid: (    0/    root)   Gid: (    0/    root)
Context: system_u:object_r:net_conf_t:s0
Access: 2026-11-07 09:01:12.000000000 +0000
Modify: 2026-10-30 14:12:44.000000000 +0000
Change: 2026-10-30 14:12:44.000000000 +0000
```

Three timestamps live in the inode: **atime** (last read; RHEL mounts with `relatime` so it is updated
lazily), **mtime** (content last modified, what `ls -l` shows), and **ctime** (inode last changed: content,
permissions, owner or link count). There is no "creation time" in the classic model, though modern kernels
can show a birth time.

### Hard links

A **hard link** is simply a second directory entry pointing at the **same inode**:

```bash
ln /srv/data/notes.txt /root/notes-hard.txt
ls -li /srv/data/notes.txt /root/notes-hard.txt
# 1835 -rw-r--r--. 2 root root 42 ... /root/notes-hard.txt
# 1835 -rw-r--r--. 2 root root 42 ... /srv/data/notes.txt
```

Same inode number, and the **link count** (the `2` after the permissions) went up. Neither name is "the
original"; they are equal. Changing the content or permissions through one name changes it for both, because
there is only one inode. Deleting one name (`rm` actually calls `unlink`) decrements the link count; the data
is freed only when the count reaches zero **and** no process still has the file open.

That last clause explains a classic puzzle: you delete a huge log file but `df` shows no space freed. A
running process still has it open. `lsof +L1` lists deleted-but-open files; restarting the process releases
the space.

Hard-link limitations follow from the design: inode numbers are only meaningful **within one file system**,
so hard links cannot cross mount points; and hard links to directories are forbidden (they would allow loops
in the tree). Every directory's link count is at least 2 (its name in the parent, plus its own `.` entry),
plus one for each subdirectory's `..`.

### Symbolic (soft) links

A **symbolic link** is a separate small file, with its own inode, whose content is a **path**. When a program
opens the symlink, the kernel reads that path and follows it.

```bash
ln -s /srv/data/report.sh /usr/local/bin/report
ls -l /usr/local/bin/report
# lrwxrwxrwx. 1 root root 19 ... /usr/local/bin/report -> /srv/data/report.sh
readlink /usr/local/bin/report       # the stored path
readlink -f /usr/local/bin/report    # fully resolved absolute path
```

Because it is just a path:

- It **can** cross file systems and point to directories.
- It can **dangle**: if the target is removed or renamed, the link remains but points nowhere. `ls -l` shows
  it (often in red), and opening it fails with "No such file or directory".
- Its permissions (`lrwxrwxrwx`) are irrelevant; the target's permissions apply.
- A **relative** target is resolved relative to the **directory containing the link**, not your current
  directory. `ln -s ../data/x /srv/links/x` points at `/srv/data/x`. This is the most common way to create a
  broken symlink: typing a path relative to where you are standing.

`ln -sf` replaces an existing link, and `ln -sfn` does so without descending into a link that points at a
directory.

| | Hard link | Symbolic link |
|---|---|---|
| What it is | another name for the same inode | a tiny file containing a path |
| Crosses file systems | no | yes |
| Can point to a directory | no | yes |
| Survives deleting the "original" name | yes, data remains | no, it dangles |
| `ls -l` shows | normal file, link count > 1 | `l` type and `-> target` |

> **Exam angle.** If a task says a command "doesn't work", check `ls -l` on it: a symlink to a moved or
> misspelled path is a typical planted fault. Fix it with `ln -sf correct-target linkname`.

---

## 1.10 List, set, and change standard ugo/rwx permissions

### The model

Every inode records an **owner** (a UID), a **group** (a GID), and a 12-bit **mode**: 9 permission bits plus
3 special bits. The 9 bits are three sets of read/write/execute:

```text
-rwxr-x---.  1 harry devops  4096 Nov  7 10:00 report.sh
│└┬┘└┬┘└┬┘│
│ │  │  │ └ "." = has an SELinux label ("+" would mean an ACL is set)
│ │  │  └── other: ---
│ │  └───── group (devops): r-x
│ └──────── user/owner (harry): rwx
└────────── type: - file, d directory, l symlink, b/c block/char device, p pipe, s socket
```

When a process accesses a file, the kernel picks **exactly one** of the three sets:

1. If the process's UID is the file's owner, use the **user** bits.
2. Else if the file's group is among the process's groups, use the **group** bits.
3. Else use the **other** bits.

It does not fall through. If you are the owner and the owner bits deny write, you are denied even if "other"
allows write. (Root bypasses read/write checks entirely, and execute too as long as any `x` bit is set.)

### What r, w and x mean for files versus directories

This is the single most misunderstood thing in Unix permissions, and the exam's "fix the permission
problem" tasks rely on it:

| | On a file | On a directory |
|---|---|---|
| `r` | read the content | **list** the names in it (`ls`) |
| `w` | change the content | **create, delete, rename** entries in it |
| `x` | execute it as a program | **enter/traverse** it: `cd` into it, or access anything inside by path |

Consequences:

- **Deleting a file depends on the directory**, not the file. If you have `w` and `x` on the directory, you
  can delete a file in it that you cannot even read. (The sticky bit, below, closes that hole.)
- To reach `/srv/data/report.txt` you need `x` on `/`, `/srv` and `/srv/data`, plus `r` on the file. One
  missing `x` anywhere in the path blocks you. `namei -l /srv/data/report.txt` shows the permissions of every
  component, and is the fastest way to find the culprit.
- `r` without `x` on a directory lets you list names but not open anything (and `ls -l` shows `?????`).
  `x` without `r` lets you open files whose names you already know: a "drop box" that can't be browsed.
- A script needs `r` and `x`, because the interpreter must read it.

### Changing permissions: chmod

**Symbolic** form: who (`u`, `g`, `o`, `a`), operator (`+`, `-`, `=`), what (`r`, `w`, `x`, `X`, `s`, `t`).

```bash
chmod u+x script.sh
chmod g-w,o= file             # remove group write, clear all "other" bits
chmod a=r file                # everyone read only
chmod -R g+rwX /srv/shared    # X: execute only on directories (and files already executable by someone)
```

**Octal** form: each set is a digit, r=4, w=2, x=1, summed.

| Octal | Bits | Typical use |
|---|---|---|
| 7 | rwx | |
| 6 | rw- | |
| 5 | r-x | |
| 4 | r-- | |
| 0 | --- | |

`chmod 640 file` gives `rw-r-----`. `chmod 750 dir` gives `rwxr-x---`. `644` and `755` are the normal file and
directory/program defaults; `600` and `700` are private. Octal sets **all** bits at once; symbolic changes
only what you name. Use whichever the task makes easier.

### Owner and group: chown and chgrp

```bash
chown harry file
chown harry:devops file      # owner and group
chown :devops file           # group only (same as chgrp devops file)
chown -R harry:harry /home/harry
```

Only root can give a file away to another owner. An ordinary user can change a file's group, but only to a
group they belong to.

### The special bits

The fourth, leading octal digit holds three more bits:

| Bit | Octal | On a file | On a directory | Shown as |
|---|---|---|---|---|
| setuid | 4000 | the program runs with the **file owner's** UID | (no effect) | `s` in user x: `rwsr-xr-x` |
| setgid | 2000 | runs with the **file's group** | new files inside **inherit the directory's group**; new subdirectories inherit setgid | `s` in group x: `rwxrws---` |
| sticky | 1000 | (no effect on Linux) | users can delete only **their own** files in it | `t` in other x: `rwxrwxrwt` |

A capital `S` or `T` means the special bit is set but the underlying `x` is not, which is usually a mistake.

Where you see them:

- **setuid**: `/usr/bin/passwd` is `-rwsr-xr-x root`. Any user runs it with root's identity, which is how it can
  write to `/etc/shadow`. This is powerful and dangerous, so you rarely set it yourself; `find / -perm -4000`
  is a standard audit.
- **setgid on a directory**: the standard recipe for a team directory. With `chgrp devops /srv/shared;
  chmod 2770 /srv/shared`, every file anyone creates there belongs to group `devops`, so the team can share
  without each person running `chgrp`.
- **sticky on a directory**: `/tmp` is `drwxrwxrwt`. Everyone can create files, but no one can delete or rename
  anyone else's.

```bash
chmod 2770 /srv/shared        # setgid + rwxrwx---
chmod g+s /srv/shared         # same special bit, symbolically
chmod 1777 /srv/dropbox       # sticky, world-writable
chmod o+t /srv/dropbox
```

### Beyond the nine bits

Two more layers can affect access and appear in permission troubleshooting (objective 6.5):
**ACLs** (`getfacl`/`setfacl`, flagged by a `+` after the mode in `ls -l`), and **SELinux** (Lecture 10),
flagged by the `.` and inspected with `ls -Z`. Default permissions for new files come from the **umask**
(objective 10.2).

> **Exam angle.** Typical tasks: "Create /common/admin owned by group admins, members can read and write,
> others no access, and new files must belong to admins" → `mkdir -p /common/admin; chgrp admins
> /common/admin; chmod 2770 /common/admin`. Verify with `ls -ld` and by creating a test file as a member.

---

## 1.11 Locate, read, and use system documentation including man, info, and files in /usr/share/doc

There is no internet in the exam room, but every RHEL system ships with thousands of pages of documentation.
Knowing how to find the right one in under a minute is worth points, because you will forget a syntax.

### man pages

`man` displays reference manuals, organised in numbered **sections**:

| Section | Contents | Example |
|---|---|---|
| 1 | user commands | `man 1 passwd` (the command) |
| 5 | file formats and configuration files | `man 5 passwd` (the file), `man 5 fstab`, `man 5 crontab` |
| 8 | system administration commands | `man 8 lvcreate`, `man 8 semanage-fcontext` |
| 2, 3 | system calls, library functions | for programmers |
| 7 | overviews and conventions | `man 7 regex`, `man 7 signal`, `man 7 bootup` |

When a name exists in several sections, `man name` shows the first found (usually 1), so `man passwd`
documents the command. Ask for the section explicitly: `man 5 passwd`. `man -a passwd` shows them all in turn.

Inside man (it uses the `less` pager): `Space`/`b` page down/up, `/word` search, `n`/`N` next/previous match,
`g`/`G` top/bottom, `q` quit. Pages follow a standard layout: NAME, SYNOPSIS (`[ ]` optional, `...`
repeatable, `|` alternatives), DESCRIPTION, OPTIONS, often **EXAMPLES** near the end (jump there with
`/EXAMPLES` or `G`), FILES, and SEE ALSO, which tells you where to look next.

**Searching when you don't know the name:** `man -k keyword` (same as `apropos keyword`) searches the
one-line descriptions:

```bash
man -k partition
man -k '^lv'           # regex on names
man -k passwd | grep '(5)'
```

`man -k` uses a database built by `mandb`. On a fresh or minimal install it may return "nothing appropriate";
run `mandb` as root to build it (a daily timer normally does). `whatis cmd` prints just the one-line
description, and `man -f` is the same.

High-value pages for this exam, worth knowing exist before the day: `man 5 fstab`, `man 5 crontab`,
`man systemd.timer` and `man systemd.time` (calendar syntax), `man nmcli-examples`, `man 5 nm-settings`,
`man semanage-fcontext` (examples at the bottom), `man firewalld.richlanguage`, `man 5 sudoers` (examples),
`man chage`, `man useradd`, `man 5 chrony.conf`, `man lvm`, `man 7 bootup`, `man dracut.cmdline`.
Many service-specific SELinux pages such as `man httpd_selinux` come from the `selinux-policy-doc` package.

### info

GNU projects (coreutils, grep, tar, bash) maintain their full manuals in **info** format; the man page is
sometimes a summary. `info grep` opens a hyperlinked document organised into **nodes**:

| Key | Action |
|---|---|
| arrows, `Space` | move, page down |
| `Enter` | follow the link under the cursor (lines starting with `*`) |
| `n` / `p` / `u` | next / previous / up node |
| `l` | go back |
| `/` or `s` | search |
| `q` | quit |

`pinfo` is a friendlier viewer if installed. `info coreutils 'ls invocation'` jumps straight to a node.

### /usr/share/doc

Each package may install extra documentation under `/usr/share/doc/PACKAGE/`: READMEs, changelogs and,
importantly, **example configuration files**. Examples worth knowing: `/usr/share/doc/chrony/`,
`/usr/share/doc/openssh*/`, `/usr/share/doc/sudo/examples/`. Ask rpm which docs a package installed:

```bash
rpm -qd tar            # documentation files (man pages, info, /usr/share/doc)
rpm -qc openssh-server # configuration files
rpm -ql chrony         # every file
rpm -qf /etc/chrony.conf   # which package owns this file
```

Note that container images and minimal installs often strip docs (`tsflags=nodocs`); the lab images restore
them so you can practise.

### --help

Most commands print a usage summary with `--help` (or `-h`). It is often the fastest reminder of an option
letter: `lvcreate --help | grep -i size`.

> **Exam strategy.** Spend your memory on concepts and workflows, and let the docs hold details. Before exam
> day, practise answering questions purely from man pages: "what is the fstab option to stop boot from
> failing if a disk is missing?" (`nofail`, in `man 5 fstab`), "what OnCalendar string means every weekday
> at 06:00?" (`man systemd.time`).

---

## Putting it together

Look at how the pieces of this lecture combine in one realistic chain, the kind of thing the exam is made of:

```bash
# Find files owned by harry, ignore errors, keep a list, then archive them preserving everything.
find / -user harry -type f 2>/dev/null > /root/harry-files.txt
tar -czf /root/harry.tar.gz --selinux --acls --xattrs -T /root/harry-files.txt
tar -tzf /root/harry.tar.gz | head
```

`find` tests inode metadata, `2>` separates the error stream, `>` captures the results, and `tar -T` reads the
list of files to archive from a file. None of it requires memorising a magic incantation if you understand
what each part does.

**Now practise:** do [Lab 01](#/lab/01). Its tasks map one to one onto the objectives above, and several of
them are planted faults (a dangling symlink, wrong ownership) that you can only fix by reasoning about inodes
and permission bits.

## Review questions

1. Why does `cd` have to be a shell builtin rather than a program in `/usr/bin`?
2. You run `find /etc -name *.conf` in a directory containing `x.conf` and get only one result. Why?
3. What is the difference between `cmd > f 2>&1` and `cmd 2>&1 > f`?
4. Why does `sudo echo hi > /root/test` fail, and how do you fix it?
5. Write a grep that prints the non-comment, non-blank lines of `/etc/chrony.conf`.
6. A file has link count 3. What does that tell you, and what happens to its data if you `rm` one name?
7. You create a relative symlink `ln -s data/file /tmp/link` while standing in `/srv`. Does it work? Why?
8. A user can read `/srv/a/b/file.txt` (mode 644) but not `cd` into `/srv/a`. Which bit is missing, and where?
9. A user with `w` on a directory deletes another user's file in it. How do you prevent that while keeping
   the directory writable for everyone?
10. What do `rws` in the owner field and `rws` in the group field each mean, on a file and on a directory?
11. `man -k fstab` prints "nothing appropriate". What do you run?
12. How do you find which package installed `/etc/ssh/sshd_config`, and list that package's docs?

<details><summary>Answers</summary>

1. A separate process can only change its own working directory; when it exits, your shell would be unchanged.
2. The shell expanded `*.conf` to `x.conf` before `find` ran. Quote the pattern: `-name '*.conf'`.
3. The first sends both streams to `f`. In the second, stderr is pointed at the terminal (where stdout was at
   that moment), and then only stdout moves to `f`.
4. The redirection is performed by your unprivileged shell. Use `echo hi | sudo tee /root/test`.
5. `grep -Ev '^\s*(#|$)' /etc/chrony.conf`.
6. Three directory entries point at the same inode. Removing one leaves the data reachable through the other
   two; the count drops to 2.
7. No: the stored path `data/file` is resolved relative to `/tmp` (the link's directory), giving `/tmp/data/file`.
8. Execute (`x`) on `/srv/a` for the relevant class (user, group or other).
9. Set the sticky bit: `chmod +t dir` (for example mode 1777).
10. Owner `s` = setuid (file: run as the owner; directory: no effect). Group `s` = setgid (file: run as the
    group; directory: new entries inherit the group).
11. `mandb` (as root), then try again.
12. `rpm -qf /etc/ssh/sshd_config` (gives `openssh-server`), then `rpm -qd openssh-server`.

</details>
