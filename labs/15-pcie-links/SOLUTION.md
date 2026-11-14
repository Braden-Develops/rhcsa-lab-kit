# Lab 15 solution

## 1. AER

```bash
journalctl -k | grep -E 'AER|PCIe Bus Error' | head
# pcieport 0000:00:02.1: AER: Correctable error message received from 0000:01:00.0
# virtio-pci 0000:01:00.0: PCIe Bus Error: severity=Correctable, type=Physical Layer, (Receiver ID)
# virtio-pci 0000:01:00.0:    [ 0] RxErr                  (First)
lspci -s 01:00.0 -k                      # Ethernet controller: Red Hat, Inc. Virtio network device; driver virtio-pci
ls /sys/bus/pci/devices/0000:01:00.0/    # virtio1/ ... for a virtio device, the netdev sits one level down
ls /sys/bus/pci/devices/0000:01:00.0/virtio*/net/       # eth1 / enp1s0
# the other direction: from an interface to its PCI address
ethtool -i enp1s0 | grep bus-info
readlink -f /sys/class/net/enp1s0/device
```

`aer_device` = that interface, `aer_severity=correctable`.

**What it means.** The PCIe link layer corrected these errors by retrying (RxErr = the receiver saw a bad symbol;
BadTLP and BadDLLP = a packet failed its CRC and was replayed), so nothing was lost and the device kept working. A few
over a server's lifetime are normal. A **steady stream** from one device means a marginal link: a badly seated card or
riser, a damaged slot, or a signal-integrity problem. Reseat the card, move it to another slot, and if the errors
follow the card, replace it. Correctable errors that keep rising are the early warning before non-fatal and fatal
ones, which do lose data and can take the device offline. The counters are in
`/sys/bus/pci/devices/*/aer_dev_correctable` on hardware with AER (a QEMU virtual device usually has none).

## 2. Link training

```bash
grep -E '^[0-9a-f]{2}:|LnkCap:|LnkSta:' /root/evidence/stor-117-lspci-vvv.txt
```

Every device should show the same speed and width in `LnkSta` as in `LnkCap`. Recent lspci versions annotate the
status with `(downgraded)`, but don't rely on that: older versions don't. A x4 NVMe drive at `Width x2` has half its
bandwidth; one at `Speed 8GT/s` instead of 16 is a Gen3 link instead of Gen4, also half. Both still "work", so
nothing fails until someone benchmarks them. Typical causes: a bad riser or cable, a damaged slot, a card that isn't
fully seated, or a BIOS setting that forced a lower generation.

## 3. pcie-linkcheck

```bash
cat > /usr/local/bin/pcie-linkcheck <<'S'
#!/bin/bash
# pcie-linkcheck [FILE]: compare LnkCap with LnkSta for every PCIe device
if [ $# -gt 0 ]; then
  [ -r "$1" ] || { echo "pcie-linkcheck: cannot read $1" >&2; exit 2; }
  src=$(cat "$1")
else
  src=$(lspci -vvv 2>/dev/null) || { echo "pcie-linkcheck: lspci failed" >&2; exit 2; }
fi
echo "$src" | awk '
  /^[0-9a-f]/ { dev = $1; cap = ""; next }
  /^\t+LnkCap:/ { match($0, /Speed [0-9.]+GT\/s/); cs = substr($0, RSTART + 6, RLENGTH - 10)
                  match($0, /Width x[0-9]+/);      cw = substr($0, RSTART + 7, RLENGTH - 7); cap = 1; next }
  /^\t+LnkSta:/ { if (!cap) next
                  ss = 0; sw = 0
                  if (match($0, /Speed [0-9.]+GT\/s/)) ss = substr($0, RSTART + 6, RLENGTH - 10)
                  if (match($0, /Width x[0-9]+/))      sw = substr($0, RSTART + 7, RLENGTH - 7)
                  st = (ss + 0 < cs + 0 || sw + 0 < cw + 0) ? "DEGRADED" : "OK"
                  printf "%s %s cap=%sGT/s,x%s sta=%sGT/s,x%s\n", dev, st, cs, cw, ss, sw
                  n++; if (st == "DEGRADED") bad++; cap = "" }
  END { if (!n) { print "pcie-linkcheck: no PCIe link information found" > "/dev/stderr"; exit 2 }
        exit bad ? 1 : 0 }'
S
chmod +x /usr/local/bin/pcie-linkcheck
pcie-linkcheck /root/evidence/stor-117-lspci-vvv.txt; echo $?
```

The regular expressions anchor on `LnkCap:` and `LnkSta:` with the colon, so `LnkCap2:` and `LnkSta2:` don't
match. Run it on the VM itself and notice that QEMU's virtual links often report odd values: on real hardware, run it
as root, because lspci hides the capability registers from ordinary users. In a real check you would also compare
against the **build sheet** (expected speed and width per slot), since a x16 card in a x8 slot trains at x8 and
`LnkCap` vs `LnkSta` alone can't tell you the slot was wrong.

## What was simulated

The AER messages were written into the kernel log through `/dev/kmsg`, naming a real device of this VM. The lspci
capture is generated text in the exact `lspci -vvv` layout.
