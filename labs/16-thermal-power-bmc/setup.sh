#!/bin/bash
# Lab 16: a server's BMC (simulated by bmc-sim, a small Redfish service) reports a dead fan, a lost PSU and a hot
# zone, but first the BMC service itself has to be brought back up.
set -e
. /opt/labkit/lib/hw.sh
truth_reset
SIM=$LABDIR/bmc-sim.py
mkdir -p /opt/bmc-sim /etc/bmc-sim /var/lib/bmc-sim /root/evidence
install -m 755 "$SIM" /opt/bmc-sim/bmc-sim.py
id bmcsim &>/dev/null || useradd -r -s /sbin/nologin -d /var/lib/bmc-sim bmcsim

# --- this server's state, and its answers ---
python3 /opt/bmc-sim/bmc-sim.py --generate faulty --out /tmp/state.json
python3 - <<'P' > /tmp/truth.env
import json
s = json.load(open("/tmp/state.json")); t = s.pop("truth")
json.dump(s, open("/var/lib/bmc-sim/state.json", "w"), indent=1)
for k, v in t.items(): print(f"{k}='{v}'")
P
. /tmp/truth.env
truth fan "$fan"; truth psu "$psu"; truth redundancy "$redundancy"; truth hot_sensor "$hot" "${hot// /}"
# BROKEN 2: the state file is readable by root only, but the service runs as bmcsim
chown root:root /var/lib/bmc-sim/state.json; chmod 600 /var/lib/bmc-sim/state.json

# --- a second server, captured with ipmitool by a tech ---
python3 /opt/bmc-sim/bmc-sim.py --generate faulty --out /tmp/b.json --ipmi-out /root/evidence/node-b-ipmitool.txt
python3 -c "import json; t=json.load(open('/tmp/b.json'))['truth']; print(f\"bfan='{t['fan']}' bpsu='{t['psu']}'\")" > /tmp/b.env
. /tmp/b.env; truth nodeb_fan "$bfan"; truth nodeb_psu "$bpsu"
rm -f /tmp/state.json /tmp/truth.env /tmp/b.json /tmp/b.env

# BROKEN 1: a typo in the port
cat > /etc/bmc-sim/bmc-sim.conf <<'C'
# bmc-sim: simulated BMC (Redfish over HTTP)
bind = 127.0.0.1
port = 80000
state = /var/lib/bmc-sim/state.json
user = admin
password = labpass
C
chmod 640 /etc/bmc-sim/bmc-sim.conf; chgrp bmcsim /etc/bmc-sim/bmc-sim.conf
cat > /etc/systemd/system/bmc-sim.service <<'U'
[Unit]
Description=Simulated BMC (Redfish service) for lab 16
After=network.target
[Service]
User=bmcsim
ExecStart=/usr/bin/python3 /opt/bmc-sim/bmc-sim.py --config /etc/bmc-sim/bmc-sim.conf
Restart=on-failure
RestartSec=2
StartLimitBurst=3
[Install]
WantedBy=multi-user.target
U
systemctl daemon-reload
systemctl enable bmc-sim.service
systemctl start bmc-sim.service || true
answers_template fan psu redundancy hot_sensor nodeb_fan nodeb_psu
echo "Lab 16 ready."
