#!/bin/bash
. /opt/labkit/lib/check.sh
. /opt/labkit/lib/vm.sh; load_vars
fstab_uuid() { local u; u=$(blkid -s UUID -o value "$1") && grep -Ev '^\s*#' /etc/fstab | grep -Eq "^UUID=\"?$u\"?\s+$2\s+$3"; }
mib() { echo $(( $(lsblk -bndo SIZE "$1") / 1048576 )); }
section "Task 1: file systems"
i=1; for spec in "vfat /mnt/vfat" "ext4 /mnt/ext4" "xfs /mnt/xfs"; do
  set -- $spec
  check "partition $i is $1 mounted on $2" "p=\$(part $DISK1 $i) && [ \"\$(findmnt -no FSTYPE $2)\" = $1 ] && [ \"\$(findmnt -no SOURCE $2)\" = \"\$p\" ]"
  check "partition $i in fstab by UUID" "fstab_uuid \$(part $DISK1 $i) $2 $1"
  i=$((i+1))
done
section "Task 2: extend"
check "lvgrow is 800 MiB" '[ "$(lvs --noheadings --units m -o lv_size vgfs/lvgrow | xargs)" = 800.00m ]'
check "XFS on /srv/grow grew too" '[ "$(df -m --output=size /srv/grow | tail -1 | xargs)" -ge 700 ]'
check "lvext is 400 MiB" '[ "$(lvs --noheadings --units m -o lv_size vgfs/lvext | xargs)" = 400.00m ]'
check "ext4 on /srv/ext grew too" '[ "$(df -m --output=size /srv/ext | tail -1 | xargs)" -ge 350 ]'
check "data still there" '[ -f /srv/grow/fill ] && [ -f /srv/ext/fill ]'
section "Task 3: NFS"
check "/mnt/projects is an NFS mount of /exports/projects" 'findmnt -no FSTYPE,SOURCE /mnt/projects | grep -Eq "^nfs4?\s+nfs(.lab.example.com)?:/exports/projects"'
check "NFS mount is in fstab" 'grep -Ev "^\s*#" /etc/fstab | grep -Eq "^nfs(.lab.example.com)?:/exports/projects\s+/mnt/projects\s+nfs4?\s"'
section "Task 4: autofs"
check "autofs active and enabled" 'systemctl is-active autofs && systemctl is-enabled autofs'
check "/remote/homes/alice automounts" 'grep -q "alice" /remote/homes/alice/welcome.txt'
check "/remote/homes/bob automounts (wildcard map)" 'grep -q "bob" /remote/homes/bob/welcome.txt'
check "mounted read-write over NFS" 'ls /remote/homes/alice >/dev/null; findmnt -no FSTYPE,OPTIONS /remote/homes/alice | grep -Eq "^nfs4?\s+rw"'
section "Task 5: permissions"
check "/srv/team group is team" '[ "$(stat -c %G /srv/team)" = team ]'
check "alice can create files" 'su - alice -c "touch /srv/team/.check-alice" && rm -f /srv/team/.check-alice'
check "new files belong to group team (setgid)" 'su - bob -c "touch /srv/team/.check-bob" && [ "$(stat -c %G /srv/team/.check-bob)" = team ]; r=$?; rm -f /srv/team/.check-bob; exit $r'
check "carol has no access" '! su - carol -c "ls /srv/team" 2>/dev/null'
check "bob can edit plan.txt" 'su - bob -c "echo bob-was-here >> /srv/team/plan.txt"'
section "Task 6: unmount"
check "/mnt/old not mounted" '! findmnt /mnt/old'
check "/mnt/legacy not mounted" '! findmnt /mnt/legacy'
check "neither is in fstab" '! grep -Ev "^\s*#" /etc/fstab | grep -Eq "\s/mnt/(old|legacy)\s"'
check "vgfs/lvold deleted" '! lvs vgfs/lvold'
summary
