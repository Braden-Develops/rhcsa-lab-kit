# Lecture H5: PCIe: link training, LnkCap vs. LnkSta, and AER

Almost everything fast in a server hangs off PCI Express: NVMe drives, NICs, storage HBAs, GPUs and
accelerators. PCIe problems have two signatures. A link can **train badly** (fewer lanes or a lower speed than it
should) and keep working at a fraction of its bandwidth, with no error anywhere. Or a link can be **electrically
marginal** and produce a stream of corrected errors that eventually become uncorrected ones. Both are cheap to
check for and both are commonly missed.

This lecture covers PCIe addressing and topology, link training, reading `lspci -vvv`, Advanced Error Reporting,
and how to get from a PCI address to a device name and a physical slot.

Practice: [Lab 15](#/lab/15).

---

## Addresses and topology

Every PCI function has an address **domain:bus:device.function**, written `0000:17:00.0` (lspci drops the
domain when it's 0000: `17:00.0`). This address is called the **BDF**.

```bash
lspci                         # one line per function
lspci -tv                     # tree: root ports, switches, endpoints
lspci -nn                     # with [vendor:device] IDs
lspci -k                      # with the kernel driver in use
lspci -s 17:00.0 -vvv         # everything about one device (run as root: capabilities are hidden from users)
```

```text
 CPU socket ─ root complex ─┬─ root port 16:01.0 ══ x4 link ══ NVMe 17:00.0
                            ├─ root port 30:02.0 ══ x16 link ═ NIC 31:00.0 / 31:00.1 (two functions)
                            └─ root port 4a:01.0 ══ x8 link ══ SAS HBA 4b:00.0
```

- A **root port** is the CPU side of a link; an **endpoint** is the device. A **PCIe switch** fans one link out to
  several. Each link has two ends, and each end reports the link's state.
- Bus numbers tell you which socket a device hangs off (roughly: one range per socket), which matters for NUMA:
  a NIC on socket 1 serving a process on socket 0 crosses the interconnect.
- A multi-function device (`31:00.0`, `31:00.1`: a dual-port NIC) shares one link.

### From a BDF to a Linux name, and back

```bash
ls /sys/bus/pci/devices/0000:17:00.0/              # driver -> ..., nvme/ (nvme0), net/ (for NICs), ...
ls /sys/bus/pci/devices/0000:31:00.0/net/          # ens1f0np0
readlink -f /sys/class/net/ens1f0np0/device        # .../0000:31:00.0
ethtool -i ens1f0np0 | grep bus-info               # bus-info: 0000:31:00.0
readlink -f /sys/class/nvme/nvme0/device           # NVMe controller -> BDF
readlink -f /sys/block/sda/device                  # disk -> SCSI address -> HBA's BDF further up the path
```

For virtio devices in a VM, the network or block device sits one level below the PCI device (`.../virtio1/net/`).

### From a BDF to a physical slot

```bash
lspci -vvv -s 17:00.0 | grep -i 'physical slot'     # "Physical Slot: 3" from the firmware's slot table
ls /sys/bus/pci/slots/                              # slot numbers, each with an "address" file
dmidecode -t 9                                      # System Slots: designation, type, current usage, bus address
```

`dmidecode -t 9` maps the board's slot labels ("PCIe Slot 3", "OCP 3.0") to bus addresses. Like DIMM labels, it's
only as good as the firmware's tables, so verify once per platform.

---

## Link training: speed and width

When a system powers on, each link **trains**: the two ends negotiate the number of **lanes** (width: x1, x2, x4,
x8, x16) and the **speed** (generation):

| Generation | Rate per lane | Approx. usable bandwidth, x16 |
|---|---|---|
| Gen1 | 2.5 GT/s | 4 GB/s |
| Gen2 | 5 GT/s | 8 GB/s |
| Gen3 | 8 GT/s | 16 GB/s |
| Gen4 | 16 GT/s | 32 GB/s |
| Gen5 | 32 GT/s | 64 GB/s |

The link trains to the highest speed and widest width **both** ends and the channel between them support. If some
lanes are damaged, dirty or not making contact, or the signal is marginal, the link **trains down**: fewer lanes or
a lower generation. **The device still works.** The OS sees it, the driver loads, it passes I/O. It just has half
or a quarter of its bandwidth, and nothing reports an error.

Common causes: a card not fully seated, a damaged or dirty slot or connector, a bad riser card or cable (riser
cables are a frequent culprit), a retimer problem, a BIOS setting that forces a lower generation, or a card
plugged into a slot that is physically x16 but electrically x8 (a build error, not a fault).

### Reading LnkCap and LnkSta

```bash
lspci -vvv -s 17:00.0 | grep -E 'LnkCap:|LnkSta:'
```

```text
LnkCap:	Port #0, Speed 16GT/s, Width x4, ASPM L1, Exit Latency L1 <64us
LnkSta:	Speed 16GT/s (ok), Width x2 (downgraded)
```

- **LnkCap** (link capabilities): what this end supports.
- **LnkSta** (link status): what the link actually trained to.
- Recent lspci versions annotate `(ok)` or `(downgraded)`; older versions don't, so compare the numbers yourself.
- **LnkCap2 / LnkSta2 / LnkCtl2** are different registers (supported speeds vector, target speed, equalisation
  status). Don't confuse them when parsing.
- **LnkCtl2: Target Link Speed** below the capability means software or firmware asked for a lower speed.

Check both ends: the root port's `LnkSta` describes the same link and should agree. Also compare with the **build
sheet**: a x16 card that a x8 slot limits shows `LnkCap x16, LnkSta x8`, which is "degraded" but correct for that
slot, and only the build sheet tells you which slot it should be in.

The kernel also logs a downgraded link at boot on recent versions:

```text
pci 0000:17:00.0: 15.752 Gb/s available PCIe bandwidth, limited by 8.0 GT/s PCIe x2 link at 0000:16:01.0
  (capable of 31.504 Gb/s with 16.0 GT/s x2 link)
```

### A link check

For each device with both registers: degraded if current speed < capable speed or current width < capable width;
compare against the expected speed and width for that slot from the build sheet; report the BDF, the slot, the
device, and expected vs. actual. If there's no link information at all (not root, lspci missing), report "cannot
check", not "pass". Lab 15 builds this.

Links can also **retrain** at runtime (`BWMgmt+` / `ABWMgmt+` in LnkSta mean the link changed bandwidth on its
own). A link that retrains under load is marginal.

---

## Advanced Error Reporting (AER)

PCIe protects every packet with CRCs and retries at the link layer. **AER** is the optional capability through
which devices report errors to the root port, which signals the OS.

| Class | Examples | What it means |
|---|---|---|
| **Correctable** | Receiver Error (RxErr), Bad TLP, Bad DLLP, Replay Timer Timeout, Replay Num Rollover | The link layer detected and recovered (retransmitted). No data lost. |
| **Uncorrectable, non-fatal** | Completion Timeout, Unsupported Request, Poisoned TLP | A transaction failed; the link is still up. The driver must recover. |
| **Uncorrectable, fatal** | Data Link Protocol Error, Surprise Down, Malformed TLP, Receiver Overflow | The link itself is unreliable; the device usually has to be reset, and may disappear. |

Kernel messages:

```text
pcieport 0000:16:01.0: AER: Correctable error message received from 0000:17:00.0
nvme 0000:17:00.0: PCIe Bus Error: severity=Correctable, type=Physical Layer, (Receiver ID)
nvme 0000:17:00.0:   device [144d:a80a] error status/mask=00000001/0000e000
nvme 0000:17:00.0:    [ 0] RxErr                  (First)
```

- The first line comes from the **root port** that received the report; the following lines name the **device**
  that detected the error, its vendor:device IDs, and the bits set in its AER status register.
- *Receiver ID* means the error was detected by the receiving end; *Transmitter ID* by the sender.
- *Physical Layer* errors (RxErr) are about the electrical signal; *Data Link Layer* errors (Bad TLP, Bad DLLP) are
  corrupted packets caught by CRC.

Counters (on kernels and hardware that expose them):

```bash
grep . /sys/bus/pci/devices/0000:17:00.0/aer_dev_correctable      # per-error-type counts, plus TOTAL_ERR_COR
grep . /sys/bus/pci/devices/0000:17:00.0/aer_dev_nonfatal /sys/bus/pci/devices/0000:17:00.0/aer_dev_fatal
ras-mc-ctl --errors                                                # rasdaemon records AER events too
```

### Interpreting AER

- **A few correctable errors** over a server's life are normal. Don't fail hardware for one.
- **A steady stream** from one device, especially rising under load, means a marginal link. Reseat the card;
  move it to another slot; if the errors follow the card, replace it; if they stay with the slot, it's the slot,
  riser or board. The same swap logic as DIMMs.
- **Uncorrectable errors** mean data was lost or the device was reset. Treat them as failures.
- Errors on **several devices behind the same root port or switch** point at what they share.
- **Firmware-first platforms** may handle AER in firmware and report through APEI/GHES (lecture H8) or the BMC's
  SEL instead of native AER messages. Check `dmesg` for `HEST` / `GHES` and the SEL.
- Some platforms mask correctable errors by default, or the OS reports *AER: ... masked*. "No AER messages" can mean
  "no errors" or "not reported". Know which on your platform before trusting silence.

---

## Stress for PCIe

Links fail under traffic and heat, so test them busy: run fio on NVMe drives, `iperf3` traffic through NICs, a
compute load on accelerators, all at once to also load the power supply and raise temperatures. Read AER counters
and the kernel log before and after, and check `LnkSta` again at the end (a link that retrained mid-test may
report a lower speed now).

---

## Quick reference

| Task | Command |
|---|---|
| Tree | `lspci -tv` |
| Driver per device | `lspci -k` |
| Link capability vs. status | `lspci -vvv \| grep -E '^[0-9a-f]\|LnkCap:\|LnkSta:'` (as root) |
| Slot mapping | `lspci -vvv` *Physical Slot*, `dmidecode -t 9`, `/sys/bus/pci/slots/` |
| BDF of a NIC or disk | `ethtool -i IF`, `readlink -f /sys/class/net/IF/device`, `/sys/class/nvme/nvme0/device` |
| AER messages | `journalctl -k \| grep -E 'AER\|PCIe Bus Error'` |
| AER counters | `/sys/bus/pci/devices/*/aer_dev_{correctable,nonfatal,fatal}` |

Reading: kernel `Documentation/PCI/pcieaer-howto.rst`; Budruk, Anderson and Shanley, *PCI Express System
Architecture* (link training and error handling chapters).

---

## Review questions

1. An NVMe drive benchmarks at half its peers' throughput and the kernel log is clean. What do you check first?
2. A card shows `LnkCap: Width x16` and `LnkSta: Width x8`. Is it faulty?
3. How do you find which network interface is `0000:31:00.1`?
4. What does a correctable *Receiver Error* tell you, and when does it matter?
5. Errors appear on three devices behind the same PCIe switch. Where's the problem likely to be?
6. Why parse `LnkCap:` with the colon?
7. A check finds no `LnkCap` lines on a server. Pass or fail?

<details><summary>Answers</summary>

1. Its link: `lspci -vvv -s BDF` and compare `LnkSta` with `LnkCap` (speed and width), and look for the kernel's
   "limited by" bandwidth message at boot.
2. Not necessarily: if the slot is electrically x8, that's expected (but maybe a build error). Compare with the
   build sheet; if the slot should be x16, reseat and investigate.
3. `ls /sys/bus/pci/devices/0000:31:00.1/net/`, or `ethtool -i` on each interface and match `bus-info`.
4. The receiver saw a bad symbol on the wire and the link layer recovered. Occasional ones are normal; a steady or
   rising rate under load means a marginal link (seating, slot, riser).
5. What they share: the switch, its upstream link, or the riser or board it sits on.
6. To avoid matching `LnkCap2:`, a different register (supported speeds), which would corrupt the parse.
7. Neither: it couldn't check (probably not run as root, or no PCIe devices visible). It must report an error, not a
   pass.

</details>
