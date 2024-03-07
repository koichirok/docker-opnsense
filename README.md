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