# Lab 17 solution

## 1. Fan-out fio

```ini
; /root/fanout.fio
[global]
rw=randread
bs=4k
direct=1
ioengine=libaio
iodepth=16
time_based
runtime=30

[slot0]
filename=/dev/mapper/encl0-slot0
[slot1]
filename=/dev/mapper/encl0-slot1
; ... one section per slot ...
[slot7]
filename=/dev/mapper/encl0-slot7
```

```bash
fio /root/fanout.fio --output-format=json --output=/root/fanout.json
jq -r '.jobs[] | "\(.jobname) err=\(.error) bw=\(.read.bw)KiB/s iops=\(.read.iops|floor) clat_p99=\(.read.clat_ns.percentile["99.000000"])ns"' /root/fanout.json
```

Jobs in one file run in parallel unless you add `stonewall`. Running every drive at once is the point: it loads the
HBA, expanders, cables, enclosure power and cooling together, which single-drive tests never do.

## 2. peer-outliers

```bash
cat > /usr/local/bin/peer-outliers <<'S'
#!/bin/bash
# peer-outliers FIO.json [PERCENT]: flag jobs slower than PERCENT% of the median, or with errors
f=$1; pct=${2:-70}
[ -r "$f" ] || { echo "peer-outliers: cannot read $f" >&2; exit 2; }
jq -e '.jobs | length > 0' "$f" >/dev/null 2>&1 || { echo "peer-outliers: no fio jobs in $f" >&2; exit 2; }
out=$(jq -r --argjson pct "$pct" '
  ([.jobs[].read.bw] | sort) as $s | ($s | length) as $n
  | (if $n % 2 == 1 then $s[($n - 1) / 2] else ($s[$n/2 - 1] + $s[$n/2]) / 2 end) as $median
  | .jobs[]
  | select(.error != 0 or .read.bw < $median * $pct / 100)
  | "\(.jobname) OUTLIER bw=\(.read.bw)KiB/s median=\($median)KiB/s error=\(.error)"' "$f")
[ -z "$out" ] && { echo "peer-outliers: no outliers"; exit 0; }
echo "$out"; exit 1
S
chmod +x /usr/local/bin/peer-outliers
peer-outliers /root/fanout.json
```

The **median** matters: with a mean, a couple of very slow drives drag the average down until they no longer look
slow. A job with an I/O error is an outlier however fast it ran before the error.

## 3. The slots

- **Slow slot:** far lower IOPS and much higher latency (look at `clat_ns` percentiles) than its seven peers.
  `dmsetup table` shows why: a `delay` target adding 25 ms to every I/O. On real hardware this pattern is a drive
  doing internal retries (weak head, failing media), a drive stuck in a degraded link, or a firmware problem.
  It passes any "does it work" check and every absolute threshold a careless check might set.
- **Bad slot:** fio reports `err=5` (EIO, `Input/output error`) for that job. `dmsetup table` shows an `error`
  segment in the middle of the slot: sectors that can't be read.
  (If dm-delay was missing, the setup throttled the slow slot with a cgroup I/O limit instead: see
  `systemctl show user.slice | grep IO`.)

## 4. SAS PHY counters

```bash
cd /root/evidence/jbod
for d in sas-after/expander-*/phy-*; do
  b=sas-before/${d#sas-after/}
  printf '%-28s %-10s' "${d#sas-after/}" "$(cat $d/negotiated_linkrate)"
  for c in invalid_dword_count running_disparity_error_count loss_of_dword_sync_count phy_reset_problem_count; do
    printf ' %s=+%d' ${c%%_*} $(( $(cat $d/$c) - $(cat $b/$c) ))
  done; echo
done
```

- **Cable:** all four PHYs 0 to 3 of one expander (its wide-port uplink to the HBA) gained thousands of invalid
  dwords and disparity errors during the run, at the same time. Four lanes failing together means the thing they
  share: the cable (or the HBA port / expander connector it plugs into). Every drive behind that expander would
  show errors or timeouts too. RMAing those four drives would leave the bad cable in place.
- **One drive link:** a single drive-facing PHY with new errors and PHY resets. That's that drive's own link: the
  drive, or its slot connector on the backplane. Reseat it first; if the errors follow the drive to another slot,
  replace the drive.
- **Slow link:** one drive PHY at `6.0 Gbit` while the rest run at `12.0 Gbit`. It works, at half the bandwidth,
  usually because of a marginal connector or a drive that only supports 6G.
- **Trap:** several PHYs have large counts that are the same before and after. Those are old events (cabling work,
  a past reset); only the **delta during the run** says anything about the hardware today.

On real hardware, read these from `/sys/class/sas_phy/*/`, map PHYs to slots with `sg_ses --page=aes` (or
`--join`) and `/sys/class/enclosure/`, list expander PHYs with `smp_discover`, and blink a slot's locate LED with
`sg_ses --index=N --set=ident` before anyone pulls a drive.

## What was simulated

The eight slots are device-mapper devices carved out of one virtual disk; the delay and error targets are real
kernel device-mapper targets, so fio sees genuine latency and genuine EIO. A VM has no SAS, expanders or SES, so the
PHY counters are generated files in the sysfs layout.
