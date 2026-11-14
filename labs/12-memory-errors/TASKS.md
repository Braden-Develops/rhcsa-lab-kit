# Lab 12: Break-fix: memory errors

**Ticket:** *"Host flagged by fleet monitoring: memory errors on the console. Find the bad DIMM, decide whether
it goes back to the vendor, and make sure we never miss errors on this box again."*

Write your findings in **`/root/answers.txt`** as `key=value` lines (the file has the keys ready).
Vendor documentation for this server is in **`/root/evidence/`**.

1. **Get error recording working again.** The RAS daemon that logs memory and CPU errors has been switched off.
   Make it run now and at every boot.
2. **Diagnose.** Using the kernel log and the RAS daemon's records:
   - `dimm=` the **silkscreen label** a technician would look for on the board (for example `CPU0_DIMM_A1`)
   - `count=` the **total** number of correctable errors recorded against that DIMM
   - `action=` `replace` or `monitor`, according to the vendor's RMA criteria
3. **Write a stress wrapper that reads telemetry.** Create the executable **`/usr/local/bin/ce-delta`**:
   - usage: `ce-delta COMMAND [ARG...]`: it runs the command and reports how many **correctable errors** the memory
     controllers logged while it ran
   - it reads every `mc*/ce_count` under `$EDAC_ROOT` (default `/sys/devices/system/edac/mc`) before and after
   - prints exactly one line **`CE_DELTA=<n>`** on stdout
   - exit **0** if the command succeeded and the delta is 0; exit **1** if the command failed or the delta is above 0
   - exit **2** with a message on stderr, *without* running the command, if there are no memory controllers to read
4. **Run it.** Use your wrapper to run a 30-second memory stress with verification, for example
   `ce-delta stress-ng --vm 2 --vm-bytes 50% --verify -t 30s`, and save everything it prints (stdout and stderr)
   to **`/root/stress.log`**. Put the exit code you got in `vm_exit=`, and think about why it is the right answer.

`sudo labctl check` grades you. The DIMM changes every time you reset the lab.
