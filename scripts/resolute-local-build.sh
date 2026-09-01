#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0

set -euo pipefail

# -----------------------------------------------------------------------------
# Build configuration
#
# Edit the defaults below when this script is your regular build entry point,
# or override any value from the environment, for example:
#   THREADS=8 NDK_API=35 NDK_ARCH=x86_64 ./scripts/resolute-local-build.sh
# -----------------------------------------------------------------------------
BUILD_TARGET="${BUILD_TARGET:-all}"
THREADS="${THREADS:-$(nproc)}"
NDK_API="${NDK_API:-35}"
NDK_ARCH="${NDK_ARCH:-arm64}"
NDK_VERSION="${NDK_VERSION:-r27d}"
NDK_PATH="${NDK_PATH:-}"
PREFERRED_NDK_PATH="${PREFERRED_NDK_PATH:-/mnt/develop/android-ndk-$NDK_VERSION}"
NDK_TMP_DIR="${NDK_TMP_DIR:-/tmp}"
NDK_DOWNLOAD_URL="${NDK_DOWNLOAD_URL:-}"
BUILD_TYPE="${BUILD_TYPE:-Release}"
STATIC_LINKING="${STATIC_LINKING:-false}"
LLVM_BPF_ONLY="${LLVM_BPF_ONLY:-false}"
DOWNLOAD_NDK="${DOWNLOAD_NDK:-1}"
ALLOW_UNSUPPORTED_HOST="${ALLOW_UNSUPPORTED_HOST:-0}"
CLEAN_MODULES="${CLEAN_MODULES:-}"
CLEAN_ALL="${CLEAN_ALL:-0}"
CLEAN_ONLY="${CLEAN_ONLY:-0}"

usage() {
    cat <<'EOF'
Build ExtendedAndroidTools directly on an Ubuntu 26.04 (Resolute) host.

Usage:
  ./scripts/resolute-local-build.sh [target ...]

The default target is configured by BUILD_TARGET. The special target "all"
builds all six release artifacts for arm64 and x86_64. Other positional
arguments are passed through as Make targets. Examples:
  ./scripts/resolute-local-build.sh
  ./scripts/resolute-local-build.sh all
  NDK_ARCH=x86_64 NDK_API=35 THREADS=8 ./scripts/resolute-local-build.sh bpftools-min
  NDK_ARCH=x86_64 ./scripts/resolute-local-build.sh bpftrace-static
  NDK_PATH=/opt/android-ndk-r27d ./scripts/resolute-local-build.sh python
  CLEAN_MODULES=llvm ./scripts/resolute-local-build.sh
  CLEAN_ALL=1 CLEAN_ONLY=1 ./scripts/resolute-local-build.sh

Environment variables:
  BUILD_TARGET           Default target when no argument is given (all).
  THREADS                Parallel jobs passed to nested builds (default: nproc).
  NDK_API                Android API level used for compilation (default: 35).
  NDK_ARCH               arm64 (default), x86_64, or armv7 for individual
                         targets. The special all target builds arm64/x86_64.
  NDK_VERSION            Android NDK release used for auto-download (default: r27d).
  NDK_PATH               Explicit Android NDK path. It takes highest priority.
  PREFERRED_NDK_PATH     Preferred existing NDK path
                         (default: /mnt/develop/android-ndk-r27d).
  NDK_TMP_DIR            Auto-download parent directory (default: /tmp).
  NDK_DOWNLOAD_URL       Optional complete URL overriding the Google NDK URL.
  BUILD_TYPE             Release (default) or Debug.
  STATIC_LINKING         true or false (default: false).
  LLVM_BPF_ONLY          true or false (default: false).
  DOWNLOAD_NDK           Set to 0 to disable automatic NDK download.
  ALLOW_UNSUPPORTED_HOST Set to 1 to bypass the Ubuntu 26.04 host check.
  CLEAN_MODULES          Comma- or space-separated source modules to remove
                         before building, for example llvm or "llvm,bcc".
                         Also clears shared build/output/package artifacts.
  CLEAN_ALL              Set to 1 to clear all build/output/package artifacts
                         and all fetched project sources before building.
  CLEAN_ONLY             Set to 1 to stop after CLEAN_MODULES or CLEAN_ALL.

Cleanup never removes an NDK outside this repository, including an NDK cached
under /tmp.
EOF
}

