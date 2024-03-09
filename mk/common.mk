REPO=	koichirok/docker-opnsense

check-vars:
ifndef VERSION
	$(error VERSION is not set)
else
	@true
endif
