# Lecture 8: Manage basic networking

Networking tasks on the exam are short to type but unforgiving: one wrong prefix length, a profile that is not set
to autoconnect, or a firewall rule added only to the runtime configuration, and a service that worked when you
tested it is unreachable after the reboot. This lecture builds the concepts first (addresses, prefixes, routes,
names) and then shows how RHEL 10 manages them with NetworkManager, how hostnames are resolved, how to make network
services start at boot, and how firewalld decides what traffic gets in.

Objective 10.1 (firewall settings) continues the firewalld material in Lecture 10 with zones, sources and rich
rules.

---

## Background: just enough TCP/IP

### Layers and addresses

Network traffic is built in layers, and each has its own addressing:

| Layer | Unit | Address | Example |
|---|---|---|---|
| Link (Ethernet, Wi-Fi) | frame | **MAC address**, 48 bits, burned into the NIC, local network only | `52:54:00:3a:1f:0c` |
| Network (IP) | packet | **IP address**, routable across networks | `192.168.50.10`, `2001:db8:50::10` |
| Transport (TCP, UDP) | segment | **port**, 0–65535, identifies the application | TCP 22 (ssh), TCP 80 (http), UDP 123 (ntp) |
| Application | message | names, URLs | `http://serverb.lab.example.com/` |

To reach `serverb:80`, a client resolves the **name** to an IP address (DNS or `/etc/hosts`), decides from its
**routing table** whether that address is on the local network or must go via a **gateway** (router), finds the
MAC address of the next hop (ARP for IPv4, Neighbour Discovery for IPv6), and sends the packet. On the server, the
**firewall** decides whether the packet is accepted, and the kernel hands it to whatever process **listens** on
port 80.

When something doesn't work, troubleshoot in that order: name → address → route → firewall → listening service.

### IPv4 addresses and prefixes

An IPv4 address is 32 bits, written as four decimal octets. It is split into a **network part** and a **host part**
by the **prefix length** (CIDR notation, `/24`) or equivalently the **netmask** (`255.255.255.0`):

```text
192.168.50.10/24
├─ network:   192.168.50.0      (first 24 bits)
├─ hosts:     192.168.50.1 – 192.168.50.254
└─ broadcast: 192.168.50.255
```

Hosts with the same network part talk directly; anything else goes via a gateway. Common prefixes:

| Prefix | Netmask | Addresses | Usable hosts |
|---|---|---|---|
| /8 | 255.0.0.0 | 16,777,216 | 16,777,214 |
| /16 | 255.255.0.0 | 65,536 | 65,534 |
| /24 | 255.255.255.0 | 256 | 254 |
| /25 | 255.255.255.128 | 128 | 126 |
| /26 | 255.255.255.192 | 64 | 62 |
| /28 | 255.255.255.240 | 16 | 14 |
| /30 | 255.255.255.252 | 4 | 2 |
| /32 | 255.255.255.255 | 1 | a single host |

Private ranges (not routed on the internet): `10.0.0.0/8`, `172.16.0.0/12`, `192.168.0.0/16`. `127.0.0.0/8` is
loopback (`127.0.0.1` = this machine). `169.254.0.0/16` is link-local, auto-assigned when DHCP fails, so seeing it
is a symptom.

Getting the prefix wrong is a real failure: `192.168.50.10/16` makes the host think the whole `192.168.x.x` range
is local, so it never uses the gateway for `192.168.60.5`.

### IPv6 addresses

IPv6 addresses are 128 bits, written as eight groups of four hex digits:

```text
2001:0db8:0050:0000:0000:0000:0000:0010
2001:db8:50::10            (leading zeros dropped; one run of zero groups replaced by ::)
```

`::` may appear only once in an address. Prefixes work the same way; on LANs the prefix is almost always **/64**
(network part 64 bits, interface ID 64 bits).

