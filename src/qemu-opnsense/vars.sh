# shellcheck shell=sh
: "${PIDFILE:=/var/run/qemu-opnsense.pid}"
: "${OPNSENSE_LOG_DIR:=/var/log/qemu-opnsense}"
: "${OPNSENSE_SVC_SCRIPT_LOG_FILE:="${OPNSENSE_LOG_DIR}/control.log"}"
: "${OPNSENSE_NETWORK_SETTINGS:="${OPNSENSE_LOG_DIR}/network"}"
