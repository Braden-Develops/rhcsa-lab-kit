#!/bin/bash
. /opt/labkit/lib/check.sh
section "Task 1: broken mirror"
check "broken-mirror repo is disabled" 'dnf -q repolist --disabled 2>/dev/null | grep -qw broken-mirror'
check "broken-mirror.repo file still exists" '[ -f /etc/yum.repos.d/broken-mirror.repo ]'
section "Task 2: internal repo"
check "internal repo is enabled and readable" 'dnf -q --repo internal repoquery labtool 2>/dev/null | grep -q labtool'
check "labtool updated to 1.1" '[ "$(rpm -q --qf %{VERSION} labtool)" = 1.1 ]'
section "Task 3: extras repo"
check "extras.repo defines [extras]" 'grep -q "^\[extras\]" /etc/yum.repos.d/extras.repo'
check "labextra installed" 'rpm -q labextra'
section "Task 4: local rpm"
check "hello-lab installed" 'rpm -q hello-lab'
section "Task 5: remove"
check "tree removed" '! rpm -q tree'
section "Task 6: provides"
check "crontab-pkg.txt says cronie" '[ "$(tr -d "[:space:]" < /root/crontab-pkg.txt)" = cronie ]'
section "Task 7: flatpak"
check "system remote flathub configured" 'flatpak remotes --system --columns=name,url | grep -E "^flathub\s+https://dl.flathub.org/repo/?"'
section "Task 8: flatpak install/remove"
check "an app was installed from flatpak" 'flatpak history --columns=change,application 2>/dev/null | grep -v uninstall | grep -q "install.*org.gnome.Calculator"'
check "and uninstalled again" 'flatpak history --columns=change,application 2>/dev/null | grep -q "uninstall.*org.gnome.Calculator" && ! flatpak list --app --columns=application | grep -qx org.gnome.Calculator'
summary
