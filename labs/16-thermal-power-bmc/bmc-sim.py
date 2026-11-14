#!/usr/bin/env python3
"""bmc-sim: a tiny Redfish service that plays the part of a server's BMC for lab 16.

    bmc-sim.py --config /etc/bmc-sim/bmc-sim.conf          serve (config: port, bind, state, user, password)
    bmc-sim.py --generate faulty|healthy --out state.json  write a random server state (plus ipmitool-style text)

It implements just enough of the DMTF Redfish schema (ServiceRoot, Systems, Chassis with Thermal and Power,
Managers with the SEL log service) for curl + jq practice. HTTP basic auth, no TLS (real BMCs use HTTPS).
"""
import argparse
import base64
import json
import random
import sys
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

FANS = [f"FAN{i}" for i in range(1, 7)]
TEMPS = [("Inlet Temp", 24, 40, 45), ("Exhaust Temp", 38, 70, 75), ("CPU0 Temp", 61, 90, 98),
         ("CPU1 Temp", 63, 90, 98), ("DIMM Zone 0 Temp", 41, 80, 85), ("DIMM Zone 1 Temp", 43, 80, 85),
         ("PCH Temp", 52, 85, 90)]


def ts(ago):
    return time.strftime("%Y-%m-%dT%H:%M:%S+00:00", time.gmtime(time.time() - ago))


def generate(kind):
    r = random.Random()
    bad_fan = r.choice(FANS) if kind == "faulty" else None
    bad_psu = r.choice(["PSU1", "PSU2"]) if kind == "faulty" else None
    hot = r.choice(["CPU0 Temp", "CPU1 Temp", "DIMM Zone 0 Temp", "DIMM Zone 1 Temp"]) if kind == "faulty" else None
    fans = []
    for f in FANS:
        dead = f == bad_fan
        fans.append({"Name": f, "MemberId": f, "Reading": 0 if dead else r.randrange(9800, 12400, 120),
                     "ReadingUnits": "RPM", "LowerThresholdCritical": 600, "LowerThresholdNonCritical": 800,
                     "Status": {"State": "Enabled", "Health": "Critical" if dead else "OK"}})
    temps = []
    for name, base, warn, crit in TEMPS:
        val = warn + r.randint(1, crit - warn - 1) if name == hot else base + r.randint(-3, 4) + (6 if bad_fan else 0)
        temps.append({"Name": name, "MemberId": name.replace(" ", ""), "ReadingCelsius": val,
                      "UpperThresholdNonCritical": warn, "UpperThresholdCritical": crit,
                      "Status": {"State": "Enabled", "Health": "Warning" if val >= warn else "OK"}})
    psus = []
    for p in ("PSU1", "PSU2"):
        lost = p == bad_psu
        psus.append({"Name": p, "MemberId": p, "Model": "PWS-1K62A-1R", "PowerCapacityWatts": 1600,
                     "LineInputVoltage": 0 if lost else r.choice([207, 208, 209, 230, 231]),
                     "PowerInputWatts": 0 if lost else r.randint(410, 520),
                     "Status": {"State": "UnavailableOffline" if lost else "Enabled",
                                "Health": "Critical" if lost else "OK"}})
    sel, n = [], 0

    def ev(ago, sev, stype, sensor, msg, assert_=True):
        nonlocal n
        n += 1
        sel.append({"Id": str(n), "Created": ts(ago), "Severity": sev, "SensorType": stype, "SensorName": sensor,
                    "Message": msg, "EntryType": "SEL", "EventDirection": "Asserted" if assert_ else "Deasserted"})
    ev(864000, "OK", "System Event", "System Event", "Log area reset/cleared")
    ev(860000, "OK", "Power Unit", "Power Unit", "Power off/down", False)
    if bad_psu:
        ev(r.randint(20000, 90000), "Critical", "Power Supply", f"{bad_psu} Status", "Power Supply AC lost")
        ev(r.randint(5000, 19000), "Critical", "Power Supply", "PSU Redundancy", "Redundancy Lost")
    if bad_fan:
        ev(r.randint(3000, 4900), "Critical", "Fan", bad_fan, "Lower Critical going low")
    if hot:
        ev(r.randint(600, 2900), "Warning", "Temperature", hot, "Upper Non-critical going high")
    sel.sort(key=lambda e: e["Created"])
    for i, e in enumerate(sel, 1):
        e["Id"] = str(i)
    redundancy = "Critical" if bad_psu else "OK"
    return {"serial": f"S{r.randint(10**8, 10**9 - 1)}", "fans": fans, "temps": temps, "psus": psus, "sel": sel,
            "redundancy": redundancy, "truth": {"fan": bad_fan, "psu": bad_psu, "hot": hot,
                                                "redundancy": "lost" if bad_psu else "ok"}}


