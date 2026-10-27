# docker-opnsense

Run OPNsense in a Docker container using QEMU/KVM. This image is intended for
testing and evaluation, not production use. It requires elevated networking
permissions and exposes a virtual firewall; do not expose it to untrusted
networks.

## Run a published image

Choose a versioned tag published on
[GitHub Container Registry](https://github.com/koichirok/docker-opnsense/pkgs/container/docker-opnsense).
For Docker Compose, create a `.env` file next to `docker-compose.yml`:

```dotenv
OPNSENSE_VERSION=26.7.7
```

Replace the example with an available tag, then start the container:

```sh
docker compose up -d
```

The included [docker-compose.yml](./docker-compose.yml) publishes the OPNsense
web interface on host port `10443`. It grants `NET_ADMIN` and permits access to
the KVM device. If preferred, pass `/dev/kvm` explicitly using the `devices`
entry instead of `device_cgroup_rules` (see the comments in the Compose file).
The host must have working KVM support; the container also needs enough memory
for the guest (2 GiB by default).

For `docker run`, the equivalent basic setup is:

```sh
docker run -it \
  --name opnsense \
  --device /dev/kvm \
  --cap-add NET_ADMIN \
  -p 10443:443 \
  ghcr.io/koichirok/docker-opnsense:26.7.7
```

Stop and start this container without removing it to preserve guest state:

```sh
docker stop opnsense
docker start opnsense
```

When startup completes, open <https://localhost:10443/>. The web interface
uses HTTPS and may show a browser warning for its certificate. The default
login is `root` / `opnsense`; change the password after signing in. The
container logs show the guest's LAN address and startup status:

```sh
docker compose logs -f opnsense
```

At startup, the container generates an API key for the root user and stores a
JSON object containing `key` and `secret` at
`/root/.opnsense_api_key.json` inside the container (mode `0600`). Treat this
file as a credential. To copy it to the host, use `docker cp` with the running
container name and store the copy securely. For example, with Compose:

```sh
docker cp "$(docker compose ps -q opnsense)":/root/.opnsense_api_key.json ./opnsense-api-key.json
```

The virtual disk is stored in the container at `/var/lib/qemu/opnsense.qcow2`.
Stopping and restarting the same container preserves its state; removing and
recreating the container (for example, with `docker compose down`) does not.
Back up the disk before replacing the container if you need to keep guest
changes. The API key file is also in the container's writable layer and is
generated again if it is absent.

## Build locally

To build an image yourself, use Ubuntu 24.04 with Docker, `curl`, Python 3,
QEMU, `expect`, `picocom`, and `zstd` installed. KVM is optional for building;
without it, QEMU uses slower software emulation.

```sh
./scripts/build-opnsense-disk.sh
VERSION="$(cat build/opnsense.version)"
docker build \
  --build-arg "OPNSENSE_VERSION=${VERSION}" \
  --tag "docker-opnsense:${VERSION}" .
```

The build starts from the current release image prepared by
[`anyvm-org/opnsense-builder`](https://github.com/anyvm-org/opnsense-builder),
applies available OPNsense updates, and uses the resulting guest version as
the image tag. It does not install an arbitrary pinned patch release. The
build also restores this project's expected LAN configuration and removes
builder-only SSH configuration. For details about publishing images and
maintaining the automated build, see [CONTRIBUTING.md](./CONTRIBUTING.md).
