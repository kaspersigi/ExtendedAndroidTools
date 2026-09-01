#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0

set -euo pipefail

# Build-output verification configuration. Values can be overridden through
# the environment or by passing one or more architectures as arguments.
OUT_DIR="${OUT_DIR:-}"
ARCHES="${ARCHES:-arm64 x86_64}"

usage() {
    cat <<'EOF'
Verify ExtendedAndroidTools release artifacts without running Android code.

Usage:
  ./scripts/verify-artifacts.sh [arm64|x86_64 ...]

Environment variables:
  OUT_DIR  Build output directory (default: <project>/out).
  ARCHES   Space-separated architectures used when no arguments are supplied
           (default: "arm64 x86_64").
EOF
}

fail() {
    echo "error: $*" >&2
    exit 1
}

require_file() {
    [[ -f "$1" ]] || fail "required file is missing: $1"
}

require_archive_entry() {
    local listing="$1"
    local pattern="$2"
    local description="$3"

    if ! grep -Eq "$pattern" "$listing"; then
        fail "$description is missing from $(basename "${listing%.list}")"
    fi
}

reject_archive_entry() {
    local listing="$1"
    local pattern="$2"
    local description="$3"

    if grep -Eq "$pattern" "$listing"; then
        fail "$description was unexpectedly included in $(basename "${listing%.list}")"
    fi
}

elf_machine_pattern() {
    case "$1" in
    arm64)
        echo 'AArch64'
        ;;
    x86_64)
        echo 'Advanced Micro Devices X86-64|X86-64'
        ;;
    *)
        return 1
        ;;
    esac
}

verify_elf_architecture() {
    local binary="$1"
    local arch="$2"
    local expected_machine

    expected_machine="$(elf_machine_pattern "$arch")"
    if ! readelf -h "$binary" | grep -Eq "Machine:.*($expected_machine)"; then
        fail "$binary does not have the expected $arch ELF machine"
    fi
}

verify_static_dependencies() {
    local binary="$1"
    local dependency
    local dynamic_section

    dynamic_section="$(readelf -d "$binary" 2>/dev/null || true)"
    while IFS= read -r dependency; do
        [[ -n "$dependency" ]] || continue
        if is_android_system_library "$dependency"; then
            continue
        fi
        echo "$dynamic_section" >&2
        fail "$binary depends on non-system shared library $dependency"
    done < <(sed -n 's/.*Shared library: \[\([^]]*\)\].*/\1/p' <<< "$dynamic_section")
}

is_elf_file() {
    local magic=""

    IFS= read -r -N 4 magic < "$1" || true
    [[ "$magic" == $'\x7fELF' ]]
}

is_android_system_library() {
    case "$1" in
    libc.so|libdl.so|liblog.so|libm.so|libz.so)
        return 0
        ;;
    *)
        return 1
        ;;
    esac
}

verify_archive_elf_closure() {
    local archive_root="$1"
    local arch="$2"
    local candidate
    local dependency
    local relative_candidate
    local soname
    local -A provided_libraries=()

    while IFS= read -r -d '' candidate; do
        if ! is_elf_file "$candidate"; then
            continue
        fi

        verify_elf_architecture "$candidate" "$arch"
        provided_libraries["$(basename -- "$candidate")"]=1
        soname="$(readelf -d "$candidate" 2>/dev/null | \
            sed -n 's/.*(SONAME).*\[\([^]]*\)\].*/\1/p' | head -n 1)"
        if [[ -n "$soname" ]]; then
            provided_libraries["$soname"]=1
        fi
    done < <(find "$archive_root" -type f -print0)

    while IFS= read -r -d '' candidate; do
        if ! is_elf_file "$candidate"; then
            continue
        fi

        relative_candidate="${candidate#"$archive_root"/}"
        while IFS= read -r dependency; do
            [[ -n "$dependency" ]] || continue
            if [[ -n "${provided_libraries[$dependency]+present}" ]] || \
               is_android_system_library "$dependency"; then
                continue
            fi
            fail "$relative_candidate needs unpackaged shared library $dependency"
        done < <(readelf -d "$candidate" 2>/dev/null | \
            sed -n 's/.*Shared library: \[\([^]]*\)\].*/\1/p')
    done < <(find "$archive_root" -type f -print0)
}

if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
    usage
    exit 0
