FROM alpine:3 as s6
ARG S6_OVERLAY_VERSION=3.1.6.2

ADD https://github.com/just-containers/s6-overlay/releases/download/v${S6_OVERLAY_VERSION}/s6-overlay-noarch.tar.xz /tmp
ADD https://github.com/just-containers/s6-overlay/releases/download/v${S6_OVERLAY_VERSION}/s6-overlay-x86_64.tar.xz /tmp
RUN mkdir -p /s6/root \
    && tar -C /s6/root -Jxpf /tmp/s6-overlay-noarch.tar.xz \
    && tar -C /s6/root -Jxpf /tmp/s6-overlay-x86_64.tar.xz

FROM debian:trixie-slim as opnsense

ARG DEBCONF_NOWARNINGS="yes"
ARG DEBIAN_FRONTEND="noninteractive"
ARG DEBCONF_NONINTERACTIVE_SEEN="true"
ARG OPNSENSE_VERSION="24.1"
ARG OPNSENSE_DOWNLOAD_MIRRORS="\
    https://mirror.cloudfence.com.br/opnsense/releases/${OPNSENSE_VERSION}/\
    https://opnsense.aivian.org/releases/${OPNSENSE_VERSION}/\
    https://mirrors.pku.edu.cn/opnsense/releases/${OPNSENSE_VERSION}/\
    https://mirror.upb.edu.co/opnsense/releases/${OPNSENSE_VERSION}/\
    http://mirror.venturasystems.tech/opnsense/releases/mirror/\
    https://mirrors.dotsrc.org/opnsense/releases/${OPNSENSE_VERSION}/\
    https://opnsense.c0urier.net/releases/${OPNSENSE_VERSION}/\
    https://mirror.cedia.org.ec/opnsense/releases/${OPNSENSE_VERSION}/\
    http://mirror.espoch.edu.ec/opnsense/releases/${OPNSENSE_VERSION}/\
    http://mirror.uta.edu.ec/opnsense/releases/${OPNSENSE_VERSION}/\
    https://mirror.vraphim.com/opnsense/releases/${OPNSENSE_VERSION}/\
    https://mirror.dns-root.de/opnsense/releases/${OPNSENSE_VERSION}/\
    https://mirror.informatik.hs-fulda.de/opnsense/releases/${OPNSENSE_VERSION}/\
    https://mirror.uvensys.de/opnsense/releases/${OPNSENSE_VERSION}/\
    https://mirror.level66.network/opnsense-dist/releases/${OPNSENSE_VERSION}/\
    https://mirror.fra10.de.leaseweb.net/opnsense/releases/${OPNSENSE_VERSION}/\
    https://ftp.cc.uoc.gr/mirrors/opnsense/releases/${OPNSENSE_VERSION}/\
    https://quantum-mirror.hu/mirrors/pub/opnsense/releases/${OPNSENSE_VERSION}/\
    https://mirror.bardia.tech/opnsense/releases/${OPNSENSE_VERSION}/\
    https://mirror.mangohost.net/opnsense/releases/${OPNSENSE_VERSION}/\
    https://mirror.marwan.ma/opnsense/releases/${OPNSENSE_VERSION}/\
    https://mirror.catalyst.net.nz/opnsense/releases/${OPNSENSE_VERSION}/\
    https://mirror.terrahost.no/opnsense/releases/${OPNSENSE_VERSION}/\
    https://mirror.surf/opnsense/releases/${OPNSENSE_VERSION}/\
    https://opnsense-mirror.hiho.ch/releases/mirror/\
    https://mirror.init7.net/opnsense/releases/${OPNSENSE_VERSION}/\
    https://mirror-opnsense.serverbase.ch/releases/mirror/\
    https://mirror.ntct.edu.tw/opnsense/releases/${OPNSENSE_VERSION}/\
    https://mirror.ams1.nl.leaseweb.net/opnsense/releases/${OPNSENSE_VERSION}/\
    https://mirror.serverion.com/opnsense/releases/${OPNSENSE_VERSION}/\
    https://mirror.verinomi.com/opnsense/releases/${OPNSENSE_VERSION}/\
    https://mirrors.nycbug.org/pub/opnsense/releases/${OPNSENSE_VERSION}/\
    https://mirror.wdc1.us.leaseweb.net/opnsense/releases/${OPNSENSE_VERSION}/\
    https://mirror.sfo12.us.leaseweb.net/opnsense/releases/${OPNSENSE_VERSION}/\
    https://mirror2.sandyriver.net/pub/opnsense/releases/${OPNSENSE_VERSION}/\
    https://mirrors.ocf.berkeley.edu/opnsense/releases/${OPNSENSE_VERSION}/\
    https://www.mirrorservice.org/sites/opnsense.org/releases/${OPNSENSE_VERSION}/\
    http://mirror.wjcomms.co.uk/opnsense/releases/${OPNSENSE_VERSION}/"

