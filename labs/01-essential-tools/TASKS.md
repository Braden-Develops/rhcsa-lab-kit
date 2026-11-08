# Lab 01: Understand and use essential tools

Work as root (`./lab shell 01`). Grade any time with `labctl check`.

1. **grep / regex.** Write every line of `/srv/data/app.log` that *starts with* `2026-11` and contains the
   word `ERROR` into `/root/nov-errors.txt`, keeping the original order. Nothing else may be in the file.
2. **Redirection.** Search `/srv` and `/opt` for everything owned by user `harry`. In a single command, the list
   of paths must go to `/root/harry-files.txt` and any error messages to `/root/find-errors.txt`.
3. **Archives.**
   a. Create `/root/ssh-backup.tar.bz2`, a bzip2-compressed tar archive of `/etc/ssh`.
   b. Extract `/srv/data/payroll.tar.gz` into `/opt/restore` (so `/opt/restore/payroll/q1.csv` exists).
   c. Create `/root/notes.txt.gz` from a copy of `/srv/data/notes.txt` with gzip (keep the original in `/srv/data`).
4. **Links.**
   a. Create a **hard** link `/root/notes-hard.txt` to `/srv/data/notes.txt`.
   b. Create a **symbolic** link `/usr/local/bin/report` pointing to `/srv/data/report.sh`.
   c. *Broken:* the command `backup` (in `/usr/local/bin`) does not work. Make it work for every user
      without moving `/opt/tools/bin/backup.sh`. Running `backup` must print `backup ok`.
5. **Permissions.** *Broken:* `/srv/data/secret.txt` is world-writable and owned by `nobody`.
   Make it owned by `harry:devops`, readable and writable by harry, readable by the group, and no access for others.
   Then create `/srv/shared/project` owned by group `devops`, mode `2770`.
6. **SSH.** Log in over SSH to `localhost` as `sally` (password `sally-pass`), read `~/flag.txt`,
   and save its contents into `/root/flag.txt`. (Yes, root could cheat. Don't.)
7. **Documentation.**
   a. Without searching the web, find which man page section documents the *file format* of `/etc/passwd`
      (not the command). Write just the section number into `/root/man-section.txt`.
   b. Using grep's **info** documentation (not its man page), find grep's **long** option that prints only a
      count of matching lines. Write it (e.g. `--something`) into `/root/info-answer.txt`.
   c. Write the path of every documentation file the `tar` package installed into `/root/tar-docs.txt`,
      one path per line.
8. **Log in and switch users.** Starting from root, switch to user `student` with a full login environment.
   From that session, switch to user `harry` (password `harry-pass`), again with a full login environment.
   As harry, create `~/whoami.txt` containing the username the system reports for your current session.
   (Console logins on a text-mode tty of a multi-user target are drilled in VM lab 05.)
9. **Create and edit text files.** Using a text editor, edit `/srv/data/app.conf` so that: the port is `9090`,
   the `debug=true` line is gone, and a new last line reads `owner=ops`. Leave the other lines unchanged.
   Then create a new file `/root/motd.txt` whose only line is `Authorized use only`.
10. **Create, delete, copy and move.**
    a. Create the directories `/srv/projects/alpha/docs` and `/srv/projects/beta` in one command.
    b. Copy `/srv/data/notes.txt` into `/srv/projects/alpha/docs/`, **keeping** its original timestamp.
    c. Move `/srv/data/misc/b.cfg` into `/srv/projects/beta/`.
    d. Delete the directory `/srv/cleanup/old-reports` and everything in it (keep `/srv/cleanup/keep.txt`).
    e. Create an empty file `/srv/projects/beta/README`.
