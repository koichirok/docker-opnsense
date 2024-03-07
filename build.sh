#!/bin/sh -e

REPO=koichirok/docker-opnsense
VERSION="$1"
: "${KEEP_CUSTOM_BUILDER:=''}"

if [ -z "$VERSION" ]; then
    echo "Usage: $0 <version>"
    exit 1
fi

if cd ./image-builder; then
    docker build . -f Dockerfile.builder -t $REPO:image-builder --pull --push
    docker build . -f Dockerfile.base    -t "$REPO:$VERSION-image" --build-arg OPNSENSE_VERSION="$VERSION" --pull --push
    . ./functions.bash
    series=$(get_product_series "$VERSION")
    if [ "$VERSION" != "$series" ]; then
        if ! docker buildx inspect insecure-builder > /dev/null 2>&1; then
            docker buildx create --use --name insecure-builder \
                --buildkitd-flags '--allow-insecure-entitlement security.insecure'
        fi
        docker build . -f Dockerfile.update -t "$REPO:$VERSION-image" \
            --builder insecure-builder \
            --allow security.insecure \
            --build-arg OPNSENSE_VERSION="$VERSION" \
            --build-arg OPNSENSE_SERIES="$series" \
            --pull --push
        if [ -z "$KEEP_CUSTOM_BUILDER" ]; then
            docker buildx rm insecure-builder
        fi
    fi
fi
