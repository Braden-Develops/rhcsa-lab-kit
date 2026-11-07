# Lab 02 solution

```bash
# 1  find the culprit from the error message, then disable it
dnf repolist                                  # error names broken-mirror
dnf config-manager --set-disabled broken-mirror   # or edit the file: enabled=0
# 2  fix the path, enable it, and turn off gpgcheck (packages are unsigned)
sed -i -e 's|/srv/repo/internal|/srv/repos/internal|' -e 's/enabled=0/enabled=1/' -e 's/gpgcheck=1/gpgcheck=0/' /etc/yum.repos.d/internal.repo
dnf clean all && dnf -y update labtool         # or: dnf upgrade labtool ; dnf check-update lists updates
# 3
cat > /etc/yum.repos.d/extras.repo <<'R'
[extras]
name=Extras
baseurl=file:///srv/repos/extras
enabled=1
gpgcheck=0
R
dnf -y install labextra
# 4  dnf resolves dependencies; plain rpm -i would not
dnf -y install /root/rpms/hello-lab-2.0-1.noarch.rpm
# 5
dnf -y remove tree
# 6
dnf provides /usr/bin/crontab                   # or: rpm -qf /usr/bin/crontab
rpm -qf --qf '%{NAME}\n' /usr/bin/crontab > /root/crontab-pkg.txt
# 7
flatpak remote-add --system --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo
flatpak remotes
# 8
flatpak search calculator
flatpak install -y flathub org.gnome.Calculator
flatpak list --app
flatpak uninstall -y org.gnome.Calculator
flatpak uninstall -y --unused                   # removes the now-unused runtime
flatpak history
```

**CDN (task 9).** On a real RHEL system: `subscription-manager register --username U --password P`
(a free Red Hat Developer account works), then `subscription-manager repos --list-enabled` /
`dnf repolist` shows `rhel-10-for-x86_64-baseos-rpms` and `...-appstream-rpms`; `dnf update` / `dnf install`
work as usual. `subscription-manager status` and `/etc/yum.repos.d/redhat.repo` (managed, don't edit) are the
places to look. The exam itself uses local repositories instead, but the objective names the CDN.

**Exam notes.** On the exam you'll usually get a URL like `http://content.example.com/rhel10.0/x86_64/dvd/BaseOS`
and `AppStream`: make two repo files (or `dnf config-manager --add-repo URL` twice) and set `gpgcheck=0` unless
you're told to import a key (`rpm --import URL`). `dnf config-manager --add-repo` names the repo after the URL,
which is fine. Flatpak: `flatpak remote-add`, `flatpak install <remote> <app-id>`, `flatpak uninstall`,
`flatpak list`, `flatpak search`; `--system` is the default as root, `--user` for per-user installs.
