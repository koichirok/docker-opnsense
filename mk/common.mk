REPO=	koichirok/docker-opnsense
SED=	sed

INIT_SCRIPT_PATH=	/etc/init.d/qemu-opnsense
ENTRYPOINT_PATH=	/opt/qemu-opnsense/entrypoint.sh
API_KEY_GENERATOR_PATH=	/opt/qemu-opnsense/generate-api-key

.PHONY: all check-vars

# dummy default target
all:

check-vars:
ifndef VERSION
	$(error VERSION is not set)
else
	@true
endif
