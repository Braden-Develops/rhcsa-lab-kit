# Lab 05 solution

## Task 1: reset root's password (console)
1. Reboot. At the GRUB menu press any arrow key to stop the countdown, highlight the normal kernel, press **e**.
2. On the line starting with `linux`, delete `systemd.unit=emergency.target` (it's a one-time edit here) and
   append **`rd.break`**. Press **Ctrl+x** to boot.
3. In the `switch_root:/#` shell:
```bash
mount -o remount,rw /sysroot
chroot /sysroot
passwd root                 # type redhat twice (or: echo redhat | passwd --stdin root)
touch /.autorelabel         # passwd wrote /etc/shadow without an SELinux label: relabel on next boot
exit; exit                  # the system continues booting (and relabels, then reboots once)
```
Alternative: append `init=/bin/bash` instead of `rd.break`, then `mount -o remount,rw /`, `passwd`,
`touch /.autorelabel`, `exec /sbin/init`. If you prefer not to relabel the whole disk: after `passwd`, run
`load_policy -i` and `restorecon -v /etc/shadow` instead of creating `/.autorelabel`.

## Tasks 2 to 5 (as root, after logging in)
```bash
grubby --info=ALL | grep -E '^(kernel|args)'             # see what every kernel boots with
grubby --update-kernel=ALL --remove-args="systemd.unit=emergency.target"
grubby --update-kernel=ALL --args="audit_backlog_limit=8192"
sed -i 's/^GRUB_TIMEOUT=.*/GRUB_TIMEOUT=10/' /etc/default/grub
grub2-mkconfig -o /boot/grub2/grub.cfg                    # same path on BIOS and UEFI on RHEL 9/10
systemctl set-default multi-user.target
```

## Task 6: one-off rescue boot
Reboot, press **e** on the kernel entry, append `systemd.unit=rescue.target` to the `linux` line, Ctrl+x.
Enter root's password, look around, then `systemctl default` (or just reboot).

## Tasks 7 to 9
```bash
systemctl poweroff         # same as: shutdown -h now ; `shutdown -r +5 "msg"` schedules, `shutdown -c` cancels
# start the VM again, then at the console: Ctrl+Alt+F2 -> login: student -> su - -> exit -> exit
systemctl reboot
```

**Notes.** `systemctl isolate rescue.target` switches a *running* system; the GRUB edit changes *one* boot.
`systemd.unit=emergency.target` (or just `emergency`) mounts root read-only and starts almost nothing: that's the
target you use when `/etc/fstab` is broken. Kernel args for all kernels live in the BLS entries under
`/boot/loader/entries/`, which is why `grubby` is the right tool and editing `GRUB_CMDLINE_LINUX` alone only affects
future kernels (unless you add `--update-bls-cmdline` to grub2-mkconfig).
