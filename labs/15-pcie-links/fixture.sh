#!/bin/bash
# lspci -vvv style text for a made-up server, used by setup.sh (evidence) and check.sh (grading fixtures).
# lspci_dev BDF "CLASS: NAME" CAP_GTS CAP_W STA_GTS STA_W
lspci_dev() {
  local bdf=$1 name=$2 cs=$3 cw=$4 ss=$5 sw=$6 sn wn
  sn=$( [ "$ss" != "$cs" ] && echo " (downgraded)" || echo " (ok)"); wn=$( [ "$sw" != "$cw" ] && echo " (downgraded)" || echo " (ok)")
  cat <<D
$bdf $name
	Subsystem: Vendor Device $(printf '%04x' $((RANDOM % 65535)))
	Control: I/O- Mem+ BusMaster+ SpecCycle- MemWINV- VGASnoop- ParErr- Stepping- SERR- FastB2B- DisINTx+
	Status: Cap+ 66MHz- UDF- FastB2B- ParErr- DEVSEL=fast >TAbort- <TAbort- <MAbort- >SERR- <PERR- INTx-
	Latency: 0, Cache Line Size: 64 bytes
	NUMA node: $( [[ $bdf < 80 ]] && echo 0 || echo 1)
	IOMMU group: $((RANDOM % 200))
	Capabilities: [40] Power Management version 3
		Flags: PMEClk- DSI- D1- D2- AuxCurrent=0mA PME(D0-,D1-,D2-,D3hot-,D3cold-)
	Capabilities: [70] Express (v2) Endpoint, MSI 00
		DevCap:	MaxPayload 512 bytes, PhantFunc 0, Latency L0s unlimited, L1 unlimited
			ExtTag+ AttnBtn- AttnInd- PwrInd- RBE+ FLReset+ SlotPowerLimit 75W
		DevCtl:	CorrErr+ NonFatalErr+ FatalErr+ UnsupReq+
			RlxdOrd+ ExtTag+ PhantFunc- AuxPwr- NoSnoop+ FLReset-
			MaxPayload 256 bytes, MaxReadReq 512 bytes
		DevSta:	CorrErr- NonFatalErr- FatalErr- UnsupReq- AuxPwr- TransPend-
		LnkCap:	Port #0, Speed ${cs}GT/s, Width x${cw}, ASPM not supported
			ClockPM- Surprise- LLActRep- BwNot- ASPMOptComp+
		LnkCtl:	ASPM Disabled; RCB 64 bytes, Disabled- CommClk+
			ExtSynch- ClockPM- AutWidDis- BWInt- AutBWInt-
		LnkSta:	Speed ${ss}GT/s${sn}, Width x${sw}${wn}
			TrErr- Train- SlotClk+ DLActive- BWMgmt- ABWMgmt-
		DevCap2: Completion Timeout: Range ABCD, TimeoutDis+ NROPrPrP- LTR+
		LnkCap2: Supported Link Speeds: 2.5-${cs}GT/s, Crosslink- Retimer+ 2Retimers+ DRS-
		LnkCtl2: Target Link Speed: ${cs}GT/s, EnterCompliance- SpeedDis-
		LnkSta2: Current De-emphasis Level: -6dB, EqualizationComplete+ EqualizationPhase1+
	Capabilities: [100 v2] Advanced Error Reporting
		UESta:	DLP- SDES- TLP- FCP- CmpltTO- CmpltAbrt- UnxCmplt- RxOF- MalfTLP- ECRC- UnsupReq- ACSViol-
		CESta:	RxErr- BadTLP- BadDLLP- Rollover- Timeout- AdvNonFatalErr-
	Kernel driver in use: $(case $name in *Non-Volatile*) echo nvme;; *Ethernet*) echo mlx5_core;; *SCSI*) echo mpi3mr;; *VGA*) echo ast;; *) echo pcieport;; esac)

D
}
lspci_host_bridge() {
  cat <<D
00:00.0 Host bridge: Intel Corporation Device 09a2 (rev 04)
	Subsystem: Intel Corporation Device 0000
	Control: I/O- Mem- BusMaster- SpecCycle- MemWINV- VGASnoop- ParErr- Stepping- SERR- FastB2B- DisINTx-
	Capabilities: [40] Express (v2) Root Complex Integrated Endpoint, MSI 00
		DevCap:	MaxPayload 128 bytes, PhantFunc 0
		DevSta:	CorrErr- NonFatalErr- FatalErr- UnsupReq- AuxPwr- TransPend-

D
}
# server_lspci WIDTH_BDF SPEED_BDF : the whole server, degrading those two devices (pass "" for none)
server_lspci() {
  local w=$1 s=$2 b
  lspci_host_bridge
  for b in 17:00.0 18:00.0 4b:00.0 b1:00.0; do
    local name="Non-Volatile memory controller: Samsung Electronics Co Ltd NVMe SSD Controller PM9A1/PM9A3/980PRO" cw=4
    [ $b = 4b:00.0 ] && { name="Serial Attached SCSI controller: Broadcom / LSI Fusion-MPT 24GSAS/PCIe SAS40xx (rev 01)"; cw=8; }
    local ss=16 sw=$cw
    [ "$b" = "$w" ] && sw=$((cw / 2))
    [ "$b" = "$s" ] && ss=8
    lspci_dev $b "$name" 16 $cw $ss $sw
  done
  lspci_dev 31:00.0 "Ethernet controller: Mellanox Technologies MT2892 Family [ConnectX-6 Dx]" 16 16 16 16
  lspci_dev 31:00.1 "Ethernet controller: Mellanox Technologies MT2892 Family [ConnectX-6 Dx]" 16 16 16 16
  lspci_dev 03:00.0 "VGA compatible controller: ASPEED Technology, Inc. ASPEED Graphics Family (rev 52)" 5 1 5 1
}
