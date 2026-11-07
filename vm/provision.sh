#!/bin/bash
# Runs once inside the VM on first `vagrant up`. Also usable on any RHEL 10 / AlmaLinux 10 / Rocky 10 VM you built
# yourself: copy the kit's bin/ lib/ labs/ into /opt/labkit, run  sudo bash vm/provision.sh,
# then  sudo ln -s /opt/labkit/bin/labctl /usr/local/bin/labctl
set -e
dnf -y --setopt=strict=0 install lvm2 parted gdisk dosfstools xfsprogs e2fsprogs nfs-utils httpd firewalld \
  policycoreutils-python-utils setroubleshoot-server selinux-policy-doc tuned chrony cronie at \
  acl man-pages man-db bash-completion vim-enhanced tar bzip2 rsync python3 grubby \
  NetworkManager diffutils curl flatpak
dnf -y remove autofs 2>/dev/null || true     # you install it yourself in lab 07
echo 'root:redhat' | chpasswd
id student &>/dev/null || useradd -m -c "Lab student" student
echo 'student:student' | chpasswd
echo 'student ALL=(ALL) ALL' > /etc/sudoers.d/student && chmod 440 /etc/sudoers.d/student
# Show the GRUB menu (cloud images hide it) so you can interrupt the boot in lab 05
sed -i 's/^GRUB_TIMEOUT_STYLE=.*/GRUB_TIMEOUT_STYLE=menu/; s/^GRUB_TIMEOUT=.*/GRUB_TIMEOUT=5/' /etc/default/grub
grep -q '^GRUB_TIMEOUT_STYLE' /etc/default/grub || echo 'GRUB_TIMEOUT_STYLE=menu' >> /etc/default/grub
grub2-editenv - unset menu_auto_hide || true
grub2-mkconfig -o /boot/grub2/grub.cfg >/dev/null
systemctl enable --now firewalld
systemctl set-default multi-user.target
echo "Lab VM ready. Take a snapshot now if you're not using ./lab:  vagrant snapshot save clean"