| Address | Meaning |
|---|---|
| `::1/128` | loopback |
| `fe80::/10` | **link-local**: every IPv6 interface automatically has one; valid only on that link |
| `2000::/3` | global unicast (internet-routable) |
| `fd00::/8` | unique local (private, like 10/8) |
| `2001:db8::/32` | reserved for documentation and examples (and exams) |
| `ff00::/8` | multicast (IPv6 has no broadcast) |

IPv6 hosts can configure themselves with **SLAAC** (stateless address autoconfiguration, from router
advertisements), with **DHCPv6**, or manually. An interface typically has several IPv6 addresses at once (link-local
plus global), which is normal. Link-local addresses need the interface when used: `ping fe80::1%eth1`.

### Routes, gateways and DNS servers

The **routing table** lists destinations and how to reach them. A host normally has a route for each directly
connected network, and a **default route** (`0.0.0.0/0`, written `default`) via the gateway for everything else.

```text
$ ip route
default via 192.168.122.1 dev enp1s0 proto dhcp metric 100
192.168.50.0/24 dev enp7s0 proto kernel scope link src 192.168.50.10 metric 101
192.168.122.0/24 dev enp1s0 proto kernel scope link src 192.168.122.88 metric 100
```

The gateway must be on a directly connected network. A **metric** breaks ties when several routes match: lower wins.
`ip route get 8.8.8.8` shows which route and source address a destination would use.

**DNS servers** translate names to addresses. Their addresses are part of the network configuration too.

### Interface names

RHEL uses **predictable network interface names** based on hardware location: `enp1s0` (Ethernet, PCI bus 1,
slot 0), `ens3` (hot-plug slot 3), `eno1` (onboard), `wlp2s0` (wireless). Virtual machines and clouds may show
`eth0`. `lo` is loopback. Names are stable across reboots unless hardware moves, unlike the old `eth0`/`eth1`
ordering. `ip link` lists them.

---

## 8.1 Configure IPv4 and IPv6 addresses

### NetworkManager's model: devices and connections

On RHEL, networking is managed by **NetworkManager** (the `NetworkManager` service). Its central idea, and the one
people trip on, is the separation of:

- **Devices**: the network interfaces that exist (`enp1s0`, `enp7s0`, `lo`).
- **Connections** (connection **profiles**): named collections of settings: which device (or which MAC) they apply
  to, IPv4 and IPv6 method and addresses, gateway, DNS, autoconnect behaviour, and so on.

A device has **at most one active connection** at a time, and you can have several profiles for the same device
(for example "office" and "home"), activating whichever you need. **Addresses belong to the connection, not the
device.** Configuration is done by creating or modifying a connection and then **activating** it on a device.

On RHEL 10, connection profiles are stored only in **keyfile** format, in
`/etc/NetworkManager/system-connections/NAME.nmconnection` (mode 0600, owned by root). The old
`/etc/sysconfig/network-scripts/ifcfg-*` files are no longer supported. Profiles created at runtime but not saved
live under `/run/NetworkManager/system-connections/`. You can read a keyfile to understand a profile:

```ini
[connection]
id=lab-static
uuid=3c6c...
type=ethernet
interface-name=enp7s0
autoconnect=true

[ipv4]
method=manual
address1=192.168.50.10/24
dns-search=lab.example.com;

[ipv6]
method=manual
address1=2001:db8:50::10/64
```

You may edit keyfiles by hand, then run `nmcli connection reload` (and reactivate) for NetworkManager to notice, but
`nmcli` is safer: it validates settings.

### Looking at the current state

```bash
nmcli general status
nmcli device                         # = nmcli device status: DEVICE TYPE STATE CONNECTION
nmcli connection                     # = nmcli con show: NAME UUID TYPE DEVICE (active ones have a DEVICE)
nmcli connection show --active
nmcli connection show lab-static     # every setting of a profile (long), and active IPs at the end
nmcli -f ipv4,ipv6 con show lab-static
nmcli device show enp7s0             # addresses, gateway, DNS actually in use on the device
ip -br addr                          # brief: device, state, addresses
ip addr show enp7s0
ip -6 addr
ip route ; ip -6 route
```

