#!/bin/bash

set -euo pipefail

# shellcheck disable=SC1091
. /opt/qemu-opnsense/lib/prepare-env.subr

ensure_directories
ensure_devices
ensure_network_interfaces
