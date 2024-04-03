# docker-opnsense

This is a Docker image for running OPNsense in a container using KVM.
It's intended for testing purposes and not designed for use in a production environment.

## Usage

To run this image, following options are required:

* `--cap_add NET_ADMIN`
* one of the following:
    * `--device /dev/kvm`
    * `--device-cgroup_rule "c 10:232 rwm"`

## Example Usage

Via `docker run`:

```sh
docker run --rm -it \
    --device /dev/kvm \
    --cap_add NET_ADMIN \
    -p 10443:443 \
    koichirok/docker-opnsense:24.1.3
```

Via `docker-compose.yml`:

```yaml
version: "3"
services:
  opnsense:
    image: koichirok/docker-opnsense:24.1.3
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

If you want to create a Docker image of a version that has not yet been uploaded to Docker Hub, first create a Docker image with the ${VERSION}-image tag.

For example, to create an image of version 24.1.4:

```
make -C image-builder VERSION=24.1.4
```

This will create a Docker image which contains a sparsed QCOW2 image of the OPNsense.
The OPNsense is upgraded to the latest version if the specified version includes a patch version.

Note that builds specifying an older patch release version than the latest version will always fail.
This is because `opnsense-update` may fail when trying to upgrade to certain patch releases.
As a workaround, it was decided not to specify a version.

After preparing the ${VERSION}-image Docker image, you can build the docker-opnsense image as follows:

```
make VERSION=24.1.4
```