The `ip` command (from `iproute2`) shows and can change the kernel's live state, but changes made with `ip addr add`
are **not persistent** and NetworkManager may overwrite them. Use `ip` to look and `nmcli` to configure.

### Creating a static connection

```bash
nmcli connection add type ethernet con-name lab-static ifname enp7s0 \
    ipv4.method manual ipv4.addresses 192.168.50.10/24 ipv4.gateway 192.168.50.1 \
    ipv4.dns 192.168.50.1 ipv4.dns-search lab.example.com \
    ipv6.method manual ipv6.addresses 2001:db8:50::10/64 ipv6.gateway 2001:db8:50::1 \
    connection.autoconnect yes
nmcli connection up lab-static
```

- `type ethernet`, `con-name` (the profile name you choose) and `ifname` (the device it binds to).
- `ipv4.method`: **`manual`** (static), `auto` (DHCP), `disabled`, `link-local`, `shared` (share the connection
  to others via NAT).
- `ipv6.method`: `manual`, `auto` (SLAAC, plus DHCPv6 if the router says so), `dhcp` (DHCPv6 only), `ignore`,
  `disabled`, `link-local`.
- `ipv4.addresses` takes **CIDR** notation; leaving off `/24` gives a `/32` (single host), a quiet but serious mistake.
- Several addresses or DNS servers: comma-separated (`ipv4.dns "192.168.50.1,192.168.50.2"`).
- `autoconnect yes` is the default for new profiles, but saying it explicitly costs nothing.

The `nmcli con add` command line is long. Tab completion works for property names and values, and
`man nmcli-examples` has complete examples you can adapt in the exam.

### Modifying a connection

```bash
nmcli connection modify lab-static ipv4.addresses 192.168.50.11/24      # replace
nmcli connection modify lab-static +ipv4.addresses 192.168.50.12/24     # add another
nmcli connection modify lab-static -ipv4.addresses 192.168.50.12/24     # remove one
nmcli connection modify lab-static ipv4.gateway ""                      # clear
nmcli connection modify lab-static ipv4.method auto ipv4.addresses "" ipv4.gateway ""   # back to DHCP
nmcli connection modify "System eth0" connection.id eth0                # rename a profile
nmcli connection up lab-static                                          # APPLY the change
```

**Modifying a profile changes the saved settings, not the live interface.** The change takes effect the next time
the profile is activated: `nmcli con up NAME` (or `nmcli device reapply DEV`), or at the next boot. Forgetting this
leads to "I changed it, but `ip addr` still shows the old address".

Two settings that come up:

- `ipv4.ignore-auto-dns yes` (and `ipv6.ignore-auto-dns yes`): on a DHCP connection, use only the DNS servers you
  configured, ignoring those from DHCP.
- `connection.autoconnect-priority N`: when several profiles could autoconnect on the same device, the highest
  priority wins.

### Other operations

```bash
nmcli connection down lab-static
nmcli connection delete lab-old            # remove a profile (and its keyfile)
nmcli device disconnect enp7s0             # and stop autoconnecting until told otherwise
nmcli device connect enp7s0
nmcli connection reload                    # re-read keyfiles edited by hand
nmcli networking off ; nmcli networking on
nmcli radio wifi off
nmtui                                      # text UI: edit, activate, set hostname
```

### Two profiles, one device

A classic planted fault: an old profile for the same device still exists with `autoconnect yes`. At boot,
NetworkManager picks one of them (by priority, then most recently used), and it may not be yours. Symptoms: your
settings work after `nmcli con up` but are gone after reboot. Fix: `nmcli con show` to spot duplicates, then delete
the stale profile, or set it to `autoconnect no`.

### Testing connectivity

```bash
ping -c3 192.168.50.20           # IPv4 reachability (ICMP)
ping -c3 2001:db8:50::20         # IPv6 (ping6 is the same as ping -6)
ping -c3 serverb                 # also tests name resolution
tracepath 8.8.8.8                # path, hop by hop (traceroute if installed)
ip neigh                         # ARP / neighbour cache: did we reach the MAC of the next hop?
ss -tlnp                         # what's listening locally (Lecture 4)
curl -v http://serverb/          # end-to-end test of a web service
```

