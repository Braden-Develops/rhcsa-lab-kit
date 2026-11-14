# Lecture H6: Thermal, power and the BMC: IPMI, the SEL and Redfish

A server has a second, smaller computer on its motherboard that watches everything the OS can't: fans,
temperatures, voltages, power supplies, chassis intrusion, and its own log of hardware events. It's the
**BMC**, and it's the most important source of evidence for thermal and power problems, and often for faults
in other subsystems too. This lecture covers how servers are cooled and powered, what the BMC measures, how to
read it with IPMI and with Redfish, and how to check cooling and power under load.

Practice: [Lab 16](#/lab/16).

---

## Cooling and power, briefly

**Cooling.** Fans pull air from the front (cold aisle) through the chassis and out the back (hot aisle). Heat
sinks on the CPUs, air baffles (plastic shrouds that direct air over the CPUs and DIMMs) and blank panels in empty
drive bays and slots keep the air going where it should. The BMC runs a **fan curve**: fan speed rises with the
hottest sensor relative to its target. Remove a baffle or leave a bay open and air takes the easy path, and some
component runs hot while the fans still look fine.

**Power.** Servers usually have two power supplies (**PSUs**), each able to carry the full load: **N+1
redundancy**. Each PSU should be fed from a **different** power distribution unit (PDU), so a failed PDU or
breaker doesn't take the server down. On the board, **voltage regulators (VRMs)** step 12 V down to the low
voltages CPUs and memory need, and are a classic source of marginal behaviour under heavy load.

Things that go wrong:

| Fault | What you see |
|---|---|
| Fan failed | fan reading 0 RPM or below its lower critical threshold; neighbouring fans speed up; temperatures rise under load |
| Heatsink badly seated, paste dried | one CPU much hotter than its twin under load; throttle events (lecture H4) |
| Missing baffle or blank | some zone (often DIMMs or the PCIe area) hot while fans are normal |
| PSU lost input | PSU status *AC lost* / *input lost*; redundancy lost; the other PSU carries everything |
| PSU failed | PSU *failure detected*; same consequences |
| Both PSUs on one PDU | nothing at all, until that PDU fails. A cabling audit (check which PDU outlet feeds each PSU) is the only way to find it |
| Marginal VRM | errors or resets only at full power; voltage sensors dipping under load |

---

## The BMC

The **baseboard management controller** (vendor names: iDRAC, iLO, XClarity, and many OEM BMCs built on
OpenBMC) is a small SoC with its own firmware, its own network port (or a shared one), and sensors wired across
the board. It runs whenever the server has standby power, even when the OS is off or hung. It provides:

- **Sensors:** temperatures, fan speeds, voltages, currents, power draw, PSU status, discrete states (chassis
  intrusion, presence).
- **Thresholds** on each sensor and an **event log**: the **SEL** (System Event Log).
- **Remote control:** power on/off/cycle, remote console (KVM), virtual media.
- **Inventory** (FRU data: part and serial numbers), and often firmware updates.

Two protocols talk to it: **IPMI** (old, binary, ubiquitous) and **Redfish** (modern REST/JSON over HTTPS).

---

## IPMI with ipmitool

From the server itself (in-band), through the kernel's IPMI driver:

```bash
modprobe ipmi_devintf ipmi_si         # usually loaded automatically
ipmitool mc info                      # BMC firmware version
ipmitool sensor                       # every sensor, value, status and thresholds
ipmitool sdr type Fan                 # just fans
ipmitool sdr type Temperature
ipmitool sel elist                    # the System Event Log, decoded
ipmitool fru                          # board, product, PSU part and serial numbers
ipmitool chassis status               # power state, last power event, faults
```

From another machine (out-of-band), over the network: add `-I lanplus -H BMC_ADDRESS -U USER -P PASSWORD`
(prefer `-E` to take the password from `IPMI_PASSWORD` rather than the command line).

### Reading `ipmitool sensor`

```text
CPU0 Temp        | 67.000     | degrees C  | ok    | na  | na      | na      | 90.000 | 98.000 | na
FAN3             | 0.000      | RPM        | cr    | na  | 600.000 | 800.000 | na     | na     | na
PSU2 Status      | 0xb        | discrete   | 0x0b00| na  | na      | na      | na     | na     | na
```

Columns: name, value, unit, **status**, then thresholds **lower non-recoverable, lower critical, lower
non-critical, upper non-critical, upper critical, upper non-recoverable**. Status is `ok`, `nc` (non-critical,
i.e. warning), `cr` (critical), `nr` (non-recoverable), or `na` (not available, e.g. no reading).

**Discrete** sensors (PSU status, presence, intrusion) report a bit field, not a reading. For a power supply
the IPMI specification defines offsets such as: presence detected, failure detected, predictive failure,
**input lost (AC/DC)**, input out of range. `ipmitool sdr` or `ipmitool sel elist` decodes them into words.

A reading of `na` on a sensor that should exist is itself a finding: a sensor the BMC can't read is a
monitoring gap, and for a check it's **missing telemetry**, not a pass.

### Reading the SEL

```text
   3 | 11/13/2026 | 15:16:19 | Power Supply PSU1 Status | Power Supply AC lost | Asserted
   4 | 11/14/2026 | 13:50:32 | Power Supply PSU Redundancy | Redundancy Lost | Asserted
   5 | 11/14/2026 | 14:48:48 | Fan FAN3 | Lower Critical going low | Asserted
   6 | 11/14/2026 | 15:18:50 | Temperature DIMM Zone 0 Temp | Upper Non-critical going high | Asserted
```

Each entry is a sensor crossing a threshold (`Asserted`) or returning (`Deasserted`), or a discrete event. Read it
as a **timeline**: here a PSU lost AC first, later a fan died, and with less airflow a DIMM zone crossed its warning
threshold. Fix causes, not symptoms: the DIMM zone is a consequence of the fan.

The SEL also records events Linux may never see: memory training failures, uncorrectable errors that reset the
machine before the OS could log them, CPU IERR/thermal trips, PCIe errors handled firmware-first, BIOS POST errors.
**Read the SEL first** when a server rebooted unexpectedly. It's small (often a few hundred to a few thousand
entries) and can fill up; a full SEL stops logging, so clear it (`ipmitool sel clear`) only after saving it, and
only as part of a defined process (for example at the start of a factory test, so every entry afterwards belongs
to this test).

