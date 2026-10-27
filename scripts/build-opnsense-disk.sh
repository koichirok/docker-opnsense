#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUTPUT_DIR="${ROOT_DIR}/build"
WORK_DIR="$(mktemp -d)"
QEMU_PIDFILE="${WORK_DIR}/qemu.pid"

cleanup() {
    if [ -f "$QEMU_PIDFILE" ]; then
        qemu_pid="$(cat "$QEMU_PIDFILE")"
        if [ -r "/proc/${qemu_pid}/comm" ] \
            && [ "$(cat "/proc/${qemu_pid}/comm")" = qemu-system-x86_64 ]; then
            kill "$qemu_pid"
            timeout 10 tail --pid="$qemu_pid" -f /dev/null || true
        fi
    fi
    rm -rf "$WORK_DIR"
}
trap cleanup EXIT

require_command() {
    if ! command -v "$1" >/dev/null 2>&1; then
        echo "Required command is missing: $1" >&2
        exit 1
    fi
}

for command in curl python3 qemu-img qemu-system-x86_64 expect picocom zstd sha256sum timeout tail; do
    require_command "$command"
done

if [ -r /dev/kvm ] && [ -w /dev/kvm ]; then
    QEMU_ACCEL_ARGS=(-enable-kvm)
    echo "Using KVM acceleration."
else
    QEMU_ACCEL_ARGS=(-accel tcg,thread=multi)
    echo "KVM is unavailable; using QEMU TCG software emulation. This will be slower." >&2
fi

OPNSENSE_SERIES="${OPNSENSE_SERIES:-$(python3 "${ROOT_DIR}/scripts/check-opnsense-version.py" --series-only)}"
if [[ ! "$OPNSENSE_SERIES" =~ ^[0-9]+\.[0-9]+$ ]]; then
    echo "Invalid OPNsense series: $OPNSENSE_SERIES" >&2
    exit 1
fi

mkdir -p "$OUTPUT_DIR"
rm -f "${OUTPUT_DIR}/opnsense.qcow2" "${OUTPUT_DIR}/opnsense.version"

GITHUB_HEADERS=(-H "Accept: application/vnd.github+json")
if [ -n "${GH_TOKEN:-}" ]; then
    GITHUB_HEADERS+=(-H "Authorization: Bearer ${GH_TOKEN}")
fi

release_json="${WORK_DIR}/builder-release.json"
curl --fail --silent --show-error "${GITHUB_HEADERS[@]}" \
    https://api.github.com/repos/anyvm-org/opnsense-builder/releases/latest \
    -o "$release_json"
unset GH_TOKEN GITHUB_HEADERS

python3 - "$release_json" "$OPNSENSE_SERIES" "$WORK_DIR" <<'PY'
import json
import pathlib
import sys

release_file, series, work_dir = sys.argv[1:]
release = json.loads(pathlib.Path(release_file).read_text())
asset_name = f"opnsense-{series}.qcow2.zst"
asset = next((item for item in release.get("assets", []) if item["name"] == asset_name), None)
if asset is None:
    raise SystemExit(
        f"Builder release {release.get('tag_name')} has no {asset_name}; "
        "wait for anyvm-org/opnsense-builder to publish the new series image."
    )
digest = (asset.get("digest") or "").removeprefix("sha256:")
if len(digest) != 64:
    raise SystemExit(f"Builder release asset {asset_name} has no valid SHA-256 digest.")
pathlib.Path(work_dir, "image-url").write_text(asset["browser_download_url"])
pathlib.Path(work_dir, "image-sha256").write_text(digest)
print(f"Using {asset_name} from builder release {release['tag_name']}")
PY

curl --fail --location --silent --show-error \
    "$(cat "${WORK_DIR}/image-url")" \
    -o "${WORK_DIR}/opnsense.qcow2.zst"

expected_sha256="$(cat "${WORK_DIR}/image-sha256")"
if [ -n "$expected_sha256" ]; then
    printf '%s  %s\n' "$expected_sha256" "${WORK_DIR}/opnsense.qcow2.zst" \
        | sha256sum --check --status
fi

zstd --decompress --force "${WORK_DIR}/opnsense.qcow2.zst" \
    -o "${WORK_DIR}/opnsense.qcow2"

qemu-system-x86_64 \
    -nodefaults \
    "${QEMU_ACCEL_ARGS[@]}" \
    -daemonize \
    -m 3072 \
    -smp 2 \
    -nographic \
    -pidfile "$QEMU_PIDFILE" \
    -chardev "pty,id=serial,logfile=${WORK_DIR}/console.log" \
    -serial "chardev:serial" \
    -monitor none \
    -netdev "user,id=wan0" \
    -device "virtio-net-pci,netdev=wan0" \
    -drive "file=${WORK_DIR}/opnsense.qcow2,format=qcow2,cache=none,discard=unmap,detect-zeroes=unmap" \
    > "${WORK_DIR}/qemu.log" 2>&1

attempt=0
while [ "$attempt" -lt 30 ]; do
    if grep -qE '/dev/pts/[0-9]+' "${WORK_DIR}/qemu.log"; then
        break
    fi
    sleep 1
    attempt=$((attempt + 1))
done

serial_device="$(grep -oE '/dev/pts/[0-9]+' "${WORK_DIR}/qemu.log" | head -n 1 || true)"
if [ -z "$serial_device" ]; then
    echo "Could not locate the QEMU serial console." >&2
    cat "${WORK_DIR}/qemu.log" >&2
    if [ -f "$QEMU_PIDFILE" ]; then
        qemu_pid="$(cat "$QEMU_PIDFILE")"
        kill "$qemu_pid" 2>/dev/null || true
        sleep 1
    fi
    exit 1
fi

expect "${ROOT_DIR}/scripts/update-opnsense.exp" "$serial_device"

qemu_pid="$(cat "$QEMU_PIDFILE")"
if ! timeout 300 tail --pid="$qemu_pid" -f /dev/null; then
    echo "QEMU did not shut down after the OPNsense update." >&2
    exit 1
fi
rm -f "$QEMU_PIDFILE"

version_output="$(
    sed -n '/BUILD_VERSION_BEGIN/,/BUILD_VERSION_END/p' "${WORK_DIR}/console.log" \
        | sed '1d;$d'
)"
OPNSENSE_VERSION="$(
    printf '%s\n' "$version_output" \
        | python3 -c '
import re
import sys

text = sys.stdin.read()
match = re.search(r"\b(\d+\.\d+(?:\.\d+)?)(?:_\d+)?\b", text)
if not match:
    raise SystemExit(f"Could not parse the updated OPNsense version from: {text!r}")
print(match.group(1))
'
)"
if [[ "$OPNSENSE_VERSION" != "$OPNSENSE_SERIES" && "$OPNSENSE_VERSION" != "$OPNSENSE_SERIES".* ]]; then
    echo "Updated version ${OPNSENSE_VERSION} does not belong to series ${OPNSENSE_SERIES}." >&2
    exit 1
fi

qemu-img convert -c -O qcow2 \
    "${WORK_DIR}/opnsense.qcow2" "${OUTPUT_DIR}/opnsense.qcow2"
printf '%s\n' "$OPNSENSE_VERSION" > "${OUTPUT_DIR}/opnsense.version"

echo "OPNsense series: ${OPNSENSE_SERIES}"
echo "Updated OPNsense version: ${OPNSENSE_VERSION}"
if [ -n "${GITHUB_OUTPUT:-}" ]; then
    {
        echo "series=${OPNSENSE_SERIES}"
        echo "version=${OPNSENSE_VERSION}"
    } >> "$GITHUB_OUTPUT"
fi