> **Exam angle.** Use `nmcli` (or `nmtui` if you prefer menus). After configuring, check `ip -br addr`,
> `ip route`, `cat /etc/resolv.conf`, and `nmcli con show NAME | grep autoconnect`. Reboot once to prove it.
> If you are working over SSH on the interface you are changing, a mistake disconnects you; on the exam, use the
> console for network changes on the main interface.

---

## 8.2 Configure hostname resolution

### Hostnames

A system has a **hostname**. systemd distinguishes three kinds:

- **static**: stored in `/etc/hostname`, used at boot. This is the one you set on the exam.
- **transient**: the kernel's current hostname, which DHCP or NetworkManager may set if there is no static one.
- **pretty**: a free-form display name ("Braden's Lab Server").

```bash
hostnamectl                                       # all of them, plus OS, kernel, hardware
hostnamectl hostname servera.lab.example.com      # set static (and transient) hostname
hostnamectl set-hostname servera.lab.example.com  # older spelling, same effect
hostname                                          # current
hostname -s ; hostname -f                         # short name; fully qualified name
cat /etc/hostname
```

A **fully qualified domain name** (FQDN) such as `servera.lab.example.com` is the short name plus the DNS domain.
Set the FQDN when the task gives one. The change is immediate for new shells; your current prompt updates at your
next login.

### How a name becomes an address

Programs call the C library resolver (`getaddrinfo`), which consults the sources listed on the `hosts:` line of
**`/etc/nsswitch.conf`** (the Name Service Switch) in order:

```text
hosts:      files dns myhostname
```

- **`files`**: `/etc/hosts`.
- **`dns`**: the DNS servers listed in `/etc/resolv.conf`.
- **`myhostname`**: systemd's module that always resolves the machine's own hostname and `localhost`.

The first source that gives an answer wins, so an entry in `/etc/hosts` overrides DNS.

**`/etc/hosts`** maps addresses to names, one address per line, canonical name first, then aliases:

```text
127.0.0.1         localhost localhost.localdomain localhost4
::1               localhost localhost.localdomain localhost6
192.168.50.20     serverb.lab.example.com serverb
2001:db8:50::20   serverb.lab.example.com serverb
```

It is consulted for every lookup, needs no service, and takes effect immediately. It is ideal for small labs and
exam tasks ("make serverb resolve to ...").

**`/etc/resolv.conf`** tells the resolver which DNS servers to ask:

```text
# Generated by NetworkManager
search lab.example.com
nameserver 192.168.50.1
nameserver 192.168.50.2
```

- `nameserver`: up to three DNS servers, tried in order.
- `search`: domains appended to short names, so `ping serverb` tries `serverb.lab.example.com`.

On RHEL, **NetworkManager writes this file** from the active connections' DNS settings. If you edit it by hand,
NetworkManager overwrites it on the next connection change. The persistent way is to set DNS on the connection:

```bash
nmcli con mod lab-static ipv4.dns "192.168.50.1 192.168.50.2" ipv4.dns-search lab.example.com
nmcli con mod lab-static ipv4.ignore-auto-dns yes     # if it's a DHCP profile and you want only yours
nmcli con up lab-static
cat /etc/resolv.conf
```

### Testing name resolution: the right tool

```bash
getent hosts serverb          # uses nsswitch, exactly like real programs: files, then dns
getent ahosts serverb         # all addresses (IPv4 and IPv6)
ping -c1 serverb
host serverb.lab.example.com  # DNS only (bind-utils): ignores /etc/hosts!
dig serverb.lab.example.com   # DNS only, detailed
dig -x 192.168.50.20          # reverse lookup
```

`host`, `dig` and `nslookup` talk to DNS servers directly and **bypass `/etc/hosts`**. If you added a hosts entry
and `dig` doesn't show it, that's expected; `getent hosts` is the correct test.

