#!/bin/bash -e

# shellcheck disable=SC1091
. /opt/qemu-opnsense/lib/opnsense.subr

start() {
    local banner_message lan_ipv4_address lan_ipv4_netmask hostname
    echo ">>> Start opnsense."
    start_opnsense

    echo -n "Waiting for opnsense to be ready..."
    wait_opnsense_ready
    echo "done."

    banner_message="$(
        grep -A 11 -F 'Root file system: /dev/ufs/OPNsense_Nano' "${OPNSENSE_CONSOLE_LOG_FILE}" | sed -n -e '3,$p'
    )"
    while IFS=$'\n'$'\r' read -r line; do
        case "${line}" in
            "*** "*": "*)
                hostname="${line#*** }"
                hostname="${hostname%%:*}"
                ;;
            " LAN"*"v4: "*)
                lan_ipv4_address="${line#*v4: }"
                lan_ipv4_netmask="${lan_ipv4_address##*/}"
                lan_ipv4_address="${lan_ipv4_address%/*}"
                ;;
        esac
    done <<< "${banner_message}"

    # save current network settings
    cat <<-EOF > "${OPNSENSE_CURRENT_NETWORK_SETTINGS}"
	HOSTNAME="${hostname}"
	LAN_IPV4_ADDRESS="${lan_ipv4_address}"
	LAN_IPV4_NETMASK="${lan_ipv4_netmask}"
	EOF

    echo -n "Configuring network..." 
    # use first available address in the OPNsense LAN network as the container's bridge address
    configure_network "${lan_ipv4_address}" "${lan_ipv4_netmask}"
    echo done.

    echo -n "Updating /etc/hosts..."
    echo -e "${lan_ipv4_address}\t${hostname} ${hostname%%.*}" >> /etc/hosts
    echo done.

    echo -n "Generating API key..."
    if [ -e "${OPNSENSE_API_KEY_FILE}" ]; then
        echo "API key file already exists at ${OPNSENSE_API_KEY_FILE}"
    elif generate_api_key "${lan_ipv4_address}"; then
        echo done.
    else
        echo "Failed to generate API key. Exiting."
        exit 1
    fi

    echo "****************************************************************"
    echo
    echo OPNsense is now operational with the following configuration:
    echo "${banner_message}"
    echo
    echo Web Interface Access:
    echo "- Within the container: http://${lan_ipv4_address}/"
    echo "- Outside the container: https://<container-name>/"
    echo
    echo Note: To access from the host, publish port 443 to the host.
    echo
    echo API Key:
    echo "The API key for the root user is stored at: ${OPNSENSE_API_KEY_FILE}"
    echo
}

stop() {
    echo -n "Stopping opnsense..."
    stop_opnsense
    echo done.

    # Remove br-opnsense-lan's IP address and related iptables rules
    unconfigure_network
}

#setup_logging

case "${1}" in
    start) start;;
    stop)  stop ;;
    restart)
        stop
        start
        ;;
    *)
        echo "Usage: $0 {start|stop|restart}"
        exit 1
        ;;
esac
