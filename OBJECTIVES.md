# EX200 objectives → study guide → labs

Source: Red Hat, *Red Hat Certified System Administrator (RHCSA) exam (EX200)*, exam objectives for **RHEL 10**,
<https://www.redhat.com/training/courses/ex200/examobjective> (also listed on the EX200 course page).
Page last published 2026-09-16; fetched and checked 2026-11-07. **62 objective lines in 10 sections.**
Red Hat adds: *"As with all Red Hat performance-based exams, configurations must persist after reboot without intervention."*

Every line below has a numbered row in `STUDY-GUIDE.md` and at least one graded lab task (exceptions noted).
Red Hat changes this page from time to time: re-check it before booking your exam.


## 1. Understand and use essential tools

| # | Objective (verbatim) | Lab task(s) |
|---|---|---|
| 1.1 | Access a shell prompt and issue commands with correct syntax | every lab; 05 task 8 (console) (implicit everywhere) |
| 1.2 | Use input-output redirection (>, >>, \|, 2>, etc.) | 01 task 2 |
| 1.3 | Use grep and regular expressions to analyze text | 01 task 1 |
| 1.4 | Access remote systems using SSH | 01 task 6 |
| 1.5 | Log in and switch users in multi-user targets | 01 task 8; 05 task 8 |
| 1.6 | Archive, compress, unpack, and uncompress files using tar, gzip, and bzip2 | 01 task 3 |
| 1.7 | Create and edit text files | 01 task 9 |
| 1.8 | Create, delete, copy, and move files and directories | 01 task 10 |
| 1.9 | Create hard and soft links | 01 task 4 |
| 1.10 | List, set, and change standard ugo/rwx permissions | 01 task 5 |
| 1.11 | Locate, read, and use system documentation including man, info, and files in /usr/share/doc | 01 task 7 |

## 2. Manage software

| # | Objective (verbatim) | Lab task(s) |
|---|---|---|
| 2.1 | Configure access to RPM repositories | 02 tasks 1–3 |
| 2.2 | Install and remove RPM software packages | 02 tasks 2–6 |
| 2.3 | Configure access to Flatpak repositories | 02 task 7 |
| 2.4 | Install and remove Flatpak software packages | 02 task 8 |

## 3. Create simple shell scripts

| # | Objective (verbatim) | Lab task(s) |
|---|---|---|
| 3.1 | Conditionally execute code (use of: if, test, [], etc.) | 03 tasks 1, 3, 4 |
| 3.2 | Use Looping constructs (for, etc.) to process file, command line input | 03 tasks 2, 4 |
| 3.3 | Process script inputs ($1, $2, etc.) | 03 tasks 1–4 |
| 3.4 | Processing output of shell commands within a script | 03 tasks 1, 3 |

## 4. Operate running systems

| # | Objective (verbatim) | Lab task(s) |
|---|---|---|
| 4.1 | Boot, reboot, and shut down a system normally | 05 tasks 1, 7, 9 |
| 4.2 | Boot systems into different targets manually | 05 task 6 |
| 4.3 | Interrupt the boot process in order to gain access to a system | 05 task 1 |
| 4.4 | Identify CPU/memory intensive processes and kill processes | 04 task 1 |
| 4.5 | Adjust process scheduling | 04 task 2 |
| 4.6 | Manage tuning profiles | 04 task 3 |
| 4.7 | Locate and interpret system log files and journals | 04 task 4 |
| 4.8 | Preserve system journals | 04 task 5 |
| 4.9 | Start, stop, and check the status of network services | 04 task 6 |
| 4.10 | Securely transfer files between systems | 04 task 7 |

## 5. Configure local storage

| # | Objective (verbatim) | Lab task(s) |
|---|---|---|
| 5.1 | List, create, and delete partitions on GPT disks | 06 tasks 1, 5, 6 |
| 5.2 | Create and remove physical volumes | 06 tasks 2, 5 |
| 5.3 | Assign physical volumes to volume groups | 06 tasks 2, 6 |
| 5.4 | Create and delete logical volumes | 06 tasks 3, 5 |
| 5.5 | Configure systems to mount file systems at boot by universally unique ID (UUID) or label | 06 tasks 1, 3, 4 |
| 5.6 | Add new partitions and logical volumes, and swap to a system non-destructively | 06 tasks 1, 3, 6 |

