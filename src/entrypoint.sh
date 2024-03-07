#!/bin/bash

set -eu

/opt/qemu-opnsense/libexec/prepare-env.sh

exec /usr/bin/monit
