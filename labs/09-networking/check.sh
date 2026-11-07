#!/bin/bash
. /opt/labkit/lib/check.sh
. /opt/labkit/lib/vm.sh; load_vars
g() { nmcli -g "$1" con show lab-static 2>/dev/null; }
section "Task 1: lab-static"
check "profile lab-static exists on $IFACE" '[ "$(g connection.interface-name)" = "$IFACE" ]'
check "IPv4 192.168.50.10/24 manual" '[ "$(g ipv4.method)" = manual ] && g ipv4.addresses | grep -q "192.168.50.10/24"'
check "IPv6 2001:db8:50::10/64 manual" '[ "$(g ipv6.method)" = manual ] && g ipv6.addresses | grep -q "2001:db8:50::10/64"'
check "DNS search lab.example.com" 'g ipv4.dns-search | grep -q lab.example.com || g ipv6.dns-search | grep -q lab.example.com'
check "autoconnect yes" '[ "$(g connection.autoconnect)" = yes ]'
check "addresses are live on $IFACE" 'ip -4 addr show $IFACE | grep -q 192.168.50.10/24 && ip -6 addr show $IFACE | grep -q 2001:db8:50::10/64'
section "Task 2: lab-old"
check "lab-old is gone" '! nmcli con show lab-old'
check "10.0.0.5 not configured" '! ip addr show $IFACE | grep -q 10.0.0.5'
section "Task 3: hostname"
check "static hostname servera.lab.example.com" '[ "$(hostnamectl hostname --static 2>/dev/null || cat /etc/hostname)" = servera.lab.example.com ]'
section "Task 4: name resolution"
check "serverb resolves to 192.168.50.20" 'getent ahostsv4 serverb | grep -q 192.168.50.20'
check "serverb.lab.example.com resolves to 2001:db8:50::20" 'getent ahostsv6 serverb.lab.example.com | grep -q 2001:db8:50::20'
section "Task 5: httpd"
check "httpd active and enabled" 'systemctl is-active httpd && systemctl is-enabled httpd'
check "serves the lab page on 192.168.50.10" 'curl -s --max-time 3 http://192.168.50.10/ | grep -q lab09'
section "Task 6: firewall"
z=$(firewall-cmd --get-default-zone 2>/dev/null)
check "http+https permanent" 'firewall-cmd --permanent --zone=$z --list-services | grep -qw http && firewall-cmd --permanent --zone=$z --list-services | grep -qw https'
check "8443/tcp permanent" 'firewall-cmd --permanent --zone=$z --list-ports | grep -qw 8443/tcp'
check "all three active now (runtime)" 'firewall-cmd --zone=$z --list-services | grep -qw https && firewall-cmd --zone=$z --list-ports | grep -qw 8443/tcp'
summary
