#!/bin/bash
set -e
useradd -m harry 2>/dev/null || true
useradd -m sally 2>/dev/null || true
echo 'sally-pass' | passwd --stdin sally >/dev/null
groupadd -f devops

mkdir -p /srv/data/logs /srv/data/misc /srv/shared/reports /opt/tools/bin
# A log file to mine with grep
python3 - <<'PY'
import random
random.seed(42)
levels = ["INFO", "INFO", "INFO", "WARN", "ERROR", "DEBUG"]
msgs = ["disk usage at %d%%", "user login id=%d", "request took %dms", "worker %d restarted", "cache miss key=%d"]
with open("/srv/data/app.log", "w") as f:
    for i in range(400):
        month = random.choice(["2026-10", "2026-11"])
        day = random.randint(1, 28)
        lvl = random.choice(levels)
        f.write(f"{month}-{day:02d} 10:{i%60:02d}:00 {lvl} " + random.choice(msgs) % random.randint(1, 999) + "\n")
    f.write("note: ERRORS are summarised nightly\n")
PY
# Files owned by harry scattered around
for f in /srv/data/misc/a.cfg /srv/data/logs/h1.log /srv/data/logs/.hidden-h2 /srv/shared/reports/q3.csv /opt/tools/harry.txt; do
  echo "data" > "$f"; chown harry "$f"
done
echo "not harry's" > /srv/data/misc/b.cfg
mkdir -p /var/lib/labkit; find /srv /opt -user harry 2>/dev/null | sort > /var/lib/labkit/harry-files
echo "Remember to rotate the logs." > /srv/data/notes.txt
# An archive to unpack
mkdir -p /tmp/arch/payroll && echo "jan,feb,mar" > /tmp/arch/payroll/q1.csv && echo "apr,may,jun" > /tmp/arch/payroll/q2.csv
tar -C /tmp/arch -czf /srv/data/payroll.tar.gz payroll && rm -rf /tmp/arch
# Report script for the symlink task
printf '#!/bin/bash\necho "report generated on $(hostname)"\n' > /srv/data/report.sh; chmod 755 /srv/data/report.sh
# BROKEN: dangling symlink + non-executable target
printf '#!/bin/bash\necho "backup ok"\n' > /opt/tools/bin/backup.sh; chmod 644 /opt/tools/bin/backup.sh
ln -sfn /opt/tools/backup.sh /usr/local/bin/backup
# BROKEN: wide open secret file
echo "api_key=12345" > /srv/data/secret.txt; chmod 666 /srv/data/secret.txt; chown nobody:nobody /srv/data/secret.txt
# SSH flag readable only by sally
echo "FLAG-$(od -An -N4 -tx4 /dev/urandom | tr -d ' ')" > /home/sally/flag.txt
chown sally:sally /home/sally/flag.txt; chmod 600 /home/sally/flag.txt
cp /home/sally/flag.txt /var/lib/labkit/.flag 2>/dev/null || { mkdir -p /var/lib/labkit; cp /home/sally/flag.txt /var/lib/labkit/.flag; }
chmod 600 /var/lib/labkit/.flag
# Files for the edit / copy / move / delete tasks
cat > /srv/data/app.conf <<'C'
# application settings
name=inventory
port=8080
debug=true
workers=4
C
mkdir -p /srv/cleanup/old-reports/2025 && for m in 01 02 03; do echo "report $m" > /srv/cleanup/old-reports/2025/$m.txt; done
echo "keep me" > /srv/cleanup/keep.txt
touch -d '2026-01-15 09:30' /srv/data/notes.txt
echo 'harry:harry-pass' | chpasswd
# Allow password SSH logins for this lab
sed -i 's/^#\?PasswordAuthentication.*/PasswordAuthentication yes/' /etc/ssh/sshd_config
systemctl restart sshd
