#!/bin/bash
. /opt/labkit/lib/check.sh
. /opt/labkit/lib/vm.sh; load_vars
. /opt/labkit/lib/hw.sh
MD=$(readlink -f /dev/md/data 2>/dev/null)
det() { mdadm --detail /dev/md/data 2>/dev/null; }
member() { det | grep -Eq "active sync +$(readlink -f "$1")$"; }

section "Task 1: find the failed drive"
check "failed_disk = the physical disk behind the failed RAID member" 'answer_is failed_disk'

section "Task 2: replace it"
check "array has 2 active, in-sync members" 'det | grep -Eq "Active Devices : 2" && det | grep -Eq "Working Devices : 2"'
check "array is not degraded or rebuilding" 'det | grep -E "^ *State :" | grep -vqE "degraded|recovering|resync"'
check "DISK1 and DISK3 are the members" 'member $DISK1 && member $DISK3'
check "the failed member is no longer listed" '! det | grep -q "jbod-bay2\|faulty\|$(readlink -f /dev/mapper/jbod-bay2 2>/dev/null || echo NONE)"'
check "the failed drive has been pulled (its mapping is removed)" '! dmsetup info jbod-bay2'
check "data is intact" 'cd /srv/data && sha256sum --quiet -c MANIFEST.sha256'
check "/etc/mdadm.conf describes the array by UUID" 'u=$(mdadm --detail --export /dev/md/data | sed -n "s/^MD_UUID=//p"); grep -Eq "^ARRAY .*UUID=$u" /etc/mdadm.conf'
check "/srv/data mounted from the array" '[ "$(readlink -f "$(findmnt -no SOURCE /srv/data)")" = "$MD" ]'

section "Task 3: SMART triage"
check "cable = the drive whose problem is the link, not the media" 'answer_is cable'
check "replace = every drive that needs an RMA" 'answer_is replace'

section "Task 4: verify the new mirror with fio"
check "/root/verify.fio uses direct I/O" 'grep -Eq "^\s*direct\s*=\s*1" /root/verify.fio'
check "/root/verify.fio writes then verifies with a checksum" 'grep -Eq "^\s*verify\s*=\s*(crc32c|crc32c-intel|md5|sha256|xxhash)" /root/verify.fio && grep -Eq "^\s*rw\s*=\s*(rand)?write" /root/verify.fio'
check "/root/verify.fio works on /srv/data, at least 256 MiB" 'grep -Eq "^\s*(directory|filename)\s*=\s*/srv/data" /root/verify.fio && grep -Eiq "^\s*size\s*=\s*([0-9]{4,}m|[0-9]+g|25[6-9]m|2[6-9][0-9]m)" /root/verify.fio'
check "/root/fio-verify.log shows a clean run" 'grep -q "err= 0" /root/fio-verify.log && ! grep -Eqi "verify.*(bad|fail)|err= *[1-9]" /root/fio-verify.log'

section "Overall"
check "rebooted since setup, array still healthy" '[ "$(stat -c %Y /var/lib/labkit/setup-done)" -lt "$(date -d "$(uptime -s)" +%s)" ] && det | grep -Eq "Active Devices : 2"'
summary
