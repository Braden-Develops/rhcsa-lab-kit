#!/bin/bash
. /opt/labkit/lib/check.sh
section "Task 1: enforcing"
check "getenforce = Enforcing" '[ "$(getenforce)" = Enforcing ]'
check "/etc/selinux/config SELINUX=enforcing" 'grep -qx "SELINUX=enforcing" /etc/selinux/config'
section "Task 2: contexts"
check "sshd-type.txt = sshd_t" '[ "$(tr -d "[:space:]" < /root/sshd-type.txt)" = sshd_t ]'
check "shadow-type.txt = shadow_t" '[ "$(tr -d "[:space:]" < /root/shadow-type.txt)" = shadow_t ]'
section "Task 3: /srv/www on port 82"
check "persistent fcontext rule for /srv/www" 'semanage fcontext -l -C | grep -E "^/srv/www(\(/\.\*\)\?)?\s" | grep -q httpd_sys_content_t'
check "/srv/www/index.html labelled httpd_sys_content_t" 'ls -Z /srv/www/index.html | grep -q httpd_sys_content_t'
check "port 82/tcp labelled http_port_t" 'semanage port -l -C | grep -E "^http_port_t\s+tcp" | grep -qw 82'
check "httpd active and enabled" 'systemctl is-active httpd && systemctl is-enabled httpd'
check "curl localhost:82 works" 'curl -s --max-time 3 http://localhost:82/ | grep -q "lab11 port 82"'
section "Task 4: restorecon"
check "moved.html has httpd_sys_content_t" 'ls -Z /var/www/html/moved.html | grep -q httpd_sys_content_t'
check "curl moved.html works" 'curl -s --max-time 3 http://localhost/moved.html | grep -q "moved page"'
section "Task 5: boolean"
check "httpd_enable_homedirs on (runtime)" 'getsebool httpd_enable_homedirs | grep -q "on$"'
check "httpd_enable_homedirs on (persistent)" 'semanage boolean -l -C | grep -E "^httpd_enable_homedirs" | grep -q "(on\s*,\s*on)"'
section "Task 6: firewall"
z=$(firewall-cmd --get-default-zone 2>/dev/null)
for mode in "--permanent" ""; do
  label=${mode:+permanent}; label=${label:-runtime}
  check "http allowed ($label)" "firewall-cmd $mode --zone=$z --list-services | grep -qw http"
  check "82/tcp allowed ($label)" "firewall-cmd $mode --zone=$z --list-ports | grep -qw 82/tcp"
  check "cockpit removed ($label)" "! firewall-cmd $mode --zone=$z --list-services | grep -qw cockpit"
  check "rich rule rejects 192.168.50.99 ($label)" "firewall-cmd $mode --zone=$z --list-rich-rules | grep 192.168.50.99 | grep -q reject"
done
section "Task 7: umask"
check "student login umask is 0027" '[ "$(su - student -c umask)" = 0027 ]'
section "Task 8: SSH keys"
check "student -> sally@localhost works without password" 'su - student -c "ssh -o BatchMode=yes -o StrictHostKeyChecking=accept-new sally@localhost true"'
check "sally ~/.ssh is 700 and authorized_keys 600" '[ "$(stat -c %a /home/sally/.ssh)" = 700 ] && [ "$(stat -c %a /home/sally/.ssh/authorized_keys)" = 600 ]'
summary
