#!/bin/bash
set -e
work=$(mktemp -d)
mkpkg() { # name version summary
  local n=$1 v=$2
  mkdir -p "$work/SPECS"
  cat > "$work/SPECS/$n.spec" <<SPEC
Name: $n
Version: $v
Release: 1
Summary: $3
License: MIT
BuildArch: noarch
%description
$3
%install
mkdir -p %{buildroot}/usr/local/bin
printf '#!/bin/sh\necho "$n $v"\n' > %{buildroot}/usr/local/bin/$n
chmod 755 %{buildroot}/usr/local/bin/$n
%files
/usr/local/bin/$n
SPEC
  rpmbuild -bb --define "_topdir $work" "$work/SPECS/$n.spec" >/dev/null
}
mkpkg labtool 1.0 "Internal lab tool"
mkpkg labtool 1.1 "Internal lab tool"
mkpkg labextra 3.2 "Extra goodies"
mkpkg hello-lab 2.0 "Standalone package"
mkdir -p /srv/repos/internal /srv/repos/extras /root/rpms
cp "$work"/RPMS/noarch/labtool-*.rpm /srv/repos/internal/
cp "$work"/RPMS/noarch/labextra-*.rpm /srv/repos/extras/
cp "$work"/RPMS/noarch/hello-lab-*.rpm /root/rpms/
createrepo_c -q /srv/repos/internal; createrepo_c -q /srv/repos/extras
# labtool 1.0 is already installed from a file; the task is to update it from the repo
rpm -i "$work"/RPMS/noarch/labtool-1.0-1.noarch.rpm
rm -rf "$work"

# BROKEN: repo with a wrong path, disabled, and gpgcheck with no key
cat > /etc/yum.repos.d/internal.repo <<'REPO'
[internal]
name=Internal lab packages
baseurl=file:///srv/repo/internal
enabled=0
gpgcheck=1
REPO
# BROKEN: a mirror that does not exist and makes dnf fail
cat > /etc/yum.repos.d/broken-mirror.repo <<'REPO'
[broken-mirror]
name=Decommissioned mirror
baseurl=http://mirror.invalid.lab.example.com/el10/
enabled=1
gpgcheck=0
skip_if_unavailable=False
REPO
