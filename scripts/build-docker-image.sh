#!/usr/bin/env bash
# Copyright (c) Meta Platforms, Inc. and affiliates.

set -euo pipefail

IMAGE_NAME="${IMAGE_NAME:-extended-android-tools}"
DOCKER_BIN="${DOCKER_BIN:-docker}"

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
project_root="$(cd -- "$script_dir/.." && pwd -P)"
# shellcheck source=scripts/ndk-config.sh
source "$script_dir/ndk-config.sh"

if [[ -z "${DOCKER_PLATFORM:-}" ]]; then
    case "$(ndk_host_tag)" in
        linux-x86_64) DOCKER_PLATFORM=linux/amd64 ;;
        linux-aarch64) DOCKER_PLATFORM=linux/arm64 ;;
        *) exit 1 ;;
    esac
fi
case "$DOCKER_PLATFORM" in
    linux/amd64) docker_ndk_host_tag=linux-x86_64 ;;
    linux/arm64|linux/arm64/v8) docker_ndk_host_tag=linux-aarch64 ;;
    *) echo "error: unsupported Docker platform: $DOCKER_PLATFORM" >&2; exit 2 ;;
esac

if ! command -v "$DOCKER_BIN" >/dev/null 2>&1; then
    echo "error: Docker command not found: $DOCKER_BIN" >&2
    exit 1
fi
if [[ ! "$NDK_VERSION" =~ ^[A-Za-z0-9._-]+$ ]]; then
    echo "error: NDK_VERSION may contain only letters, numbers, dots, underscores, and dashes" >&2
    exit 2
fi
ndk_download_defaults "$docker_ndk_host_tag"

exec "$DOCKER_BIN" build \
    --pull \
    --no-cache \
    --platform "$DOCKER_PLATFORM" \
    --tag "$IMAGE_NAME" \
    --build-arg "NDK_DOWNLOAD_URL=$NDK_DOWNLOAD_URL" \
    --build-arg "NDK_DOWNLOAD_SHA256=$NDK_DOWNLOAD_SHA256" \
    --file "$project_root/docker/Dockerfile" \
    "$project_root"
