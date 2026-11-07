#!/bin/bash
. /opt/labkit/lib/check.sh
section "Task 1: find and kill"
check "hog.pid holds the hog's PID" '[ "$(tr -d "[:space:]" < /root/hog.pid)" = "$(cat /var/lib/labkit/hog.pid)" ]'
check "the hog is gone" '! pgrep -f /usr/local/sbin/cruncher'
check "memhog.pid holds the memory hog's PID" '[ "$(tr -d "[:space:]" < /root/memhog.pid)" = "$(cat /var/lib/labkit/memhog.pid)" ]'
check "the memory hog is gone" '! pgrep -f /usr/local/sbin/hoarder'
section "Task 2: priorities"
check "batchjob runs at nice 10" '[ "$(ps -o ni= -p $(pgrep -f /usr/local/bin/batchjob | head -1) | tr -d " ")" = 10 ]'
check "indexer runs at nice 15" '[ "$(ps -o ni= -p $(pgrep -f /usr/local/bin/indexer | head -1) | tr -d " ")" = 15 ]'
section "Task 3: tuned"
check "tuned enabled" 'systemctl is-enabled tuned'
check "active profile is throughput-performance" 'grep -qx throughput-performance /etc/tuned/active_profile'
check "recommended profile recorded" '[ "$(tr -d "[:space:]" < /root/tuned-recommended.txt)" = "$(tuned-adm recommend 2>/dev/null | tr -d "[:space:]")" ]'
section "Task 4: journal search"
check "journal-code.txt has the right code" '[ "$(tr -d "[:space:]" < /root/journal-code.txt)" = "$(cat /var/lib/labkit/journal.code)" ]'
section "Task 5: persistent journal"
check "Storage=persistent configured (or /var/log/journal exists)" 'grep -rqs "^Storage=persistent" /etc/systemd/journald.conf /etc/systemd/journald.conf.d/ || [ -d /var/log/journal ]'
check "journal is being written to /var/log/journal" 'ls /var/log/journal/*/system.journal'
section "Task 6: httpd"
check "httpd config is valid" 'httpd -t'
check "httpd is active" 'systemctl is-active httpd'
check "httpd is enabled" 'systemctl is-enabled httpd'
check "serves the lab page" 'curl -s http://localhost/ | grep -q lab04'
check "crond stopped" '! systemctl is-active crond'
check "crond still enabled" 'systemctl is-enabled crond'
check "crond.pid recorded a real crond PID" 'journalctl -q --no-pager -u crond | grep -q "crond\[$(tr -d "[:space:]" < /root/crond.pid)\]"'
section "Task 7: file transfer"
check "report.txt is in sally's home, owned by sally" '[ "$(stat -c %U /home/sally/report.txt)" = sally ]'
check "/root/data.csv downloaded" 'grep -q id,value /root/data.csv'
summary
