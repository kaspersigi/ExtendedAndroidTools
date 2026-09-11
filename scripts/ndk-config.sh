#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# Sourced by local builds, Docker helpers and CI. NDK release selection lives
# exclusively in projects/versions.mk; no shell copy of those defaults is kept.

ndk_manifest="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)/projects/versions.mk"

ndk_manifest_value() {
    awk -v key="$1" '
        $1 == key && $2 == ":=" && NF == 3 { value = $3; count++ }
        END { if (count != 1) exit 1; print value }
    ' "$ndk_manifest" || {
        echo "error: expected one literal $1 := value in $ndk_manifest" >&2
        return 1
    }
}

ndk_config_version="$(ndk_manifest_value NDK_VERSION)"
if [[ -n "${NDK_VERSION:-}" && "$NDK_VERSION" != "$ndk_config_version" ]]; then
    echo "error: configure NDK_VERSION in $ndk_manifest" >&2
    return 2
fi
NDK_VERSION="$ndk_config_version"
NDK_REVISION="$(ndk_manifest_value NDK_REVISION)"
NDK_API="${NDK_API:-$(ndk_manifest_value NDK_API)}"
NDK_DOWNLOAD_URL="${NDK_DOWNLOAD_URL:-}"
NDK_DOWNLOAD_SHA256="${NDK_DOWNLOAD_SHA256:-}"

ndk_host_tag() {
    case "${1:-$(uname -m)}" in
        x86_64|amd64) echo linux-x86_64 ;;
        aarch64|arm64) echo linux-aarch64 ;;
        *) echo "error: unsupported NDK host architecture: ${1:-$(uname -m)}" >&2; return 1 ;;
    esac
}

# Google supplies the Linux x86_64 archive. Linux AArch64 needs the locally
# built NDK, or an explicitly supplied archive URL and its own checksum.
ndk_download_defaults() {
    if [[ -z "$NDK_DOWNLOAD_URL" ]]; then
        if [[ "$1" != "linux-x86_64" ]]; then
            echo "error: $1 requires a self-built NDK; set NDK_PATH locally or NDK_DOWNLOAD_URL and NDK_DOWNLOAD_SHA256" >&2
            return 1
        fi
        NDK_DOWNLOAD_URL="https://dl.google.com/android/repository/android-ndk-$NDK_VERSION-linux.zip"
        NDK_DOWNLOAD_SHA256="${NDK_DOWNLOAD_SHA256:-$(ndk_manifest_value NDK_LINUX_X86_64_SHA256)}"
    fi
    if [[ ! "$NDK_DOWNLOAD_SHA256" =~ ^[0-9a-f]{64}$ ]]; then
        echo "error: NDK_DOWNLOAD_SHA256 must be set to a lowercase SHA-256 value for this download" >&2
        return 2
    fi
}

ndk_validate_revision() {
    local actual_revision
    actual_revision="$(sed -n 's/^[[:space:]]*Pkg\.Revision[[:space:]]*=[[:space:]]*//p' "$1/source.properties")"
    if [[ "$actual_revision" != "$NDK_REVISION" ]]; then
        echo "error: expected NDK $NDK_VERSION revision $NDK_REVISION at $1; found ${actual_revision:-unknown}" >&2
        return 1
    fi
}
