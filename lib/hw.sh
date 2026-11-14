#!/bin/bash
# Helpers for the hardware break-fix labs (12-18), sourced by their setup.sh / check.sh.
#
# A VM or container has no real DIMMs, fans or PCIe links to break, so these labs fake the *evidence*
# the way it would reach you on real hardware, and use real kernel mechanisms wherever a VM allows:
#   kmsg         write a line into the kernel ring buffer (it shows up in dmesg and journalctl -k)
#   ras_insert   add records to rasdaemon's SQLite database (ras-mc-ctl reads them back)
#   device-mapper (linear + error targets, dm-delay) and md RAID for real I/O errors and slow disks
TRUTH=/var/lib/labkit/truth
ANSWERS=/root/answers.txt

# kmsg LEVEL TEXT...   LEVEL is a syslog level: 2 crit, 3 err, 4 warning, 6 info
kmsg() { local lvl=$1; shift; printf "<%s>%s\n" "$lvl" "$*" > "${KMSG:-/dev/kmsg}"; }

# Answers are compared in a normal form: lower case, no blanks, comma lists sorted.
_norm() { printf '%s' "$1" | tr -d ' \t\r' | tr 'A-Z' 'a-z' | tr ',' '\n' | grep -v '^$' | sort -u | paste -sd, -; }
_h() { printf '%s' "$1" | sha256sum | cut -c1-20; }
# truth KEY VALUE [VALUE...]   record the accepted answer(s), hashed, so a quick `cat` doesn't give them away
truth() { local k=$1 v; shift; mkdir -p "${TRUTH%/*}"; for v in "$@"; do echo "$k=$(_h "$(_norm "$v")")" >> $TRUTH; done; }
truth_reset() { mkdir -p "${TRUTH%/*}"; : > $TRUTH; }
# answer_is KEY        true if /root/answers.txt has KEY=<an accepted value>
answer_is() {
  local v; v=$(grep -E "^[[:space:]]*$1[[:space:]]*=" $ANSWERS 2>/dev/null | tail -1 | cut -d= -f2-)
  [ -n "$v" ] && grep -qx "$1=$(_h "$(_norm "$v")")" $TRUTH
}
# answers_template KEY...   create /root/answers.txt with empty keys for the student to fill in
answers_template() { { echo "# Fill in your findings as key=value (one per line). Graded by: labctl check"; for k in "$@"; do echo "$k="; done; } > $ANSWERS; }

# need_pkgs PKG...   install whatever is missing (VM snapshots made before these labs existed lack them)
need_pkgs() {
  local miss=() p
  for p in "$@"; do rpm -q "$p" >/dev/null 2>&1 || miss+=("$p"); done
  [ ${#miss[@]} -eq 0 ] && return 0
  echo "Installing: ${miss[*]}"
  dnf -y -q --setopt=strict=0 install "${miss[@]}" || true
  # EPEL carries a few of them (stress-ng, stressapptest) on some releases
  for p in "${miss[@]}"; do rpm -q "$p" >/dev/null 2>&1 || echo "note: package $p is not available; the lab works without it"; done
}

# ras_insert TABLE JSON-ROWS   add rows to rasdaemon's database (creates it if rasdaemon never ran)
ras_insert() { python3 /opt/labkit/lib/rasdb.py "$@"; }

# pick ITEM...   print one of the arguments at random
pick() { local a=("$@"); echo "${a[RANDOM % ${#a[@]}]}"; }
# ago SECONDS [FORMAT]   a timestamp SECONDS in the past
ago() { date -d "@$(( $(date +%s) - $1 ))" "+${2:-%Y-%m-%d %H:%M:%S %z}"; }
