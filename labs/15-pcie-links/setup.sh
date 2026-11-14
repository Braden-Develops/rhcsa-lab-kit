#!/bin/bash
# Lab 15: AER errors against a real device of this VM (simulated messages: QEMU's virtual links never fail),
# and lspci captures from a server with two links that trained below their capability.
set -e
. /opt/labkit/lib/vm.sh
. /opt/labkit/lib/hw.sh
. "$LABDIR/fixture.sh"
need_pkgs pciutils
truth_reset

# --- pick a real PCI device: the lab NIC (falls back to any non-bridge PCI device) ---
IF=$(lab_iface)
d=$(readlink -f /sys/class/net/$IF/device 2>/dev/null || true)
case $(basename "${d:-x}") in virtio*) d=$(dirname "$d");; esac
if [ -z "$IF" ] || [ ! -e "$d/vendor" ]; then
  echo "No second NIC found; using the first disk controller instead"
  d=$(readlink -f /sys/block/$(lsblk -dno NAME | grep -v '^sr' | head -1)/device); while [ ! -e "$d/vendor" ]; do d=$(dirname "$d"); done
  IF=$(basename "$d")
fi
BDF=$(basename "$d"); PORT=$(basename "$(dirname "$d")")
[[ $PORT =~ ^[0-9a-f]{4}: ]] || PORT=0000:00:00.0
DRV=$(basename "$(readlink -f $d/driver)" 2>/dev/null || echo pcieport)
VID=$(sed 's/0x//' $d/vendor); DID=$(sed 's/0x//' $d/device)
truth aer_device "$IF" "$BDF" "${BDF#0000:}"
truth aer_severity correctable
echo "AER target: $BDF ($IF, $DRV)"
for i in $(seq 1 14); do
  bit=$(pick "0:RxErr:Physical Layer:00000001" "6:BadTLP:Data Link Layer:00000040" "7:BadDLLP:Data Link Layer:00000080")
  n=${bit%%:*}; r=${bit#*:}; name=${r%%:*}; r=${r#*:}; layer=${r%%:*}; mask=${r#*:}
  kmsg 4 "pcieport $PORT: AER: Correctable error message received from $BDF"
  kmsg 4 "$DRV $BDF: PCIe Bus Error: severity=Correctable, type=$layer, (Receiver ID)"
  kmsg 4 "$DRV $BDF:   device [$VID:$DID] error status/mask=$mask/0000e000"
  kmsg 4 "$DRV $BDF:    [ $n] $name$(printf '%*s' $((22 - ${#name})) '')(First)"
done

# --- evidence: lspci -vvv from a storage server, two links degraded ---
set -- 17:00.0 18:00.0 4b:00.0 b1:00.0
W=$(pick "$@"); while :; do S=$(pick "$@"); [ "$S" != "$W" ] && break; done
truth width_degraded "$W" "0000:$W"
truth speed_degraded "$S" "0000:$S"
mkdir -p /root/evidence
server_lspci "$W" "$S" > /root/evidence/stor-117-lspci-vvv.txt
cat > /root/evidence/stor-117-expected.txt <<'X'
stor-117 build sheet (expected PCIe configuration)
  17:00.0, 18:00.0, b1:00.0   NVMe SSD (PM9A3)            PCIe Gen4 x4
  4b:00.0                     SAS 24G HBA                 PCIe Gen4 x8
  31:00.0, 31:00.1            100GbE NIC (ConnectX-6 Dx)  PCIe Gen4 x16
  03:00.0                     BMC video                   PCIe Gen2 x1
Gen1 = 2.5 GT/s, Gen2 = 5 GT/s, Gen3 = 8 GT/s, Gen4 = 16 GT/s, Gen5 = 32 GT/s
X
answers_template aer_device aer_severity width_degraded speed_degraded
echo "Lab 15 ready."
