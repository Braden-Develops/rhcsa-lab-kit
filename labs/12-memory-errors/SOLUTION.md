# Lab 12 solution

## 1. rasdaemon

```bash
systemctl status rasdaemon            # "masked": its unit is a symlink to /dev/null
systemctl unmask rasdaemon
systemctl enable --now rasdaemon
```

## 2. Diagnosis

```bash
journalctl -k | grep -i edac          # or: dmesg -T | grep -i edac
ras-mc-ctl --summary                  # error totals per DIMM label
ras-mc-ctl --errors                   # every event, with timestamps
```

The kernel lines all name one label, for example `CPU_SrcID#1_MC#1_Chan#1_DIMM#0`. Decode it with
`/root/evidence/board-dimm-map.txt`: socket 1, MC#1 Chan#1 = **E**, DIMM#0 = **1**, so **`CPU1_DIMM_E1`**.
The `EDAC MCn` number in the kernel line is the global controller index (socket × 2 + controller here). It is not
the same thing as the `MC#` inside the label, which is a common way to send a technician to the wrong slot.

`count` is the sum of `err_count` for that label (rasdaemon may store several errors in one record), which is what
`ras-mc-ctl --summary` prints. You can also ask the database directly:

```bash
sqlite3 /var/lib/rasdaemon/ras-mc_event.db \
  "select label, err_type, sum(err_count) from mc_event group by label, err_type;"
```

The other DIMM with a single error 45 days ago is background noise. `action` is `replace` if the busy DIMM has
1000 or more CEs (all of them landed within the last six hours), otherwise `monitor`.

## 3. ce-delta

```bash
cat > /usr/local/bin/ce-delta <<'S'
#!/bin/bash
# ce-delta COMMAND [ARG...]: run COMMAND, report correctable memory errors logged meanwhile
EDAC_ROOT=${EDAC_ROOT:-/sys/devices/system/edac/mc}
ce_total() {
  local f sum=0 n=0
  for f in "$EDAC_ROOT"/mc*/ce_count; do
    [ -r "$f" ] || continue
    sum=$((sum + $(cat "$f"))); n=$((n + 1))
  done
  [ $n -gt 0 ] || return 1
  echo $sum
}
[ $# -gt 0 ] || { echo "usage: ce-delta COMMAND [ARG...]" >&2; exit 2; }
before=$(ce_total) || { echo "ce-delta: no EDAC memory controllers under $EDAC_ROOT; refusing to report a pass" >&2; exit 2; }
"$@"; rc=$?
after=$(ce_total) || { echo "ce-delta: EDAC telemetry disappeared during the run" >&2; exit 2; }
delta=$((after - before))
echo "CE_DELTA=$delta"
[ $rc -eq 0 ] && [ $delta -eq 0 ] && exit 0
exit 1
S
chmod +x /usr/local/bin/ce-delta
```

## 4. The real run

```bash
ce-delta stress-ng --vm 2 --vm-bytes 50% --verify -t 30s > /root/stress.log 2>&1; echo $?     # 2
echo vm_exit=2 >> /root/answers.txt    # or edit the existing vm_exit= line
```

It exits **2**: a virtual machine has no EDAC memory controller (`ls /sys/devices/system/edac/mc` is empty), so the
wrapper cannot tell a clean run from one that corrupted memory, and it must not call that a pass. On real hardware
the same command prints `CE_DELTA=0` on a healthy box. This is the most important rule in hardware checks:
**missing telemetry is a failure, not a pass.** A stress run with zero miscompares still fails a DIMM whose CE
count jumped during the run.

## What was simulated

The EDAC lines were written into the kernel ring buffer through `/dev/kmsg` (try `dmesg -x`: they carry the
`user` facility, where real ones say `kern`), and the rasdaemon records were inserted into its SQLite database.
The diagnosis steps are exactly the ones you would use on real hardware.
