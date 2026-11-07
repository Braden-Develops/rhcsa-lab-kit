# Lab 10 solution

```bash
# 1
groupadd -g 4000 sysops
groupadd dbadmin
# 2
useradd -G sysops natasha
useradd -G sysops harry
useradd -s /sbin/nologin sarah
useradd -u 3500 -c "John Smith" -G dbadmin john
for u in natasha harry sarah john; do echo "$u:Rhcsa@2026" | chpasswd; done
#   (or: echo 'Rhcsa@2026' | passwd --stdin natasha)
# 3   do 3c BEFORE creating users on the exam: login.defs only affects new accounts
chage -M 90 -W 7 natasha
chage -d 0 harry                      # or: passwd -e harry
sed -i 's/^PASS_MAX_DAYS.*/PASS_MAX_DAYS\t60/' /etc/login.defs
# 4
echo '%sysops ALL=(ALL) NOPASSWD: ALL' > /etc/sudoers.d/sysops
echo 'sarah ALL=(root) /usr/bin/systemctl restart httpd' > /etc/sudoers.d/sarah
chmod 440 /etc/sudoers.d/sysops /etc/sudoers.d/sarah
visudo -c
# 5   shell typo, locked password, expired account
usermod -s /bin/bash dave
usermod -U dave                       # or passwd -u dave
chage -E -1 dave
# 6
userdel -r tempuser
# 7
mkdir -p /home/dbadmin
usermod -d /home/dbadmin/john -m john
chage -E 2027-12-31 john
```

**Notes.** `-G` *replaces* supplementary groups; `usermod -aG` *appends*, and forgetting `-a` is a classic mistake.
`id user`, `chage -l user`, `passwd -S user`, `getent passwd|shadow|group` are your checking tools.
Always edit sudoers with `visudo` (or `visudo -f /etc/sudoers.d/x`) because a syntax error can lock you out of sudo.
A leading `!` in the shadow hash means locked.
