# Lab 09 solution  (IFACE={{IFACE}})

```bash
# 1 + 2
nmcli con show                                   # see lab-old bound to {{IFACE}}
nmcli con delete lab-old
nmcli con add type ethernet con-name lab-static ifname {{IFACE}} \
  ipv4.method manual ipv4.addresses 192.168.50.10/24 \
  ipv6.method manual ipv6.addresses 2001:db8:50::10/64 \
  ipv4.dns-search lab.example.com connection.autoconnect yes
#   on the exam you'll usually also get: ipv4.gateway X ipv4.dns Y
nmcli con up lab-static
ip addr show {{IFACE}}
# 3
hostnamectl set-hostname servera.lab.example.com
# 4
cat >> /etc/hosts <<'H'
192.168.50.20     serverb.lab.example.com serverb
2001:db8:50::20   serverb.lab.example.com serverb
H
getent hosts serverb
# 5
dnf -y install httpd
systemctl enable --now httpd
# 6
firewall-cmd --permanent --add-service={http,https}
firewall-cmd --permanent --add-port=8443/tcp
firewall-cmd --reload                            # loads permanent config into runtime
firewall-cmd --list-all
```

**Notes.** Profiles are stored as keyfiles in `/etc/NetworkManager/system-connections/*.nmconnection` on RHEL 9/10
(no more `ifcfg` files). `nmcli con mod` changes a profile but the device only picks it up after
`nmcli con up <name>` (or a reboot). Name resolution order comes from `/etc/nsswitch.conf` (`files` = /etc/hosts
first), and DNS servers end up in `/etc/resolv.conf`, which NetworkManager manages. `firewall-cmd` without
`--permanent` changes only runtime; with it, only the saved config: so do both or use `--reload`
(or `--runtime-to-permanent`).
