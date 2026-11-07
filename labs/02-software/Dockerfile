ARG BASE=rhcsa-base:10
FROM ${BASE}
RUN dnf -y install rpm-build createrepo_c flatpak && dnf clean all
COPY labs/02-software/ /opt/labkit/labs/02-software/
RUN echo 02-software > /etc/labkit/lab-id
