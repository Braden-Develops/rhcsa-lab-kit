# RHCSA lab base image: AlmaLinux 10 (a RHEL 10 rebuild) with real systemd as PID 1.
# ./lab builds this automatically; by hand:  docker build -t rhcsa-base:10 -f images/base/Dockerfile .
FROM docker.io/almalinux/10-init:latest

# Everyday admin tooling you'd find on an exam system
RUN dnf -y upgrade && dnf -y --setopt=strict=0 install procps-ng iproute iputils hostname sudo passwd shadow-utils \
        openssh-server openssh-clients vim-enhanced nano less man-db man-pages \
        which findutils file tar gzip bzip2 xz zip unzip rsync tree bash-completion \
        cronie at chrony tuned python3 lsof psmisc policycoreutils-python-utils \
        acl diffutils dnf-plugins-core info \
    # Container images ship without man pages for preinstalled packages: put them back,
    # then build the whatis database so `man -k` / `apropos` work (exam objective!)
    && (dnf -y --setopt=strict=0 reinstall '*' || true) \
    && mandb -q \
    && dnf clean all

# Units that make no sense in a container; services the labs expect
RUN systemctl mask systemd-remount-fs.service dev-hugepages.mount \
        sys-fs-fuse-connections.mount getty.target console-getty.service \
        systemd-udev-trigger.service systemd-udevd.service; \
    systemctl enable sshd crond atd

# Accounts: root/redhat and student/student (student has sudo)
RUN echo 'root:redhat' | chpasswd \
    && useradd -m -c "Lab student" student \
    && echo 'student:student' | chpasswd \
    && mkdir -p /etc/sudoers.d && echo 'student ALL=(ALL) ALL' > /etc/sudoers.d/student \
    && chmod 0440 /etc/sudoers.d/student

COPY bin/ /opt/labkit/bin/
COPY lib/ /opt/labkit/lib/
COPY systemd/ /opt/labkit/systemd/
RUN chmod +x /opt/labkit/bin/* \
    && ln -sf /opt/labkit/bin/labctl /usr/local/bin/labctl \
    && mkdir -p /etc/labkit /opt/labkit/labs \
    && cp /opt/labkit/systemd/labkit-setup.service /etc/systemd/system/ \
    && systemctl enable labkit-setup.service

STOPSIGNAL SIGRTMIN+3
CMD ["/sbin/init"]
