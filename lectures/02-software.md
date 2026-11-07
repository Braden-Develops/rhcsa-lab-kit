# Lecture 2: Manage software

A RHEL system is a few thousand packages working together. This lecture explains what a package actually
is, how RPM keeps track of every file on the system, how DNF finds packages in repositories and solves
dependencies, how Red Hat delivers software through its Content Delivery Network, and how Flatpak, the
second software channel that is new to the RHEL 10 objectives, differs from RPM in almost every way.

Objective 7.5 ("Install and update software packages from Red Hat Content Delivery Network, a remote
repository, or from the local file system") is examined in Section 7 but belongs with this material, so it is
explained here too; Lecture 7 points back.

---

## Background: what a package is

### The problem packages solve

You could install software by unpacking tarballs into `/usr`. You would then have no idea which files belong to
which program, no way to remove a program cleanly, no record of versions, no way to know whether a library
another program needs is present, and no way to tell whether a file was tampered with. A **package manager**
solves all of that by treating software as named, versioned, signed units with declared dependencies, and by
keeping a database of exactly what is installed.

RHEL uses two layers:

- **RPM** (`rpm`): the low-level tool and file format. It installs, removes, queries and verifies individual
  package files, and owns the database of installed software. It does **not** download anything and does not
  resolve dependencies; it only refuses to proceed when they are missing.
- **DNF** (`dnf`, also available as `yum`, which is a symlink to it): the high-level tool. It reads
  **repositories**, works out the full set of packages a request needs, downloads them, checks their
  signatures and hands them to the RPM library to install, all in one transaction.

### Inside an .rpm file

An RPM file contains:

1. A **header** of metadata: name, version, release, architecture, summary, description, license, the list of
   files with their permissions, owners and checksums, what the package **requires** and what it
   **provides**, and scripts to run before and after install or removal.
2. A **signature** over the header and payload, made with the vendor's GPG key.
3. The **payload**: a compressed archive of the files.

### Package names: NEVRA

A package file name encodes its identity:

```text
openssh-server-9.9p1-7.el10.x86_64.rpm
└──── name ───┘ └ver ┘ └rel ┘ └arch┘
```

- **Name**: `openssh-server`.
- **Version**: the upstream version, `9.9p1`.
- **Release**: the packager's build number for that version, plus a distribution tag. `el10` means
  Enterprise Linux 10. Red Hat backports security fixes into old versions and bumps the release, so a RHEL
  package's version number alone tells you little about which fixes it contains.
- **Architecture**: `x86_64`, `aarch64`, or `noarch` for architecture-independent packages (scripts, data).
- An optional **Epoch** (`1:`) overrides normal version comparison when upstream versioning goes backwards.

Together these are called the **NEVRA**. When you type `dnf install openssh-server`, you give only the name and
DNF chooses the best available version and architecture.

### Dependencies are capabilities, not package names

A package does not really say "I need package X". It says "I require capability Y", for example
`libssl.so.3()(64bit)` or `/usr/bin/python3` or `config(openssh)`. Other packages declare which capabilities they
**provide**. DNF's solver finds a set of packages whose provides satisfy all the requires, without conflicts.
This is why `dnf provides /usr/bin/crontab` or `dnf provides '*/semanage'` can tell you which package to
install to get a command you need: file paths are capabilities too.

### The RPM database

Every installed package's header is stored in the RPM database (on RHEL 10 it lives under
`/usr/lib/sysimage/rpm`, with `/var/lib/rpm` kept as a compatibility path). Because the database records
every file with its checksum, size, permissions and owner, RPM can answer questions about the system that
nothing else can:

```bash
rpm -qa                       # every installed package
rpm -qa | grep -i ssh
rpm -q openssh-server         # is it installed, which version?
rpm -qi openssh-server        # info: summary, license, build date, signature
rpm -ql openssh-server        # every file it installed
rpm -qc openssh-server        # only its configuration files
rpm -qd openssh-server        # only its documentation
rpm -qf /etc/ssh/sshd_config  # which package owns this file?
rpm -q --requires openssh-server
rpm -q --whatrequires openssl-libs
rpm -q --scripts openssh-server   # install/remove scriptlets
rpm -q --changelog openssh-server | head   # often mentions fixed CVEs
rpm -V openssh-server         # verify installed files against the database
rpm -Va                       # verify everything (slow)
```

