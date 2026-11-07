# Lab 04 solution

```bash
# 1  top sorts by CPU by default (press P); ps works too
ps -eo pid,user,%cpu,cmd --sort=-%cpu | head -3
pid=$(ps -eo pid= --sort=-%cpu | head -1 | tr -d ' ')
echo "$pid" > /root/hog.pid
kill "$pid"            # escalate with kill -9 only if it ignores SIGTERM
ps -eo pid,user,rss,%mem,cmd --sort=-rss | head -3     # or top, then M
mpid=$(ps -eo pid= --sort=-rss | head -1 | tr -d ' ')
echo "$mpid" > /root/memhog.pid
kill "$mpid"
# 2
renice -n 10 -p $(pgrep -f /usr/local/bin/batchjob)
nice -n 15 /usr/local/bin/indexer &>/dev/null &
# 3
systemctl enable --now tuned
tuned-adm profile throughput-performance
tuned-adm active
tuned-adm recommend > /root/tuned-recommended.txt
# 4
journalctl -t payroll-sync -p err
journalctl -t payroll-sync -p err -o cat | grep -o 'PSYNC-[0-9]*' > /root/journal-code.txt
# 5
mkdir -p /etc/systemd/journald.conf.d
printf '[Journal]\nStorage=persistent\n' > /etc/systemd/journald.conf.d/persistent.conf
systemctl restart systemd-journald
journalctl --flush                 # move the runtime journal to /var/log/journal now
# 6
systemctl start httpd; systemctl status httpd --no-pager; httpd -t   # shows the bad line
sed -i '/^Listen: 8081/d' /etc/httpd/conf/httpd.conf
systemctl enable --now httpd
curl -s http://localhost/
systemctl status crond --no-pager            # "Main PID: NNN (crond)"
systemctl show -p MainPID --value crond > /root/crond.pid
systemctl stop crond
systemctl is-active crond; systemctl is-enabled crond
# 7  (interactive: you'll be asked for sally's password)
scp /root/transfer/report.txt sally@localhost:
scp sally@localhost:/home/sally/outbox/data.csv /root/data.csv
```

**Notes.** `nice` sets priority for a *new* process; `renice` changes a running one. Only root can lower niceness.
In `top`: `P` sort by CPU, `M` by memory, `k` to kill, `r` to renice. On RHEL 10 the journal is volatile by default
(`Storage=auto` and no `/var/log/journal`): either set `Storage=persistent` or just `mkdir /var/log/journal` and
restart/flush journald. `journalctl -u unit`, `-p err`, `-b -1` (previous boot), `--since "1 hour ago"`, `-f` follow.
