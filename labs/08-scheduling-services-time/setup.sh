#!/bin/bash
set -e
useradd -m natasha 2>/dev/null || true
# BROKEN service
cat > /usr/local/bin/labapp <<'S'
#!/bin/bash
while :; do echo "labapp alive"; sleep 30; done
S
chmod 755 /usr/local/bin/labapp
cat > /etc/systemd/system/labapp.service <<'U'
[Unit]
Description=Lab application

[Service]
ExecStart=/usr/bin/labapp
Restart=no

[Install]
WantedBy=multi-user.target
U
systemctl daemon-reload
systemctl start labapp 2>/dev/null || true
# cleanup script for the timer task
cat > /usr/local/bin/cleanup.sh <<'S'
#!/bin/bash
find /tmp -maxdepth 1 -name 'scratch-*' -mmin +60 -delete
logger -t cleanup "cleanup ran"
S
chmod 755 /usr/local/bin/cleanup.sh
# BROKEN time service: masked, and pointed at a public pool
systemctl disable --now chronyd 2>/dev/null || true
systemctl mask chronyd
# a default target that is "wrong" for a server
systemctl set-default graphical.target