Add `-p` to query a package **file** that is not installed: `rpm -qlp ./hello-lab-2.0-1.noarch.rpm`.

`rpm -V` prints nothing if all is well, or a line per changed file with codes: `S` size, `5` checksum, `M`
mode, `U` user, `G` group, `T` mtime, and a `c` before configuration files. Seeing `S.5....T.  c
/etc/ssh/sshd_config` just means someone edited the config, which is normal. Seeing that on `/usr/bin/ls` means
something is very wrong.

**Configuration files** are handled carefully. When an update ships a new default config and you had modified
yours, RPM keeps your file and writes the new one as `file.rpmnew`; in some cases it saves yours as
`file.rpmsave`. After major updates, `find /etc -name '*.rpmnew'` shows what to review.

### Signatures and trust

Red Hat signs every package with its GPG key. Public keys are imported into the RPM database (`rpm --import
/etc/pki/rpm-gpg/RPM-GPG-KEY-redhat-release`; RHEL ships its keys there), and then:

```bash
rpm -K package.rpm       # check a file's digests and signature
rpm -qa gpg-pubkey*      # keys you trust
```

DNF checks signatures before installing whenever a repository has `gpgcheck=1`. A package from an unsigned
repository, like a lab or exam repository built with `createrepo`, needs `gpgcheck=0`, or DNF refuses with
a "GPG check FAILED" or "public key not installed" error.

---

## 2.1 Configure access to RPM repositories

### What a repository is

A **repository** is nothing more than a directory, served over HTTP(S), FTP, or as a local path, containing
package files and a `repodata/` subdirectory of **metadata**. The metadata (produced by `createrepo_c`) lists
every package's NEVRA, dependencies, provides, file lists, sizes and checksums. `repodata/repomd.xml` is the
index pointing to the other metadata files.

DNF never browses the package directory. It downloads the metadata, caches it under `/var/cache/dnf/`, does all
its searching and dependency solving against that cache, and downloads only the packages it needs. This
explains several behaviours:

- `dnf search`, `dnf info` and `dnf provides` work without the packages being downloaded.
- If the metadata is stale, DNF may not see a package you just added to a repository; `dnf clean all` or
  `dnf makecache` refreshes it. Metadata also expires on its own (`metadata_expire`, 48 hours by default on
  RHEL, configurable per repo).
- **If any enabled repository is unreachable or its metadata is broken, almost every `dnf` command fails**,
  even commands about packages in other repositories, because DNF loads all enabled repositories before doing
  anything. (`skip_if_unavailable=False` is the RHEL default.) The fix is to correct or disable that repo.

### BaseOS and AppStream

RHEL's content is split into two main repositories:

- **BaseOS**: the core operating system: kernel, systemd, glibc, coreutils, openssh, LVM, NetworkManager.
  It is supported for the life of the release with a traditional, stable package set.
- **AppStream**: applications, languages, databases and tools: httpd, nginx, PHP, Python modules, PostgreSQL,
  developer tools, and so on. Some components here have shorter life cycles, and alternative versions are
  offered over time ("application streams"). In RHEL 8 and 9 those alternatives were mostly delivered as
  **modules** (`dnf module`); RHEL 10 largely moves away from modularity, so alternative versions appear as
  separately named packages and `dnf module list` shows little or nothing.

A working RHEL system needs both. The installation DVD contains both, in the `BaseOS/` and `AppStream/`
directories, and that is exactly what exam environments usually serve over HTTP.

### Repository definition files

DNF reads its main configuration from `/etc/dnf/dnf.conf` and repository definitions from every `*.repo` file in
`/etc/yum.repos.d/`. A repo file is in INI format, and may define several repositories:

