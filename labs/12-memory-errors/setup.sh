#!/bin/bash
# Lab 12: a DIMM is throwing correctable errors. The evidence arrives the way it would on a real server:
# EDAC lines in the kernel log, records in rasdaemon's database, and the vendor's slot map.
# A VM has no memory controller to break, so the kernel lines and database rows are simulated (see lecture 12).
set -e
. /opt/labkit/lib/hw.sh
need_pkgs rasdaemon sqlite dmidecode stress-ng perl-DBD-SQLite
truth_reset

# --- pick the failing DIMM: socket 0-1, memory controller 0-1, channel 0-2, DIMM 0 ---
S=$((RANDOM % 2)); M=$((RANDOM % 2)); C=$((RANDOM % 3)); D=0
LETTERS=(A B C D E F)
SLOT="CPU${S}_DIMM_${LETTERS[$((M * 3 + C))]}$((D + 1))"
LABEL="CPU_SrcID#${S}_MC#${M}_Chan#${C}_DIMM#${D}"
EMC=$((S * 2 + M))                      # EDAC numbers memory controllers globally: mc0..mc3
if [ $((RANDOM % 2)) -eq 0 ]; then COUNT=$((1200 + RANDOM % 1200)); ACTION=replace; else COUNT=$((150 + RANDOM % 450)); ACTION=monitor; fi
truth dimm "$SLOT"
truth count "$COUNT"
truth action "$ACTION"
truth vm_exit 2

# --- background noise: an old, isolated error on a different DIMM (normal in a big fleet) ---
NS=$(( (S + 1) % 2 )); NM=$((RANDOM % 2)); NC=$((RANDOM % 3))
NLABEL="CPU_SrcID#${NS}_MC#${NM}_Chan#${NC}_DIMM#0"

# --- rasdaemon: let it create its database, then record the events ---
systemctl unmask rasdaemon 2>/dev/null || true
systemctl start rasdaemon 2>/dev/null && sleep 3 || true
systemctl stop rasdaemon 2>/dev/null || true
rows="["
rows+="{\"timestamp\":\"$(ago 3888000)\",\"err_count\":1,\"err_type\":\"Corrected\",\"err_msg\":\"memory read error\",\"label\":\"$NLABEL\",\"mc\":$((NS*2+NM)),\"top_layer\":$NC,\"middle_layer\":0,\"lower_layer\":-1,\"address\":$((RANDOM*4096)),\"grain\":32,\"syndrome\":0,\"driver_detail\":\"err_code:0x0000:0x009f\"},"
left=$COUNT; n=0
while [ $left -gt 0 ]; do
  c=$(( left > 80 ? 20 + RANDOM % 60 : left )); left=$((left - c)); n=$((n + 1))
  rows+="{\"timestamp\":\"$(ago $(( 21600 - n * 300 )))\",\"err_count\":$c,\"err_type\":\"Corrected\",\"err_msg\":\"memory read error\",\"label\":\"$LABEL\",\"mc\":$EMC,\"top_layer\":$C,\"middle_layer\":$D,\"lower_layer\":-1,\"address\":$(( (RANDOM % 64) * 4096 + 0x3f1a2000 )),\"grain\":32,\"syndrome\":0,\"driver_detail\":\"err_code:0x0000:0x009f ProcessorSocketId:0x$S MemoryControllerId:0x$M PhysicalRankId:$((RANDOM % 2))\"},"
done
rows="${rows%,}]"
ras_insert mc_event "$rows"

# --- kernel log: what the EDAC driver would print as the errors arrived ---
for i in $(seq 1 12); do
  kmsg 4 "EDAC MC${EMC}: $((RANDOM % 40 + 1)) CE memory read error on ${LABEL} (channel:${C} slot:${D} page:0x3f1a$((RANDOM % 9)) offset:0x$((RANDOM % 9))40 grain:32 syndrome:0x0 - err_code:0x0000:0x009f ProcessorSocketId:0x${S} MemoryControllerId:0x${M} PhysicalRankId:$((RANDOM % 2)) Row:0x2a6c Column:0x1e8 Bank:0x2 BankGroup:0x1)"
done
kmsg 4 "EDAC skx MC${EMC}: HANDLING MCE MEMORY ERROR"
kmsg 4 "mce: [Hardware Error]: Machine check events logged"

# --- BROKEN: someone turned error recording off "because it was noisy" ---
systemctl disable rasdaemon 2>/dev/null || true
systemctl mask rasdaemon

# --- the vendor's documentation for this board ---
mkdir -p /root/evidence
cat > /root/evidence/board-dimm-map.txt <<MAP
Server board DIMM population guide (vendor service manual, section 4.2)

The Linux EDAC driver names DIMMs by socket, memory controller, channel and DIMM:
    CPU_SrcID#<socket>_MC#<controller>_Chan#<channel>_DIMM#<dimm>

The silkscreen label printed on the board next to each slot is CPU<socket>_DIMM_<letter><n>:

    MC#0 Chan#0 -> A     MC#1 Chan#0 -> D
    MC#0 Chan#1 -> B     MC#1 Chan#1 -> E
    MC#0 Chan#2 -> C     MC#1 Chan#2 -> F
    DIMM#0 -> 1 (blue slot, populate first)    DIMM#1 -> 2 (black slot)

Example: CPU_SrcID#1_MC#0_Chan#2_DIMM#0 is the slot printed CPU1_DIMM_C1.
MAP
cat > /root/evidence/rma-criteria.txt <<'RMA'
DIMM replacement criteria (vendor RMA policy)

Replace the DIMM if ANY of these is true:
  * one or more uncorrectable (UE) errors attributed to the DIMM
  * 1000 or more correctable (CE) errors on the DIMM within 24 hours
  * the platform disabled the rank or page (sparing / page offlining exhausted)

Otherwise: monitor. Isolated CEs spread over weeks are normal at fleet scale and are not RMA-able.
RMA
cat > /root/evidence/dmidecode-memory.txt <<DMI
# dmidecode -t memory   (captured from this server's twin; the VM's own dmidecode shows QEMU's fake DIMM)
$(for s in 0 1; do for l in A B C D E F; do cat <<ONE
Handle 0x00$s$l, DMI type 17, 92 bytes
Memory Device
	Array Handle: 0x0030
	Total Width: 72 bits
	Data Width: 64 bits
	Size: 32 GB
	Form Factor: DIMM
	Locator: CPU${s}_DIMM_${l}1
	Bank Locator: NODE ${s}
	Type: DDR5
	Speed: 4800 MT/s
	Manufacturer: Samsung
	Serial Number: $(printf '%08X' $(( (RANDOM << 15) | RANDOM )))
	Part Number: M321R4GA3BB6-CQKET
	Rank: 2
	Configured Memory Speed: 4800 MT/s

ONE
done; done)
DMI
answers_template dimm count action vm_exit
echo "Lab 12 ready."
