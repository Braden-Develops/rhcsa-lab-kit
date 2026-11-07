#!/bin/bash
. /opt/labkit/lib/check.sh
S=/root/scripts
t=$(mktemp -d); trap 'rm -rf $t; userdel -r tmpcheck1 2>/dev/null; userdel -r tmpcheck2 2>/dev/null' EXIT

section "Task 1: userinfo.sh"
check "is executable with a bash shebang" '[ -x $S/userinfo.sh ] && head -1 $S/userinfo.sh | grep -q "^#!/bin/bash"'
check "no args -> usage on stderr, exit 2" '$S/userinfo.sh >$t/o 2>$t/e; [ $? -eq 2 ] && [ ! -s $t/o ] && grep -q "^Usage: userinfo.sh USERNAME" $t/e'
check "existing user -> USER/UID/SHELL line" '[ "$($S/userinfo.sh student)" = "USER student UID $(id -u student) SHELL $(getent passwd student | cut -d: -f7)" ]'
check "missing user -> message and exit 1" 'out=$($S/userinfo.sh nobody_here); [ $? -eq 1 ] && [ "$out" = "nobody_here: no such user" ]'

section "Task 2: mkusers.sh"
check "users from newusers.txt exist" 'id mia && id noah'
check "is executable" '[ -x $S/mkusers.sh ]'
check "fresh run: correct created/exists output" 'printf "#c\ntmpcheck1\n\nstudent\ntmpcheck2\n" > $t/in; [ "$($S/mkusers.sh $t/in)" = "$(printf "created tmpcheck1\nexists student\ncreated tmpcheck2")" ] && id tmpcheck1 && id tmpcheck2'

section "Task 3: bigfiles.sh"
check "is executable" '[ -x $S/bigfiles.sh ]'
check "lists files > 1000 KB sorted + TOTAL" '[ "$($S/bigfiles.sh /srv/lab03/data 1000)" = "$(printf "/srv/lab03/data/file4.bin\n/srv/lab03/data/file5.bin\n/srv/lab03/data/sub/big.bin\nTOTAL 3")" ]'
check "bad directory -> exit 1, message on stderr" '$S/bigfiles.sh /nonexistent 10 >$t/o 2>$t/e; [ $? -eq 1 ] && [ -s $t/e ]'

section "Task 4: backup-homes.sh"
check "script is executable and has valid syntax" '[ -x /usr/local/bin/backup-homes.sh ] && bash -n /usr/local/bin/backup-homes.sh'
check "backs up alice and bob, skips ghost" 'rm -rf $t/b; out=$(/usr/local/bin/backup-homes.sh $t/b alice bob ghost 2>&1); echo "$out" | grep -q "skipping unknown user ghost" && [ -f $t/b/alice.tar.gz ] && [ -f $t/b/bob.tar.gz ]'
check "alice.tar.gz really contains /home/alice" 'tar -tzf $t/b/alice.tar.gz | grep -q "home/alice/notes.txt"'
check "/backup/alice.tar.gz exists (you ran it)" '[ -f /backup/alice.tar.gz ]'
summary
