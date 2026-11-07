# Lab 11 solution

```bash
# 1
setenforce 1
sed -i 's/^SELINUX=.*/SELINUX=enforcing/' /etc/selinux/config
getenforce
# 2  -Z works on ps, ls, id, cp, mkdir ...
ps -eZ | grep sshd               # system_u:system_r:sshd_t:s0-s0:c0.c1023 ...
echo sshd_t > /root/sshd-type.txt
ls -Z /etc/shadow
echo shadow_t > /root/shadow-type.txt
# 3
systemctl restart httpd          # fails: "Permission denied: could not bind to address [::]:82"
journalctl -t setroubleshoot -e  # or: ausearch -m AVC -ts recent ; sealert -a /var/log/audit/audit.log
semanage port -a -t http_port_t -p tcp 82
semanage fcontext -a -t httpd_sys_content_t '/srv/www(/.*)?'
restorecon -Rv /srv/www
systemctl enable --now httpd; systemctl restart httpd
curl http://localhost:82/
# 4  mv keeps the source label (admin_home_t); cp would have taken the destination's
ls -Z /var/www/html/moved.html
restorecon -v /var/www/html/moved.html
# 5
getsebool -a | grep homedirs
setsebool -P httpd_enable_homedirs on
# 6
firewall-cmd --permanent --add-service=http
firewall-cmd --permanent --add-port=82/tcp
firewall-cmd --permanent --remove-service=cockpit
firewall-cmd --permanent --add-rich-rule='rule family="ipv4" source address="192.168.50.99" reject'
firewall-cmd --reload
firewall-cmd --list-all
# 7
echo 'umask 027' >> /home/student/.bashrc
# 8  (ssh-copy-id asks for sally's password once)
su - student -c 'ssh-keygen -t ed25519 -N "" -f ~/.ssh/id_ed25519'
su - student -c 'ssh-copy-id sally@localhost'
su - student -c 'ssh sally@localhost hostname'
```

**Notes.** Never answer an SELinux task with `setenforce 0` or `chcon` on the exam: `chcon` labels don't survive a
relabel or `restorecon`. The pattern is always *diagnose* (`ausearch -m AVC`, `sealert`, `journalctl`), then
*fix the policy* (`semanage fcontext` + `restorecon`, `semanage port`, `setsebool -P`). `semanage ... -l -C`
lists only your local customizations. `man semanage-fcontext` has examples, and installing `selinux-policy-doc`
gives per-service pages like `man httpd_selinux`. System-wide umask lives in `/etc/login.defs` (UMASK) and
`/etc/profile.d/*.sh`; per user, in `~/.bashrc` or `~/.bash_profile`.
