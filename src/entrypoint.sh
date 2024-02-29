#!/bin/sh

# Create kvm as needed
if [ ! -e /dev/kvm ]; then
    mknod /dev/kvm c 10 232
fi
# Create tap0 as needed
if [ ! -e /dev/net/tun ]; then
    mkdir -p /dev/net
    mknod /dev/net/tun c 10 200
fi

exec /usr/bin/monit
