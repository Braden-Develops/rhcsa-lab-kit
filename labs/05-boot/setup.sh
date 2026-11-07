#!/bin/bash
set -e
. /opt/labkit/lib/vm.sh
# Persistent journal so the grader can see what happened in earlier boots
mkdir -p /var/log/journal && systemctl restart systemd-journald && journalctl --flush
date +%s > /var/lib/labkit/setup-time
# Unknown root password
echo "root:$(head -c 18 /dev/urandom | base64)" | chpasswd
# Wrong default target and a short GRUB timeout
systemctl set-default graphical.target
sed -i 's/^GRUB_TIMEOUT=.*/GRUB_TIMEOUT=1/' /etc/default/grub
grub2-mkconfig -o /boot/grub2/grub.cfg >/dev/null 2>&1
# BROKEN: every kernel boots into emergency mode
grubby --update-kernel=ALL --args="systemd.unit=emergency.target"
echo "Setup done. Read the tasks, then reboot the VM from its console (virt-manager / VirtualBox window)."
