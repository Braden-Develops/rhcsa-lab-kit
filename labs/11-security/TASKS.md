# Lab 11: Manage security

1. **SELinux mode.** Put SELinux in **enforcing** mode now and at every boot.
2. **Contexts.** Write the SELinux **type** of the running `sshd` process into `/root/sshd-type.txt` and the type of
   `/etc/shadow` into `/root/shadow-type.txt` (just the type, e.g. `foo_t`).
3. **Non-standard web content + port.** httpd is configured to serve `/srv/www` on **port 82**
   (`/etc/httpd/conf.d/lab11.conf`). With SELinux enforcing, it breaks. Make it work **the SELinux way**
   (don't disable SELinux, don't use `chcon`): a persistent file-context rule for `/srv/www`, a port label,
   then restart httpd. `curl http://localhost:82/` must work and httpd must be enabled at boot.
4. **Restore default contexts.** `curl http://localhost/moved.html` returns 403. Fix it.
5. **Booleans.** Allow httpd to serve users' home directories (`httpd_enable_homedirs`), persistently.
6. **Firewall** (default zone, permanent and active now):
   - allow service **http** and port **82/tcp**
   - remove the **cockpit** service
   - **reject** all traffic from **192.168.50.99** with a rich rule
7. **Default permissions.** User `student` must get a umask of **027** at every login
   (new files 640, new directories 750).
8. **SSH keys.** Set up **key-based** SSH so `student` can log in to `sally@localhost` without a password
   (sally's password is `sally-pass`). Keep sally's `~/.ssh` permissions correct.