def ipmi_text(st):
    """The same state as `ipmitool sensor` and `ipmitool sel elist` would print it."""
    out = ["# ipmitool sensor"]
    row = lambda *c: "{:<17}| {:<11}| {:<11}| {:<6}| {:<10}| {:<10}| {:<10}| {:<10}| {:<10}| {:<10}".format(*c)
    for t in st["temps"]:
        s = "nc" if t["Status"]["Health"] == "Warning" else "ok"
        out.append(row(t["Name"], f"{t['ReadingCelsius']:.3f}", "degrees C", s, "na", "na", "na",
                       f"{t['UpperThresholdNonCritical']:.3f}", f"{t['UpperThresholdCritical']:.3f}", "na"))
    for f in st["fans"]:
        s = "cr" if f["Status"]["Health"] == "Critical" else "ok"
        out.append(row(f["Name"], f"{f['Reading']:.3f}", "RPM", s, "na", "600.000", "800.000", "na", "na", "na"))
    for p in st["psus"]:
        out.append(row(f"{p['Name']} Status", "0x1" if p["Status"]["Health"] == "OK" else "0xb", "discrete",
                       "0x0b00" if p["Status"]["Health"] != "OK" else "0x0100", "na", "na", "na", "na", "na", "na"))
    out += ["", "# ipmitool sel elist"]
    for e in st["sel"]:
        t = time.strptime(e["Created"][:19], "%Y-%m-%dT%H:%M:%S")
        out.append(f"{int(e['Id']):>4} | {time.strftime('%m/%d/%Y | %H:%M:%S', t)} | {e['SensorType']} {e['SensorName']} | "
                   f"{e['Message']} | {e['EventDirection']}")
    return "\n".join(out) + "\n"


def resources(st):
    odata = lambda p, t, **kw: {"@odata.id": p, "@odata.type": t, **kw}
    link = lambda p: {"@odata.id": p}
    health = "Critical" if any(x["Status"]["Health"] == "Critical" for x in st["fans"] + st["psus"]) else (
        "Warning" if any(t["Status"]["Health"] != "OK" for t in st["temps"]) else "OK")
    R = "/redfish/v1"
    return {
        R: odata(R, "#ServiceRoot.v1_15_0.ServiceRoot", Id="RootService", Name="Root Service", RedfishVersion="1.17.0",
                 Systems=link(R + "/Systems"), Chassis=link(R + "/Chassis"), Managers=link(R + "/Managers")),
        R + "/Systems": odata(R + "/Systems", "#ComputerSystemCollection.ComputerSystemCollection",
                              Name="Systems", Members=[link(R + "/Systems/1")], **{"Members@odata.count": 1}),
        R + "/Systems/1": odata(R + "/Systems/1", "#ComputerSystem.v1_20_0.ComputerSystem", Id="1", Name="System",
                                Manufacturer="Example Server Co", Model="ESC-2U-2S", SerialNumber=st["serial"],
                                PowerState="On", BiosVersion="2.4.1",
                                Status={"State": "Enabled", "Health": health, "HealthRollup": health}),
        R + "/Chassis": odata(R + "/Chassis", "#ChassisCollection.ChassisCollection", Name="Chassis",
                              Members=[link(R + "/Chassis/1")], **{"Members@odata.count": 1}),
        R + "/Chassis/1": odata(R + "/Chassis/1", "#Chassis.v1_23_0.Chassis", Id="1", Name="Chassis",
                                ChassisType="RackMount", SerialNumber=st["serial"],
                                Status={"State": "Enabled", "Health": health},
                                Thermal=link(R + "/Chassis/1/Thermal"), Power=link(R + "/Chassis/1/Power")),
        R + "/Chassis/1/Thermal": odata(R + "/Chassis/1/Thermal", "#Thermal.v1_7_1.Thermal", Id="Thermal",
                                        Name="Thermal", Temperatures=st["temps"], Fans=st["fans"]),
        R + "/Chassis/1/Power": odata(R + "/Chassis/1/Power", "#Power.v1_7_1.Power", Id="Power", Name="Power",
                                      PowerControl=[{"Name": "System Power Control", "PowerConsumedWatts":
                                                     sum(p["PowerInputWatts"] for p in st["psus"])}],
                                      PowerSupplies=st["psus"],
                                      Redundancy=[{"Name": "PSU Redundancy", "Mode": "N+1", "MinNumNeeded": 1,
                                                   "MaxNumSupported": 2, "RedundancySet": [link(R + "/Chassis/1/Power#/PowerSupplies/0"), link(R + "/Chassis/1/Power#/PowerSupplies/1")],
                                                   "Status": {"State": "Enabled", "Health": st["redundancy"]}}]),
        R + "/Managers": odata(R + "/Managers", "#ManagerCollection.ManagerCollection", Name="Managers",
                               Members=[link(R + "/Managers/1")], **{"Members@odata.count": 1}),
        R + "/Managers/1": odata(R + "/Managers/1", "#Manager.v1_19_0.Manager", Id="1", Name="BMC",
                                 ManagerType="BMC", FirmwareVersion="1.62.0",
                                 LogServices=link(R + "/Managers/1/LogServices")),
        R + "/Managers/1/LogServices": odata(R + "/Managers/1/LogServices", "#LogServiceCollection.LogServiceCollection",
                                             Members=[link(R + "/Managers/1/LogServices/SEL")]),
        R + "/Managers/1/LogServices/SEL": odata(R + "/Managers/1/LogServices/SEL", "#LogService.v1_5_0.LogService",
                                                 Id="SEL", Name="System Event Log", Entries=link(R + "/Managers/1/LogServices/SEL/Entries")),
        R + "/Managers/1/LogServices/SEL/Entries": odata(R + "/Managers/1/LogServices/SEL/Entries",
                                                         "#LogEntryCollection.LogEntryCollection", Name="SEL Entries",
                                                         Members=st["sel"], **{"Members@odata.count": len(st["sel"])}),
    }


