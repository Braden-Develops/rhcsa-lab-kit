# Lab 16: Break-fix: thermal, power and the BMC

**Ticket:** *"servera's chassis LED is amber. The BMC's Redfish service on this box (port 8000) isn't answering
either. Get the BMC back, tell us what it says is wrong, and write a check so burn-in catches this next time."*

The BMC here is **bmc-sim**, a small Redfish service that stands in for a real baseboard management controller
(`/opt/bmc-sim`, unit `bmc-sim.service`, config `/etc/bmc-sim/bmc-sim.conf`). Credentials: **admin / labpass**.
Answers go in **`/root/answers.txt`**.

1. **Bring the BMC service back.** It must run (as the `bmcsim` user, as designed), start at boot, and answer
   `curl -u admin:labpass http://127.0.0.1:8000/redfish/v1/`. There may be more than one problem; don't make the
   state file readable by everyone.
2. **Ask the BMC over Redfish** (curl and jq; start at `/redfish/v1` and follow the `@odata.id` links):
   - `fan=` the fan that has failed
   - `psu=` the power supply that lost its input
   - `redundancy=` `ok` or `lost`: is the power supply redundancy intact?
   - `hot_sensor=` the temperature sensor that is in **warning** (its `Name`)
   - read the System Event Log too, and work out the order in which things went wrong
3. **A second server, IPMI style.** A tech captured `ipmitool sensor` and `ipmitool sel elist` from node B:
   `/root/evidence/node-b-ipmitool.txt`. Fill in `nodeb_fan=` and `nodeb_psu=`.
4. **Write the check.** Create the executable **`/usr/local/bin/thermal-check`**:
   - reads `REDFISH_URL` (default `http://127.0.0.1:8000`), `REDFISH_USER` (default `admin`) and
     `REDFISH_PASSWORD` (default `labpass`)
   - looks at every fan, temperature sensor and power supply under `/redfish/v1/Chassis/1/Thermal` and `/Power`
   - prints one line per problem, naming the component (for example `FAN3 Critical 0 RPM`)
   - exit **0** if everything reports `Health` `OK`, **1** if anything is `Warning` or `Critical`, and **2** if the
     BMC can't be reached or refuses the credentials (no telemetry is never a pass)