> **Exam angle.** "Set the hostname to X" → `hostnamectl hostname X`; check `hostname` and `/etc/hostname`.
> "Make name Y resolve to address Z" → `/etc/hosts`; check with `getent hosts Y`. "Use DNS server D" →
> `ipv4.dns` on the connection; check `/etc/resolv.conf`.

---

## 8.3 Configure network services to start automatically at boot

"A network service starts automatically at boot and is reachable" involves four separate things, and a task can
fail on any of them:

1. **The connection comes up at boot**: the profile has `connection.autoconnect yes` and is the one that wins for
   that device (8.1). Check with `nmcli -f connection.autoconnect con show NAME`.
2. **The service is enabled**: `systemctl enable --now httpd` (Lecture 7, 7.2). Check `systemctl is-enabled`.
3. **The firewall allows it**, permanently: `firewall-cmd --permanent --add-service=http; firewall-cmd --reload`
   (8.4).
4. **SELinux allows it**, if it uses a non-standard port or directory: `semanage port` / `semanage fcontext`
   (Lecture 10).

### Services that need the network to be up

Some services fail if they start before the network is configured (binding to a specific address, mounting NFS,
contacting a server). systemd provides targets for ordering:

- `network.target`: network management has *started* (not necessarily configured).
- `network-online.target`: the network is *configured and up*. NetworkManager supports this through
  `NetworkManager-wait-online.service`, which waits (by default up to a timeout) for connections to come up.

A service needing a working network declares `Wants=network-online.target` and `After=network-online.target` in
its unit. NFS mounts in fstab get this automatically via `_netdev`/the `nfs` type. You rarely need to change it,
but knowing it explains why an NFS mount or a service bound to a static IP fails at boot when the network profile
is broken.

### NetworkManager itself

`NetworkManager.service` must be enabled (it is by default). If someone disabled it, nothing configures interfaces at
boot. `systemctl is-enabled NetworkManager`.

### Verify like the grader

```bash
systemctl is-enabled httpd ; systemctl is-active httpd
ss -tlnp | grep ':80 '
firewall-cmd --list-services
curl -s http://localhost/ | head -3            # locally
# and from another machine: curl http://servera.lab.example.com/
```

Then reboot and run the same checks.

---

## 8.4 Restrict network access using firewalld and firewall-cmd

### What a host firewall does

Every packet arriving at the machine passes through the kernel's packet filter, **netfilter**, which RHEL 10
programs with **nftables**. Rules decide whether each incoming connection is accepted, rejected (with an error back
to the sender) or dropped (silently). Replies to connections the machine itself started are allowed automatically
because netfilter tracks connection state.

Writing nftables rules by hand is possible but error-prone. **firewalld** is a service that manages them for you
using higher-level concepts, can change them without dropping existing connections, and is controlled with
`firewall-cmd` (or the web console). It is installed, enabled and running by default on RHEL.

### Zones

firewalld groups rules into **zones**: named trust levels. Each zone has a list of allowed **services** and
**ports**, and a default behaviour (target) for everything else. Every incoming packet is handled by exactly one
zone, chosen like this:

1. If the packet's **source address** matches a source assigned to a zone, that zone.
2. Otherwise, the zone the **interface** it arrived on is assigned to.
3. Otherwise, the **default zone**.

On a fresh RHEL system all interfaces are in the default zone, **`public`**, so in practice you work there unless
told otherwise.

| Zone | Default behaviour |
|---|---|
| `drop` | drop everything incoming, no reply |
| `block` | reject everything incoming |
| `public` | **default**: reject except selected services (ssh, dhcpv6-client, cockpit) |
| `external` | for a router's outside interface; masquerading on |
| `dmz` | only ssh |
| `work`, `home`, `internal` | progressively more trusted defaults |
| `trusted` | accept everything |

### Services and ports

