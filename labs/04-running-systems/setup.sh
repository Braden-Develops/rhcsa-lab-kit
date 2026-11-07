#!/bin/bash
set -e
useradd -m harry 2>/dev/null || true
useradd -m sally 2>/dev/null || true
echo 'sally:sally-pass' | chpasswd
mkdir -p /var/lib/labkit

# A CPU hog running as harry (a transient unit keeps it alive after setup ends)
cat > /usr/local/sbin/cruncher <<'S'
#!/bin/bash
while :; do :; done
S
chmod 755 /usr/local/sbin/cruncher
systemd-run --unit=lab-cruncher --uid=harry /usr/local/sbin/cruncher >/dev/null
sleep 1; pgrep -f /usr/local/sbin/cruncher > /var/lib/labkit/hog.pid

# A memory hog running as sally (holds ~300 MB)
cat > /usr/local/sbin/hoarder <<'S'
#!/usr/bin/python3
import time
blob = bytearray(300 * 1024 * 1024)
for i in range(0, len(blob), 4096):
    blob[i] = 1
while True:
    time.sleep(60)
S
chmod 755 /usr/local/sbin/hoarder
systemd-run --unit=lab-hoarder --uid=sally /usr/local/sbin/hoarder >/dev/null
sleep 2; pgrep -f /usr/local/sbin/hoarder > /var/lib/labkit/memhog.pid

# A low-priority batch job running at the default niceness
cat > /usr/local/bin/batchjob <<'S'
#!/bin/bash
while :; do sleep 5; done
S
chmod 755 /usr/local/bin/batchjob
systemd-run --unit=lab-batchjob /usr/local/bin/batchjob >/dev/null
cat > /usr/local/bin/indexer <<'S'
#!/bin/bash
while :; do sleep 7; done
S
chmod 755 /usr/local/bin/indexer

# A journal entry to find
code="PSYNC-$(od -An -N2 -tu2 /dev/urandom | tr -d ' ')"
echo "$code" > /var/lib/labkit/journal.code; chmod 600 /var/lib/labkit/journal.code
for i in 1 2 3; do logger -t payroll-sync -p user.info "sync batch $i ok"; done
logger -t payroll-sync -p user.err "sync failed: upstream rejected batch, error code $code"
logger -t payroll-sync -p user.info "retry scheduled"

# Make sure the journal is volatile to start with
rm -rf /var/log/journal
sed -i 's/^#\?Storage=.*/#Storage=auto/' /etc/systemd/journald.conf
rm -f /etc/systemd/journald.conf.d/*.conf 2>/dev/null || true

# BROKEN httpd: a typo in the config keeps it from starting
echo '<h1>lab04 web server</h1>' > /var/www/html/index.html
sed -i 's/^Listen 80$/Listen 80\nListen: 8081/' /etc/httpd/conf/httpd.conf
systemctl disable --now httpd 2>/dev/null || true

# File transfer material
mkdir -p /root/transfer /home/sally/outbox
echo "quarterly report" > /root/transfer/report.txt
echo "id,value" > /home/sally/outbox/data.csv
chown -R sally:sally /home/sally/outbox
sed -i 's/^#\?PasswordAuthentication.*/PasswordAuthentication yes/' /etc/ssh/sshd_config
systemctl restart sshd
systemctl enable --now crond >/dev/null 2>&1 || true
systemctl disable tuned >/dev/null 2>&1 || true