```ini
[baseos]
name=Lab BaseOS
baseurl=http://content.example.com/rhel10.0/x86_64/dvd/BaseOS
enabled=1
gpgcheck=1
gpgkey=file:///etc/pki/rpm-gpg/RPM-GPG-KEY-redhat-release

[appstream]
name=Lab AppStream
baseurl=http://content.example.com/rhel10.0/x86_64/dvd/AppStream
enabled=1
gpgcheck=0
```

| Key | Meaning |
|---|---|
| `[id]` | the repository ID: unique, no spaces; what `dnf repolist` and `--repo=` use |
| `name=` | human-readable description (optional but expected) |
| `baseurl=` | where the repo is: `http://`, `https://`, `ftp://` or `file:///` (three slashes: `file://` plus an absolute path) |
| `mirrorlist=` / `metalink=` | alternatively, a URL returning a list of mirrors |
| `enabled=` | `1` to use it (default if omitted), `0` to ignore it |
| `gpgcheck=` | `1` to verify package signatures, `0` to skip |
| `gpgkey=` | URL or `file:///` path of the public key to import when needed |
| `priority=`, `cost=`, `metadata_expire=`, `skip_if_unavailable=`, `sslverify=` | less common tuning |

The `baseurl` must point at the directory that **contains `repodata/`**. A very common mistake is pointing one
level too high or too low. You can check with a browser-free test:
`curl -s http://content.example.com/rhel10.0/x86_64/dvd/BaseOS/repodata/repomd.xml | head -3`.

### Three ways to create a repository definition

1. **Write the file** with vim or a heredoc, as above. You control the ID, name and gpg settings, and it is
   the most reliable approach.
2. **`dnf config-manager --add-repo URL`** (from `dnf-plugins-core`, installed by default) generates a file
   such as `/etc/yum.repos.d/content.example.com_rhel10.0_x86_64_dvd_BaseOS.repo` with the URL as both ID and
   name. It does not set `gpgcheck`, so the global default from `dnf.conf` (`gpgcheck=1`) applies; add
   `gpgcheck=0` to the file (or import the key) if the repository is unsigned.
3. **`dnf config-manager --add-repo /path/to/file.repo`** or a URL ending in `.repo` copies a ready-made
   definition into `/etc/yum.repos.d/`.

Enable and disable without editing: `dnf config-manager --set-disabled ID`, `--set-enabled ID`. For a single
command only: `dnf --disablerepo=ID ...`, `dnf --enablerepo=ID ...`, or `dnf --repo=ID ...` to use one repository
exclusively.

### Checking your work

```bash
dnf repolist            # enabled repos (ID and name)
dnf repolist all        # including disabled ones
dnf repolist -v         # baseurl, package counts, metadata age
dnf repoinfo baseos
dnf clean all           # throw away cached metadata (after fixing a repo)
dnf makecache           # download fresh metadata now
```

A local directory of RPMs can be turned into a repository with `createrepo_c /srv/repo` (package
`createrepo_c`) and then referenced with `baseurl=file:///srv/repo`. Mounting the installation ISO and pointing
two repo files at its `BaseOS` and `AppStream` directories is the classic way to install software on a
disconnected machine:

```bash
mkdir -p /mnt/dvd
mount -o loop,ro /root/rhel-10.0-x86_64-dvd.iso /mnt/dvd      # or /dev/sr0
# then baseurl=file:///mnt/dvd/BaseOS and file:///mnt/dvd/AppStream
```

> **Exam angle.** Typical: "Configure the system to use these two repositories: URL/BaseOS and URL/AppStream."
> Write both files, set `gpgcheck=0` unless a key is supplied (if a key URL is given, set `gpgcheck=1` and
> `gpgkey=URL`, or `rpm --import URL`), then prove it with `dnf repolist` and a test install. Get this right
> early: many later tasks install packages, and a typo here costs you every one of them.

---

## 2.2 Install and remove RPM software packages

### What happens during `dnf install`

