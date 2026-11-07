#!/bin/bash
set -e
mkdir -p /root/scripts /srv/lab03/data /backup
for u in alice bob; do useradd -m $u 2>/dev/null || true; echo "$u's files" > /home/$u/notes.txt; done
# sample data for task 3
for i in 1 2 3 4 5; do head -c $((i * 300 * 1024)) /dev/zero > /srv/lab03/data/file$i.bin; done
mkdir -p /srv/lab03/data/sub && head -c $((2 * 1024 * 1024)) /dev/zero > /srv/lab03/data/sub/big.bin
# input list for task 2
cat > /root/scripts/newusers.txt <<'L'
# accounts for the new team
mia
alice

noah
L
# BROKEN script for task 4
cat > /usr/local/bin/backup-homes.sh <<'S'
#!/bin/bash
# Archive each user's home directory into $DEST/<user>.tar.gz
# Usage: backup-homes.sh DEST user [user...]
DEST=$1
shift
if [ -z $DEST ] then
  echo "usage: $0 DEST user..." >&2
  exit 1
fi
mkdir -p $DEST
for user in $*
  if id $user >/dev/null 2>&1; then
    tar -czf $DEST/$user.tar.gz /home/user
    echo "backed up $user"
  else
    echo "skipping unknown user $user"
done
S
chmod 644 /usr/local/bin/backup-homes.sh
