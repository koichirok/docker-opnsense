#!/bin/bash

SCRIPT_DIR="$(realpath "$(dirname "$0")")"

# shellcheck disable=SC1091
. "${SCRIPT_DIR}/vars.sh"

exec 2>&1
exec > >(tee -i "${OPNSENSE_SVC_SCRIPT_LOG_FILE}")

: "${RAM_SIZE:=2048}"
: "${IMAGE_PATH}"
: "${SERIAL_DEV_ID:=ptyS0}"
: "${LOGFILE:=${OPNSENSE_LOG_DIR}/console.log}"
: "${LAN_TAP_DEV:=tap0}"
: "${OPNSENSE_READY_TIMEOUT:=300}"
: "${OPNSENSE_API_KEY_FILE:=/root/.opnsense_api_key.json}"

wait_opnsense_ready() {
    local newest_log
    while [ "${OPNSENSE_READY_TIMEOUT}" -gt 0 ]; do
        newest_log="$(tail -n 1 "${LOGFILE}")"
        if [[ "${newest_log}" == "login: " ]]; then
            return 0
        fi
        echo -n "."
        sleep 1
        OPNSENSE_READY_TIMEOUT=$((OPNSENSE_READY_TIMEOUT-1))
    done
    echo "FATAL: Timeout waiting for opnsense to be ready." >&2
    exit 1
}

if [ -z "${IMAGE_PATH}" ]; then
    echo "IMAGE_PATH is not set. Exiting."
    exit 1
fi
if [[ "${IMAGE_PATH}" =~ \.qcow2$ ]]; then
    IMAGE_FORMAT=qcow2
else
    IMAGE_FORMAT=raw
fi

PIDDIR="${PIDFILE%/*}"
if [ ! -d "${PIDDIR}" ]; then
    mkdir -p "${PIDDIR}"
fi

typeset -a QEMU_ARGS
QEMU_ARGS+=(
    -nodefaults -enable-kvm
    -pidfile "${PIDFILE}"
    -daemonize
    -cpu "host,kvm=on,l3-cache=on,migratable=no"
    -smp "1,sockets=1,dies=1,cores=1,threads=1"
    -m "${RAM_SIZE}"
    # Note: q35 chipset is supported by OPNsense >= 21.x
    -machine "type=q35,graphics=off,vmport=off,dump-guest-core=off,hpet=off,accel=kvm"

    # Allow to connect to the serial console via pty device
    -nographic
    -chardev "pty,id=${SERIAL_DEV_ID},logfile=${LOGFILE}"
    -serial "chardev:${SERIAL_DEV_ID}"
    -monitor "telnet:localhost:7100,server,nowait,nodelay"
    -netdev "tap,id=nd0,ifname=${LAN_TAP_DEV},script=no,downscript=no"
    -device "virtio-net-pci,netdev=nd0"
    -netdev "user,id=nd1"
    -device "virtio-net-pci,netdev=nd1"
    -drive "file=${IMAGE_PATH},if=virtio,format=${IMAGE_FORMAT},cache=none,aio=native,discard=on,detect-zeroes=on"
)

# -global kvm-pit.lost_tick_policy=discard
# -device virtio-balloon-pci,id=balloon0,bus=pcie.0,addr=0x4
# -object rng-random,id=objrng0,filename=/dev/urandom
# -device virtio-rng-pci,rng=objrng0,id=rng0,bus=pcie.0,addr=0x1c
# -name qemu,process=qemu,debug-threads=on

qemu-system-x86_64 "${QEMU_ARGS[@]}"

echo -n "Waiting for opnsense to be ready..."
wait_opnsense_ready
echo "done."

BANNER_MESSAGE="$(
    grep -A 11 -F 'Root file system: /dev/ufs/OPNsense_Nano' "${LOGFILE}" | sed -n -e '3,$p'
)"
while IFS=$'\n' read -r line; do
    case "${line}" in
        "*** "*": "*)
            HOSTNAME="${line#*** }"
            HOSTNAME="${HOSTNAME%%:*}"
            ;;
        " LAN"*"v4: "*)
            LAN_IPV4_ADDRESS="${line#*v4: }"
            LAN_IPV4_NETMASK="${LAN_IPV4_ADDRESS##*/}"
            LAN_IPV4_ADDRESS="${LAN_IPV4_ADDRESS%/*}"
            ;;
    esac
done <<< "${BANNER_MESSAGE}"

# save current network settings
cat <<EOF > "${OPNSENSE_NETWORK_SETTINGS}"
HOSTNAME="${HOSTNAME}"
LAN_IPV4_ADDRESS="${LAN_IPV4_ADDRESS}"
LAN_IPV4_NETMASK="${LAN_IPV4_NETMASK}"
EOF

echo -n "Configuring network..." 
# use first available address in the OPNsense LAN network as the container's bridge address
BRIDGE_ADDRESS="$(
    perl -MNet::Netmask -e '
        @addrs = Net::Netmask->safe_new(join "/", @ARGV)->enumerate();
        # reject opnsense_lan_address, network and broadcast addresses
        @available = grep !/\\Q\$ARGV[0]\\E/, @addrs[1..$#addrs-1];
        print $available[0];' "${LAN_IPV4_ADDRESS}" "${LAN_IPV4_NETMASK}"
)"
if ip addr show br-opnsense-lan | grep -q "${BRIDGE_ADDRESS}"; then
    ip addr add "${BRIDGE_ADDRESS}/${LAN_IPV4_NETMASK}" dev br-opnsense-lan
fi

iptables \
    -t nat -A PREROUTING -i eth0 -p tcp --dport 443 -j DNAT \
    --to-destination "${LAN_IPV4_ADDRESS}:443"
iptables -t nat -A POSTROUTING -o br-opnsense-lan -j MASQUERADE

echo done.

echo -n "Updating /etc/hosts..."
echo -e "${LAN_IPV4_ADDRESS}\t${HOSTNAME} ${HOSTNAME%%.*}" >> /etc/hosts
echo done.

echo -n "Generating API key..."
if [ -e "${OPNSENSE_API_KEY_FILE}" ]; then
    echo "API key file already exists at ${OPNSENSE_API_KEY_FILE}"
elif "$SCRIPT_DIR/generate-opnsense-api-key.pl" -H "${LAN_IPV4_ADDRESS}" -f "${OPNSENSE_API_KEY_FILE}"; then
    echo done.
else
    echo "Failed to generate API key. Exiting."
    exit 1
fi

exec > >(tee -i "${OPNSENSE_SVC_SCRIPT_LOG_FILE}" /proc/1/fd/1)

echo "****************************************************************"
echo
echo OPNsense is now operational with the following configuration:
echo "${BANNER_MESSAGE}"
echo
echo Web Interface Access:
echo "- Within the container: http://${LAN_IPV4_ADDRESS}/"
echo "- Outside the container: https://<container-name>/"
echo
echo Note: To access from the host, publish port 443 to the host.
echo
echo API Key:
echo "The API key for the root user is stored at: ${OPNSENSE_API_KEY_FILE}"
echo