def serve(conf):
    try:
        port = int(conf.get("port", "8000"))
        if not 0 < port < 65536:
            raise ValueError
    except ValueError:
        sys.exit(f"bmc-sim: invalid port '{conf.get('port')}' in config (must be 1-65535)")
    path = conf.get("state", "/var/lib/bmc-sim/state.json")
    try:
        with open(path) as f:
            st = json.load(f)
    except OSError as e:
        sys.exit(f"bmc-sim: cannot read state file: {e}")
    res = resources(st)
    auth = "Basic " + base64.b64encode(f"{conf.get('user', 'admin')}:{conf.get('password', '')}".encode()).decode()

    class H(BaseHTTPRequestHandler):
        def send(self, code, body):
            data = json.dumps(body, indent=2).encode()
            self.send_response(code)
            self.send_header("Content-Type", "application/json")
            self.send_header("OData-Version", "4.0")
            if code == 401:
                self.send_header("WWW-Authenticate", 'Basic realm="BMC"')
            self.send_header("Content-Length", str(len(data)))
            self.end_headers()
            self.wfile.write(data)

        def do_GET(self):
            p = self.path.split("?")[0].rstrip("/") or "/"
            if p in ("/redfish", "/redfish/v1") or p == "/":
                return self.send(200, {"v1": "/redfish/v1/"} if p != "/redfish/v1" else res["/redfish/v1"])
            if self.headers.get("Authorization") != auth:
                return self.send(401, {"error": {"code": "Base.1.0.InsufficientPrivilege", "message": "Authentication required"}})
            if p in res:
                return self.send(200, res[p])
            self.send(404, {"error": {"code": "Base.1.0.ResourceMissingAtURI", "message": f"{p} not found"}})

        def log_message(self, fmt, *a):
            sys.stderr.write("bmc-sim: " + (fmt % a) + "\n")

    srv = ThreadingHTTPServer((conf.get("bind", "127.0.0.1"), port), H)
    print(f"bmc-sim: Redfish service on http://{conf.get('bind', '127.0.0.1')}:{port}/redfish/v1", flush=True)
    srv.serve_forever()


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--config")
    ap.add_argument("--generate", choices=["faulty", "healthy"])
    ap.add_argument("--out")
    ap.add_argument("--ipmi-out")
    a = ap.parse_args()
    if a.generate:
        st = generate(a.generate)
        with open(a.out, "w") as f:
            json.dump(st, f, indent=1)
        if a.ipmi_out:
            with open(a.ipmi_out, "w") as f:
                f.write(ipmi_text(st))
        return
    conf = {}
    try:
        for line in open(a.config):
            line = line.split("#")[0].strip()
            if "=" in line:
                k, v = line.split("=", 1)
                conf[k.strip()] = v.strip()
    except (OSError, TypeError) as e:
        sys.exit(f"bmc-sim: cannot read config: {e}")
    serve(conf)


if __name__ == "__main__":
    main()
