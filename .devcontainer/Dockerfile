FROM mcr.microsoft.com/devcontainers/base:trixie

# hadolint ignore=DL3008
RUN apt-get update \
    && export DEBIAN_FRONTEND=noninteractive \
    && apt-get -y install --no-install-recommends \
        expect \
        libwww-mechanize-perl \
        libperl-critic-perl \
        perl-doc \
        perltidy \
        picocom \
        python3 \
        qemu-system-x86 \
        qemu-utils \
        zstd \
    && apt-get autoremove -y \
    && apt-get clean -y && rm -rf /var/lib/apt/lists/*
