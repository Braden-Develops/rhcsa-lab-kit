ARG BASE=rhcsa-base:10
FROM ${BASE}
RUN dnf -y --setopt=strict=0 install jq curl ipmitool && dnf clean all
COPY labs/16-thermal-power-bmc/ /opt/labkit/labs/16-thermal-power-bmc/
RUN echo 16-thermal-power-bmc > /etc/labkit/lab-id
