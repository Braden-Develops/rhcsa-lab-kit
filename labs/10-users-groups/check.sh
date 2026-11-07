#!/bin/bash
. /opt/labkit/lib/check.sh
section "Task 1: groups"
check "sysops has GID 4000" '[ "$(getent group sysops | cut -d: -f3)" = 4000 ]'
check "dbadmin exists" 'getent group dbadmin'
section "Task 2: users"
check "natasha in sysops" 'user_in_group natasha sysops'
check "harry in sysops" 'user_in_group harry sysops'
check "sarah has nologin shell" 'getent passwd sarah | cut -d: -f7 | grep -Eq "/(s?bin)/(nologin|false)$"'
check "sarah not in sysops" '! user_in_group sarah sysops'
check "john UID 3500, comment John Smith" '[ "$(getent passwd john | cut -d: -f3,5)" = "3500:John Smith" ]'
check "john in dbadmin" 'user_in_group john dbadmin'
for u in natasha harry sarah john; do check "$u password is Rhcsa@2026" "password_is $u 'Rhcsa@2026'"; done
section "Task 3: aging"
check "natasha max 90 days" '[ "$(getent shadow natasha | cut -d: -f5)" = 90 ]'
check "natasha warn 7 days" '[ "$(getent shadow natasha | cut -d: -f6)" = 7 ]'
check "harry must change password at next login" '[ "$(getent shadow harry | cut -d: -f3)" = 0 ]'
check "login.defs PASS_MAX_DAYS 60" 'grep -Eq "^PASS_MAX_DAYS\s+60\s*$" /etc/login.defs'
section "Task 4: sudo"
check "sudoers files are valid" 'visudo -c'
check "sysops: NOPASSWD ALL" 'sudo -l -U natasha | grep -q "NOPASSWD: ALL"'
check "sarah: only systemctl restart httpd" 'sudo -l -U sarah | grep -q "/usr/bin/systemctl restart httpd" && ! sudo -l -U sarah | grep -Eq "\(ALL( : ALL)?\) (NOPASSWD: )?ALL$"'
section "Task 5: dave"
check "dave has a valid shell" 'sh=$(getent passwd dave | cut -d: -f7); grep -qx "$sh" /etc/shells'
check "dave is not locked" '! getent shadow dave | cut -d: -f2 | grep -q "^!"'
check "dave account not expired" 'exp=$(getent shadow dave | cut -d: -f8); [ -z "$exp" ] || [ "$exp" -gt $(( $(date +%s) / 86400 )) ]'
check "dave still has password OldPass123" "password_is dave OldPass123"
section "Task 6: tempuser"
check "tempuser removed" '! getent passwd tempuser'
check "/home/tempuser removed" '[ ! -e /home/tempuser ]'
section "Task 7: john"
check "john home is /home/dbadmin/john" '[ "$(getent passwd john | cut -d: -f6)" = /home/dbadmin/john ] && [ -d /home/dbadmin/john ]'
check "contents moved (.bashrc present, owned by john)" '[ "$(stat -c %U /home/dbadmin/john/.bashrc)" = john ]'
check "john expires 2027-12-31" '[ "$(chage -l john | grep "Account expires" | cut -d: -f2 | xargs)" = "Dec 31, 2027" ]'
summary
