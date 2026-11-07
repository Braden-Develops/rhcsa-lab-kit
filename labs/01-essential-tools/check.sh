#!/bin/bash
. /opt/labkit/lib/check.sh
D=/srv/data

section "Task 1: grep"
check "/root/nov-errors.txt has exactly the November ERROR lines" \
  'same <(grep -E "^2026-11" $D/app.log | grep -w ERROR) /root/nov-errors.txt'

section "Task 2: redirection"
check "harry-files.txt lists harry's files" \
  'same /var/lib/labkit/harry-files <(sort /root/harry-files.txt)'
check "find-errors.txt exists (stderr was redirected)" '[ -f /root/find-errors.txt ]'

section "Task 3: archives"
check "ssh-backup.tar.bz2 is bzip2 data" 'file /root/ssh-backup.tar.bz2 | grep -q bzip2'
check "ssh-backup.tar.bz2 contains etc/ssh/sshd_config" 'tar -tjf /root/ssh-backup.tar.bz2 | grep -q "etc/ssh/sshd_config$"'
check "payroll extracted to /opt/restore/payroll" '[ -f /opt/restore/payroll/q1.csv ] && [ -f /opt/restore/payroll/q2.csv ]'
check "notes.txt.gz is gzip data" 'file /root/notes.txt.gz | grep -q gzip && zcat /root/notes.txt.gz | grep -q rotate'
check "original notes.txt still in /srv/data" '[ -f $D/notes.txt ]'

section "Task 4: links"
check "notes-hard.txt is a hard link (same inode)" '[ "$(stat -c %i /root/notes-hard.txt)" = "$(stat -c %i $D/notes.txt)" ] && [ ! -L /root/notes-hard.txt ]'
check "report is a symlink to /srv/data/report.sh" '[ -L /usr/local/bin/report ] && [ "$(readlink -f /usr/local/bin/report)" = $D/report.sh ]'
check "backup prints \"backup ok\" for a normal user" 'su - student -c backup | grep -qx "backup ok"'
check "backup.sh was not moved" '[ -f /opt/tools/bin/backup.sh ]'

section "Task 5: permissions"
check "secret.txt owned by harry:devops" '[ "$(file_owner $D/secret.txt)" = harry:devops ]'
check "secret.txt mode is 640" '[ "$(file_mode $D/secret.txt)" = 640 ]'
check "/srv/shared/project is group devops, mode 2770" '[ "$(stat -c %G $D/../shared/project)" = devops ] && [ "$(file_mode /srv/shared/project)" = 2770 ]'

section "Task 6: ssh"
check "/root/flag.txt matches sally's flag" 'same /root/flag.txt /var/lib/labkit/.flag'
check "sally actually logged in over ssh" 'last sally 2>/dev/null | grep -q sally || journalctl -u sshd --no-pager | grep -q "Accepted password for sally"'

section "Task 7: documentation"
check "man section is 5" '[ "$(tr -d "[:space:]" < /root/man-section.txt)" = 5 ]'
check "info answer is --count" '[ "$(tr -d "[:space:]" < /root/info-answer.txt)" = --count ]'
check "tar-docs.txt lists tar's documentation files" 'same <(rpm -qd tar | sort) <(sort /root/tar-docs.txt)'

section "Task 8: switch users"
check "/home/harry/whoami.txt says harry, owned by harry" '[ "$(cat /home/harry/whoami.txt)" = harry ] && [ "$(stat -c %U /home/harry/whoami.txt)" = harry ]'
check "harry session was opened by student via su" 'journalctl -q --no-pager | grep "pam_unix(su" | grep -Eq "session opened for user harry.* by [a-z]*\(uid=$(id -u student)\)"'

section "Task 9: edit text files"
check "app.conf: port=9090" 'grep -qx "port=9090" /srv/data/app.conf && ! grep -q "port=8080" /srv/data/app.conf'
check "app.conf: debug line removed" '! grep -q "^debug" /srv/data/app.conf'
check "app.conf: last line owner=ops" '[ "$(tail -n1 /srv/data/app.conf)" = owner=ops ]'
check "app.conf: other lines untouched" 'grep -qx "name=inventory" /srv/data/app.conf && grep -qx "workers=4" /srv/data/app.conf && grep -qx "# application settings" /srv/data/app.conf'
check "motd.txt has exactly one line" '[ "$(cat /root/motd.txt)" = "Authorized use only" ]'

section "Task 10: create, delete, copy, move"
check "directories created" '[ -d /srv/projects/alpha/docs ] && [ -d /srv/projects/beta ]'
check "notes.txt copied with original timestamp" '[ "$(stat -c %Y /srv/projects/alpha/docs/notes.txt)" = "$(stat -c %Y /srv/data/notes.txt)" ] && [ ! "$(stat -c %i /srv/projects/alpha/docs/notes.txt)" = "$(stat -c %i /srv/data/notes.txt)" ]'
check "b.cfg moved (gone from misc)" '[ -f /srv/projects/beta/b.cfg ] && [ ! -e /srv/data/misc/b.cfg ]'
check "old-reports deleted, keep.txt kept" '[ ! -e /srv/cleanup/old-reports ] && [ -f /srv/cleanup/keep.txt ]'
check "README is an empty file" '[ -f /srv/projects/beta/README ] && [ ! -s /srv/projects/beta/README ]'
summary
