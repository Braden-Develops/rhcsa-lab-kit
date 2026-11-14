# Lab 13: Break-fix: a failing disk

**Ticket:** *"Storage alerts on servera: the data mirror at /srv/data is degraded. Replace whatever failed using the
spare disk, keep the data, and while you're at it, triage the SMART reports a tech dropped in /root/evidence/smart."*

Spare disk: **{{DISK3}}**. Answers go in **`/root/answers.txt`** (`key=value`).

1. **Find the failed drive.** The array is made of a whole disk and a device-mapper device (as you'd see behind a
   multipath or enclosure layer). Work out which **physical disk** of this VM sits behind the failed member, and
   put it in `failed_disk=` (for example `/dev/vdx`). Read the kernel log too: what exactly did the kernel see?
2. **Replace it.**
   - remove the failed member from the array and **pull the drive** (remove its device-mapper mapping)
   - add {{DISK3}} as the new mirror half and let it rebuild completely
   - make the array's definition persistent in **`/etc/mdadm.conf`**
   - the data in `/srv/data` must survive (check it against `/srv/data/MANIFEST.sha256`)
3. **SMART triage.** Read the four reports in `/root/evidence/smart/`. Ignore the `PASSED` verdicts and read the
   attributes.
   - `cable=` serial number of the drive whose errors point at the **cable or backplane**, not the drive
   - `replace=` serial numbers of **all** drives that should be RMA'd (comma separated)
4. **Prove the new mirror with fio.** Write a job file **`/root/verify.fio`** that writes at least **256 MiB** of data
   into `/srv/data` with **direct I/O**, then reads it back and **verifies it with a checksum**. Run it and save the
   output to **`/root/fio-verify.log`**.
5. Reboot and run `sudo labctl check` again: the array must come back healthy and mounted.
