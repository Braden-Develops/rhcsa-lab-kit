#!/bin/bash
set -e
# BROKEN account: bad shell, expired, locked
useradd -m -s /bin/bsah dave
echo 'dave:OldPass123' | chpasswd
usermod -L dave
chage -E 2020-01-01 dave
# Leftover account to delete
useradd -m -c "Temporary contractor" tempuser
echo "contract notes" > /home/tempuser/notes.txt
# sudo package policy
sed -i 's/^PASS_MAX_DAYS.*/PASS_MAX_DAYS\t99999/' /etc/login.defs
