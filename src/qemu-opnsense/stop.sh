#!/bin/bash

# shellcheck source=vars.sh
. "$(dirname "$0")/vars.sh"

: "${OPNSENSE_GRACETIME:=180}"

exec 2>&1
exec > >(tee -i "${OPNSENSE_SVC_SCRIPT_LOG_FILE}")

if [ ! -e "${PIDFILE}" ]; then
    echo "PID file ${PIDFILE} not found. Do nothing."
    exit 0
fi

printf 'system_powerdown\n' | nc -q 1 localhost 7100

pid="$(cat "${PIDFILE}")"
while [ "${OPNSENSE_GRACETIME}" -gt 0 ]; do
    OPNSENSE_GRACETIME=$((OPNSENSE_GRACETIME-1))
    if pgrep --pid "${pid}" > /dev/null; then
        sleep 1
    else
        exit 0
    fi
done

echo "Timeout waiting for opnsense to gracefully shutdown." >&2
kill "$pid"

# Remove br-opnsense-lan's IP address and related iptables rules
. "${OPNSENSE_NETWORK_SETTINGS}"

ip addr del "${LAN_IPV4_ADDRESS}/${LAN_IPV4_NETMASK}" dev br-opnsense-lan

iptables -t nat -D PREROUTING -i eth0 -p tcp --dport 443 -j DNAT \
    --to-destination "${LAN_IPV4_ADDRESS}:443"
iptables -t nat -D POSTROUTING -o br-opnsense-lan -j MASQUERADE
