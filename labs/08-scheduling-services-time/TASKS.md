# Lab 08: Deploy, configure and maintain systems (scheduling, services, targets, time)

> Software installation is in lab 02; modifying the bootloader is in the VM lab 05-boot.

1. **cron.**
   a. As user `natasha`, run `/usr/bin/logger "rhcsa-cron"` every day at **14:23**.
   b. As root, run `/usr/bin/date >> /var/log/heartbeat.log` **every 5 minutes, Monday to Friday**.
2. **at.** As user `student`, schedule `touch /tmp/at-ran` to run **2 hours from now**, using `at`.
3. **systemd timer.** Create `cleanup.service` (runs `/usr/local/bin/cleanup.sh`) and `cleanup.timer`
   (in `/etc/systemd/system`) that triggers it **every 15 minutes**. The timer must be running and enabled at boot.
4. *Broken:* `labapp.service` failed. Fix the unit (the program lives in `/usr/local/bin`), start it,
   and make it start at boot.
5. **Default target.** This is a server: make it boot into the text-mode multi-user target by default.
6. **Time client.** *Broken:* the time service is unusable. Configure chrony to use **only** the server
   `classroom.lab.example.com` (with `iburst`), and make sure chronyd is enabled and starts at boot.
   Set the time zone to `America/Chicago`.
   (Inside a container chronyd can't actually steer the clock; the grader checks your configuration.)
