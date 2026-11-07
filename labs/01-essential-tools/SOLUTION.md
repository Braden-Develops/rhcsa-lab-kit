# Lab 01 solution

```bash
# 1
grep -E '^2026-11' /srv/data/app.log | grep -w ERROR > /root/nov-errors.txt
#   or in one regex:  grep -E '^2026-11.*\bERROR\b' /srv/data/app.log > /root/nov-errors.txt
# 2
find /srv /opt -user harry > /root/harry-files.txt 2> /root/find-errors.txt
# 3
tar -cjf /root/ssh-backup.tar.bz2 /etc/ssh          # -j = bzip2, -z = gzip, -J = xz
mkdir -p /opt/restore && tar -xzf /srv/data/payroll.tar.gz -C /opt/restore
cp /srv/data/notes.txt /root/ && gzip /root/notes.txt   # gzip replaces the file with file.gz
# 4
ln /srv/data/notes.txt /root/notes-hard.txt
ln -s /srv/data/report.sh /usr/local/bin/report
ls -l /usr/local/bin/backup                          # points at a path that doesn't exist
ln -sfn /opt/tools/bin/backup.sh /usr/local/bin/backup
chmod 755 /opt/tools/bin/backup.sh                   # it also wasn't executable
# 5
chown harry:devops /srv/data/secret.txt && chmod 640 /srv/data/secret.txt
mkdir /srv/shared/project && chgrp devops /srv/shared/project && chmod 2770 /srv/shared/project
# 6
ssh sally@localhost cat flag.txt > /root/flag.txt    # or ssh in interactively and copy it
# 7
man -k passwd         # passwd (5) - password file
echo 5 > /root/man-section.txt
info grep             # Invoking > Output Line Selection... /count to search, q to quit
echo --count > /root/info-answer.txt
rpm -qd tar > /root/tar-docs.txt        # -d = documentation files, -c = config files, -l = all files
# 8  (interactive)
#   su - student
#   su - harry            # password harry-pass
#   whoami > ~/whoami.txt
#   exit; exit
# 9  in vim: /8080 then cw9090 Esc ; /debug then dd ; G o owner=ops Esc ; :wq
sed -i -e 's/^port=8080$/port=9090/' -e '/^debug=true$/d' /srv/data/app.conf
echo 'owner=ops' >> /srv/data/app.conf
echo 'Authorized use only' > /root/motd.txt
# 10
mkdir -p /srv/projects/alpha/docs /srv/projects/beta
cp -p /srv/data/notes.txt /srv/projects/alpha/docs/      # -p keeps mode, ownership, timestamps (cp -a also)
mv /srv/data/misc/b.cfg /srv/projects/beta/
rm -rf /srv/cleanup/old-reports
touch /srv/projects/beta/README
```

**Why it matters on the exam:** hard links share an inode and cannot cross file systems; symlinks are
just paths, so a typo leaves them dangling (`ls -l` shows the target in red). The setgid bit (the `2` in
2770) makes new files inherit the directory's group: that's the standard "shared group directory" task.
