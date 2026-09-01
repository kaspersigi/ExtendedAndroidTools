#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0

set -euo pipefail

# Device-test configuration. Auto mode skips cleanly unless exactly one usable
# device is selected; required mode turns selection failures into errors.
DEVICE_TEST="${DEVICE_TEST:-auto}"
DEVICE_NETWORK_TEST="${DEVICE_NETWORK_TEST:-1}"
DEVICE_NETWORK_REQUIRED="${DEVICE_NETWORK_REQUIRED:-0}"
DEVICE_BPF_REQUIRED="${DEVICE_BPF_REQUIRED:-0}"
ADB="${ADB:-adb}"
ANDROID_SERIAL="${ANDROID_SERIAL:-}"
OUT_DIR="${OUT_DIR:-}"

usage() {
    cat <<'EOF'
Run ExtendedAndroidTools smoke tests on a connected Android device.

Usage:
  ./scripts/android-smoke-test.sh

Environment variables:
  DEVICE_TEST              auto (default), required, or 0.
  DEVICE_NETWORK_TEST      Test an online pure-Python pip install (default: 1).
  DEVICE_NETWORK_REQUIRED  Fail instead of warn if the network test fails
                           (default: 0).
  DEVICE_BPF_REQUIRED      Require a root BPF BEGIN probe to pass (default: 0).
  ADB                      adb executable (default: adb).
  ANDROID_SERIAL           Explicit device serial; otherwise exactly one device
                           in the "device" state must be connected.
  OUT_DIR                  Build output directory (default: <project>/out).
EOF
}

fail() {
    echo "error: $*" >&2
    exit 1
}

skip_or_fail() {
    if [[ "$DEVICE_TEST" == "required" ]]; then
        fail "$*"
    fi
    echo "Skipping Android device tests: $*"
    exit 0
}

validate_zero_or_one() {
    local name="$1"
    local value="$2"
    [[ "$value" == "0" || "$value" == "1" ]] || fail "$name must be 0 or 1"
}

if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
    usage
    exit 0