download_ndk_to_tmp() {
    local archive_name="android-ndk-${NDK_VERSION}-linux.zip"
    local download_url="$NDK_DOWNLOAD_URL"
    local staging_dir
    local archive_path
    local extracted_ndk

    if [[ -z "$download_url" ]]; then
        download_url="https://dl.google.com/android/repository/$archive_name"
    fi

    staging_dir="$(mktemp -d "$NDK_TMP_DIR/extended-android-tools-ndk.XXXXXX")"
    archive_path="$staging_dir/$archive_name"
    extracted_ndk="$staging_dir/android-ndk-$NDK_VERSION"

    echo "Downloading Android NDK $NDK_VERSION into temporary storage..."
    if ! curl --fail --location --retry 3 --output "$archive_path" "$download_url"; then
        rm -rf -- "$staging_dir"
        return 1
    fi
    if ! unzip -q "$archive_path" -d "$staging_dir"; then
        rm -rf -- "$staging_dir"
        return 1
    fi

    if [[ ! -d "$extracted_ndk" ]]; then
        echo "error: downloaded archive does not contain android-ndk-$NDK_VERSION" >&2
        rm -rf -- "$staging_dir"
        return 1
    fi

    if ! mv "$extracted_ndk" "$NDK_TMP_DIR/android-ndk-$NDK_VERSION"; then
        rm -rf -- "$staging_dir"
        return 1
    fi
    rm -rf -- "$staging_dir"
}

if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
    usage
    exit 0
fi

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
project_root="$(cd -- "$script_dir/.." && pwd -P)"

