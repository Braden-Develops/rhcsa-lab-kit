# Lab 03: Create simple shell scripts

All scripts must start with `#!/bin/bash` and be executable. The grader runs them with its own inputs.

1. **Conditionals + inputs.** Write `/root/scripts/userinfo.sh`:
   - no argument: print `Usage: userinfo.sh USERNAME` to **stderr** and exit with status **2**
   - user exists: print exactly `USER <name> UID <uid> SHELL <shell>` and exit 0
   - user doesn't exist: print `<name>: no such user` and exit **1**
2. **Loops over a file.** Write `/root/scripts/mkusers.sh FILE`. For each line of FILE (skip blank lines and lines
   starting with `#`): if the user exists print `exists <name>`, otherwise create the user and print `created <name>`.
   Run it once on `/root/scripts/newusers.txt`.
3. **Processing command output.** Write `/root/scripts/bigfiles.sh DIR SIZE_KB` that prints the path of every
   regular file under DIR (recursively) larger than SIZE_KB kilobytes, one per line, sorted alphabetically,
   followed by a last line `TOTAL <count>`. Exit 1 with a message to stderr if DIR is not a directory.
4. *Broken:* `/usr/local/bin/backup-homes.sh` has several bugs (syntax, quoting, a wrong path, and it isn't
   executable). Fix it so that `backup-homes.sh /backup alice bob ghost` creates `/backup/alice.tar.gz` and
   `/backup/bob.tar.gz` containing **that user's** home, and prints `skipping unknown user ghost`.
