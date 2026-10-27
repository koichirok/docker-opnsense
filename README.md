# docker-opnsense

This is a Docker image for running OPNsense in a container using KVM.
It's intended for testing purposes and not designed for use in a production environment.

## Usage

To run this image, following options are required:

* `--cap_add NET_ADMIN`
* one of the following:
    * `--device /dev/kvm`
    * `--device-cgroup_rule "c 10:232 rwm"`

Set `OPNSENSE_VERSION` to a versioned tag published on GitHub Container Registry
(GHCR).

## Example Usage

Via `docker run`:

```sh
export OPNSENSE_VERSION=26.7.7 # Replace with an available GHCR tag.

docker run --rm -it \
    --device /dev/kvm \
    --cap_add NET_ADMIN \
    -p 10443:443 \
    "ghcr.io/koichirok/docker-opnsense:${OPNSENSE_VERSION}"
```

Via `docker-compose.yml`:

```yaml
services:
  opnsense:
    image: ghcr.io/koichirok/docker-opnsense:${OPNSENSE_VERSION}
    devices:
      - /dev/kvm
    # device_cgroup_rules:
    #   - 'c 10:232 rwm'
    cap_add:
      - NET_ADMIN
    ports:
      - 10443:443
    stop_grace_period: 3m
```

## Building Image

The build uses the current release image prepared by
[`anyvm-org/opnsense-builder`](https://github.com/anyvm-org/opnsense-builder),
then boots it with QEMU/KVM and applies the available OPNsense updates. The
resulting version is read from the guest and used as the Docker image tag; the
build does not claim to install an arbitrary, pinned patch release.

On Ubuntu 24.04 with Docker, KVM, `curl`, Python 3, QEMU, `expect`, `picocom`,
and `zstd` installed, build the disk and Docker image with:

```sh
./scripts/build-opnsense-disk.sh
VERSION="$(cat build/opnsense.version)"
docker build \
  --build-arg "OPNSENSE_VERSION=${VERSION}" \
  --tag "ghcr.io/koichirok/docker-opnsense:${VERSION}" .
```

The scheduled GitHub Actions workflow checks weekly for a new Production
release. A lightweight `check` job reads the stable `opnsense` package version
from the official package mirror (discovering the FreeBSD amd64 ABI for the
selected series), then checks for that version's manifest on GHCR. Only a
missing manifest (HTTP 404 after successful registry authentication) triggers
a build; network, authentication, and parsing
errors fail the check instead of being treated as "no update".
The build pushes the versioned image to GHCR using the automatically provided
`GITHUB_TOKEN`; no Docker Hub credentials or personal access token are needed.
The check job has `packages: read` permission and the build job has
`packages: write` permission. The `workflow_dispatch` trigger can
be used to run it manually; leave the series input empty for the latest
Production series. Enable `force` to skip the registry lookup and rebuild an
already published version.
Package revisions (such as `_1`) and dependency-only updates do not trigger
automatic rebuilds. There is no periodic forced rebuild.
The actual updated guest version must match the checked version before
publishing; a mismatch fails the build so the next run can check again.
The build runner must expose a usable `/dev/kvm`; the current
`anyvm-org/opnsense-builder` release must also contain a disk for the selected
series.

For the first publication, run the workflow manually with `force: true`:
GHCR can deny registry token requests for a package that does not exist yet.
After the push, change the package visibility to **Public** in its GitHub
package settings so users can pull without logging in. The workflow links the
package to this repository. If a package with this name already exists,
ensure this repository has Actions access to it before running the workflow.
Outside Actions, the release check can access a public package anonymously;
for authenticated checks, set `GH_TOKEN` and `GITHUB_ACTOR` to credentials
with package read access.

The downloaded VM image is the CI-ready qcow2 release from the upstream
builder. Before using it in the container, the build applies OPNsense updates,
restores the LAN configuration expected by this project, and removes the
builder's CI-only SSH key/configuration.

Before shutdown, the build zeroes root filesystem free space, leaving 64 MiB
of headroom for guest services, then converts the stopped disk to a compressed,
sparse qcow2. QEMU unmaps zero writes during this step to avoid allocating the
full virtual disk on the build host. This is compaction, not secure erasure.
The runtime image excludes build-only disk tools and unused QEMU executables.

At startup, the container creates a root API key using the current user
management API (or the legacy user manager on older releases). Credentials
are saved as a JSON object containing `key` and `secret`, with file mode
`0600`, at `OPNSENSE_API_KEY_FILE`. Failure to generate the key fails startup
instead of reporting the container as ready.