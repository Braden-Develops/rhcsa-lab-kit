# Lab 08 solution

```bash
# 1  (crontab -e is the interactive way; fields: minute hour day-of-month month day-of-week)
echo '23 14 * * * /usr/bin/logger "rhcsa-cron"' | crontab -u natasha -
(crontab -l 2>/dev/null; echo '*/5 * * * 1-5 /usr/bin/date >> /var/log/heartbeat.log') | crontab -
# 2
su - student -c 'echo "touch /tmp/at-ran" | at now + 2 hours'
atq
# 3
cat > /etc/systemd/system/cleanup.service <<'U'
[Unit]
Description=Clean old scratch files

[Service]
Type=oneshot
ExecStart=/usr/local/bin/cleanup.sh
U
cat > /etc/systemd/system/cleanup.timer <<'U'
[Unit]
Description=Run cleanup every 15 minutes

[Timer]
OnCalendar=*:0/15
Persistent=true

[Install]
WantedBy=timers.target
U
systemctl daemon-reload
systemctl enable --now cleanup.timer
systemctl list-timers cleanup.timer
# 4
systemctl status labapp --no-pager      # "Failed to locate executable /usr/bin/labapp"
sed -i 's|^ExecStart=/usr/bin/labapp|ExecStart=/usr/local/bin/labapp|' /etc/systemd/system/labapp.service
systemctl daemon-reload
systemctl enable --now labapp
# 5
systemctl set-default multi-user.target
# 6
sed -i -E 's/^(server|pool)\s/#&/' /etc/chrony.conf
echo 'server classroom.lab.example.com iburst' >> /etc/chrony.conf
systemctl unmask chronyd
systemctl enable chronyd
systemctl restart chronyd || true      # in a container it may refuse to run; on a VM: chronyc sources -v
timedatectl set-timezone America/Chicago 2>/dev/null || ln -sf /usr/share/zoneinfo/America/Chicago /etc/localtime
```

**Notes.** `OnCalendar` syntax can be tested with `systemd-analyze calendar '*:0/15'`. A *masked* unit is linked to
`/dev/null` and can't be started even manually; `systemctl unmask` first. `systemctl isolate multi-user.target`
switches now; `set-default` changes the next boot. `at` accepts `now + 2 hours`, `teatime tomorrow`, `16:00 Dec 1`;
`atq` lists and `atrm` removes jobs. `/etc/cron.allow` / `cron.deny` and `/etc/at.allow` / `at.deny` control who may
schedule.
