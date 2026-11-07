#!/bin/bash
set -e
. /opt/labkit/lib/vm.sh
for u in student sally; do id $u &>/dev/null || useradd -m $u; echo "$u:$u-pass" | chpasswd; done
rm -rf /home/student/.ssh /home/sally/.ssh
sed -i '/^umask/d' /home/student/.bashrc /home/student/.bash_profile 2>/dev/null || true
# SELinux starts permissive (runtime and config)
setenforce 0 || true
sed -i 's/^SELINUX=.*/SELINUX=permissive/' /etc/selinux/config
setsebool -P httpd_enable_homedirs off
# Web content in a non-standard place, served on a non-standard port
mkdir -p /srv/www
echo '<h1>lab11 port 82</h1>' > /srv/www/index.html
chcon -R -t default_t /srv/www
semanage fcontext -d '/srv/www(/.*)?' 2>/dev/null || true
semanage port -d -t http_port_t -p tcp 82 2>/dev/null || true
cat > /etc/httpd/conf.d/lab11.conf <<'C'
Listen 82
<VirtualHost *:82>
    DocumentRoot /srv/www
</VirtualHost>
<Directory /srv/www>
    Require all granted
</Directory>
C
# A file that was moved (not copied) into the web root keeps the wrong label
echo '<h1>moved page</h1>' > /root/moved.html
mv -f /root/moved.html /var/www/html/moved.html
chmod 644 /var/www/html/moved.html
systemctl enable httpd >/dev/null
systemctl restart httpd     # works only because SELinux is permissive right now
# Firewall starting point
systemctl enable --now firewalld >/dev/null
firewall-cmd -q --permanent --add-service=cockpit 2>/dev/null || true
for s in http; do firewall-cmd -q --permanent --remove-service=$s 2>/dev/null || true; done
firewall-cmd -q --permanent --remove-port=82/tcp 2>/dev/null || true
firewall-cmd -q --permanent --remove-rich-rule='rule family="ipv4" source address="192.168.50.99" reject' 2>/dev/null || true
firewall-cmd -q --reload
# sshd must allow passwords for the first ssh-copy-id
sed -i 's/^#\?PasswordAuthentication.*/PasswordAuthentication yes/' /etc/ssh/sshd_config
rm -f /etc/ssh/sshd_config.d/*-cloud*.conf 2>/dev/null || true
systemctl restart sshd
