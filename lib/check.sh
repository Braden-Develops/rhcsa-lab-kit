#!/bin/bash
# Grading helpers, sourced by each lab's check.sh
#   section "Task 1: ..."
#   check "description" 'shell expression that succeeds when done right'
#   summary     (prints score, exits 0 only if everything passed)
_T=0; _P=0
if [ -t 1 ]; then G=$'\e[32m'; R=$'\e[31m'; B=$'\e[1m'; N=$'\e[0m'; else G=; R=; B=; N=; fi
section() { printf '\n%s%s%s\n' "$B" "$*" "$N"; }
check() {
  local desc=$1 expr=$2
  _T=$((_T+1))
  if (eval "$expr") >/dev/null 2>&1; then
    _P=$((_P+1)); printf '  %sPASS%s %s\n' "$G" "$N" "$desc"
  else
    printf '  %sFAIL%s %s\n' "$R" "$N" "$desc"
  fi
}
summary() {
  printf '\n%sScore: %d/%d%s\n' "$B" "$_P" "$_T" "$N"
  [ "$_P" -eq "$_T" ] && echo "All checks passed. VM labs: reboot and run the check again, because exam work must survive a reboot."
  [ "$_P" -eq "$_T" ]
}
# helpers
file_mode() { stat -c %a "$1"; }
file_owner() { stat -c %U:%G "$1"; }
user_in_group() { id -nG "$1" 2>/dev/null | tr ' ' '\n' | grep -qx "$2"; }
# Check a local user's password without logging in (works for SHA-512 and yescrypt hashes)
password_is() {
  local user=$1 pw=$2 hash
  hash=$(getent shadow "$user" | cut -d: -f2)
  [ -n "$hash" ] || return 1
  python3 - "$hash" "$pw" <<'PY'
import sys, ctypes, ctypes.util
h, pw = sys.argv[1], sys.argv[2]
lib = ctypes.CDLL(ctypes.util.find_library("crypt") or "libcrypt.so.2")
lib.crypt.restype = ctypes.c_char_p
out = lib.crypt(pw.encode(), h.encode())
sys.exit(0 if out and out.decode() == h else 1)
PY
}
# same FILE1 FILE2 : byte-identical contents (works with <(process substitution))
same() { python3 -c 'import sys; sys.exit(open(sys.argv[1],"rb").read() != open(sys.argv[2],"rb").read())' "$1" "$2"; }
