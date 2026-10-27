#!/bin/bash -e

REPO=koichirok/docker-opnsense
: "${DO_PUSH:=--push}"
: "${KEEP_CUSTOM_BUILDER:=''}"
VERSION="$1"

if [ -z "$VERSION" ]; then
    echo "Usage: $0 <version>"
    exit 1
fi
SERIES="$(. ./image-builder/src/functions.bash; get_product_series "$VERSION")"

if cd ./image-builder; then
    # docker build . -f Dockerfile.builder -t $REPO:image-builder --pull "$DO_PUSH"
    # docker build . -f Dockerfile.base    -t "$REPO:$series-image" \
    #     --build-arg OPNSENSE_VERSION="$series" --pull "$DO_PUSH"
    if [ "$VERSION" != "$SERIES" ]; then
        if ! docker buildx inspect insecure-builder > /dev/null 2>&1; then
            docker buildx create --use --name insecure-builder \
                --buildkitd-flags '--allow-insecure-entitlement security.insecure'
        fi
        docker build . -f Dockerfile.update -t "$REPO:$VERSION-image" \
            --builder insecure-builder \
            --allow security.insecure \
            --build-arg OPNSENSE_VERSION="$VERSION" \
            --build-arg OPNSENSE_SERIES="$SERIES" \
            --pull "$DO_PUSH"
        if [ -z "$KEEP_CUSTOM_BUILDER" ]; then
            docker buildx rm insecure-builder
        fi
    fi
fi
