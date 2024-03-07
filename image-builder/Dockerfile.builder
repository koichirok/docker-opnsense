FROM debian:trixie-slim

# hadolint ignore=DL3008
RUN apt-get update \
    && apt-get --no-install-recommends -y install \
        bzip2 ca-certificates expect netselect \
        picocom procps qemu-system-x86 qemu-utils wget \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*

COPY src /builder