1. DNF loads enabled repositories (metadata from cache or network) and the RPM database.
2. The **solver** (libsolv) computes a transaction: the requested packages plus every dependency not already
   satisfied, possibly upgrades of installed packages needed for compatibility.
3. DNF shows you the transaction and asks for confirmation (`-y` answers yes).
4. It downloads the packages into the cache and checks each signature (`gpgcheck`).
5. It runs a test transaction (file conflicts, disk space), then the real one: RPM runs each package's
   pre-install scriptlet, unpacks files, records them in the database and runs post-install scriptlets
   (which might create a system user, or reload systemd).
6. The transaction is recorded in DNF's history.

Installing a package that contains a service **does not start or enable it**. On RHEL, presets usually leave
new services disabled, so `dnf install httpd` is always followed by `systemctl enable --now httpd` (Lecture 7).

### The commands

```bash
dnf install httpd            # install (plus dependencies)
dnf install -y httpd mod_ssl # several, no prompt
dnf reinstall openssh-server # put back deleted or damaged files
dnf remove httpd             # remove it and anything that depends on it
dnf autoremove               # remove dependencies nothing needs any more
dnf upgrade                  # update everything (dnf update is the same)
dnf upgrade openssh*         # update matching packages
dnf check-update             # list available updates (exit status 100 if any)
dnf downgrade pkg

dnf search keyword           # name and summary
dnf search all keyword       # also descriptions
dnf info httpd               # version, repo, size, summary, whether installed
dnf list installed | grep http
dnf list available 'python3*'
dnf list --upgrades
dnf provides /usr/sbin/semanage   # which package delivers this file or capability
dnf provides '*bin/nmap'
dnf repoquery -l chrony      # files in a package without installing it
dnf deplist httpd            # its dependencies and who provides them
```

`dnf remove` removes the package **and every installed package that requires it**. Read the transaction
summary before you answer `y`: removing a library can take a lot of software with it. Unused dependencies
pulled in automatically are cleaned by `autoremove` (DNF tracks which packages you asked for and which came
in as dependencies).

### Package groups

**Groups** (also called environments for the biggest ones) install a predefined set of packages for a role:

```bash
dnf group list               # also: dnf group list --hidden
dnf group info "Development Tools"
dnf group install "Development Tools"     # or dnf install @development
dnf group remove "Development Tools"
```

The "Minimal Install", "Server" and "Server with GUI" choices in the installer are environment groups.

### History and undo

Every DNF transaction is numbered:

```bash
dnf history                  # list
dnf history info 7           # what transaction 7 did
dnf history undo 7           # reverse it
dnf history rollback 5       # undo everything after 5
```

This is a genuinely useful safety net when an install drags in or removes more than you expected.

### Kernels are special

Most packages are *upgraded*, replacing the old version. The kernel is *installed alongside*: each
`dnf upgrade` that brings a new kernel adds it, the bootloader gets a new entry, and the newest becomes the
default. The old ones stay so you can boot back if the new kernel fails. `installonly_limit=3` in
`/etc/dnf/dnf.conf` keeps the three newest. Lecture 7 (objective 7.6) explains how to choose the default.

### Installing from the local file system

You can give DNF a path instead of a name:

```bash
dnf install ./hello-lab-2.0-1.noarch.rpm
dnf install /root/rpms/*.rpm
dnf install https://example.com/pkgs/tool-1.0-1.el10.noarch.rpm
```

DNF installs the local file **and resolves its dependencies from your enabled repositories**. Compare
`rpm -ivh hello-lab-2.0-1.noarch.rpm` (`-i` install, `-v` verbose, `-h` progress hashes; `-U` upgrade,
`-F` freshen, `-e` erase), which only succeeds if every dependency is already installed, and which bypasses
DNF's history. Prefer `dnf` unless you have a reason not to. One advantage of DNF here is that the package
is still checked against GPG keys if `gpgcheck` applies to local packages (`localpkg_gpgcheck`, off by
default); if a signed local package fails due to a missing key, `rpm --import` the key or use `--nogpgcheck`.

