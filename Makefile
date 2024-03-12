include mk/common.mk

.PHONY: all build builder image docker-login

all: build

docker-login:
	@docker login

builder:
	@make -C image-builder builder

image:
	@make -C image-builder image

test-src:
	@make -C src test

src:
	@make -C src

Dockerfile: Dockerfile.in
	@$(SED) -e 's|@INIT_SCRIPT_PATH@|$(INIT_SCRIPT_PATH)|g' \
		-e 's|@ENTRYPOINT_PATH@|$(ENTRYPOINT_PATH)|g' \
		-e 's|@API_KEY_GENERATOR_PATH@|$(API_KEY_GENERATOR_PATH)|g' \
		$< > $@

build: Dockerfile src check-vars
	@docker build . -t ${REPO}:${VERSION} --build-arg OPNSENSE_VERSION=${VERSION}

push: check-vars
	@docker push ${REPO}:${VERSION}

lint:
	@hadolint Dockerfile	

clean:
	@rm -f Dockerfile