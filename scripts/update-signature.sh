#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0

set -euo pipefail

if (( $# < 2 )); then
    echo "usage: $0 OUTPUT KEY=VALUE [...]" >&2
    exit 2
fi

output_file="$1"
shift
output_dir="$(dirname -- "$output_file")"
mkdir -p "$output_dir"

temporary_file="$(mktemp "$output_dir/.signature.XXXXXX")"
trap 'rm -f -- "$temporary_file"' EXIT
printf '%s\n' "$@" > "$temporary_file"

if [[ -f "$output_file" ]] && cmp -s "$output_file" "$temporary_file"; then
    chmod 0644 "$output_file"
    exit 0
fi

if [[ -f "$output_file" ]]; then
    echo "Configuration signature changed: $output_file"
    diff -u "$output_file" "$temporary_file" || true
else
    echo "Recording configuration signature: $output_file"
fi

chmod 0644 "$temporary_file"
mv "$temporary_file" "$output_file"
trap - EXIT