### Red Hat Content Delivery Network (objective 7.5)

On a real, registered RHEL system, BaseOS and AppStream come from Red Hat's **Content Delivery Network** (CDN,
`cdn.redhat.com`), and access depends on a subscription. The flow is:

```bash
subscription-manager register --username USER --password PASS   # or: rhc connect
subscription-manager status
subscription-manager repos --list-enabled
dnf repolist
# rhel-10-for-x86_64-baseos-rpms
# rhel-10-for-x86_64-appstream-rpms
dnf upgrade
```

Registration installs an entitlement certificate and generates `/etc/yum.repos.d/redhat.repo`, which
`subscription-manager` manages: do not edit it by hand, enable extra repositories with
`subscription-manager repos --enable=REPO-ID` (or `dnf config-manager --set-enabled`). `rhc connect` registers
the system and also connects it to Red Hat's Insights services. With Simple Content Access (now the norm),
registering is enough: there is no per-system "attach a subscription" step. A free Red Hat Developer
subscription lets you practise this on your own RHEL VM.

The exam room has no internet, so CDN tasks cannot be tested directly; expect local HTTP repositories
instead. Still, know the commands above: the objective names the CDN explicitly.

> **Exam angle.** "Install the package that provides the `semanage` command", "install the X group",
> "update the system", "install the RPM at http://.../file.rpm". Each is one `dnf` line once repositories work.

---

## 2.3 Configure access to Flatpak repositories

### Why a second packaging system?

RPM packages share libraries: one copy of `glibc` or GTK serves every program. That is efficient and lets Red
Hat patch a library once for everything, but it ties applications to the library versions of the OS release.
A desktop user on a ten-year enterprise release cannot easily get a current version of a graphical app.

**Flatpak** is designed for desktop applications and solves that differently:

- An **app** is bundled together with the libraries it needs beyond a common base.
- That base comes from a **runtime**: a large, versioned set of libraries such as
  `org.freedesktop.Platform` or `org.gnome.Platform`. Many apps share one runtime.
- Apps run in a **sandbox** (using kernel namespaces via `bubblewrap`): they see their own `/usr` (the
  runtime) and `/app` (the application), and get only the access to your files, devices and network that their
  **permissions** grant. Access to files outside is brokered by **portals** (a file chooser that hands the app
  only what you pick).
- Apps and runtimes are stored in an **OSTree** repository, which is content-addressed and de-duplicated, so
  updates download only changed files and several versions can coexist.

So Flatpak does not replace RPM: the OS, services and command-line tools stay RPMs. Flatpak is for
user-facing applications, and RHEL 10 includes `flatpak` in the default desktop installation and in the
objectives.

### Remotes

A Flatpak **remote** is a repository of apps and runtimes, identified by a local name. You configure it from a
`.flatpakrepo` file, a small description holding the URL and the GPG key used to verify content:

```bash
flatpak remote-add --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo
flatpak remotes                 # list configured remotes (add -d for details)
flatpak remotes --show-disabled
flatpak remote-ls flathub --app # what it offers (apps only)
flatpak remote-modify --disable flathub
flatpak remote-modify --enable flathub
flatpak remote-delete flathub
```

`--if-not-exists` makes the command safe to repeat. Remote names are case-sensitive and are what you pass to
`flatpak install`. **Flathub** is the main community repository. RHEL also ships a `rhel` remote definition that
provides Red Hat-built Flatpaks from Red Hat's container registry, which requires logging in with your Red Hat
account; on a disconnected exam system, expect to be given a remote URL or `.flatpakrepo` file instead.

### System-wide versus per-user

Flatpak keeps two independent **installations**:

| | System (`--system`) | User (`--user`) |
|---|---|---|
| Location | `/var/lib/flatpak` | `~/.local/share/flatpak` |
| Who can use the apps | every user | that user only |
| Who manages it | root (or users allowed by polkit) | the user, no privileges |
| Remote config | `/var/lib/flatpak/repo/config` | in the user's directory |

