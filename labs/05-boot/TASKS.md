# Lab 05: Boot targets, root password reset, GRUB

Covers: *boot, reboot, shut down normally; log in and switch users in multi-user targets; boot into different targets manually; interrupt the boot process to
gain access; configure the default target; modify the bootloader.*

**You need the VM's console for this lab**, not `vagrant ssh`: open it in virt-manager (libvirt) or
start the VM with `LAB_GUI=1` for VirtualBox (see README). The root password is now unknown.

1. Reboot the VM (`sudo systemctl reboot`). It comes up in **emergency mode** and asks for a root password
   you don't have. Interrupt the boot at the GRUB menu and **reset root's password to `redhat`**.
   Make sure SELinux won't block logins afterwards.
2. Find what forces emergency mode and remove it **permanently, for every installed kernel**.
3. Add the kernel argument `audit_backlog_limit=8192` **persistently to every kernel**.
4. Make the GRUB menu wait **10 seconds** by default (persistently).
5. Make the system boot into **multi-user.target** by default.
6. Boot **once** into **rescue.target** by editing the kernel line at the GRUB menu, log in as root,
   and from there continue to the normal target (`systemctl default`).
7. **Shut down normally**: power the VM off with `systemctl poweroff`, then start it again
   (`vagrant up`, virt-manager or VirtualBox).
8. **Log in on a text console of the multi-user target**: at the VM console switch to the second virtual terminal
   (Ctrl+Alt+F2; in virt-manager use *Send Key*), log in as `student` (password `student`), then use `su -` to
   become root (password `redhat`). Log out again.
9. Finally reboot normally (`systemctl reboot`), log in, and run `sudo labctl check`.
