include mk/common.mk

.PHONY: builder image docker-login build

all: build

docker-login:
	@docker login

builder:
	@make -C image-builder builder

image:
	@make -C image-builder image

test-src:
	@make -C src test

build: check-vars test-src
	@docker build . -t ${REPO}:${VERSION} --build-arg OPNSENSE_VERSION=${VERSION}
