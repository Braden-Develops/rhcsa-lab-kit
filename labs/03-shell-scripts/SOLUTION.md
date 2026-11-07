# Lab 03 solution

```bash
cat > /root/scripts/userinfo.sh <<'S'
#!/bin/bash
if [ $# -lt 1 ]; then
  echo "Usage: userinfo.sh USERNAME" >&2
  exit 2
fi
if entry=$(getent passwd "$1"); then
  uid=$(echo "$entry" | cut -d: -f3)
  shell=$(echo "$entry" | cut -d: -f7)
  echo "USER $1 UID $uid SHELL $shell"
else
  echo "$1: no such user"
  exit 1
fi
S

cat > /root/scripts/mkusers.sh <<'S'
#!/bin/bash
while read -r name; do
  [[ -z "$name" || "$name" == \#* ]] && continue
  if id "$name" &>/dev/null; then
    echo "exists $name"
  else
    useradd "$name" && echo "created $name"
  fi
done < "$1"
S

cat > /root/scripts/bigfiles.sh <<'S'
#!/bin/bash
dir=$1 size=$2
if [ ! -d "$dir" ]; then
  echo "bigfiles.sh: $dir is not a directory" >&2
  exit 1
fi
count=0
for f in $(find "$dir" -type f -size +"${size}"k | sort); do
  echo "$f"
  count=$((count + 1))
done
echo "TOTAL $count"
S
chmod +x /root/scripts/*.sh
/root/scripts/mkusers.sh /root/scripts/newusers.txt

# Task 4: missing ';' before then, unquoted vars, 'for' without 'do', missing 'fi',
# /home/user instead of /home/$user, not executable
cat > /usr/local/bin/backup-homes.sh <<'S'
#!/bin/bash
DEST=$1
shift
if [ -z "$DEST" ]; then
  echo "usage: $0 DEST user..." >&2
  exit 1
fi
mkdir -p "$DEST"
for user in "$@"; do
  if id "$user" >/dev/null 2>&1; then
    tar -czf "$DEST/$user.tar.gz" "/home/$user"
    echo "backed up $user"
  else
    echo "skipping unknown user $user"
  fi
done
S
chmod 755 /usr/local/bin/backup-homes.sh
/usr/local/bin/backup-homes.sh /backup alice bob ghost
```

Tips: `bash -n script` checks syntax without running; `bash -x script` traces each line. `$#` is the argument
count, `"$@"` keeps each argument intact, `$?` is the last exit status, `$(cmd)` captures output.
`find -size +1000k` means "more than 1000 KiB" (find rounds up, so be careful with `-size` and small units).
