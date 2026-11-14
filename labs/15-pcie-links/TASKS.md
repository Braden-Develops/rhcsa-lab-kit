# Lab 15: Break-fix: PCIe links and AER errors

**Ticket:** *"Kernel log on servera is full of PCIe errors. Which device, and how bad? Also, a storage server
(stor-117) benchmarks slow on two drives; the tech captured `lspci -vvv` for you."*

Answers go in **`/root/answers.txt`**. Evidence is in **`/root/evidence/`**.

1. **AER.** Read the PCIe errors in this VM's kernel log.
   - `aer_device=` the device that reported them: give its **network interface name** if it is a NIC (or its PCI
     address otherwise). You'll need to get from a PCI address to a Linux device name.
   - `aer_severity=` the AER severity class of these errors (one word)
   - Decide what you would do about them on real hardware (the solution discusses it)
2. **Link training.** Compare each device's link capability with its link status in
   `stor-117-lspci-vvv.txt`, using `stor-117-expected.txt` as the build sheet.
   - `width_degraded=` the PCI address (as lspci prints it, for example `5e:00.0`) of the device that trained with **fewer lanes** than it supports
   - `speed_degraded=` the device that trained at a **lower speed** than it supports
3. **Make it a check.** Write the executable **`/usr/local/bin/pcie-linkcheck`**:
   - `pcie-linkcheck FILE` parses saved `lspci -vvv` output; with no argument it checks this machine (`lspci -vvv`)
   - for every device that has both a `LnkCap:` and a `LnkSta:` line, print one line starting with the device's
     address followed by **`OK`** or **`DEGRADED`** (for example `17:00.0 DEGRADED cap=16GT/s,x4 sta=16GT/s,x2`)
   - a link is degraded if its current speed **or** width is lower than its capability
   - exit **0** if all links are OK, **1** if any is degraded, **2** if the file is missing or contains **no link
     information at all** (a check that sees nothing must not pass)
   - careful: `LnkCap2:` and `LnkSta2:` are different registers
