#!/usr/bin/env bash
# Copyright (c) Meta Platforms, Inc. and affiliates.

set -euo pipefail

IMAGE_NAME="${IMAGE_NAME:-extended-android-tools}"
DOCKER_BIN="${DOCKER_BIN:-docker}"
DOCKER_PLATFORM="${DOCKER_PLATFORM:-linux/amd64}"
NDK_VERSION="${NDK_VERSION:-r27d}"
NDK_DOWNLOAD_SHA256="${NDK_DOWNLOAD_SHA256:-}"

if [[ -z "$NDK_DOWNLOAD_SHA256" && "$NDK_VERSION" == "r27d" ]]; then
    NDK_DOWNLOAD_SHA256="601246087a682d1944e1e16dd85bc6e49560fe8b6d61255be2829178c8ed15d9"
fi

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
project_root="$(cd -- "$script_dir/.." && pwd -P)"

if ! command -v "$DOCKER_BIN" >/dev/null 2>&1; then
    echo "error: Docker command not found: $DOCKER_BIN" >&2
    exit 1
fi
if [[ ! "$NDK_VERSION" =~ ^[A-Za-z0-9._-]+$ ]]; then
    echo "error: NDK_VERSION may contain only letters, numbers, dots, underscores, and dashes" >&2
    exit 2
fi
if [[ ! "$NDK_DOWNLOAD_SHA256" =~ ^[0-9a-f]{64}$ ]]; then
    echo "error: NDK_DOWNLOAD_SHA256 must be set to a lowercase SHA-256 value" >&2
    exit 2
fi

exec "$DOCKER_BIN" build \
    --pull \
    --no-cache \
    --platform "$DOCKER_PLATFORM" \
    --tag "$IMAGE_NAME" \
    --build-arg "NDK_VERSION=$NDK_VERSION" \
    --build-arg "NDK_DOWNLOAD_SHA256=$NDK_DOWNLOAD_SHA256" \
    --file "$project_root/docker/Dockerfile" \
    "$script_dir"
