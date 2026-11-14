#!/usr/bin/env python3
"""Insert simulated events into rasdaemon's SQLite database.

    rasdb.py TABLE '[{"col": value, ...}, ...]'

Only columns that exist in the table are written, so this works across rasdaemon versions. If rasdaemon has
never created the database (no EDAC driver in a VM, for example), the tables are created with rasdaemon's
standard columns.
"""
import json
import os
import sqlite3
import sys

DB = os.environ.get("RAS_DB", "/var/lib/rasdaemon/ras-mc_event.db")
SCHEMA = {
    "mc_event": "id INTEGER PRIMARY KEY, timestamp TEXT, err_count INTEGER, err_type TEXT, err_msg TEXT, label TEXT, "
                "mc INTEGER, top_layer INTEGER, middle_layer INTEGER, lower_layer INTEGER, address INTEGER, "
                "grain INTEGER, syndrome INTEGER, driver_detail TEXT",
    "mce_record": "id INTEGER PRIMARY KEY, timestamp TEXT, mcgcap INTEGER, mcgstatus INTEGER, status INTEGER, "
                  "addr INTEGER, misc INTEGER, ip INTEGER, tsc INTEGER, walltime INTEGER, cpu INTEGER, cpuid INTEGER, "
                  "apicid INTEGER, socketid INTEGER, cs INTEGER, bank INTEGER, cpuvendor INTEGER, bank_name TEXT, "
                  "error_msg TEXT, mcgstatus_msg TEXT, mcistatus_msg TEXT, mcastatus_msg TEXT, user_action TEXT, "
                  "mc_location TEXT",
    "aer_event": "id INTEGER PRIMARY KEY, timestamp TEXT, dev_name TEXT, err_type TEXT, err_msg TEXT",
}


def main():
    table, rows = sys.argv[1], json.loads(sys.argv[2])
    os.makedirs(os.path.dirname(DB), exist_ok=True)
    con = sqlite3.connect(DB)
    con.execute(f"CREATE TABLE IF NOT EXISTS {table} ({SCHEMA[table]})")
    cols = {r[1] for r in con.execute(f"PRAGMA table_info({table})")}
    for row in rows:
        row = {k: v for k, v in row.items() if k in cols}
        con.execute(f"INSERT INTO {table} ({','.join(row)}) VALUES ({','.join('?' * len(row))})", list(row.values()))
    con.commit()


if __name__ == "__main__":
    main()
