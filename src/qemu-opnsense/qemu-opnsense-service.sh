#!/bin/bash -e

OPNSENSE_PIDFILE="${OPNSENSE_RUN_STATE_DIR}/qemu.pid"
OPNSENSE_CONSOLE_LOG_FILE="${OPNSENSE_LOG_DIR}/console.log"
OPNSENSE_CONTROL_LOG_FILE="${OPNSENSE_LOG_DIR}/control.log"
OPNSENSE_CURRENT_NETWORK_SETTINGS="${OPNSENSE_RUN_STATE_DIR}/network.env"
OPNSENSE_QEMU_MONITOR="telnet:localhost:7100,server,nowait,nodelay"

fatal () {
    echo "FATAL: $*" >&2
    exit 1
}

setup_logging() {
    local -a logfiles
    logfiles+=("${OPNSENSE_CONTROL_LOG_FILE}")

    if [ "${MONIT_PROCESS_PID}" ]; then
        {
            echo "MONIT_PROCESS_PID=${MONIT_PROCESS_PID}" >> "$OPNSENSE_CONTROL_LOG_FILE"
            ps -ef 
        } >> "$OPNSENSE_CONTROL_LOG_FILE"
    fi
    if [ ! -t 0 ]; then
        # This shell has no tty
        logfiles+=(" > /dev/null")
    fi
    exec > >(tee -i "${logfiles[@]}")
    exec 2>&1
}

# start qemu instance
start() {
    local image_format
    local -a qemu_args
    case "${OPNSENSE_IMAGE_PATH}" in
        *.qcow2) image_format=qcow2;;
        *)       image_format=raw;;
    esac
    qemu_args+=(
        -nodefaults -enable-kvm
        -pidfile "${OPNSENSE_PIDFILE}"
        -daemonize
        -cpu "host,kvm=on,l3-cache=on,migratable=no"
        -smp "1,sockets=1,dies=1,cores=1,threads=1"
        -m "${OPNSENSE_RAM_SIZE}"
        # Note: q35 chipset is supported by OPNsense >= 21.x
        -machine "type=q35,graphics=off,vmport=off,dump-guest-core=off,hpet=off,accel=kvm"

        # Allow to connect to the serial console via pty device
        -nographic
        -chardev "pty,id=${OPNSENSE_QEMU_SERIAL_DEV_NAME},logfile=${OPNSENSE_CONSOLE_LOG_FILE}"
        -serial "chardev:${OPNSENSE_QEMU_SERIAL_DEV_NAME}"
        -monitor "${OPNSENSE_QEMU_MONITOR}"
        -netdev "tap,id=nd0,ifname=${OPNSENSE_LAN_DEVICE_NAME},script=no,downscript=no,br=${OPNSENSE_LAN_BRIDGE_NAME}"
        -device "virtio-net-pci,netdev=nd0"
        -netdev "user,id=nd1"
        -device "virtio-net-pci,netdev=nd1"
        -drive "file=${OPNSENSE_IMAGE_PATH},if=virtio,format=${image_format},cache=none,aio=native,discard=on,detect-zeroes=on"
        -name "qemu-opnsense"
    )
    # -global kvm-pit.lost_tick_policy=discard
    # -device virtio-balloon-pci,id=balloon0,bus=pcie.0,addr=0x4
    # -object rng-random,id=objrng0,filename=/dev/urandom
    # -device virtio-rng-pci,rng=objrng0,id=rng0,bus=pcie.0,addr=0x1c
    qemu-system-x86_64 "${qemu_args[@]}" 2>&1
}

wait_opnsense_ready() {
    local newest_log tries
    tries="${OPNSENSE_READY_TIMEOUT}"
    while [ "${tries}" -gt 0 ]; do
        newest_log="$(tail -n 1 "${OPNSENSE_CONSOLE_LOG_FILE}")"
        if [[ "${newest_log}" == "login: " ]]; then
            return 0
        fi
        echo -n "."
        sleep 1
        tries=$((tries - 1))
    done
    fatal "Timeout waiting for opnsense to be ready."
}

start_and_wait_ready() {
    start
    echo -n "Waiting for opnsense to be ready..."
    wait_opnsense_ready
    echo "done."
    post_opnsense_ready
}

