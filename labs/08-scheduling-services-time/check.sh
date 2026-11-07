#!/bin/bash
. /opt/labkit/lib/check.sh
section "Task 1: cron"
check "natasha: 23 14 * * * logger rhcsa-cron" 'crontab -l -u natasha | grep -Eq "^\s*23\s+14\s+\*\s+\*\s+\*\s+/usr/bin/logger\s+\"?rhcsa-cron"'
check "root: */5 * * * 1-5 date >> heartbeat" 'crontab -l -u root | grep -Eq "^\s*(\*/5|0,5,10,15,20,25,30,35,40,45,50,55)\s+\*\s+\*\s+\*\s+(1-5|mon-fri|Mon-Fri)\s+/usr/bin/date\s*>>\s*/var/log/heartbeat.log"'
section "Task 2: at"
check "student has a pending at job" 'atq | grep -qw student'
check "the job touches /tmp/at-ran" 'for j in $(atq | awk "\$NF==\"student\"{print \$1}"); do at -c $j | grep -q "touch /tmp/at-ran" && exit 0; done; exit 1'
section "Task 3: timer"
check "cleanup.service runs cleanup.sh" 'systemctl cat cleanup.service | grep -q "^ExecStart=/usr/local/bin/cleanup.sh"'
check "cleanup.timer is active" 'systemctl is-active cleanup.timer'
check "cleanup.timer is enabled" 'systemctl is-enabled cleanup.timer'
check "timer fires every 15 minutes" 'systemctl cat cleanup.timer | grep -Eq "^(OnCalendar=\*:0?0/15|OnCalendar=\*:00,15,30,45|OnCalendar=\*-\*-\* \*:0?0/15(:00)?|OnUnitActiveSec=15m(in)?|OnUnitActiveSec=900)"'
section "Task 4: labapp"
check "labapp is active" 'systemctl is-active labapp'
check "labapp is enabled" 'systemctl is-enabled labapp'
section "Task 5: default target"
check "default target is multi-user.target" '[ "$(systemctl get-default)" = multi-user.target ]'
section "Task 6: time"
check "chrony.conf uses classroom.lab.example.com iburst" 'grep -Eq "^(server|pool)\s+classroom.lab.example.com\s+iburst" /etc/chrony.conf'
check "no other server/pool lines" '[ "$(grep -Ec "^(server|pool)\s" /etc/chrony.conf)" = 1 ]'
check "chronyd unmasked and enabled" 'systemctl is-enabled chronyd | grep -qx enabled'
check "time zone is America/Chicago" 'readlink /etc/localtime | grep -q "America/Chicago$"'
summary