targets=("$@")
if (( ${#targets[@]} == 0 )); then
    if [[ -z "$BUILD_TARGET" ]]; then
        echo "error: BUILD_TARGET must not be empty when no target is provided" >&2
        exit 2
    fi
    targets=("$BUILD_TARGET")
fi

build_all=0
for target in "${targets[@]}"; do
    if [[ "$target" == "all" ]]; then
        if (( ${#targets[@]} != 1 )); then
            echo "error: the special target all cannot be combined with other targets" >&2
            exit 2
        fi
        build_all=1
    fi
done

for binary_flag_name in DOWNLOAD_NDK ALLOW_UNSUPPORTED_HOST CLEAN_ALL CLEAN_ONLY; do
    binary_flag_value="${!binary_flag_name}"
    if [[ "$binary_flag_value" != "0" && "$binary_flag_value" != "1" ]]; then
        echo "error: $binary_flag_name must be 0 or 1" >&2
        exit 2
    fi
done

normalized_clean_modules="${CLEAN_MODULES//,/ }"
clean_modules=()
if [[ -n "$normalized_clean_modules" ]]; then
    read -r -a requested_clean_modules <<< "$normalized_clean_modules"
    declare -A seen_clean_modules=()

    for clean_module in "${requested_clean_modules[@]}"; do
        if [[ ! "$clean_module" =~ ^[a-z0-9][a-z0-9+._-]*$ ]]; then
            echo "error: invalid module name in CLEAN_MODULES: $clean_module" >&2
            exit 2
        fi
        if [[ -n "${seen_clean_modules[$clean_module]+present}" ]]; then
            continue
        fi
        if ! make --silent -C "$project_root" --dry-run \
            "remove-$clean_module-sources" >/dev/null 2>&1; then
            echo "error: module does not have a removable source cache: $clean_module" >&2
            exit 2
        fi
        clean_modules+=("$clean_module")
        seen_clean_modules["$clean_module"]=1
    done
fi

if [[ "$CLEAN_ALL" == "1" && ${#clean_modules[@]} -ne 0 ]]; then
    echo "error: CLEAN_ALL and CLEAN_MODULES cannot be used together" >&2
    exit 2
fi

cleanup_requested=0
if [[ "$CLEAN_ALL" == "1" || ${#clean_modules[@]} -ne 0 ]]; then
    cleanup_requested=1
fi
if [[ "$CLEAN_ONLY" == "1" && "$cleanup_requested" == "0" ]]; then
    echo "error: CLEAN_ONLY=1 requires CLEAN_ALL or CLEAN_MODULES" >&2
    exit 2
fi

if [[ "$cleanup_requested" == "1" ]]; then
    echo "Cleaning shared build and output artifacts..."
    make --silent -C "$project_root" clean

    if [[ "$CLEAN_ALL" == "1" ]]; then
        echo "Removing all fetched project sources..."
        make --silent -C "$project_root" remove-sources
    else
        for clean_module in "${clean_modules[@]}"; do
            echo "Removing fetched sources for module: $clean_module"
            make --silent -C "$project_root" "remove-$clean_module-sources"
        done
    fi

    while IFS= read -r -d '' package_archive; do
        echo "Removing package artifact: ${package_archive##*/}"
        rm -f -- "$package_archive"
    done < <(find "$project_root" -maxdepth 1 -type f \
        -name 'bpftools-*.tar.gz' -print0)

    if [[ "$CLEAN_ONLY" == "1" ]]; then
        echo "Cleanup completed; CLEAN_ONLY=1, so no build was started."
        exit 0
    fi
fi

if [[ ! -r /etc/os-release ]]; then
    echo "error: cannot identify the host because /etc/os-release is unavailable" >&2
    exit 1
fi

# /etc/os-release is the system-provided source of distribution metadata.
# shellcheck disable=SC1091
source /etc/os-release

ubuntu_codename="${VERSION_CODENAME:-${UBUNTU_CODENAME:-}}"
if [[ "$ALLOW_UNSUPPORTED_HOST" != "1" ]] && \
   { [[ "${ID:-}" != "ubuntu" ]] || [[ "$ubuntu_codename" != "resolute" ]]; }; then
    echo "error: this script supports Ubuntu 26.04 (Resolute); detected ${PRETTY_NAME:-unknown}" >&2
    echo "       set ALLOW_UNSUPPORTED_HOST=1 to continue at your own risk" >&2
    exit 1
fi

if [[ "$(uname -m)" != "x86_64" ]]; then
    echo "error: the current build files require the NDK linux-x86_64 host toolchain" >&2
    exit 1
fi

required_commands=(
    autoreconf
    autopoint
    bison
    curl
    flex
    g++
    git
    help2man
    libtoolize
    make
    perl
    pkg-config
    po4a
    python3
    texi2any
    unzip
    wget
    xxd
    zstd
)
missing_commands=()
for required_command in "${required_commands[@]}"; do
    if ! command -v "$required_command" >/dev/null 2>&1; then
        missing_commands+=("$required_command")
    fi
done

if (( ${#missing_commands[@]} != 0 )); then
    echo "error: missing build commands: ${missing_commands[*]}" >&2
    echo "       run $project_root/scripts/resolute-install-deps.sh first" >&2
    exit 1
fi

ndk_arch="$NDK_ARCH"
ndk_api="$NDK_API"
build_type="$BUILD_TYPE"
threads="$THREADS"
static_linking="$STATIC_LINKING"
llvm_bpf_only="$LLVM_BPF_ONLY"

if [[ ! "$NDK_VERSION" =~ ^[A-Za-z0-9._-]+$ ]]; then
    echo "error: NDK_VERSION may contain only letters, numbers, dots, underscores, and dashes" >&2
    exit 2
fi

android_triple_for_arch() {
    case "$1" in
    arm64)
        echo "aarch64-linux-android"
        ;;
    x86_64)
        echo "x86_64-linux-android"
        ;;
    armv7)
        echo "armv7a-linux-androideabi"
        ;;
    *)
        return 1
        ;;
    esac
}

if ! android_triple_for_arch "$ndk_arch" >/dev/null; then
    echo "error: NDK_ARCH must be arm64, x86_64, or armv7" >&2
    exit 2
fi

if [[ "$build_type" != "Release" && "$build_type" != "Debug" ]]; then
    echo "error: BUILD_TYPE must be Release or Debug" >&2
    exit 2
fi

if [[ ! "$threads" =~ ^[1-9][0-9]*$ ]]; then
    echo "error: THREADS must be a positive integer" >&2
    exit 2
fi

if [[ ! "$ndk_api" =~ ^[1-9][0-9]*$ ]]; then
    echo "error: NDK_API must be a positive integer" >&2
    exit 2
fi

for boolean_value in "$static_linking" "$llvm_bpf_only"; do
    if [[ "$boolean_value" != "true" && "$boolean_value" != "false" ]]; then
        echo "error: STATIC_LINKING and LLVM_BPF_ONLY must be true or false" >&2
        exit 2
    fi
done

ndk_may_be_downloaded=false
if [[ -n "$NDK_PATH" ]]; then
    ndk_path="$NDK_PATH"
elif [[ -e "$PREFERRED_NDK_PATH" ]]; then
    ndk_path="$PREFERRED_NDK_PATH"
else
    ndk_path="$NDK_TMP_DIR/android-ndk-$NDK_VERSION"
    ndk_may_be_downloaded=true
fi

compiler_arches=("$ndk_arch")
if [[ "$build_all" == "1" ]]; then
    compiler_arches=(arm64 x86_64)
fi

missing_ndk_compilers=()
for compiler_arch in "${compiler_arches[@]}"; do
    compiler_triple="$(android_triple_for_arch "$compiler_arch")"
    ndk_compiler="$ndk_path/toolchains/llvm/prebuilt/linux-x86_64/bin/${compiler_triple}${ndk_api}-clang"
    if [[ ! -x "$ndk_compiler" ]]; then
        missing_ndk_compilers+=("$ndk_compiler")
    fi
done

if (( ${#missing_ndk_compilers[@]} != 0 )); then
    if [[ "$ndk_may_be_downloaded" != "true" ]]; then
        echo "error: selected NDK does not contain the expected compiler: ${missing_ndk_compilers[0]}" >&2
        exit 1
    fi
    if [[ "$DOWNLOAD_NDK" == "0" ]]; then
        echo "error: Android NDK $NDK_VERSION was not found and DOWNLOAD_NDK=0" >&2
        exit 1
    fi
    if [[ -e "$ndk_path" ]]; then
        echo "error: temporary NDK path exists but is incomplete: $ndk_path" >&2
        echo "       remove or repair that path before retrying" >&2
        exit 1
    fi

    ndk_parent="$NDK_TMP_DIR"
    mkdir -p "$ndk_parent"
    echo "Android NDK $NDK_VERSION was not found; downloading it to $ndk_parent..."
    download_ndk_to_tmp
fi

for compiler_arch in "${compiler_arches[@]}"; do
    compiler_triple="$(android_triple_for_arch "$compiler_arch")"
    ndk_compiler="$ndk_path/toolchains/llvm/prebuilt/linux-x86_64/bin/${compiler_triple}${ndk_api}-clang"
    if [[ ! -x "$ndk_compiler" ]]; then
        echo "error: expected NDK compiler was not installed: $ndk_compiler" >&2
        exit 1
    fi
done

echo "Building ExtendedAndroidTools locally"
echo "  project:        $project_root"
echo "  targets:        ${targets[*]}"
echo "  NDK_PATH:       $ndk_path"
if [[ "$build_all" == "1" ]]; then
    echo "  NDK_ARCH:       arm64 x86_64"
else
    echo "  NDK_ARCH:       $ndk_arch"
fi
echo "  NDK_API:        $ndk_api"
echo "  NDK_VERSION:    $NDK_VERSION"
echo "  BUILD_TYPE:     $build_type"
echo "  THREADS:        $threads"
if [[ "$build_all" == "1" ]]; then
    echo "  STATIC_LINKING: managed per artifact"
    echo "  LLVM_BPF_ONLY:  false (shared full LLVM build)"
else
    echo "  STATIC_LINKING: $static_linking"
    echo "  LLVM_BPF_ONLY:  $llvm_bpf_only"
fi

make_common_args=(
    "NDK_PATH=$ndk_path"
    "NDK_API=$ndk_api"
    "BUILD_TYPE=$build_type"
    "THREADS=$threads"
)

if [[ "$build_all" == "1" ]]; then
    for artifact_arch in arm64 x86_64; do
        echo "Building three $artifact_arch artifacts..."
        make -C "$project_root" \
            bpftools bpftools-min bpftrace-static \
            "${make_common_args[@]}" \
            "NDK_ARCH=$artifact_arch" \
            "STATIC_LINKING=false" \
            "LLVM_BPF_ONLY=false"
    done

    echo "All six artifacts are available under $project_root/out:"
    printf '  %s\n' \
        "bpftools-arm64.tar.gz" \
        "bpftools-min-arm64.tar.gz" \
        "bpftrace-arm64" \
        "bpftools-x86_64.tar.gz" \
        "bpftools-min-x86_64.tar.gz" \
        "bpftrace-x86_64"
    exit 0
fi

exec make -C "$project_root" \
    "${targets[@]}" \
    "${make_common_args[@]}" \
    "NDK_ARCH=$ndk_arch" \
    "STATIC_LINKING=$static_linking" \
    "LLVM_BPF_ONLY=$llvm_bpf_only"