---

## Redfish

**Redfish** (DMTF standard) exposes the same information as JSON over HTTPS, as a tree of resources, each linking
to others with `@odata.id`:

```text
/redfish/v1                                   service root
  /Systems/1                                  the computer: model, serial, power state, BIOS, health rollup
  /Chassis/1                                  the box: health, links to its thermal and power data
    /Thermal                                  Temperatures[], Fans[]       (newer: /ThermalSubsystem)
    /Power                                    PowerSupplies[], Redundancy[], PowerControl[] (newer: /PowerSubsystem)
  /Managers/1                                 the BMC itself: firmware version
    /LogServices/SEL/Entries                  the event log (path names vary by vendor)
  /UpdateService, /AccountService, /SessionService ...
```

```bash
B=https://bmc.example.net
curl -sk -u admin:PASSWORD $B/redfish/v1/ | jq .
curl -sk -u admin:PASSWORD $B/redfish/v1/Chassis/1/Thermal |
  jq -r '.Fans[] | "\(.Name) \(.Reading) \(.ReadingUnits) \(.Status.Health)"'
curl -sk -u admin:PASSWORD $B/redfish/v1/Chassis/1/Power | jq '.PowerSupplies[] | {Name, LineInputVoltage, Status}'
```

Every resource carries `Status`: `State` (Enabled, Absent, UnavailableOffline...) and `Health` (OK, Warning,
Critical); collections roll up into `HealthRollup`. Sensors carry their thresholds (`UpperThresholdNonCritical`,
`UpperThresholdCritical`, `LowerThresholdCritical`).

Practical notes:

