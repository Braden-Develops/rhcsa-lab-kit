#!/bin/bash
. /opt/labkit/lib/check.sh
since="@$(cat /var/lib/labkit/setup-time 2>/dev/null || echo 0)"
section "Task 1: root password"
check "root password is redhat" "password_is root redhat"
check "/etc/shadow has SELinux type shadow_t" 'ls -Z /etc/shadow | grep -q shadow_t'
section "Task 2: emergency mode removed"
check "no kernel has systemd.unit=emergency.target" '! grubby --info=ALL | grep "^args" | grep -q "systemd.unit=emergency"'
check "current boot is not emergency" '! grep -q systemd.unit=emergency /proc/cmdline'
section "Task 3: kernel argument"
check "every kernel has audit_backlog_limit=8192" '[ "$(grubby --info=ALL | grep -c "^args")" = "$(grubby --info=ALL | grep "^args" | grep -c "audit_backlog_limit=8192")" ]'
check "running kernel booted with it (you rebooted)" 'grep -q audit_backlog_limit=8192 /proc/cmdline'
section "Task 4: GRUB timeout"
check "/etc/default/grub has GRUB_TIMEOUT=10" 'grep -Eq "^GRUB_TIMEOUT=\"?10\"?$" /etc/default/grub'
check "grub.cfg regenerated with timeout=10" 'grep -q "set timeout=10" /boot/grub2/grub.cfg'
section "Task 5: default target"
check "default target is multi-user.target" '[ "$(systemctl get-default)" = multi-user.target ]'
section "Task 6: rescue boot"
check "journal shows a boot into rescue.target since setup" 'journalctl -q --no-pager --since "$since" | grep -q "Reached target rescue.target"'
section "Task 7: clean power-off"
check "journal shows a normal power-off since setup" 'journalctl -q --no-pager --since "$since" | grep -Eq "System is powering down|Reached target .*(poweroff.target|Power-Off)"'
section "Task 8: console login"
check "student logged in on a text console (tty)" 'journalctl -q --no-pager --since "$since" _COMM=login | grep -q "LOGIN ON tty[0-9]* BY student\|session opened for user student"'
check "student used su - to become root" 'journalctl -q --no-pager --since "$since" | grep "pam_unix(su" | grep -Eq "session opened for user root.* by student"'
section "Task 9: normal boot"
check "currently in multi-user/graphical (not rescue)" 'systemctl is-active multi-user.target && ! systemctl is-active rescue.target'
summary
