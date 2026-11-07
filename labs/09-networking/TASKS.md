# Lab 09: Manage basic networking

The lab NIC is **{{IFACE}}**. Leave the first NIC (Vagrant's management network) alone.
Use `nmcli` (or `nmtui`); everything must persist across reboots.

1. Create a NetworkManager connection named **`lab-static`** on {{IFACE}}:
   - IPv4 **192.168.50.10/24**, manual (no gateway on this network)
   - IPv6 **2001:db8:50::10/64**, manual
   - DNS search domain **lab.example.com**
   - connects automatically at boot
2. *Broken:* an old profile `lab-old` with a wrong address grabs {{IFACE}} at boot. Get rid of it.
3. Set the persistent hostname to **servera.lab.example.com**.
4. Make **serverb.lab.example.com** (short name **serverb**) resolve locally to **192.168.50.20** and
   **2001:db8:50::20**.
5. Install (if needed), start and enable **httpd** so it serves its default page at boot.
6. In the default firewalld zone, **permanently** allow the services **http** and **https** and port **8443/tcp**,
   and make sure they're also allowed right now.
7. Bonus (ungraded): from your host machine, `curl http://192.168.50.10/` should show `lab09`.
