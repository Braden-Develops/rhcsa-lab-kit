# Lab 14: Break-fix: the slow node

**Ticket:** *"servera fails burn-in: `labbench` scores about a tenth of its peers (same SKU, same rack build).
Hardware or config? Make it perform like its peers and tell us what the hardware logged."*

The benchmark runs as **`labbench.service`** (`systemctl start labbench`; results are appended to
`/var/log/labbench.log`), or just run **`labbench`**. Peer results are in `/root/evidence/peer-bench.txt`.
There is more than one cause. Find them all; none of the
fixes involves replacing anything.

1. **CPUs.** The VM has more CPUs than are online. Bring them all online **now**, and make sure they come up at
   **every boot**.
2. **The benchmark's own limits.** Something in the benchmark's unit configuration caps its CPU time. Remove it.
3. **A CPU hog.** Find the process eating a CPU, find what starts it and what restarts it when it dies, and get rid
   of it for good (it must not come back after a reboot).
4. **Tuning.** Put the machine on the tuned profile that tuned **recommends** for it.
5. **Prove it.** Run `labbench` again after your fixes. It should report every CPU.
6. **What did the hardware log?** From the kernel log and the RAS daemon, fill in `/root/answers.txt`:
   - `mce_cpu=` and `mce_bank=`: the CPU and MCA bank of the machine-check event
   - `mce_type=` `corrected` or `uncorrected`, decoded from the bank's status value yourself
   - `throttled_cpu=` the CPU that hit its thermal limit
7. Reboot, run `labbench` once more, then `sudo labctl check`.
