FROM mcr.microsoft.com/devcontainers/base:bullseye

# hadolint ignore=DL3008
RUN apt-get update \
    && export DEBIAN_FRONTEND=noninteractive \
    && apt-get -y install --no-install-recommends \
        execline \
        execline-doc \
        libwww-mechanize-perl \
        libperl-critic-perl \
        libxml-simple-perl \
        monit \
        perl-doc \
        perltidy \
        w3m \
    && apt-get autoremove -y \
    && apt-get clean -y && rm -rf /var/lib/apt/lists/*
RUN ln -s /usr/lib/execline/bin /command