As root, commands default to `--system`. As an ordinary user, commands that change things usually default to
`--system` as well and ask for authentication through polkit, unless you pass `--user`. Remotes belong to an
installation: a remote added with `--user` is invisible to `--system` commands and vice versa. If a task says
"system-wide" or "for all users", use `--system` explicitly; if it says "for user X", run the commands as X
with `--user`.

> **Exam angle.** "Configure the flatpak repository at URL with the name X for all users":
> `flatpak remote-add --system --if-not-exists X URL`, then `flatpak remotes` to check. If you are given a
> plain repository URL rather than a `.flatpakrepo` file, use
> `flatpak remote-add --no-gpg-verify X URL` only if told the content is unsigned.

---

## 2.4 Install and remove Flatpak software packages

### Application IDs and refs

Flatpak apps are named with **reverse-DNS IDs** such as `org.gnome.Calculator` or `org.mozilla.firefox`.
A full **ref** adds the type, architecture and branch:

```text
app/org.gnome.Calculator/x86_64/stable
runtime/org.gnome.Platform/x86_64/48
```

You normally give just the ID; Flatpak picks the architecture and the default branch.

### The commands

```bash
flatpak search calculator                     # search the appstream data of all remotes
flatpak install flathub org.gnome.Calculator  # REMOTE APP-ID; also pulls the runtime if missing
flatpak install -y --system flathub org.gnome.Calculator
flatpak list                                  # apps and runtimes
flatpak list --app                            # only apps
flatpak info org.gnome.Calculator             # ref, version, installation, size, runtime
flatpak info --show-permissions org.gnome.Calculator
flatpak run org.gnome.Calculator              # start it (needs a graphical session)
flatpak update                                # update all apps and runtimes
flatpak uninstall org.gnome.Calculator
flatpak uninstall --unused                    # remove runtimes no app needs any more
flatpak uninstall --delete-data APP-ID        # also remove ~/.var/app/APP-ID
flatpak history                               # log of installs, updates, removals
flatpak repair                                # fix a damaged installation
```

You can also install from a `.flatpakref` file, which contains both the remote and the app:
`flatpak install https://dl.flathub.org/repo/appstream/org.gnome.Calculator.flatpakref`.

Things to understand about what you see:

- **The first install is big.** Installing one app may pull a runtime of several hundred megabytes. Later apps
  using the same runtime are small.
- **Uninstalling an app leaves its runtime**, because another app might need it. `flatpak uninstall --unused`
  cleans up.
- **User data** lives in `~/.var/app/APP-ID/`, separate from the app, and survives uninstallation unless you
  ask for `--delete-data`.
- Installed apps add `.desktop` files under `/var/lib/flatpak/exports/` (or the user equivalent), which is how
  they appear in the desktop's application menu.

### RPM and Flatpak side by side

