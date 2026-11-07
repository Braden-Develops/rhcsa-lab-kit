# RHCSA (EX200, RHEL 10) Lab Kit

A study guide plus 11 hands-on labs covering every objective of the current RHCSA exam. Each lab has a
working part to build, **broken scenarios to diagnose and fix**, an automatic **grader**, and a worked **solution**.

- `OBJECTIVES.md`: the 62 official objective lines (verbatim, from Red Hat's EX200 page) mapped to guide rows and lab tasks
- `STUDY-GUIDE.md`: every exam objective, the commands that matter, gotchas, and which lab drills it
- `labs/NN-name/`: `TASKS.md`, `setup.sh` (builds the scenario), `check.sh` (grader), `SOLUTION.md`,
  plus a `Dockerfile` for container labs
- `lab`: the launcher you run on your machine
- `vm/`: the Vagrant VM used by labs that need a real kernel and real reboots

## Containers or VM? Why both

| Lab | Runs in | Why |
|---|---|---|
| 01 Essential tools | container | pure userspace |
| 02 Software: dnf repos, RPMs, Flatpak | container | pure userspace |
| 03 Shell scripts | container | pure userspace |
| 04 Processes, tuning, journal, services, scp | container (systemd inside) | systemd runs fine as PID 1 in a container |
| **05 Boot: targets, root password reset, GRUB** | **VM** | a container has no bootloader and never boots |
| **06 Local storage: GPT, LVM, swap, fstab** | **VM** | LVM/partitions in a container act on your *host's* kernel and device-mapper (risky), and fstab-at-boot can't be tested |
| **07 File systems: VFAT/ext4/XFS, lvextend, NFS, autofs** | **VM** | same, plus kernel NFS client and autofs |
| 08 cron/at/timers, services, default target, chrony | container | config-level; chrony can't steer the clock in a container (the grader checks config) |
| **09 Networking: nmcli, hostname, firewalld** | **VM** | NetworkManager and nftables need their own network stack and kernel |
| 10 Users, groups, passwords, sudo | container | pure userspace |
| **11 Security: SELinux, firewalld, umask, SSH keys** | **VM** | SELinux is a kernel feature: a container can't have its own policy or mode |

The exam's golden rule is *"configurations must persist after reboot"*, which is another reason the VM matters:
the VM grader for storage/boot checks that you actually rebooted.

## Requirements

**Container labs:** Podman (preferred, it's what RHEL uses) or Docker, on Linux, macOS or Windows.
About 1 GB for the base image. Docker runs the containers `--privileged` because systemd needs cgroup access;
Podman runs them unprivileged with `--systemd=always`.

**VM labs:** [Vagrant](https://developer.hashicorp.com/vagrant/install) plus one provider:
- Linux: **libvirt/KVM** with the `vagrant-libvirt` plugin (best), or VirtualBox
- Windows / Intel Mac: VirtualBox (or VMware)
- Apple Silicon: VMware Fusion (or Parallels) with the arm64 AlmaLinux 10 box: set `LAB_BOX` accordingly

The VM uses 2 GB RAM, 2 vCPUs, a 20 GB system disk and three 5 GB lab disks. The box is `almalinux/10`
(a RHEL 10 rebuild). AlmaLinux 10 needs an x86-64-v3 CPU (roughly Intel Haswell / AMD Excavator, 2013+);
on older CPUs run `export LAB_BOX=almalinux/10-x86_64_v2`.

## Quick start

```bash
./lab list                 # all labs and where they run
./lab start 01             # builds the base image the first time (a few minutes), boots the lab, prints tasks
./lab shell 01             # root shell in the lab
./lab check 01             # grade yourself, as often as you like
./lab solution 01          # when you're stuck (try first!)
./lab reset 01             # throw it away and start fresh
./lab stop-all             # remove every lab container
```

VM labs use the same commands:

```bash
./lab start 06             # first time: creates the VM and a "clean" snapshot, then sets up lab 06
./lab shell 06             # vagrant ssh + sudo -i
sudo labctl tasks          # inside the VM, same as ./lab tasks 06
sudo labctl check          # grade from inside; reboot, then check again
./lab start 07             # rolls the VM back to the clean snapshot first, so labs never collide
```

Lab 05 (boot) needs the VM's **console**, not SSH: open the VM in `virt-manager` (libvirt) or set
`LAB_GUI=1` before `vagrant up`/`vagrant reload` for VirtualBox/VMware.

If snapshots aren't supported by your provider, recreate the VM instead: `cd vm && vagrant destroy -f && vagrant up`,
then `vagrant ssh -c "sudo labctl setup 06"`.

**Bring your own VM:** any RHEL 10 / AlmaLinux 10 / Rocky 10 VM with three spare disks and a second NIC works.
Copy `bin/ lib/ labs/` to `/opt/labkit`, run `sudo bash vm/provision.sh`, link `/opt/labkit/bin/labctl` into
`/usr/local/bin`, snapshot it, then `sudo labctl setup 06`. A free Red Hat Developer subscription gets you real RHEL.

## Suggested study plan (about 3 to 4 weeks at an hour a day)

1. Read a section of `STUDY-GUIDE.md`, then do its lab **without** the solution. Grade it.
2. Reset the lab and redo it the next day **from memory, against a timer**. Aim for every check passing.
3. When all 11 labs are green, redo the VM labs back-to-back (05, 06, 07, 09, 11), with a reboot after each, in
   under 2.5 hours total. That's roughly exam pace.

## How a lab works (if you want to write your own)

`setup.sh` runs once as root (in a container: at first boot through `labkit-setup.service`; in the VM:
`labctl setup`). `check.sh` sources `lib/check.sh` and calls `check "description" 'shell test'` for each
requirement, and `summary` prints the score. VM labs source `lib/vm.sh` for disk/NIC discovery; `{{DISK1}}`,
`{{IFACE}}` placeholders in TASKS/SOLUTION are filled in by `labctl`.

## Honest limits

- Graders check outcomes the way an examiner would, but they're not the real exam's scripts. Passing them
  means you did the task; it doesn't guarantee you did it exactly the way an unknown exam task words it.
- In containers a few things are only checked at the config level (chronyd, tuned may warn, Flatpak apps don't run).
- Inside a Docker container on macOS/Windows, systemd runs inside Docker Desktop's own Linux VM. That works,
  but if a container lab won't boot there, try Podman Desktop instead.

## Website

The study guide, objective checklist and labs are also published as a website at
<https://braden-develops.github.io/rhcsa-lab-kit/> (search, per-browser progress tracking, lab timers,
hidden solutions). It is served by GitHub Pages from `docs/`. After editing any guide or lab file, rebuild
the site's content bundle and commit it:

```bash
python3 tools/build-site.py      # regenerates docs/content.js
```