WORKDIR /
SHELL [ "/bin/bash", "-o", "pipefail", "-c" ]
# hadolint ignore=DL3008
RUN apt-get update \
    && apt-get --no-install-recommends -y install \
        ca-certificates curl bzip2 netselect qemu-utils \
    # Install OPNsense image
    && mirror=$(netselect -s 1 -t 20 $OPNSENSE_DOWNLOAD_MIRRORS | awk '{print $2}') \
    && echo "Selected mirror: $mirror" \
    && image="OPNsense-${OPNSENSE_VERSION}-nano-amd64.img" \
    && curl --progress-bar -LO "${mirror}/${image}.bz2" \
    && set -o pipefail \
    && echo -n "Verify download: " \
    && curl -sfL "${mirror}/OPNsense-${OPNSENSE_VERSION}-checksums-amd64.sha256" \
        | grep -F "${image}" | sha256sum -c - \
    && echo "Decompress downloaded image..." \
    && bunzip2 "${image}.bz2" \
    && echo "Convert raw image to qcow2..." \
    && qemu-img convert -f raw -O qcow2 "${image}" middle.qcow2 \
    && echo "Minimize qcow2 image..." \
    && qemu-img convert -c -O qcow2 middle.qcow2 "${image%.img}.qcow2" \
    && rm -f "${image}" \
    && apt-get --purge autoremove -y curl bzip2 netselect qemu-utils \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*

FROM debian:trixie-slim as base

ARG OPNSENSE_VERSION="24.1"
ARG OPNSENSE_IMAGE_DIR="/var/lib/qemu"
ARG DEBCONF_NOWARNINGS="yes"
ARG DEBIAN_FRONTEND="noninteractive"
ARG DEBCONF_NONINTERACTIVE_SEEN="true"

ENV DEBCONF_NOWARNINGS=${DEBCONF_NOWARNINGS}
ENV DEBIAN_FRONTEND=${DEBIAN_FRONTEND}
ENV DEBCONF_NONINTERACTIVE_SEEN=${DEBCONF_NONINTERACTIVE_SEEN}
ENV IMAGE_PATH=${OPNSENSE_IMAGE_DIR}/OPNsense-${OPNSENSE_VERSION}-nano-amd64.qcow2

COPY --from=s6 /s6/root /
COPY --from=opnsense /OPNsense-${OPNSENSE_VERSION}-nano-amd64.qcow2 "${IMAGE_PATH}"

# hadolint ignore=DL3008
RUN apt-get update \
    && apt-get --no-install-recommends -y install \
        apt-utils \
        ca-certificates \
        iproute2 \
        iptables \
        libwww-mechanize-perl \
        libnet-netmask-perl \
        netcat-openbsd \
        picocom \
        procps \
        qemu-system-x86 \
        qemu-utils \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*

FROM base

ENV S6_CMD_WAIT_FOR_SERVICES_MAXTIME=300000
ENV RAM_SIZE="2048"

COPY s6-overlay /etc/s6-overlay
COPY scripts /scripts

# EXPOSE 22/tcp 53 443/tcp

ENTRYPOINT [ "/init" ]