| | RPM / DNF | Flatpak |
|---|---|---|
| Target | the whole OS, services, CLI tools | desktop applications |
| Libraries | shared system-wide | bundled + shared runtimes |
| Isolation | none (runs with the user's full rights) | sandboxed, with declared permissions |
| Repository | `/etc/yum.repos.d/*.repo` | `flatpak remote-add` |
| Install | `dnf install NAME` | `flatpak install REMOTE APP-ID` |
| Query installed | `rpm -qa`, `dnf list installed` | `flatpak list` |
| Remove | `dnf remove NAME` | `flatpak uninstall APP-ID` |
| Updates | `dnf upgrade` | `flatpak update` |
| History | `dnf history` | `flatpak history` |
| Scope | system only | system or per user |

> **Exam angle.** Expect "install application X from remote Y" and possibly "for user Z only". Use the exact
> remote name you created. Verify with `flatpak list --app` and, for a per-user install, run that as the user.

---

## Putting it together

A realistic sequence on a fresh exam system:

```bash
# 1. repositories (two files, unsigned)
cat > /etc/yum.repos.d/dvd.repo <<'EOF'
[BaseOS]
name=BaseOS
baseurl=http://content.example.com/rhel10.0/x86_64/dvd/BaseOS
gpgcheck=0
[AppStream]
name=AppStream
baseurl=http://content.example.com/rhel10.0/x86_64/dvd/AppStream
gpgcheck=0
EOF
dnf repolist
# 2. software that later tasks will need
dnf install -y policycoreutils-python-utils autofs nfs-utils chrony tuned
# 3. a local package someone dropped in /root
dnf install -y /root/custom-tool-1.2-1.el10.noarch.rpm
# 4. a flatpak remote and app
flatpak remote-add --system --if-not-exists apps http://content.example.com/flatpak/apps.flatpakrepo
flatpak install -y apps org.example.Viewer
```

Notice how failures would surface: a wrong `baseurl` breaks step 2 with "Cannot download repomd.xml"; a signed
repository with `gpgcheck=1` and no key breaks with a GPG error; a missing dependency in step 3 would be fetched
by DNF automatically, which is why you use `dnf` rather than `rpm -i`.

**Now practise:** [Lab 02](#/lab/02) plants a broken repository that makes every `dnf` command fail, a repo
file with a wrong path, and asks you to update, install from file, and handle Flatpak.

## Review questions

1. What is the difference in responsibility between `rpm` and `dnf`?
2. Decode `bash-5.2.26-6.el10.x86_64.rpm`.
3. Why can a single unreachable repository make `dnf install` of an unrelated package fail? Name two fixes.
4. What must the `baseurl` of a repository point at, precisely?
5. You added a repo with `dnf config-manager --add-repo URL` and installs fail with a GPG error. Why, and what
   are your options?
6. How do you find which package provides the `semanage` command if it is not installed?
7. What does `rpm -V` output `S.5....T.  c /etc/chrony.conf` mean? Should you worry?
8. Why is `dnf install ./pkg.rpm` usually better than `rpm -ivh pkg.rpm`?
9. Why is the kernel handled differently from other packages during upgrades?
10. What are a Flatpak runtime and a Flatpak remote?
11. An app was installed with `--user` by harry. Does `flatpak list` run by root show it? Why?
12. After `flatpak uninstall APP`, disk usage barely drops. Why, and what reclaims the space?

<details><summary>Answers</summary>

1. `rpm` installs, removes, queries and verifies individual package files and owns the database; it neither
   downloads nor resolves dependencies. `dnf` works with repositories, solves dependencies, downloads, checks
   signatures and runs whole transactions through RPM.
2. Name `bash`, version `5.2.26`, release `6.el10` (build 6 for Enterprise Linux 10), architecture `x86_64`.
3. DNF loads metadata for every enabled repository before doing anything, and `skip_if_unavailable` defaults to
   false. Fix the `baseurl`, or disable the repository (`dnf config-manager --set-disabled ID` or `enabled=0`).
4. The directory that contains the `repodata/` subdirectory.
5. The generated file has no `gpgcheck` line, so the global `gpgcheck=1` applies. Either import the key
   (`rpm --import URL`, or add `gpgkey=`), or set `gpgcheck=0` if the repository is meant to be unsigned.
6. `dnf provides '*/semanage'` (it is `policycoreutils-python-utils`).
7. The configuration file's size, checksum and mtime differ from the packaged version: someone edited it.
   That is normal for a config file.
8. DNF resolves and installs missing dependencies from your repositories and records the transaction in its
   history; `rpm -i` just fails on missing dependencies.
9. Kernels are install-only: new versions are added alongside old ones so you can boot a previous kernel if the
   new one fails (`installonly_limit` keeps a few).
10. A runtime is a shared, versioned base set of libraries that apps are built against. A remote is a named
    Flatpak repository that apps and runtimes are installed from.
11. No. Per-user installations live in `~harry/.local/share/flatpak`; root's `flatpak list` shows the system
    installation (and root's own user installation).
12. The runtime it used is still installed. `flatpak uninstall --unused` removes unused runtimes.

</details>
