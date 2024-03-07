# syntax=docker/dockerfile:1-labs
FROM debian:trixie-slim as base

ARG DEBCONF_NOWARNINGS="yes"
ARG DEBIAN_FRONTEND="noninteractive"
ARG DEBCONF_NONINTERACTIVE_SEEN="true"

ENV DEBCONF_NOWARNINGS=${DEBCONF_NOWARNINGS}
ENV DEBIAN_FRONTEND=${DEBIAN_FRONTEND}
ENV DEBCONF_NONINTERACTIVE_SEEN=${DEBCONF_NONINTERACTIVE_SEEN}

ARG OPNSENSE_VERSION="24.1"
ARG OPNSENSE_IMAGE_DIR="/var/lib/qemu"
ARG OPNSENSE_LOG_DIR="/var/log/qemu-opnsense"
ARG OPNSENSE_RUN_STATE_DIR="/var/run/qemu-opnsense"
ARG OPNSENSE_LAN_DEVICE_NAME="tap0"
ARG OPNSENSE_LAN_BRIDGE_NAME="br-opnsense-lan"
ARG OPNSENSE_RAM_SIZE="2048"
ARG OPNSENSE_PID_FILENAME="qemu.pid"
ARG OPNSENSE_QEMU_SERIAL_DEV_NAME="ptyS0"
ARG OPNSENSE_READY_TIMEOUT=300
ARG OPNSENSE_GRACETIME=180
ARG OPNSENSE_API_KEY_FILE="/root/.opnsense_api_key.json"

ENV OPNSENSE_VERSION=${OPNSENSE_VERSION}
ENV OPNSENSE_IMAGE_PATH=${OPNSENSE_IMAGE_DIR}/OPNsense-${OPNSENSE_VERSION}-nano-amd64.qcow2
ENV OPNSENSE_LOG_DIR=${OPNSENSE_LOG_DIR}
ENV OPNSENSE_RUN_STATE_DIR=${OPNSENSE_RUN_STATE_DIR}
ENV OPNSENSE_LAN_DEVICE_NAME=${OPNSENSE_LAN_DEVICE_NAME}
ENV OPNSENSE_LAN_BRIDGE_NAME=${OPNSENSE_LAN_BRIDGE_NAME}
ENV OPNSENSE_RAM_SIZE=${OPNSENSE_RAM_SIZE}
ENV OPNSENSE_PID_FILENAME=${OPNSENSE_PID_FILENAME}
ENV OPNSENSE_QEMU_SERIAL_DEV_NAME=${OPNSENSE_QEMU_SERIAL_DEV_NAME}
ENV OPNSENSE_READY_TIMEOUT=${OPNSENSE_READY_TIMEOUT}
ENV OPNSENSE_GRACETIME=${OPNSENSE_GRACETIME}
ENV OPNSENSE_API_KEY_FILE=${OPNSENSE_API_KEY_FILE}

RUN mkdir -p "${OPNSENSE_IMAGE_DIR}" "${OPNSENSE_LOG_DIR}" 

# hadolint ignore=DL3008
RUN apt-get update \
    && apt-get --no-install-recommends -y install \
        ca-certificates \
        iproute2 \
        iptables \
        libwww-mechanize-perl \
        libnet-netmask-perl \
        monit \
        netcat-openbsd \
        picocom \
        procps \
        qemu-system-x86 \
        qemu-utils \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*

COPY --chmod=0600 src/monitrc /etc/monit/conf.d/
COPY --chmod=0755 src/entrypoint.sh /
COPY ./src/qemu-opnsense /opt/qemu-opnsense

FROM base as qemu-image-builder

SHELL [ "/bin/bash", "-o", "pipefail", "-c" ]
# hadolint ignore=DL3008
RUN apt-get update \
    && apt-get --no-install-recommends -y install \
        wget bzip2 netselect expect \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*

# create sparse qcow2 image at OPNSENSE_IMAGE_PATH
RUN --security=insecure \
    /opt/qemu-opnsense/libexec/opnsense-image-setup.sh "${OPNSENSE_VERSION}"

FROM base

COPY --from=qemu-image-builder "${OPNSENSE_IMAGE_PATH}" "${OPNSENSE_IMAGE_PATH}"

# EXPOSE 22/tcp 53 443/tcp

ENTRYPOINT [ "/entrypoint.sh" ]