- BMCs use self-signed certificates (`-k`, or better, install the BMC's CA) and HTTPS only.
- Basic auth works for scripts; for many requests, create a session (`POST /redfish/v1/SessionService/Sessions`)
  and send `X-Auth-Token`.
- Paths and extras vary between vendors (`Chassis/1` vs. `Chassis/System.Embedded.1`, OEM sections). Always start
  at the service root and **follow links** rather than hard-coding paths.
- The deprecated `Thermal` and `Power` resources are still common; newer BMCs add `ThermalSubsystem` and
  `PowerSubsystem` with per-sensor `Sensors` resources. A robust tool handles both.

---

## OS-side sensors

Linux has its own view through **hwmon** drivers (`coretemp` and `k10temp` for CPUs, some board sensor chips):

```bash
sensors                                       # lm_sensors
grep . /sys/class/hwmon/hwmon*/name
grep . /sys/class/hwmon/hwmon*/temp*_input    # millidegrees C
```

CPU temperatures from hwmon are fast and per core; the BMC covers everything else. Neither is complete alone.

---

## Thermal and power checks

**Conformance:** the right PSUs (model, wattage), both present; fans present; BMC firmware at the expected version;
the SEL free of errors at the start of the test.

**During stress** (this is where the faults are):

1. Load everything at once: CPUs (`stress-ng` / `mprime`), memory, all drives (fio), NICs (iperf3). This is the
   maximum heat and power the server will see.
2. Sample sensors every few seconds: CPU and DIMM temperatures, inlet and exhaust, fan speeds, power draw, PSU
   status, voltages.
3. Fail on: any sensor reaching a warning or critical threshold, a fan below its threshold, a PSU not OK or
   redundancy lost, any thermal throttling, any new SEL entry of Warning or Critical severity.
4. **Compare peers:** with identical servers under identical load, the same sensor should read within a few
   degrees. A CPU 15 °C hotter than its twins, or a fan running at maximum where its peers run at 60%, is a
   finding even below every threshold.
5. **Missing data is a failure:** BMC unreachable, a sensor reading `na`, or a sensor that should exist and
   doesn't.

**Power redundancy test** (lab and factory, where allowed): pull one PSU's cord under full load and confirm the
server stays up, the other PSU carries the load, and the SEL logs input lost and redundancy lost; plug it back
and confirm redundancy is regained. Repeat for the other PSU.

---

## Quick reference

| Task | Command |
|---|---|
| All sensors | `ipmitool sensor`, `ipmitool sdr elist` |
| Events | `ipmitool sel elist` |
| Inventory | `ipmitool fru`, Redfish `/Systems/1`, `/Chassis/1` |
| Remote | `ipmitool -I lanplus -H BMC -U USER -E sensor` |
| Redfish fans/temps | `curl -sku USER:PASS https://BMC/redfish/v1/Chassis/1/Thermal \| jq` |
| Redfish PSUs | `.../Chassis/1/Power` |
| OS sensors | `sensors`, `/sys/class/hwmon/` |

Reading: Barroso, Hölzle and Ranganathan, *The Datacenter as a Computer* (cooling and power chapters, free);
El-Sayed et al., *Temperature Management in Data Centers* (SIGMETRICS 2012); the DMTF Redfish specification and
the DMTF "Redfish School" videos; the IPMI 2.0 specification (sensor types and event offsets).

---

## Review questions

1. What can the BMC tell you that Linux can't?
2. In `ipmitool sensor`, a fan shows status `cr` and value 0. A temperature shows `nc`. What do those mean?
3. The SEL shows PSU input lost, then redundancy lost, then a fan failure, then a DIMM zone over its warning
   threshold. What do you fix, in what order?
4. Why follow `@odata.id` links in Redfish instead of hard-coding `/Chassis/1/Thermal`?
5. A thermal check can't reach the BMC. What should it report?
6. Why must thermal checks compare identical servers under identical load?
7. Both PSUs report OK. What power-related fault could still be present?

<details><summary>Answers</summary>

1. Fans, most temperatures, voltages, PSU state, power draw and events from before the OS ran or after it crashed
   (the SEL), even with the OS off.
2. `cr`: the sensor crossed its critical threshold (a dead fan). `nc`: non-critical, i.e. the warning threshold.
3. Restore the PSU's input (check the PDU and cord before blaming the PSU) and replace the fan; the DIMM zone
   temperature should then return to normal. Confirm under load.
4. Resource paths differ between vendors and BMC versions; following links from the service root works on all of
   them.
5. An error ("cannot check"), never a pass.
6. Thresholds are set loosely to avoid false alarms, so a cooling problem can stay under them; a reading far from
   its peers' readings is the sensitive signal.
7. Both PSUs fed from the same PDU or circuit, so redundancy exists on paper only; only a cabling audit finds it.

</details>
