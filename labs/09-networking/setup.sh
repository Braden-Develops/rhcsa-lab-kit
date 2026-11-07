#!/bin/bash
set -e
. /opt/labkit/lib/vm.sh
IFACE=$(lab_iface)
[ -n "$IFACE" ] || { echo "No second network interface found (the Vagrantfile adds one)." >&2; exit 1; }
save_vars IFACE=$IFACE
echo "Lab interface: $IFACE"
# Remove every profile bound to the lab NIC, then add a bad one
for c in $(nmcli -g UUID,DEVICE con show | awk -F: -v i="$IFACE" '$2==i{print $1}'); do nmcli con delete "$c" >/dev/null; done
for c in $(nmcli -g NAME con show | grep -E '^(lab-static|lab-old|System '"$IFACE"'|Wired connection)'); do nmcli con delete "$c" >/dev/null 2>&1 || true; done
nmcli con add type ethernet con-name lab-old ifname "$IFACE" ipv4.method manual ipv4.addresses 10.0.0.5/8 \
  ipv6.method disabled connection.autoconnect yes >/dev/null
nmcli con up lab-old >/dev/null 2>&1 || true
hostnamectl set-hostname rhcsa-old
sed -i '/serverb/d' /etc/hosts
systemctl disable --now httpd >/dev/null 2>&1 || true
echo '<h1>lab09</h1>' > /var/www/html/index.html
systemctl enable --now firewalld >/dev/null
for s in http https; do firewall-cmd -q --permanent --remove-service=$s 2>/dev/null || true; done
firewall-cmd -q --permanent --remove-port=8443/tcp 2>/dev/null || true
firewall-cmd -q --reload