fi

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
project_root="$(cd -- "$script_dir/.." && pwd -P)"
OUT_DIR="${OUT_DIR:-$project_root/out}"

for command_name in find grep readelf sed tar; do
    command -v "$command_name" >/dev/null 2>&1 || \
        fail "required verification command is missing: $command_name"
done

if (( $# != 0 )); then
    requested_arches=("$@")
else
    read -r -a requested_arches <<< "$ARCHES"
fi

(( ${#requested_arches[@]} != 0 )) || fail "no architectures were selected"

work_dir="$(mktemp -d "${TMPDIR:-/tmp}/extended-android-tools-verify.XXXXXX")"
trap 'rm -rf -- "$work_dir"' EXIT

for arch in "${requested_arches[@]}"; do
    elf_machine_pattern "$arch" >/dev/null || fail "unsupported architecture: $arch"

    full_archive="$OUT_DIR/bpftools-$arch.tar.gz"
    minimal_archive="$OUT_DIR/bpftools-min-$arch.tar.gz"
    static_binary="$OUT_DIR/bpftrace-$arch"
    full_listing="$work_dir/bpftools-$arch.tar.gz.list"
    minimal_listing="$work_dir/bpftools-min-$arch.tar.gz.list"
    extract_dir="$work_dir/extract-$arch"
    full_extract_dir="$extract_dir/full"
    minimal_extract_dir="$extract_dir/minimal"

    require_file "$full_archive"
    require_file "$minimal_archive"
    require_file "$static_binary"
    tar -tzf "$full_archive" > "$full_listing"
    tar -tzf "$minimal_archive" > "$minimal_listing"

    require_archive_entry "$full_listing" '^bpftools/bin/bpftrace$' 'bpftrace binary'
    require_archive_entry "$full_listing" '^bpftools/bin/python3([.][0-9]+)?$' 'Python binary'
    require_archive_entry "$full_listing" '^bpftools/python3$' 'Python wrapper'
    require_archive_entry "$full_listing" '^bpftools/pip3$' 'pip wrapper'
    require_archive_entry "$full_listing" '^bpftools/lib/libLLVM.*[.]so' 'LLVM shared library'
    require_archive_entry "$full_listing" '^bpftools/lib/libssl[.]so' 'OpenSSL SSL library'
    require_archive_entry "$full_listing" '^bpftools/lib/libcrypto[.]so' 'OpenSSL crypto library'
    require_archive_entry "$full_listing" '^bpftools/lib/libzstd[.]so' 'Zstandard library'
    require_archive_entry "$full_listing" '^bpftools/share/certs/cacert[.]pem$' 'CA certificate bundle'
    require_archive_entry "$full_listing" '^bpftools/lib/python[^/]*/lib-dynload/_ssl[^/]*[.]so$' 'Python _ssl module'
    require_archive_entry "$full_listing" '^bpftools/lib/python[^/]*/lib-dynload/_zstd[^/]*[.]so$' 'Python _zstd module'
    require_archive_entry "$full_listing" '^bpftools/licenses/' 'third-party licenses'

    require_archive_entry "$minimal_listing" '^bpftools-min/bin/bpftrace$' 'minimal bpftrace binary'
    require_archive_entry "$minimal_listing" '^bpftools-min/lib/libLLVM.*[.]so' 'minimal LLVM shared library'
    require_archive_entry "$minimal_listing" '^bpftools-min/licenses/' 'minimal third-party licenses'
    reject_archive_entry "$minimal_listing" '^bpftools-min/(python3|pip3)$' 'Python or pip wrapper'
    reject_archive_entry "$minimal_listing" '^bpftools-min/lib/(libpython|libssl|libcrypto|libzstd)' 'Python, OpenSSL, or Zstandard library'

    mkdir -p "$full_extract_dir" "$minimal_extract_dir"
    tar -xzf "$full_archive" -C "$full_extract_dir"
    tar -xzf "$minimal_archive" -C "$minimal_extract_dir"
    verify_archive_elf_closure "$full_extract_dir/bpftools" "$arch"
    verify_archive_elf_closure "$minimal_extract_dir/bpftools-min" "$arch"
    verify_elf_architecture "$static_binary" "$arch"
    verify_static_dependencies "$static_binary"

    echo "Verified all three $arch release artifacts."
done

echo "Artifact verification completed successfully."
