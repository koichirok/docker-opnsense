include	../mk/common.mk

SERIES=	$(firstword $(subst ., ,$(VERSION))).$(word 2,$(subst ., ,$(VERSION)))
BUILDER_TAG=	image-builder
PATCH_VERSION=	$(word 3,$(subst ., ,$(VERSION)))
image_tag=	$(1)-image
IMAGE_TAG=	$(call image_tag,$(VERSION))

all: builder image

.PHONY: \
	builder image build-builder push-builder build-base-image push-base-imgage \
	build-update-image push-update-image create-insecure-builder \
	delete-insecure-builder do-build-update-image do-push-update-image

test: IMAGE_TAG = $(call image_tag,$(SERIES))
test:
	@echo "VERSION: $(VERSION)"
	@echo "SERIES: $(SERIES)"
	@echo "BUILDER_TAG: $(BUILDER_TAG)"
	@echo "IMAGE_TAG: $(IMAGE_TAG)"
	@echo "PATCH_VERSION: $(PATCH_VERSION)"
#all: src/* Dockerfile.builder Dockerfile.base Dockerfile.update

src/* Dockerfile.builder: builder
builder: $(if $(PUSH),push,build)-builder
build-builder:
	@echo "Building image builder"
	@docker build . -f Dockerfile.builder -t $(REPO):$(BUILDER_TAG)
push-builder: build-builder
	@echo "Pushing image builder"
	@docker push $(REPO):$(BUILDER_TAG)

image: $(if $(PUSH),push,build)-image

build-image: build-$(if $(PATCH_VERSION),update,base)-image
push-image: push-$(if $(PATCH_VERSION),update,base)-image

Dockerfile.base: build-base-image
build-base-image: IMAGE_TAG = $(call image_tag,$(SERIES))
build-base-image: check-vars
	@echo "Building base image"
	@docker build . -f Dockerfile.base -t $(REPO):$(IMAGE_TAG) --build-arg OPNSENSE_VERSION=$(SERIES)
push-base-image: IMAGE_TAG = $(call image_tag,$(SERIES))
push-base-imgage: check-vars build-base-image
	@echo "Pushing base image"
	@docker push $(REPO):$(IMAGE_TAG)

Dockerfile.update: build-update-image
build-update-image: insecure-builder do-build-update-image clean-insecure-builder
push-update-image: insecure-builder do-push-update-image clean-insecure-builder
do-build-update-image: check-vars
	@echo "Building updated image..."
	@docker build . -f Dockerfile.update -t "$(REPO):$(VERSION)-image" \
		--builder insecure-builder \
		--load \
		--allow security.insecure \
		--build-arg OPNSENSE_VERSION="$(VERSION)" \
		--build-arg OPNSENSE_SERIES="$(SERIES)"
do-push-update-image: check-vars do-build-update-image
	@echo "Pushing updated image"
	@docker push $(REPO):$(VERSION)-image

insecure-builder:
ifeq ($(shell docker buildx inspect insecure-builder > /dev/null 2>&1; echo $$?), 0)
	@echo "Insecure builder already exists."
else
	@echo "Creating insecure builder..."
	@docker buildx create --use --name insecure-builder \
		--buildkitd-flags "--allow-insecure-entitlement security.insecure"
endif

clean-insecure-builder:
ifndef KEEP_CUSTOM_BUILDER
	@echo "Deleting insecure builder..."
	@docker buildx rm insecure-builder || true
endif	

clean: clean-insecure-builder
	@echo "Cleaning up..."
	@docker rmi $(REPO):image-builder || true
ifdef VERSION
	@docker image rm $(REPO):$(SERIES)-image || true
	@docker image rm $(REPO):$(VERSION)-image || true
else
	@echo No VERSION specified. skip deleting versioned images
endif
