#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0

set -euo pipefail

OUT_DIR="${OUT_DIR:-}"
ARCHES="${ARCHES:-arm64 x86_64}"
CHECKSUM_FILE="${CHECKSUM_FILE:-}"

usage() {
    cat <<'EOF'
Generate SHA-256 checksums for ExtendedAndroidTools release artifacts.

Usage:
  ./scripts/generate-checksums.sh [arm64|x86_64 ...]

Environment variables:
  OUT_DIR       Build output directory (default: <project>/out).
  ARCHES        Architectures used when no arguments are supplied.
  CHECKSUM_FILE Output file (default: <OUT_DIR>/SHA256SUMS).
EOF
}

fail() {
    echo "error: $*" >&2
    exit 1
}

if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
    usage
    exit 0
fi

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
project_root="$(cd -- "$script_dir/.." && pwd -P)"
OUT_DIR="${OUT_DIR:-$project_root/out}"
CHECKSUM_FILE="${CHECKSUM_FILE:-$OUT_DIR/SHA256SUMS}"
if [[ "$CHECKSUM_FILE" != /* ]]; then
    CHECKSUM_FILE="$project_root/$CHECKSUM_FILE"
fi

if (( $# != 0 )); then
    requested_arches=("$@")
else
    read -r -a requested_arches <<< "$ARCHES"
fi
(( ${#requested_arches[@]} != 0 )) || fail "no architectures were selected"

artifact_names=()
for arch in "${requested_arches[@]}"; do
    case "$arch" in
    arm64|x86_64) ;;
    *) fail "unsupported architecture: $arch" ;;
    esac

    artifact_names+=(
        "bpftools-$arch.tar.gz"
        "bpftools-min-$arch.tar.gz"
        "bpftrace-$arch"
    )
done

for artifact_name in "${artifact_names[@]}"; do
    [[ -f "$OUT_DIR/$artifact_name" ]] || fail "required artifact is missing: $OUT_DIR/$artifact_name"
done

mkdir -p "$(dirname -- "$CHECKSUM_FILE")"
temporary_file="$(mktemp "$(dirname -- "$CHECKSUM_FILE")/.SHA256SUMS.XXXXXX")"
trap 'rm -f -- "$temporary_file"' EXIT
(
    cd "$OUT_DIR"
    sha256sum "${artifact_names[@]}"
) | LC_ALL=C sort -k2 > "$temporary_file"
chmod 0644 "$temporary_file"
mv "$temporary_file" "$CHECKSUM_FILE"
trap - EXIT

echo "Wrote checksums to $CHECKSUM_FILE"
