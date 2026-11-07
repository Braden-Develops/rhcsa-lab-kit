# Lab 02: Manage software

1. *Broken:* every `dnf` command fails. Find the repository causing it and **disable** it (don't delete the file).
2. *Broken:* `/etc/yum.repos.d/internal.repo` should provide packages from the local repository in
   `/srv/repos/internal`. The packages are unsigned. Fix the repo definition. `labtool` 1.0 is installed:
   **update** it from the repository to the newest version (1.1).
3. Create a new repository definition named `extras` (file `/etc/yum.repos.d/extras.repo`) for the repository in
   `/srv/repos/extras`, with GPG checking off, and install `labextra` from it.
4. Install the package file `/root/rpms/hello-lab-2.0-1.noarch.rpm` from the local file system with `dnf`.
5. Remove the package `tree`.
6. Find out which package provides the file `/usr/bin/crontab` and write the package **name** (no version)
   into `/root/crontab-pkg.txt`.
7. **Flatpak repositories.** Add the Flathub remote **system-wide** under the name `flathub`
   (`https://dl.flathub.org/repo/flathub.flatpakrepo`).
8. **Flatpak packages.** Install the app `org.gnome.Calculator` from `flathub` (system-wide), confirm it with
   `flatpak list --app`, then **uninstall** it. The grader reads `flatpak history`.
   Heads-up: the first install pulls the GNOME runtime (around 1 GB). Apps can't *run* in this container,
   but installing and removing works. If your container engine blocks it, do tasks 7 and 8 in the lab VM instead.
9. **Red Hat CDN (read only, no grader).** On real RHEL, software comes from the Red Hat CDN after
   `subscription-manager register`. Read the "CDN" note in the solution so you know the commands.
