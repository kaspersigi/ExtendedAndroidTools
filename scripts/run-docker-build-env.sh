#!/usr/bin/env bash
# Copyright (c) Meta Platforms, Inc. and affiliates.

set -euo pipefail

IMAGE_NAME="${IMAGE_NAME:-extended-android-tools}"
DOCKER_BIN="${DOCKER_BIN:-docker}"
DOCKER_PLATFORM="${DOCKER_PLATFORM:-linux/amd64}"
THREADS="${THREADS:-$(nproc)}"
NDK_API="${NDK_API:-35}"
NDK_VERSION="${NDK_VERSION:-r27d}"

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
project_root="$(cd -- "$script_dir/.." && pwd -P)"

if ! command -v "$DOCKER_BIN" >/dev/null 2>&1; then
    echo "error: Docker command not found: $DOCKER_BIN" >&2
    exit 1
fi
if [[ ! "$THREADS" =~ ^[1-9][0-9]*$ ]]; then
    echo "error: THREADS must be a positive integer" >&2
    exit 2
fi
if [[ ! "$NDK_API" =~ ^[1-9][0-9]*$ ]]; then
    echo "error: NDK_API must be a positive integer" >&2
    exit 2
fi
if [[ ! "$NDK_VERSION" =~ ^[A-Za-z0-9._-]+$ ]]; then
    echo "error: NDK_VERSION may contain only letters, numbers, dots, underscores, and dashes" >&2
    exit 2
fi

exec "$DOCKER_BIN" run \
    --interactive \
    --tty \
    --rm \
    --platform "$DOCKER_PLATFORM" \
    --env "MAKEFLAGS=NDK_API=$NDK_API NDK_PATH=/opt/ndk/android-ndk-$NDK_VERSION THREADS=$THREADS" \
    --volume "$project_root:/ExtendedAndroidTools" \
    --workdir /ExtendedAndroidTools \
    "$IMAGE_NAME" \
    "$@"
