#!/bin/bash
# Helpers for the VM labs (sourced by setup.sh / check.sh)
VARS=/etc/labkit/vars.env

# Spare whole disks (not the one holding /). Override: LAB_DISKS="/dev/vdb /dev/vdc /dev/vdd"
lab_disks() {
  if [ -n "${LAB_DISKS:-}" ]; then echo $LAB_DISKS; return; fi
  local rootdisks
  rootdisks=$(lsblk -nspo NAME,TYPE "$(findmnt -nvo SOURCE /)" | awk '$2=="disk"{print $1}' | sed 's/^[^/]*//')
  lsblk -dnpo NAME,TYPE,RO | awk '$2=="disk" && $3==0 {print $1}' | grep -vxF "$rootdisks" | grep -Ev '/(sr|zram|loop)' | head -3 | xargs
}
# The NIC without the default route (the lab NIC)
lab_iface() {
  local def; def=$(ip -o route show default | awk '{print $5; exit}')
  ip -o link show | awk -F': ' '{print $2}' | sed 's/@.*//' | grep -vx -e lo -e "$def" | grep -Ev '^(virbr|docker|veth|podman)' | head -1
}
# Partition N of a disk (handles /dev/vdb1 and /dev/nvme0n1p1 naming)
part() {
  local p; for p in $(lsblk -lnpo NAME "$1" | tail -n +2); do
    [ "$(cat /sys/class/block/$(basename "$p")/partition 2>/dev/null)" = "$2" ] && echo "$p" && return 0
  done; return 1
}
# Return a disk to blank: unmount, swapoff, remove LVM, wipe signatures
wipe_disk() {
  local d=$1 dev vg
  for dev in $(lsblk -lnpo NAME "$d" | tac); do
    swapoff "$dev" 2>/dev/null || true
    umount -f "$dev" 2>/dev/null || true
  done
  for dev in $(lsblk -lnpo NAME "$d"); do
    for vg in $(pvs --noheadings -o vg_name "$dev" 2>/dev/null); do
      for m in $(lsblk -lnpo NAME,MOUNTPOINT | awk -v v="$vg" '$1 ~ "/"v"-" && $2!="" {print $2}'); do umount -f "$m" || true; done
      vgremove -ff -y "$vg" >/dev/null 2>&1 || true
    done
    pvremove -ff -y "$dev" >/dev/null 2>&1 || true
  done
  wipefs -a -f $(lsblk -lnpo NAME "$d" | tac) >/dev/null 2>&1 || true
  partprobe "$d" 2>/dev/null || true; udevadm settle 2>/dev/null || true
}
# Save lab variables so tasks/checks can refer to {{DISK1}}, {{IFACE}}, ...
save_vars() { mkdir -p /etc/labkit; : > $VARS; local kv; for kv in "$@"; do echo "$kv" >> $VARS; done; }
load_vars() { [ -f $VARS ] && . $VARS; }
need_disks() {
  set -- $(lab_disks)
  [ $# -ge 3 ] || { echo "This lab needs 3 spare disks; found: $*" >&2; echo "Set LAB_DISKS=\"/dev/x /dev/y /dev/z\" if detection is wrong." >&2; exit 1; }
  DISK1=$1 DISK2=$2 DISK3=$3
}
