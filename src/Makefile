BASH=	bash
PERL=	perl

all: entrypoint.sh qemu-opnsense-init.sh

include ../mk/common.mk

test: syntax-check

entrypoint.sh: entrypoint.sh.in
	@$(SED) -e 's|@INIT_SCRIPT_PATH@|$(INIT_SCRIPT_PATH)|g' $< > $@

qemu-opnsense-init.sh: qemu-opnsense-init.sh.in
	@$(SED) -e 's|@API_KEY_GENERATOR_PATH@|$(API_KEY_GENERATOR_PATH)|g' $< > $@

syntax-check: all
	@for file in entrypoint.sh qemu-opnsense-init.sh; do \
		$(BASH) -n $$file; \
		echo $$file syntax OK; \
	done
	@$(PERL) -c generate-opnsense-api-key.pl

clean:
	@rm -f entrypoint.sh qemu-opnsense-init.sh