fi
(( $# == 0 )) || { usage >&2; exit 2; }

[[ "$DEVICE_TEST" == "auto" || "$DEVICE_TEST" == "required" || "$DEVICE_TEST" == "0" ]] || \
    fail "DEVICE_TEST must be auto, required, or 0"
validate_zero_or_one DEVICE_NETWORK_TEST "$DEVICE_NETWORK_TEST"
validate_zero_or_one DEVICE_NETWORK_REQUIRED "$DEVICE_NETWORK_REQUIRED"
validate_zero_or_one DEVICE_BPF_REQUIRED "$DEVICE_BPF_REQUIRED"

if [[ "$DEVICE_TEST" == "0" ]]; then
    echo "Skipping Android device tests: DEVICE_TEST=0."
    exit 0
fi

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
project_root="$(cd -- "$script_dir/.." && pwd -P)"
OUT_DIR="${OUT_DIR:-$project_root/out}"

command -v "$ADB" >/dev/null 2>&1 || skip_or_fail "adb is not installed"

adb_args=()
if [[ -n "$ANDROID_SERIAL" ]]; then
    adb_args=(-s "$ANDROID_SERIAL")
    device_state="$($ADB "${adb_args[@]}" get-state 2>/dev/null || true)"
    [[ "$device_state" == "device" ]] || skip_or_fail "ANDROID_SERIAL=$ANDROID_SERIAL is not ready"
else
    device_output="$($ADB devices 2>/dev/null || true)"
    mapfile -t connected_devices < <(awk '$2 == "device" { print $1 }' <<< "$device_output")
    if (( ${#connected_devices[@]} == 0 )); then
        skip_or_fail "no authorized device is in the device state"
    fi
    if (( ${#connected_devices[@]} != 1 )); then
        skip_or_fail "multiple devices are ready; set ANDROID_SERIAL explicitly"
    fi
    ANDROID_SERIAL="${connected_devices[0]}"
    adb_args=(-s "$ANDROID_SERIAL")
fi

if ! "$ADB" "${adb_args[@]}" shell true >/dev/null 2>&1; then
    skip_or_fail "adb lists $ANDROID_SERIAL as ready, but an adb shell connection could not be established"
fi

device_abi="$($ADB "${adb_args[@]}" shell getprop ro.product.cpu.abi | tr -d '\r')"
case "$device_abi" in
arm64-v8a)
    artifact_arch=arm64
    ;;
x86_64)
    artifact_arch=x86_64
    ;;
*)
    skip_or_fail "device ABI $device_abi is not supported"
    ;;
esac

full_archive="$OUT_DIR/bpftools-$artifact_arch.tar.gz"
minimal_archive="$OUT_DIR/bpftools-min-$artifact_arch.tar.gz"
static_binary="$OUT_DIR/bpftrace-$artifact_arch"
[[ -f "$full_archive" ]] || fail "device is connected but the full archive is missing: $full_archive"
[[ -f "$minimal_archive" ]] || fail "device is connected but the minimal archive is missing: $minimal_archive"
[[ -f "$static_binary" ]] || fail "device is connected but the static binary is missing: $static_binary"

remote_dir="/data/local/tmp/extended-android-tools-smoke-$$"
case "$remote_dir" in
/data/local/tmp/extended-android-tools-smoke-[0-9]*) ;;
*) fail "refusing unsafe remote test directory: $remote_dir" ;;
esac

cleanup_remote() {
    "$ADB" "${adb_args[@]}" shell rm -rf -- "$remote_dir" >/dev/null 2>&1 || true
}
trap cleanup_remote EXIT

echo "Testing $artifact_arch artifacts on $ANDROID_SERIAL ($device_abi)..."
"$ADB" "${adb_args[@]}" shell mkdir -p "$remote_dir"
"$ADB" "${adb_args[@]}" push "$full_archive" "$remote_dir/bpftools.tar.gz" >/dev/null
"$ADB" "${adb_args[@]}" push "$minimal_archive" "$remote_dir/bpftools-min.tar.gz" >/dev/null
"$ADB" "${adb_args[@]}" push "$static_binary" "$remote_dir/bpftrace-static" >/dev/null
"$ADB" "${adb_args[@]}" shell "cd '$remote_dir' && tar -xzf bpftools.tar.gz && tar -xzf bpftools-min.tar.gz && chmod 755 bpftrace-static"

bpftools_dir="$remote_dir/bpftools"
bpftools_min_dir="$remote_dir/bpftools-min"
"$ADB" "${adb_args[@]}" shell "$bpftools_dir/bpftrace --version"
"$ADB" "${adb_args[@]}" shell "$bpftools_min_dir/bpftrace --version"
"$ADB" "${adb_args[@]}" shell "$remote_dir/bpftrace-static --version"
"$ADB" "${adb_args[@]}" shell "$bpftools_dir/python3 -V"
"$ADB" "${adb_args[@]}" shell "$bpftools_dir/python3 -c 'import compression.zstd, ctypes, lzma, ssl, zlib; print(ssl.OPENSSL_VERSION)'"
"$ADB" "${adb_args[@]}" shell "$bpftools_dir/pip3 --version"

if [[ "$DEVICE_NETWORK_TEST" == "1" ]]; then
    network_command="PYTHONPATH='$remote_dir/pip-target' '$bpftools_dir/pip3' install --disable-pip-version-check --no-cache-dir --no-compile --target '$remote_dir/pip-target' idna && PYTHONPATH='$remote_dir/pip-target' '$bpftools_dir/python3' -c 'import idna; print(idna.__version__)'"
    if ! "$ADB" "${adb_args[@]}" shell "$network_command"; then
        if [[ "$DEVICE_NETWORK_REQUIRED" == "1" ]]; then
            fail "online pip installation failed"
        fi
        echo "warning: online pip installation could not be verified; device networking may be unavailable" >&2
    fi
fi

device_uid="$($ADB "${adb_args[@]}" shell id -u | tr -d '\r')"
if [[ "$device_uid" == "0" ]]; then
    if ! "$ADB" "${adb_args[@]}" shell "$bpftools_dir/bpftrace -e 'BEGIN { printf(\"EAT_BPF_OK\\n\"); exit(); }'"; then
        if [[ "$DEVICE_BPF_REQUIRED" == "1" ]]; then
            fail "root BPF smoke test failed"
        fi
        echo "warning: binaries run, but this device kernel did not pass the BPF probe" >&2
    fi
elif [[ "$DEVICE_BPF_REQUIRED" == "1" ]]; then
    fail "DEVICE_BPF_REQUIRED=1 but adb shell is not root"
else
    echo "Skipping root BPF probe: adb shell uid is $device_uid."
fi

echo "Android device smoke tests completed for $ANDROID_SERIAL."