A firewalld **service** is a named definition of the ports (and sometimes helper modules) an application needs:
`http` = TCP 80, `https` = TCP 443, `ssh` = TCP 22, `nfs` = TCP 2049, `dns` = TCP/UDP 53, `ntp` = UDP 123.
Definitions are XML files in `/usr/lib/firewalld/services/` (yours in `/etc/firewalld/services/`).

```bash
firewall-cmd --get-services                      # all known service names
firewall-cmd --info-service=nfs                  # ports it opens
```

Prefer services over raw ports: they are self-documenting and include everything the application needs. Use
`--add-port` for a port that has no service definition, or a non-standard port (e.g. 8443/tcp).

### Runtime versus permanent: the concept that costs marks

firewalld keeps **two** configurations:

- **Runtime**: what is in effect right now in the kernel. Changes take effect immediately and are **lost** on
  `--reload`, a service restart, or a reboot.
- **Permanent**: stored in `/etc/firewalld/` (zones in `/etc/firewalld/zones/*.xml`). Changes take effect only
  after `--reload` (or a restart or reboot).

`firewall-cmd` without `--permanent` changes runtime only. With `--permanent` it changes the stored config only.
To get both, use one of these patterns:

```bash
# A) permanent, then reload (reload discards runtime-only changes and loads permanent)
firewall-cmd --permanent --add-service=http
firewall-cmd --reload

# B) runtime first (test it), then save everything currently in runtime
firewall-cmd --add-service=http
firewall-cmd --runtime-to-permanent

# C) both explicitly
firewall-cmd --add-service=http
firewall-cmd --permanent --add-service=http
```

Pattern A is the simplest to remember. Just be aware that `--reload` throws away any runtime-only changes you made
earlier.

### Everyday commands

```bash
firewall-cmd --state                             # running?
firewall-cmd --get-default-zone                  # public
firewall-cmd --get-active-zones                  # zones with interfaces or sources
firewall-cmd --list-all                          # everything in the default zone (runtime)
firewall-cmd --list-all --permanent              # the saved version: compare the two!
firewall-cmd --list-services ; firewall-cmd --list-ports

firewall-cmd --permanent --add-service={http,https}      # bash brace expansion: two services
firewall-cmd --permanent --add-port=8443/tcp
firewall-cmd --permanent --add-port=5000-5010/udp
firewall-cmd --permanent --remove-service=cockpit
firewall-cmd --permanent --remove-port=8443/tcp
firewall-cmd --reload

firewall-cmd --zone=internal --list-all          # any command can target a zone explicitly
firewall-cmd --query-service=http                # yes/no
```

Reading `--list-all`:

```text
public (active)
  target: default
  icmp-block-inversion: no
  interfaces: enp1s0 enp7s0
  sources:
  services: cockpit dhcpv6-client http https ssh
  ports: 8443/tcp
  protocols:
  forward: yes
  masquerade: no
  forward-ports:
  source-ports:
  icmp-blocks:
  rich rules:
```

`target: default` in `public` means "reject what isn't allowed" (with ICMP errors). The `(active)` marker means the
zone has interfaces or sources.

### Not just the firewall

firewalld controls **incoming** connections to this host. A service that is allowed but still unreachable may not be
running, may listen only on `127.0.0.1` (`ss -tlnp`), may be blocked by SELinux (non-standard port, Lecture 10), or
the client may have the wrong address or route. Conversely, never fix "unreachable" by stopping firewalld; the exam
checks that it is running.

> **Exam angle.** "Allow HTTP and HTTPS through the firewall, persistently" →
> `firewall-cmd --permanent --add-service={http,https}; firewall-cmd --reload`, then compare
> `--list-all` and `--list-all --permanent`. If a task opens a custom port for a web server, SELinux needs
> `semanage port` too (Lecture 10, 10.7).

---

## Putting it together

A complete network task, *"Configure servera with a static address 192.168.50.10/24 and 2001:db8:50::10/64 on
enp7s0, hostname servera.lab.example.com, make serverb resolvable, and serve the default web page through the
firewall"*:

