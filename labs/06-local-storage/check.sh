#!/bin/bash
. /opt/labkit/lib/check.sh
. /opt/labkit/lib/vm.sh; load_vars
P11=$(part $DISK1 1); P12=$(part $DISK1 2)
mib() { echo $(( $(lsblk -bndo SIZE "$1") / 1048576 )); }
fstab_has() { grep -Ev '^\s*#' /etc/fstab | grep -Eq "$1"; }
section "Task 1: partitions"
check "DISK1 has a GPT label" '[ "$(lsblk -ndo PTTYPE $DISK1)" = gpt ]'
check "partition 1 is ~512 MiB" 's=$(mib $P11); [ $s -ge 500 ] && [ $s -le 530 ]'
check "partition 1 is active swap" 'swapon --show=NAME --noheadings | grep -qx "$(readlink -f $P11)"'
check "partition 1 swap in fstab by UUID" 'fstab_has "^UUID=\"?$(blkid -s UUID -o value $P11)\"?\s+(none|swap)\s+swap"'
check "partition 2 is ~2 GiB" 's=$(mib $P12); [ $s -ge 2000 ] && [ $s -le 2100 ]'
section "Task 2: PVs and VG"
check "DISK1 part 2 is a PV in vgdata" '[ "$(pvs --noheadings -o vg_name $P12 | xargs)" = vgdata ]'
check "DISK2 is a PV in vgdata" '[ "$(pvs --noheadings -o vg_name $DISK2 | xargs)" = vgdata ]'
check "vgdata extent size is 8 MiB" '[ "$(vgs --noheadings --units m -o vg_extent_size vgdata | xargs)" = 8.00m ]'
section "Task 3: LVs"
check "lvweb is 600 MiB" '[ "$(lvs --noheadings --units m -o lv_size vgdata/lvweb | xargs)" = 600.00m ]'
check "lvweb is XFS mounted on /srv/web" '[ "$(findmnt -no FSTYPE /srv/web)" = xfs ] && [ "$(readlink -f $(findmnt -no SOURCE /srv/web))" = "$(readlink -f /dev/vgdata/lvweb)" ]'
check "lvweb in fstab by UUID" 'fstab_has "^UUID=\"?$(blkid -s UUID -o value /dev/vgdata/lvweb)\"?\s+/srv/web\s+xfs"'
check "lvdocs is 50 extents" '[ "$(lvdisplay -c vgdata/lvdocs | cut -d: -f8)" = 50 ]'
check "lvdocs is ext4 labelled DOCS" '[ "$(blkid -s TYPE -o value /dev/vgdata/lvdocs)" = ext4 ] && [ "$(blkid -s LABEL -o value /dev/vgdata/lvdocs)" = DOCS ]'
check "/srv/docs mounted, in fstab by LABEL" 'findmnt /srv/docs && fstab_has "^LABEL=\"?DOCS\"?\s+/srv/docs\s+ext4"'
check "lvswap is 256 MiB and active" '[ "$(lvs --noheadings --units m -o lv_size vgdata/lvswap | xargs)" = 256.00m ] && swapon --show=NAME --noheadings | grep -qx "$(readlink -f /dev/vgdata/lvswap)"'
check "lvswap in fstab" 'fstab_has "^(/dev/vgdata/lvswap|/dev/mapper/vgdata-lvswap|UUID=\"?$(blkid -s UUID -o value /dev/vgdata/lvswap)\"?)\s+(none|swap)\s+swap"'
section "Task 4: archive"
check "/srv/archive mounted from vgold/lvarchive" '[ "$(readlink -f $(findmnt -no SOURCE /srv/archive))" = "$(readlink -f /dev/vgold/lvarchive)" ]'
check "archive data intact" 'grep -q Archived /srv/archive/README'
section "Task 5: vgtemp removed"
check "vgtemp gone" '! vgs vgtemp'
check "DISK3 partition 2 deleted" '! part $DISK3 2'
check "vgold still healthy" 'vgs vgold && lvs vgold/lvarchive'
section "Task 6: grow vgold"
check "DISK1 partition 3 is ~500 MiB" 'p=$(part $DISK1 3) && s=$(mib $p) && [ $s -ge 490 ] && [ $s -le 520 ]'
check "DISK1 partition 3 is a PV in vgold" '[ "$(pvs --noheadings -o vg_name $(part $DISK1 3) | xargs)" = vgold ]'
check "partitions 1 and 2 still in use" 'swapon --show=NAME --noheadings | grep -qx "$(readlink -f $P11)" && [ "$(pvs --noheadings -o vg_name $P12 | xargs)" = vgdata ]'
section "Overall"
check "findmnt --verify reports no errors" 'findmnt --verify 2>&1 | grep -Eq "^Success| 0 errors"'
check "rebooted since setup (persistence proven)" '[ "$(stat -c %Y /var/lib/labkit/setup-done)" -lt "$(date -d "$(uptime -s)" +%s)" ]'
summary
