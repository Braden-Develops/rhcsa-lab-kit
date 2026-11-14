# Lab 17: Break-fix: a JBOD under fan-out load

**Ticket:** *"New JBOD on servera, 8 slots (`/dev/mapper/encl0-slot0` to `encl0-slot7`). Run it the way
burn-in should: every drive at once, then compare the drives with each other. Also look at the SAS PHY counters
from jb-04 and tell us what to replace."*

Answers go in **`/root/answers.txt`**. **Read-only tests only**: the slots hold data.

1. **Fan-out fio.** Write **`/root/fanout.fio`** with **one job per slot, named `slot0` to `slot7`**, all running
   **at the same time**: random **reads**, direct I/O, 4 KiB blocks, **time based** (about 30 seconds). Run it with
   JSON output saved to **`/root/fanout.json`**.
2. **Compare to peers.** Write the executable **`/usr/local/bin/peer-outliers`**:
   - usage `peer-outliers FIO.json [PERCENT]` (default 70)
   - flags every job whose read bandwidth is below PERCENT % of the **median** of all jobs, and every job that
     reported an error: one line per flagged job, starting with the **job name** and containing `OUTLIER`
   - exit **0** if nothing is flagged, **1** if something is, **2** if the file can't be read or has no jobs
3. **Diagnose the slots.**
   - `slow_slot=` the slot that is much slower than its peers (number, for example `5`)
   - `bad_slot=` the slot that returns I/O errors
4. **SAS PHY counters.** `/root/evidence/jbod/` holds `TOPOLOGY.txt` and two snapshots of the PHY counters,
   before and after a stress run. Use the **change** during the run, not the totals.
   - `cable_expander=` the expander (0 or 1) whose **uplink cable** to the HBA should be replaced
   - `phy_err_slot=` the slot whose own drive link took errors during the run
   - `slow_link_slot=` the slot whose drive negotiated a lower SAS link rate than the rest
