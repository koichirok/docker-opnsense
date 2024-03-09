BASH=	bash
PERL=	perl
MONIT=	monit

test: syntax-check
syntax-check:
	@for file in entrypoint.sh qemu-opnsense/qemu-opnsense-service.sh; do \
		$(BASH) -n $$file; \
		echo $$file syntax OK; \
	done
	@$(PERL) -c qemu-opnsense/generate-opnsense-api-key.pl
	@$(MONIT) -t -c monitrc
