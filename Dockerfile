FROM debian:trixie-slim

ARG DEBCONF_NOWARNINGS="yes"
ARG DEBIAN_FRONTEND="noninteractive"
ARG DEBCONF_NONINTERACTIVE_SEEN="true"

# hadolint ignore=DL3008
RUN apt-get update \
    && apt-get --no-install-recommends -y install \
        ca-certificates \
        iproute2 \
        iptables \
        libwww-mechanize-perl \
        libnet-netmask-perl \
        netcat-openbsd \
        picocom \
        procps \
        qemu-system-x86 \
    && apt-get clean \
    && rm -f /usr/bin/qemu-system-i386 /usr/bin/qemu-system-x86_64-microvm \
    && rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*

ARG OPNSENSE_VERSION
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
# hadolint ignore=DL3064
ARG OPNSENSE_API_KEY_FILE="/root/.opnsense_api_key.json"

ENV OPNSENSE_VERSION=${OPNSENSE_VERSION}
ENV OPNSENSE_IMAGE=opnsense.qcow2
ENV OPNSENSE_IMAGE_PATH=${OPNSENSE_IMAGE_DIR}/${OPNSENSE_IMAGE}
ENV OPNSENSE_LOG_DIR=${OPNSENSE_LOG_DIR}
ENV OPNSENSE_RUN_STATE_DIR=${OPNSENSE_RUN_STATE_DIR}
ENV OPNSENSE_LAN_DEVICE_NAME=${OPNSENSE_LAN_DEVICE_NAME}
ENV OPNSENSE_LAN_BRIDGE_NAME=${OPNSENSE_LAN_BRIDGE_NAME}
ENV OPNSENSE_RAM_SIZE=${OPNSENSE_RAM_SIZE}
ENV OPNSENSE_PID_FILENAME=${OPNSENSE_PID_FILENAME}
ENV OPNSENSE_QEMU_SERIAL_DEV_NAME=${OPNSENSE_QEMU_SERIAL_DEV_NAME}
ENV OPNSENSE_READY_TIMEOUT=${OPNSENSE_READY_TIMEOUT}
ENV OPNSENSE_GRACETIME=${OPNSENSE_GRACETIME}
# hadolint ignore=DL3064
ENV OPNSENSE_API_KEY_FILE=${OPNSENSE_API_KEY_FILE}

RUN mkdir -p "${OPNSENSE_IMAGE_DIR}" "${OPNSENSE_LOG_DIR}" 

COPY build/opnsense.qcow2 "${OPNSENSE_IMAGE_PATH}"
COPY --chmod=0755 src/qemu-opnsense-init.sh.in /etc/init.d/qemu-opnsense
COPY --chmod=0700 src/entrypoint.sh.in /opt/qemu-opnsense/entrypoint.sh
COPY --chmod=0755 src/generate-opnsense-api-key.pl /opt/qemu-opnsense/generate-api-key

ENTRYPOINT ["/opt/qemu-opnsense/entrypoint.sh"]