## 6. Create and configure file systems

| # | Objective (verbatim) | Lab task(s) |
|---|---|---|
| 6.1 | Create, mount, unmount, and use VFAT, ext4, and XFS file systems | 07 tasks 1, 6 |
| 6.2 | Mount and unmount network file systems using NFS | 07 tasks 3, 6 |
| 6.3 | Configure autofs | 07 task 4 |
| 6.4 | Extend existing logical volumes | 07 task 2 |
| 6.5 | Diagnose and correct file permission problems | 07 task 5; 01 tasks 4–5 |

## 7. Deploy, configure, and maintain systems

| # | Objective (verbatim) | Lab task(s) |
|---|---|---|
| 7.1 | Schedule tasks using at, cron and systemd timer units | 08 tasks 1–3 |
| 7.2 | Start and stop services and configure services to start automatically at boot | 08 task 4; 04 task 6 |
| 7.3 | Configure systems to boot into a specific target automatically | 08 task 5; 05 task 5 |
| 7.4 | Configure time service clients | 08 task 6 |
| 7.5 | Install and update software packages from Red Hat Content Delivery Network, a remote repository, or from the local file system | 02 tasks 2–4, 9 (CDN: guide only, needs a subscription) (CDN part: guide only (needs a Red Hat subscription)) |
| 7.6 | Modify the system bootloader | 05 tasks 2–4 |

## 8. Manage basic networking

| # | Objective (verbatim) | Lab task(s) |
|---|---|---|
| 8.1 | Configure IPv4 and IPv6 addresses | 09 task 1 |
| 8.2 | Configure hostname resolution | 09 tasks 3–4 |
| 8.3 | Configure network services to start automatically at boot | 09 task 5 |
| 8.4 | Restrict network access using firewalld and firewall-cmd | 09 task 6; 11 task 6 |

## 9. Manage users and groups

| # | Objective (verbatim) | Lab task(s) |
|---|---|---|
| 9.1 | Create, delete, and modify local user accounts | 10 tasks 2, 5–7 |
| 9.2 | Change passwords and adjust password aging for local user accounts | 10 tasks 2–3 |
| 9.3 | Create, delete, and modify local groups and group memberships | 10 tasks 1–2 |
| 9.4 | Configure privileged access | 10 task 4 |

## 10. Manage security

| # | Objective (verbatim) | Lab task(s) |
|---|---|---|
| 10.1 | Configure firewall settings using firewall-cmd/firewalld | 11 task 6; 09 task 6 |
| 10.2 | Manage default file permissions | 11 task 7 |
| 10.3 | Configure key-based authentication for SSH | 11 task 8 |
| 10.4 | Set enforcing and permissive modes for SELinux | 11 task 1 |
| 10.5 | List and identify SELinux file and process context | 11 task 2 |
| 10.6 | Restore default file contexts | 11 task 4; 05 task 1 |
| 10.7 | Manage SELinux port labels | 11 task 3 |
| 10.8 | Use Boolean settings to modify system SELinux settings | 11 task 5 |

## Changes made after checking against the official list (2026-11-07)

The original kit already followed this exact list, but these lines were only covered by the study guide or were
drilled partially, so labs were added or extended:

- **1.5** Log in and switch users: lab 01 task 8 (`su` chain, graded from the journal) and lab 05 task 8 (console tty login).
- **1.7** Create and edit text files: lab 01 task 9.
- **1.8** Create, delete, copy, and move: lab 01 task 10.
- **1.11** Documentation: lab 01 task 7 now also covers `info` and `/usr/share/doc` (`rpm -qd`); the container image now ships man pages and a `mandb` index (container base images strip them).
- **2.4** Install and remove Flatpaks: now graded (lab 02 task 8, via `flatpak history`).
- **4.1** Shut down normally: lab 05 task 7 (graded clean power-off).
- **4.4** Memory-intensive processes: lab 04 task 1b.
- **4.9** Stop a network service: lab 04 task 6b.
- **5.3** Assign PVs to an existing VG (`vgextend`): lab 06 task 6.
- **6.1 / 6.2** Unmount local and NFS file systems (including a busy mount): lab 07 task 6.
- **7.5** *Update* (not just install) from a repository: lab 02 task 2; CDN commands in lab 02 task 9 (ungraded).