```bash
nmcli con show                                                # any old profile on enp7s0?
nmcli con delete lab-old                                      # remove it if so
nmcli con add type ethernet con-name lab-static ifname enp7s0 \
    ipv4.method manual ipv4.addresses 192.168.50.10/24 \
    ipv6.method manual ipv6.addresses 2001:db8:50::10/64 \
    ipv4.dns-search lab.example.com connection.autoconnect yes
nmcli con up lab-static
hostnamectl hostname servera.lab.example.com
cat >> /etc/hosts <<'EOF'
192.168.50.20     serverb.lab.example.com serverb
2001:db8:50::20   serverb.lab.example.com serverb
EOF
dnf install -y httpd && systemctl enable --now httpd
firewall-cmd --permanent --add-service={http,https} && firewall-cmd --reload

ip -br addr show enp7s0; getent hosts serverb; curl -s localhost | head -2; firewall-cmd --list-services
```

Then reboot and check again.

**Now practise:** [Lab 09](#/lab/09) on the VM, including a stale profile that steals the interface at boot.

## Review questions

1. What are the network address, broadcast address and number of usable hosts of `10.20.30.40/26`?
2. Write `2001:0db8:0000:0000:0000:ff00:0042:8329` in shortest form.
3. What is a link-local IPv6 address and why does every interface have one?
4. In NetworkManager, what is the difference between a device and a connection?
5. Where are connection profiles stored on RHEL 10, and in what format?
6. You ran `nmcli con mod NAME ipv4.addresses ...` but `ip addr` shows the old address. Why?
7. What happens if you configure `ipv4.addresses 192.168.50.10` without a prefix?
8. A static IP works until reboot, then the interface has a different address. What's a likely cause?
9. Explain the `hosts:` line in `/etc/nsswitch.conf`.
10. You added serverb to `/etc/hosts` but `dig serverb` fails. Is that a problem? What should you test with?
11. Why shouldn't you edit `/etc/resolv.conf` by hand, and what should you do instead?
12. List four things that must all be right for a web server to be reachable after a reboot.
13. How does firewalld choose which zone handles an incoming packet?
14. Explain runtime versus permanent configuration, and two ways to end up with a rule in both.
15. Why prefer `--add-service=http` over `--add-port=80/tcp`?

<details><summary>Answers</summary>

1. /26 = blocks of 64. 40 falls in 0–63: network `10.20.30.0`, broadcast `10.20.30.63`, 62 usable hosts.
2. `2001:db8::ff00:42:8329`.
3. An address in `fe80::/10`, automatically created on every IPv6 interface and valid only on that link; IPv6 uses
   it for neighbour discovery and router communication.
4. A device is a network interface; a connection is a named profile of settings applied to a device when activated.
5. `/etc/NetworkManager/system-connections/*.nmconnection`, keyfile (INI) format.
6. Modifying changes the saved profile only; reactivate with `nmcli con up NAME` (or reboot).
7. It becomes a `/32`: a single host with no local network, so nothing else is reachable directly.
8. Another profile for the same device also autoconnects and won at boot. Delete it or disable its autoconnect.
9. It lists the sources the resolver tries for host names, in order: e.g. `files` (`/etc/hosts`), then `dns`, then
   `myhostname`.
10. No: `dig` queries DNS only and ignores `/etc/hosts`. Test with `getent hosts serverb`.
11. NetworkManager regenerates it. Set `ipv4.dns`/`ipv4.dns-search` (and `ignore-auto-dns` if needed) on the
    connection and reactivate it.
12. The connection autoconnects with the right address; the service is enabled; the firewall permanently allows it;
    SELinux allows its port/content (and it listens on the right address).
13. Source address match first, then the interface's zone, then the default zone.
14. Runtime is active now and lost on reload/reboot; permanent is saved and applied on reload. Use `--permanent`
    then `--reload`, or a runtime change then `--runtime-to-permanent`.
15. Service definitions are self-documenting and include every port/helper the application needs.

</details>
