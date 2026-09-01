#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0

set -euo pipefail

usage() {
    cat <<'EOF'
Install the host packages required to build ExtendedAndroidTools locally on
Ubuntu 26.04 (Resolute).

Usage:
  ./scripts/resolute-install-deps.sh

Set ALLOW_UNSUPPORTED_HOST=1 to bypass the Ubuntu 26.04 host check.
EOF
}

if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
    usage
    exit 0
fi

if (( $# != 0 )); then
    usage >&2
    exit 2
fi

allow_unsupported_host="${ALLOW_UNSUPPORTED_HOST:-0}"
if [[ "$allow_unsupported_host" != "0" && "$allow_unsupported_host" != "1" ]]; then
    echo "error: ALLOW_UNSUPPORTED_HOST must be 0 or 1" >&2
    exit 2
fi

if [[ ! -r /etc/os-release ]]; then
    echo "error: cannot identify the host because /etc/os-release is unavailable" >&2
    exit 1
fi

# /etc/os-release is the system-provided source of distribution metadata.
# shellcheck disable=SC1091
source /etc/os-release

ubuntu_codename="${VERSION_CODENAME:-${UBUNTU_CODENAME:-}}"
if [[ "$allow_unsupported_host" != "1" ]] && \
   { [[ "${ID:-}" != "ubuntu" ]] || [[ "$ubuntu_codename" != "resolute" ]]; }; then
    echo "error: this script supports Ubuntu 26.04 (Resolute); detected ${PRETTY_NAME:-unknown}" >&2
    echo "       set ALLOW_UNSUPPORTED_HOST=1 to continue at your own risk" >&2
    exit 1
fi

packages=(
    autoconf
    automake
    autopoint
    binutils
    bison
    build-essential
    bzip2
    ca-certificates
    curl
    flex
    file
    g++
    gettext
    git
    help2man
    libltdl-dev
    libssl-dev
    libtool
    make
    patch
    perl
    pkg-config
    po4a
    python3
    tar
    texinfo
    unzip
    wget
    xxd
    zlib1g-dev
    zstd
)

if (( EUID == 0 )); then
    apt_command=(apt-get)
else
    if ! command -v sudo >/dev/null 2>&1; then
        echo "error: sudo is required when the script is not run as root" >&2
        exit 1
    fi
    apt_command=(sudo apt-get)
fi

echo "Installing ExtendedAndroidTools build dependencies for Ubuntu 26.04..."
"${apt_command[@]}" update
"${apt_command[@]}" install -y --no-install-recommends "${packages[@]}"

echo "Dependencies installed. Run ./scripts/resolute-local-build.sh to build locally."
