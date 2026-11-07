# Lab 10: Manage users and groups

1. Create group `sysops` with **GID 4000**, and group `dbadmin`.
2. Create users (password for each: `Rhcsa@2026`):
   - `natasha`: supplementary group `sysops`
   - `harry`: supplementary group `sysops`
   - `sarah`: **no interactive shell**, not a member of `sysops`
   - `john`: **UID 3500**, comment `John Smith`, supplementary group `dbadmin`
3. **Password aging.**
   a. `natasha` must change her password at least every **90** days and is warned **7** days before.
   b. `harry` must change his password at the next login.
   c. New accounts created from now on must get a maximum password age of **60** days by default.
4. **Privileged access.**
   a. Members of `sysops` can run any command with sudo **without a password** (use a file in `/etc/sudoers.d`).
   b. `sarah` may run only `/usr/bin/systemctl restart httpd` via sudo.
5. *Broken:* `dave` can't log in. There are three separate problems with his account. Fix them all
   (keep his existing password).
6. Remove the account `tempuser` **and** its home directory.
7. Move `john`'s home directory to `/home/dbadmin/john` (contents must move with it) and set his
   account to expire on **2027-12-31**.