post_opnsense_ready() {
    local banner_message lan_ipv4_address lan_ipv4_netmask hostname
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

    # store the current network settings
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
    # shellcheck disable=SC1090
    . "${OPNSENSE_CURRENT_NETWORK_SETTINGS}"
    
    if [ -e "${OPNSENSE_API_KEY_FILE}" ]; then
        echo "API key file already exists at ${OPNSENSE_API_KEY_FILE}"
    elif /opt/qemu-opnsense/generate-opnsense-api-key.pl \
            -H "${lan_ipv4_address}" -f "${OPNSENSE_API_KEY_FILE}"; then
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

# stop qemu instance
graceful_stop() {
    local monitor tries pid rc
    monitor="$(IFS=':,'; set -- ${OPNSENSE_QEMU_MONITOR}; echo "$2 $3")"
    pid="$(cat "${OPNSENSE_PIDFILE}")"
    echo -n "Trying to gracefully stop opnsense..."
    # shellcheck disable=SC2086
    printf 'system_powerdown\n' | nc -q 0 ${monitor}
    timeout "${OPNSENSE_GRACETIME}" tail --pid=$pid -f /dev/null
    rc=$?
    if [ $rc -eq 0 ]; then
        echo done.
    else
        echo "failed."
    fi
    return $rc
}

stop() {
    if ! graceful_stop; then
        echo -n "Forcing opnsense to stop..."
        start-stop-daemon --stop --pidfile "${OPNSENSE_PIDFILE}" --retry 5 \
            --remove-pidfile
        echo done.
    fi
}

configure_network() {
    local bridge_address LAN_IPV4_ADDRESS LAN_IPV4_NETMASK HOSTNAME
    # shellcheck disable=SC1090
    . "${OPNSENSE_CURRENT_NETWORK_SETTINGS}"

    bridge_address="$(
        perl -MNet::Netmask -e '
            @addrs = Net::Netmask->safe_new(join "/", @ARGV)->enumerate();
            # reject opnsense_lan_address, network and broadcast addresses
            @available = grep !/\Q$ARGV[0]\E/, @addrs[1..$#addrs-1];
            print $available[0];' "${LAN_IPV4_ADDRESS}" "${LAN_IPV4_NETMASK}"
    )"
    if [ "${LAN_IPV4_ADDRESS}" = "${bridge_address}" ]; then
        fatal "Failed to find an available address for the container's bridge."
    fi
    if ! ip addr show "${OPNSENSE_LAN_BRIDGE_NAME}" | grep -q "${bridge_address}"; then
        ip addr add "${bridge_address}/${LAN_IPV4_NETMASK}" dev "${OPNSENSE_LAN_BRIDGE_NAME}"
    fi

    iptables \
        -t nat -A PREROUTING -i eth0 -p tcp --dport 443 -j DNAT \
        --to-destination "${LAN_IPV4_ADDRESS}:443"
    iptables -t nat -A POSTROUTING -o "${OPNSENSE_LAN_BRIDGE_NAME}" -j MASQUERADE
}

# Remove br-opnsense-lan's IP address and related iptables rules
unconfigure_network() {
    local LAN_IPV4_ADDRESS LAN_IPV4_NETMASK HOSTNAME
    # shellcheck disable=SC1090
    . "${OPNSENSE_CURRENT_NETWORK_SETTINGS}"

    ip addr del "${LAN_IPV4_ADDRESS}/${LAN_IPV4_NETMASK}" dev "${OPNSENSE_LAN_BRIDGE_NAME}"

    iptables -t nat -D PREROUTING -i eth0 -p tcp --dport 443 -j DNAT \
        --to-destination "${LAN_IPV4_ADDRESS}:443"
    iptables -t nat -D POSTROUTING -o "${OPNSENSE_LAN_BRIDGE_NAME}" -j MASQUERADE
}

setup_logging

case "${1}" in
    start) start_and_wait_ready;;
    stop)
        stop
        # Remove br-opnsense-lan's IP address and related iptables rules
        unconfigure_network
        ;;
    restart)
        stop
        start_and_wait_ready
        ;;
    *)
        echo "Usage: $0 {start|stop|restart}"
        exit 1
        ;;
esac
