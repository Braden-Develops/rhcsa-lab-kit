ARG BASE=rhcsa-base:10
FROM ${BASE}
RUN dnf -y install httpd && dnf clean all
COPY labs/04-running-systems/ /opt/labkit/labs/04-running-systems/
RUN echo 04-running-systems > /etc/labkit/lab-id
