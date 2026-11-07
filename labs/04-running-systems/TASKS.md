# Lab 04: Operate running systems

> Rebooting, boot targets and interrupting the boot are in the VM lab **05-boot**.

1. **Find and kill.**
   a. Something is eating a whole CPU. Find the process using the most CPU, write its PID into
      `/root/hog.pid`, then kill it.
   b. Something else is sitting on a lot of memory. Find the process with the largest resident memory (RSS),
      write its PID into `/root/memhog.pid`, then kill it.
2. **Scheduling priority.**
   a. Change the niceness of the running `batchjob` process to **10**.
   b. Start `/usr/local/bin/indexer` in the background with a niceness of **15** (leave it running).
3. **Tuning profiles.** Enable and start `tuned`, then make `throughput-performance` the active profile.
   Write the profile tuned *recommends* for this machine into `/root/tuned-recommended.txt`.
   (tuned may warn about settings it can't apply inside a container. That's expected.)
4. **Logs.** The program tagged `payroll-sync` logged an **error-priority** message containing an error code like
   `PSYNC-12345`. Find it in the journal and write just the code into `/root/journal-code.txt`.
5. **Preserve the journal.** Configure journald so logs survive reboots, and apply it without rebooting.
6. **Services.**
   a. *Broken:* `httpd` won't start. Fix it, start it, and make it start at boot.
      `curl http://localhost/` must return the lab page.
   b. Check the status of `crond`, then **stop** it (leave it enabled). Write the main PID it had while running
      (from `systemctl status`) into `/root/crond.pid` before you stop it.
7. **Secure file transfer.** Using `scp`/`sftp` as user `sally` (password `sally-pass`) on host `localhost`:
   a. copy `/root/transfer/report.txt` into sally's home directory,
   b. download `/home/sally/outbox/data.csv` to `/root/data.csv`.
