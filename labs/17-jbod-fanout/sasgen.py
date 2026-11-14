#!/usr/bin/env python3
"""Write two snapshots (before and after a stress run) of SAS PHY counters for a 2-expander JBOD, laid out like
/sys/class/sas_phy, with one bad uplink cable, one drive link with errors and one drive link at half speed.

    sasgen.py OUTDIR CABLE_EXP DRIVE_ERR_SLOT SLOW_LINK_SLOT
"""
import os
import random
import sys

out, cable, errslot, slowslot = sys.argv[1], int(sys.argv[2]), int(sys.argv[3]), int(sys.argv[4])
r = random.Random()
base = {}
for e in (0, 1):
    for p in range(8):
        # some PHYs carry large *historical* counts that do not move: old events, not a current problem
        hist = r.choice([0, 0, 0, 0, r.randint(5, 40), r.randint(200, 900)])
        base[e, p] = {k: (hist if k != "phy_reset_problem_count" else 0) for k in
                      ("invalid_dword_count", "running_disparity_error_count", "loss_of_dword_sync_count",
                       "phy_reset_problem_count")}
for snap in ("before", "after"):
    for e in (0, 1):
        for p in range(8):
            c = dict(base[e, p])
            slot = e * 4 + (p - 4) if p >= 4 else None
            if snap == "after":
                if e == cable and p < 4:          # every lane of the uplink cable degrades together
                    c["invalid_dword_count"] += r.randint(3000, 9000)
                    c["running_disparity_error_count"] += r.randint(3000, 9000)
                    c["loss_of_dword_sync_count"] += r.randint(5, 30)
                if slot == errslot:
                    c["invalid_dword_count"] += r.randint(400, 1500)
                    c["running_disparity_error_count"] += r.randint(400, 1500)
                    c["phy_reset_problem_count"] += r.randint(1, 4)
            d = os.path.join(out, f"sas-{snap}", f"expander-{e}", f"phy-{e + 1}:0:{p}")
            os.makedirs(d, exist_ok=True)
            rate = "6.0 Gbit" if slot == slowslot else "12.0 Gbit"
            files = dict(c, negotiated_linkrate=rate, maximum_linkrate="12.0 Gbit",
                         sas_address=f"0x5000c500{e:02x}{p:02x}a0{r.randint(16, 255):02x}",
                         target_port_protocols="none" if p < 4 else "ssp")
            for k, v in files.items():
                with open(os.path.join(d, k), "w") as f:
                    f.write(f"{v}\n")
with open(os.path.join(out, "TOPOLOGY.txt"), "w") as f:
    f.write("""JBOD jb-04 (2 expanders, 8 drive slots), as seen from the server's HBA

  HBA port A ==[4-lane SAS cable]== expander-0 phys 0-3 (wide port uplink)
  HBA port B ==[4-lane SAS cable]== expander-1 phys 0-3 (wide port uplink)
  expander-0 phys 4,5,6,7 -> slots 0,1,2,3
  expander-1 phys 4,5,6,7 -> slots 4,5,6,7

sas-before/ was captured just before a 30-minute fan-out fio run across all slots, sas-after/ just after.
Each PHY directory holds the same files as /sys/class/sas_phy/<phy>/ on a real system.
""")
