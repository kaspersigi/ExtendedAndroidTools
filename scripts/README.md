# ExtendedAndroidTools local build guide for Ubuntu 26.04 (Resolute)

This document covers the following build and validation scripts:

- `scripts/resolute-install-deps.sh`
- `scripts/resolute-local-build.sh`
- `scripts/verify-artifacts.sh`
- `scripts/generate-checksums.sh`
- `scripts/android-smoke-test.sh`
- `scripts/test-bpftrace-tracefs.py`

These scripts build ExtendedAndroidTools directly on Ubuntu 26.04 (Resolute) x86_64 or
AArch64 hosts, without a Docker build environment.

`resolute-install-deps.sh` installs host dependencies. `resolute-local-build.sh` selects
or downloads the Android NDK, validates the build environment, optionally cleans caches,
and invokes the project Makefile for local cross-compilation. The default `all` build
also verifies six outputs, generates `out/SHA256SUMS`, and automatically runs device
smoke tests when adb can select exactly one available device.


## 1. Supported environment

Defaults:

- Host distribution: Ubuntu 26.04 (Resolute)
- Host architecture: x86_64 or AArch64
- Android NDK: r30
- Android API: 35
- Target architecture for ordinary builds: arm64 (`all` always builds arm64 and x86_64)
- Build type: Release
- Parallel jobs: the number of logical CPUs reported by `nproc`

The script selects the NDK host toolchain by host CPU: `linux-x86_64` on x86_64 and
`linux-aarch64` on AArch64. The official Google Linux package is available only for
x86_64. AArch64 hosts use a self-built r30 at `/mnt/develop/android-ndk-r30` or the path
specified by `NDK_PATH`. Automatic downloads on AArch64 require `NDK_DOWNLOAD_URL` and
`NDK_DOWNLOAD_SHA256` for that package; the script does not fall back to an x86_64
download. `NDK_ARCH` selects the Android target architecture independently of the host.

The NDK version, revision, default API, and official Linux x86_64 archive checksum are
configured in `projects/versions.mk`. Make, local scripts, Docker, and CI share this
configuration. Rebuild the Docker image after an upgrade. Before migrating an existing
build to a different NDK, run `make clean` to remove old objects and installed outputs
while retaining the `projects/*/sources/` cache.

`ALLOW_UNSUPPORTED_HOST=1` skips only the Ubuntu 26.04 distribution check. It does not
mean other distributions have been tested or are guaranteed to work.


## 2. Quick start

Enter the project root:

```bash
cd /mnt/develop/linux/ExtendedAndroidTools
```

Install build dependencies:

```bash
./scripts/resolute-install-deps.sh
```

Build all outputs with the default API 35 and Release configuration:

```bash
./scripts/resolute-local-build.sh
```

The default target is `all`. It builds arm64 and x86_64 in sequence, producing a full
archive, a minimal archive, and a static `bpftrace` for each architecture: six release
files in total.

```text
out/bpftools-arm64.tar.gz
out/bpftools-min-arm64.tar.gz
out/bpftrace-arm64
out/bpftools-x86_64.tar.gz
out/bpftools-min-x86_64.tar.gz
out/bpftrace-x86_64
```

Intermediate files and installed outputs are stored under:

```text
build/
out/
projects/*/sources/
projects/*/.source-signature
```

The repository `.gitignore` excludes these generated paths:

```text
build/
out/
projects/*/sources/
projects/*/.source-signature
```

Downloading sources and building normally therefore does not add these generated files
to Git status.


## 3. resolute-install-deps.sh

### 3.1 Purpose

`resolute-install-deps.sh` uses Ubuntu `apt-get` to install the host packages needed for
local builds.

It runs:

```text
apt-get update
apt-get install -y --no-install-recommends ...
```

For a regular user, the script uses `sudo apt-get`; for root, it invokes `apt-get`
directly.

Installed dependencies include:

```text
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
libssl-dev
libltdl-dev
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
```

`perl` is required by the project-built OpenSSL configuration step. OpenSSL
ships a fallback copy of its required `Text::Template` Perl module, so a
separate CPAN installation is not required.

The script installs host packages only. It does not:

- Download or remove the Android NDK.
- Download third-party project sources.
- Start a project build.
- Use Docker.
- Change project source versions.

### 3.2 Basic usage

```bash
./scripts/resolute-install-deps.sh
```

Show help:

```bash
./scripts/resolute-install-deps.sh --help
```

Skip the distribution check on a system other than Ubuntu 26.04:

```bash
ALLOW_UNSUPPORTED_HOST=1 ./scripts/resolute-install-deps.sh
```

This only allows the script to continue. Package names, versions, and compatibility
still depend on the distribution; the script does not automatically adapt to other
distributions.

If a regular user runs the script without `sudo` installed, it exits with an error.
Install `sudo` or run the script as root.


## 4. resolute-local-build.sh

### 4.1 Purpose

`resolute-local-build.sh` is the local Ubuntu 26.04 build entry point. It performs these
steps:

1. Read build settings from environment variables.
2. Optionally clean selected module sources or perform a full cleanup.
3. Check the Ubuntu version and supported x86_64/AArch64 host architecture.
4. Check that required build commands are available.
5. Select an installed Android NDK or download one if needed.
6. Check for an NDK Clang driver matching the target architecture and API.
7. Pass settings to the project Makefile and cross-compile locally.
8. Check archive structure, ELF files, dependencies, and contents of all six outputs from an `all` build.
9. Generate a SHA-256 checksum manifest.
10. Run or skip device tests according to adb device availability.

The script locates the project root using its own path, so the current shell directory
does not have to be the project root.

### 4.2 Command syntax

```bash
./scripts/resolute-local-build.sh [target ...]
```

Without positional targets, the script uses `BUILD_TARGET`, which defaults to `all`.
This special script target builds all six release outputs for arm64 and x86_64:

```bash
./scripts/resolute-local-build.sh all
```

Other positional arguments override `BUILD_TARGET` and are passed unchanged as Make
targets:

```bash
./scripts/resolute-local-build.sh bpftools-min
```

You can also build individual modules:

```bash
./scripts/resolute-local-build.sh llvm
./scripts/resolute-local-build.sh bcc
./scripts/resolute-local-build.sh bpftrace
./scripts/resolute-local-build.sh bpftrace-static
./scripts/resolute-local-build.sh python
```

Because positional targets are passed through to Make, other valid targets provided by
the repository Makefile can also be used.

Show script help:

```bash
./scripts/resolute-local-build.sh --help
```


## 5. Build settings

Defaults are initialized near the top of `resolute-local-build.sh`, with NDK defaults
loaded from `projects/versions.mk`. Most settings can be overridden through environment
variables; the manifest-controlled NDK version is an exception described below.

### 5.1 BUILD_TARGET

Default:

```text
all
```

Choose the Make target used when no positional target is provided:

```bash
BUILD_TARGET=bpftools-min ./scripts/resolute-local-build.sh
```

Positional targets take precedence if both are supplied.

### 5.2 THREADS

Default:

```bash
$(nproc)
```

This value controls parallelism in nested build commands:

```bash
THREADS=16 ./scripts/resolute-local-build.sh
```

It must be a positive integer. The default uses all logical CPUs; lower it manually if
memory is limited or you need to reduce load.

### 5.3 NDK_API

Default:

```text
35
```

Example:

```bash
NDK_API=35 ./scripts/resolute-local-build.sh
```

The script checks for the NDK Clang driver matching the API. For example, arm64 with API
35 requires:

```text
toolchains/llvm/prebuilt/<host-tag>/bin/aarch64-linux-android35-clang
```

`<host-tag>` is `linux-x86_64` or `linux-aarch64`. `NDK_API` must be a positive integer.
To support older Android devices, choose an appropriate minimum API and ensure the
selected NDK provides the matching toolchain entry point.

### 5.4 NDK_ARCH

Default:

```text
arm64
```

Supported values:

| NDK_ARCH | Android target triple | Typical device architecture |
| --- | --- | --- |
| `arm64` | `aarch64-linux-android` | 64-bit ARM Android device |
| `x86_64` | `x86_64-linux-android` | 64-bit x86 Android device/emulator |

This fork has removed the armv7/`armeabi-v7a` build path. Both the script and Makefile
reject that value; 32-bit ARM outputs are no longer built, verified, or published.

Example:

```bash
NDK_ARCH=x86_64 ./scripts/resolute-local-build.sh bpftools
```

The special `all` target always builds both supported architectures, so `NDK_ARCH`
affects only ordinary Make targets.

Architecture-specific Android build directories are:

```text
build/android/<NDK_ARCH>/
out/android/<NDK_ARCH>/
```

### 5.5 NDK_VERSION

Default:

```text
r30
```

`NDK_VERSION` in `projects/versions.mk` determines the preferred NDK path, download
filename, and temporary cache directory. When upgrading, also update `NDK_REVISION` and
`NDK_LINUX_X86_64_SHA256` in that file. `NDK_API` sets the default Android API. These
four NDK fields must use `NAME := literal` assignments so the shell entry points can
read them; Make expressions are not supported.

The `NDK_VERSION` environment variable cannot override the manifest; a conflicting value
is rejected. `NDK_API` can still override the local script default through the
environment. For direct Make invocations, use `make NDK_API=35 ...`.

### 5.6 NDK_PATH

Empty by default.

An explicitly specified NDK directory has the highest priority:

```bash
NDK_PATH=/opt/android-ndk-r30 ./scripts/resolute-local-build.sh
```

The script checks that the revision in `source.properties` matches the manifest and
probes the compiler version.

If the explicit directory does not exist or lacks the compiler for the selected
architecture/API, the script fails instead of switching to another NDK.

### 5.7 PREFERRED_NDK_PATH

Default:

```text
/mnt/develop/android-ndk-r30
```

The actual default is derived from `NDK_VERSION`:

```text
/mnt/develop/android-ndk-${NDK_VERSION}
```

Override the preferred path:

```bash
PREFERRED_NDK_PATH=/data/android/android-ndk-r30 \
    ./scripts/resolute-local-build.sh
```

### 5.8 NDK_TMP_DIR

Default:

```text
/tmp
```

If no NDK is explicitly selected and the preferred NDK is absent, the script uses:

```text
${NDK_TMP_DIR}/android-ndk-${NDK_VERSION}
```

as the cache path for the downloaded NDK.

Example:

```bash
NDK_TMP_DIR=/var/tmp ./scripts/resolute-local-build.sh
```

Downloads start in a randomly named staging directory under `NDK_TMP_DIR`. The NDK moves
to its final cache path only after download and extraction succeed. The staging
directory is removed on either success or failure.

The final NDK cache remains after the build for reuse.

### 5.9 NDK_DOWNLOAD_URL

Empty by default. With no override, only x86_64 hosts can use the official Google URL:

```text
https://dl.google.com/android/repository/android-ndk-${NDK_VERSION}-linux.zip
```

Provide a complete download URL:

```bash
NDK_DOWNLOAD_URL=https://example.invalid/android-ndk-r30-linux.zip \
NDK_DOWNLOAD_SHA256='<64-character-lowercase-hex-digest>' \
    ./scripts/resolute-local-build.sh
```

A custom archive must still extract to a top-level directory named
`android-ndk-${NDK_VERSION}`.

### 5.10 NDK_DOWNLOAD_SHA256

`projects/versions.mk` provides the checksum for the official r30 Linux x86_64 archive.
Downloads from a custom `NDK_DOWNLOAD_URL`, including self-built AArch64 packages,
require the corresponding lowercase SHA-256 explicitly:

```bash
NDK_DOWNLOAD_URL=https://example.invalid/android-ndk-r30-linux.zip \
NDK_DOWNLOAD_SHA256='<64-character-lowercase-hex-digest>' \
    ./scripts/resolute-local-build.sh
```

If the checksum does not match, temporary files are removed and the NDK is neither
extracted nor installed in the cache. An existing explicit NDK directory is not
recompressed for a checksum calculation; this setting protects archives downloaded by
the script.

### 5.11 DOWNLOAD_NDK

Default:

```text
1
```

Set to `0` to disable automatic downloads:

```bash
DOWNLOAD_NDK=0 ./scripts/resolute-local-build.sh
```

The script then exits with an error if no installed NDK is found.

### 5.12 BUILD_TYPE

Default:

```text
Release
```

Supported values:

```text
Release
Debug
```

Debug example:

```bash
BUILD_TYPE=Debug ./scripts/resolute-local-build.sh
```

Other values or capitalization are rejected.

### 5.13 STATIC_LINKING

Default:

```text
false
```

Must be `true` or `false`:

```bash
STATIC_LINKING=true ./scripts/resolute-local-build.sh
```

This value is passed to the project Makefile for components that support static linking.
Whether a fully static build is possible still depends on the project, NDK, and
dependency build rules.

### 5.14 LLVM_BPF_ONLY

Default:

```text
false
```

Set to `true` to enable only the BPF target in LLVM:

```bash
LLVM_BPF_ONLY=true ./scripts/resolute-local-build.sh
```

This reduces the LLVM build, but some tools need other targets. For example, BCC
rwengine also needs the LLVM target for the Android architecture. Keep the default
`false` for full functionality.

### 5.15 ALLOW_UNSUPPORTED_HOST

Default:

```text
0
```

Skip the Ubuntu 26.04 distribution check:

```bash
ALLOW_UNSUPPORTED_HOST=1 ./scripts/resolute-local-build.sh
```

This does not bypass the supported host architecture check or automatically resolve
dependency, compiler, or ABI differences on other systems.

### 5.16 VERIFY_ARTIFACTS

Defaults to `1`. After an `all` build, `verify-artifacts.sh` verifies all six outputs.
Set to `0` to skip offline validation temporarily; this is not recommended for release
builds:

```bash
VERIFY_ARTIFACTS=0 ./scripts/resolute-local-build.sh all
```

### 5.17 DEVICE_TEST

Accepts `auto`, `required`, or `0`; defaults to `auto`:

- `auto`: test only when adb can select exactly one supported device in the `device` state; otherwise skip.
- `required`: fail if no suitable device is available.
- `0`: explicitly disable device tests.

Use `ANDROID_SERIAL` to select a device when several are connected. Set
`DEVICE_NETWORK_REQUIRED=1` or `DEVICE_BPF_REQUIRED=1` to require the online pip or root
BPF probes, respectively.


## 6. Android NDK selection order

The script selects an NDK in this order:

1. Use `NDK_PATH` if it is nonempty.
2. Otherwise, use `PREFERRED_NDK_PATH` if it exists.
3. Otherwise, check `${NDK_TMP_DIR}/android-ndk-${NDK_VERSION}`.
4. If the temporary cache is also absent and `DOWNLOAD_NDK=1`, download and extract the NDK.
5. Verify that the Clang driver for the selected architecture and API is executable.

With the default settings, this is:

```text
Explicit NDK_PATH
  -> /mnt/develop/android-ndk-r30
  -> /tmp/android-ndk-r30
  -> Download to /tmp/android-ndk-r30
```

If the selected explicit or preferred directory exists but is incomplete, the script
fails. It neither overwrites that directory nor silently falls back to another NDK.

An existing but incomplete `/tmp/android-ndk-r30` is also left untouched. Inspect its
contents and handle it manually after confirming what must be preserved.


## 7. Build targets and outputs

All release files are written to the repository `out/` directory. Archives are no longer
written to the repository root.

### 7.1 all

The default build of all release outputs:

```bash
./scripts/resolute-local-build.sh all
```

This special target performs one shared build per architecture, arm64 and x86_64. The
full archive, minimal archive, and static `bpftrace` reuse LLVM, BCC, and other
dependencies for their architecture. Static `bpftrace` has a separate CMake build
directory to keep static and dynamic settings from overwriting each other. Host
`llvm-config`, `llvm-tblgen`, and `clang-tblgen` are built once with AArch64, BPF, and
X86 backends and shared by both Android architectures. Android LLVM target libraries are
still built separately for each architecture. Outputs:

```text
out/bpftools-arm64.tar.gz
out/bpftools-min-arm64.tar.gz
out/bpftrace-arm64
out/bpftools-x86_64.tar.gz
out/bpftools-min-x86_64.tar.gz
out/bpftrace-x86_64
```

`all` cannot be combined with other positional targets. It uses the full
architecture-specific and BPF LLVM targets and selects dynamic or static linking for
each product. `NDK_ARCH`, `STATIC_LINKING`, and `LLVM_BPF_ONLY` do not change this fixed
set of six outputs.

### 7.2 bpftools

The full archive:

```bash
./scripts/resolute-local-build.sh bpftools
```

It includes:

- `bpftrace`.
- `bpftrace-aotrt`, when available.
- Python executables and runtime libraries selected by `projects/versions.mk`.
- `pip`/`pip3` entry points matching that CPython version.
- OpenSSL shared libraries and a CA bundle for Python HTTPS.
- The Zstandard shared library for Python `compression.zstd`.
- BCC and BPF shared libraries.
- `libclang.so`.
- Runtime libraries such as `libbpf`, `libelf`, `liblzma`, and `libffi`.
- Shared data for bcc and bpftrace.
- Launcher wrappers and license files.

The output name depends on `NDK_ARCH`:

```text
out/bpftools-arm64.tar.gz
out/bpftools-x86_64.tar.gz
```

### 7.3 bpftools-min

The minimal archive:

```bash
./scripts/resolute-local-build.sh bpftools-min
```

The minimal archive retains the core binaries and libraries needed by bpftrace. It omits
the full package's Python environment, `libbcc.so`, and bcc shared data.

Output names:

```text
out/bpftools-min-arm64.tar.gz
out/bpftools-min-x86_64.tar.gz
```

### 7.4 bpftrace-static

Build a standalone static executable for the architecture selected by `NDK_ARCH`:

```bash
NDK_ARCH=arm64 ./scripts/resolute-local-build.sh bpftrace-static
NDK_ARCH=x86_64 ./scripts/resolute-local-build.sh bpftrace-static
```

The outputs are `out/bpftrace-arm64` and `out/bpftrace-x86_64`, respectively. This
target uses a separate CMake directory but reuses installed LLVM and other dependencies
for the same architecture. It does not replace the dynamic installation produced by the
ordinary `bpftrace` target.

### 7.5 Building individual modules

Pass a module target from the project Makefile, for example:

```bash
./scripts/resolute-local-build.sh llvm
./scripts/resolute-local-build.sh bcc
./scripts/resolute-local-build.sh bpftrace
./scripts/resolute-local-build.sh python
./scripts/resolute-local-build.sh xz
```

Individual module builds are mainly for development and diagnosing compilation failures.
They do not necessarily produce final `out/bpftools-*.tar.gz` archives.

### 7.6 Centralized versions and individual module upgrades

Versions of downloadable components and host Python packages are centralized in:

```text
projects/versions.mk
```

**LLVM/Clang is explicitly pinned to 21.1.8 (`llvmorg-21.1.8`). Keep
`LLVM_BRANCH_OR_TAG` unchanged when upgrading the NDK or other dependencies.** This
applies to host tools and Android libraries built by this project; the cross-compiler
comes from the separately configured NDK. Cache cleanup and rebuilds also use this
pinned version.

The `psf/black` GitHub Action is the only exception to centralized version management.
Workflows cannot directly read Make variables, and the third-party Action commit SHA,
Action release, and Black version input must be reviewed together.
`.github/workflows/black.yml` therefore pins them separately. A Black upgrade must
update `BLACK_VERSION` in `projects/versions.mk` along with the workflow Action SHA,
version comment, and `version` input. Other project versions remain solely in
`projects/versions.mk`.

The bpftrace tracefs patch filename is derived from `BPFTRACE_COMMIT`: for example,
`v0.27.0` uses `projects/bpftrace/tracefs_fallback_v0.27.0.patch`. Recheck the patch
against the corresponding upstream tag when upgrading. Build rules include the patch
content in the source signature, and both dynamic and standalone static builds apply it.
After fetching sources, run:

```bash
python3 scripts/test-bpftrace-tracefs.py
```

The script applies the patch to the original tag in a temporary directory. Using the
host C++17 compiler, it injects failures into the actual patched kprobe attachment class
and checks file descriptor cleanup, event rollback, and event name isolation. These
tests require neither root nor a device. Actual kernel tracefs attachment still requires
validation on a suitably privileged device.

Set the complete Python version only once in the manifest:

```make
PYTHON_VERSION := <major.minor.patch>
```

`PYTHON_ABI_VERSION`, `PYTHON_BINARY`, the source tag, host interpreter path, Android
`site-packages` path, and architecture-specific `python.xinstall` are derived from that
value. Do not add fixed `python3.<minor>` paths to modules, sysroots, or workflows.
Plain `python3` remains valid as a host dependency command or compatibility launcher in
the final archive; it does not pin a Python minor version.

Apart from the pinned LLVM, upgrade one module at a time so failures can be traced to a
specific upstream change:

```bash
# 1. Update one module version in projects/versions.mk.
# 2. Validate the module; source signatures refresh mismatched source caches.
./scripts/resolute-local-build.sh python

# 3. Validate the final dependency chain and both archives.
./scripts/resolute-local-build.sh bpftools bpftools-min
```

Replace `python` with `ffi`, `xz`, `zstd`, `elfutils`, `bcc`, or another unpinned
project. For modules selected by Git commit rather than release tag, update the commit
hash only in `projects/versions.mk`. `OPENSSL_VERSION` and `PIP_VERSION` also declare
the stable OpenSSL version and CPython-bundled pip wheel version. When upgrading Python,
check the wheel filename under `Lib/ensurepip/_bundled/` and update `PIP_VERSION`
accordingly.

Each downloaded or generated source directory has a Git-ignored
`projects/<module>/.source-signature`. Changing the version, repository, archive
checksum, or patch inputs removes the old `sources/` and fetches the newly declared
sources. Python, OpenSSL, Zstandard, BCC, bpftrace, and LLVM also record build
configuration signatures; changes to the NDK, API, architecture, linkage, or key build
rules reconfigure the existing build directory. The NDK `libc++_shared.so` has a
separate signature, so changing its path, version, or contents refreshes the output
copy. Before reinstalling, LLVM, libbpf, elfutils, Zstandard, and OpenSSL remove their
old versioned shared library families, preventing stale SONAME files from entering new
release archives. `CLEAN_MODULES` remains available for troubleshooting but is no longer
required for routine version changes.

Each `NDK_ARCH` gets its own `python.xinstall` at:

```text
build/android/<NDK_ARCH>/python.xinstall
```

Building arm64 and then x86_64 therefore does not make the second architecture's BCC
Python installation reuse the first architecture's `site-packages` path.

### 7.7 HTTPS and pip on Android

HTTPS and pip are included only in the full `bpftools` archive. Build and deploy it:

```bash
./scripts/resolute-local-build.sh bpftools
adb push out/bpftools-arm64.tar.gz /data/local/tmp/
adb shell 'cd /data/local/tmp && tar -xzf bpftools-arm64.tar.gz'
```

Check Python, OpenSSL, and pip:

```bash
adb shell /data/local/tmp/bpftools/python3 \
    -c 'import ssl; print(ssl.OPENSSL_VERSION)'
adb shell /data/local/tmp/bpftools/pip3 --version
```

Install directly into the full archive's own `site-packages`:

```bash
adb shell /data/local/tmp/bpftools/pip3 install requests rich
```

Alternatively, install into a separate directory to leave the extracted toolkit
unchanged:

```bash
adb shell 'mkdir -p /data/local/tmp/python-packages && \
    /data/local/tmp/bpftools/pip3 install \
        --target /data/local/tmp/python-packages requests rich'

adb shell 'PYTHONPATH=/data/local/tmp/python-packages \
    /data/local/tmp/bpftools/python3 -c "import requests, rich"'
```

Launcher wrappers automatically set the packaged shared library path, OpenSSL provider
path, and CA certificate file. If the caller has already set `SSL_CERT_FILE` or
`OPENSSL_MODULES`, those settings are preserved.

pip can install pure-Python wheels and Android wheels on PyPI compatible with the
current Python ABI, Android API, and CPU architecture. Packages distributed only as
native sources or ordinary Linux wheels may fail to build on the device because Android
wheels, a compiler, headers, or target libraries are missing. The root-user warning from
pip in an Android root shell is a general pip warning. Prefer `--target` when you want
to isolate installed packages.

### 7.8 Source and build configuration signatures

For each Android architecture, NDK libc++, LLVM, Python, OpenSSL, Zstandard, elfutils,
libbpf, stdc++fs, BCC, and bpftrace have automatically generated configuration
signatures, for example:

```text
build/android/<NDK_ARCH>/llvm.config
build/android/<NDK_ARCH>/libcxx-shared.config
build/android/<NDK_ARCH>/python.config
build/android/<NDK_ARCH>/openssl.config
build/android/<NDK_ARCH>/zstd.config
build/android/<NDK_ARCH>/elfutils.config
build/android/<NDK_ARCH>/libbpf.config
build/android/<NDK_ARCH>/stdc++fs.config
build/android/<NDK_ARCH>/bcc.config
build/android/<NDK_ARCH>/bpftrace.config
```

Signatures record source versions and resolved commits, NDK paths and versions, API,
architecture, CMake/Python versions, build type, `STATIC_LINKING`, `LLVM_BPF_ONLY`, LLVM
targets, shared-library options, and key module configuration inputs.
`libcxx-shared.config` also records the NDK library SHA-256, so content changes trigger
a fresh copy even if the original timestamp is unchanged. Signature files live under the
Git-ignored `build/` directory and do not change the tracked working tree.

Signatures are recalculated on every build. Unchanged contents do not update timestamps
or reconfigure/recompile LLVM. When configuration changes, the build prints old and new
field values and reruns the relevant configuration step in the existing directory.
Source and dependency completion markers propagate to final targets, triggering
downstream reconfiguration and linking as needed. For example, switching from
`STATIC_LINKING=true` back to the dynamic full archive no longer requires manual LLVM
cleanup to restore `libLLVM.so`.

LLVM sources remain at `llvmorg-21.1.8`. Switching the same sources between dynamic and
static LLVM configurations reruns CMake in the existing directory through the
configuration signature. Manual LLVM cleanup is normally unnecessary. Use
`CLEAN_MODULES=llvm` only to diagnose stale state that the upstream build system did not
handle correctly; the refetched version remains pinned.


## 8. Cleanup

No cleanup is performed by default, so ordinary invocations are incremental:

```bash
./scripts/resolute-local-build.sh
```

Cleanup settings:

- `CLEAN_MODULES`
- `CLEAN_ALL`
- `CLEAN_ONLY`

Three common workflows are:

```bash
# Clean LLVM sources and shared build outputs, then build immediately.
CLEAN_MODULES=llvm ./scripts/resolute-local-build.sh

# Clean LLVM sources and shared build outputs, then exit.
CLEAN_MODULES=llvm CLEAN_ONLY=1 ./scripts/resolute-local-build.sh

# After a cleanup-only invocation, start a build with the ordinary command.
./scripts/resolute-local-build.sh
```

With `CLEAN_ONLY=1`, the script always exits after cleanup, before checking the NDK or
starting a build. Leave it unset when you want to clean and then build immediately.

### 8.1 CLEAN_MODULES

Select one or more modules whose cached sources should be removed and fetched again.

One module:

```bash
CLEAN_MODULES=llvm ./scripts/resolute-local-build.sh
```

Comma-separated modules:

```bash
CLEAN_MODULES=llvm,bcc ./scripts/resolute-local-build.sh
```

Quote a space-separated list:

```bash
CLEAN_MODULES="llvm bcc" ./scripts/resolute-local-build.sh
```

Module names are validated against the Makefile `remove-<module>-sources` targets.
Invalid names fail before any cleanup occurs.

Several projects install into the shared `out/` directory, and the Makefile does not
have complete per-module installation manifests. To avoid stale libraries or ABI
mismatches, `CLEAN_MODULES` performs these steps:

1. Remove all of `build/`.
2. Remove all of `out/`.
3. Remove legacy `bpftools-*.tar.gz` archives that may remain in the repository root.
4. Remove source caches only for modules named in `CLEAN_MODULES`.
5. Continue with the build by default.

All build outputs are rebuilt, but sources of unselected modules remain cached and need
not be downloaded again.

Refetch and rebuild the pinned LLVM 21.1.8:

```bash
CLEAN_MODULES=llvm ./scripts/resolute-local-build.sh
```

This removes `projects/llvm/sources` and all build outputs, then downloads the
`llvmorg-21.1.8` revision pinned in `projects/versions.mk` and starts the build.

### 8.2 CLEAN_ALL

Remove all build outputs and downloaded project sources, then rebuild:

```bash
CLEAN_ALL=1 ./scripts/resolute-local-build.sh
```

This removes:

```text
build/
out/
projects/*/sources/
```

It does not remove NDK installations outside the repository, including:

```text
/mnt/develop/android-ndk-r30
/tmp/android-ndk-r30
```

`CLEAN_ALL=1` and a nonempty `CLEAN_MODULES` are mutually exclusive.

### 8.3 CLEAN_ONLY

Defaults to `0`. Set to `1` to perform only the requested cleanup, without starting the
subsequent build.

`CLEAN_ONLY` means "clean only", not "build in a clean environment".

Remove only the LLVM source cache and shared build outputs:

```bash
CLEAN_MODULES=llvm CLEAN_ONLY=1 ./scripts/resolute-local-build.sh
```

Perform a full cleanup without building:

```bash
CLEAN_ALL=1 CLEAN_ONLY=1 ./scripts/resolute-local-build.sh
```

`CLEAN_ONLY=1` requires `CLEAN_MODULES` or `CLEAN_ALL=1`; otherwise the script fails.

If you ran:

```bash
CLEAN_MODULES=llvm CLEAN_ONLY=1 ./scripts/resolute-local-build.sh
```

and saw:

```text
Cleanup completed; CLEAN_ONLY=1, so no build was started.
```

cleanup succeeded, and the build was intentionally not started. Then run:

```bash
./scripts/resolute-local-build.sh
```

to build from the cleaned state. You do not need to set `CLEAN_MODULES=llvm` again.


## 9. Common build examples

### 9.1 Build all six outputs with defaults

```bash
./scripts/resolute-local-build.sh
```

This is equivalent to explicitly selecting `all` and builds all six outputs for arm64
and x86_64.

### 9.2 Minimal arm64 archive

```bash
./scripts/resolute-local-build.sh bpftools-min
```

### 9.3 x86_64, API 35, 16 jobs

```bash
NDK_ARCH=x86_64 NDK_API=35 THREADS=16 \
    ./scripts/resolute-local-build.sh bpftools bpftools-min bpftrace-static
```

### 9.4 Debug build

```bash
BUILD_TYPE=Debug ./scripts/resolute-local-build.sh
```

### 9.5 Select an NDK

```bash
NDK_PATH=/mnt/develop/android-ndk-r30 \
    ./scripts/resolute-local-build.sh
```

### 9.6 Disable automatic NDK downloads

```bash
DOWNLOAD_NDK=0 ./scripts/resolute-local-build.sh
```

### 9.7 Build only the pinned LLVM 21.1.8

Keep `LLVM_BRANCH_OR_TAG := llvmorg-21.1.8` in `projects/versions.mk` and run:

```bash
./scripts/resolute-local-build.sh llvm
```

Source and configuration signatures refresh caches as needed. There is no need to change
the LLVM version or clean the module first.

### 9.8 Rebuild all outputs while retaining third-party sources

The existing Makefile `clean` target removes only `build/` and `out/`:

```bash
./scripts/resolute-local-build.sh clean
./scripts/resolute-local-build.sh
```

This retains source caches and removes current archives along with `out/`. Unlike
`CLEAN_MODULES`, it does not separately remove legacy `bpftools-*.tar.gz` files in the
repository root. Use `CLEAN_MODULES` or `CLEAN_ALL` when those legacy archives also need
to be removed.


## 10. Valid setting combinations

Valid combinations:

```bash
CLEAN_MODULES=llvm ./scripts/resolute-local-build.sh
CLEAN_MODULES=llvm,bcc CLEAN_ONLY=1 ./scripts/resolute-local-build.sh
CLEAN_ALL=1 ./scripts/resolute-local-build.sh
CLEAN_ALL=1 CLEAN_ONLY=1 ./scripts/resolute-local-build.sh
```

Invalid combinations:

```bash
CLEAN_ALL=1 CLEAN_MODULES=llvm ./scripts/resolute-local-build.sh
CLEAN_ONLY=1 ./scripts/resolute-local-build.sh
THREADS=0 ./scripts/resolute-local-build.sh
NDK_API=abc ./scripts/resolute-local-build.sh
STATIC_LINKING=1 ./scripts/resolute-local-build.sh
```

`STATIC_LINKING` and `LLVM_BPF_ONLY` use `true/false`. `CLEAN_ALL`, `CLEAN_ONLY`,
`DOWNLOAD_NDK`, and `ALLOW_UNSUPPORTED_HOST` use `0/1`.


## 11. Troubleshooting

### 11.1 Host distribution mismatch

Example error:

```text
error: this script supports Ubuntu 26.04 (Resolute)
```

Check `/etc/os-release` first. To explicitly try an unvalidated system, set:

```bash
ALLOW_UNSUPPORTED_HOST=1 ./scripts/resolute-local-build.sh
```

### 11.2 Missing build commands

Example error:

```text
error: missing build commands: ...
```

Run:

```bash
./scripts/resolute-install-deps.sh
```

Then rebuild.

### 11.3 Missing NDK compiler

Example error:

```text
error: selected NDK does not contain the expected compiler: ...
```

Check that:

- `NDK_PATH` points to the NDK root.
- `NDK_VERSION` matches that directory.
- `NDK_ARCH` is correct.
- `NDK_API` is supported by the NDK.
- The NDK was fully extracted.

### 11.4 Incomplete temporary NDK directory

Example error:

```text
error: temporary NDK path exists but is incomplete
```

The script does not overwrite existing directories automatically. Inspect the directory,
preserve anything needed, then repair or move it manually before rerunning.

### 11.5 Automatic refresh after a source signature change

Changing a tag, version, commit hash, or archive checksum in `projects/versions.mk`
changes the corresponding `projects/<module>/.source-signature`. The next build removes
the old `sources/` and fetches the new version. Logs show the signature differences so
you can identify what triggered the refresh.

After an interrupted download, rerun the same build command. Archives are downloaded to
temporary files and replace the final cache atomically only after checksum verification.
Use `CLEAN_MODULES=<module>` to force cleanup when diagnosing unexpected stale state.

### 11.6 Inconsistent incremental build state

Major changes to build settings, toolchains, or sources can invalidate existing
CMake/Autotools caches.

Keep sources and rebuild all outputs:

```bash
./scripts/resolute-local-build.sh clean
./scripts/resolute-local-build.sh
```

Refetch selected sources and rebuild:

```bash
CLEAN_MODULES=llvm ./scripts/resolute-local-build.sh
```

Refetch everything and rebuild:

```bash
CLEAN_ALL=1 ./scripts/resolute-local-build.sh
```

### 11.7 Flex malloc compilation failure with GCC 15

Ubuntu 26.04 GCC 15 defaults to GNU C23. In C23, the old Flex declaration `void
*malloc()` means the function accepts no arguments, so calls to `malloc(n)` fail with:

```text
error: too many arguments to function 'malloc'; expected 0, have 1
```

The repository pins Flex to the upstream master commit
`4fcc71489ae298c35b0b786114ad524945f2cf95` from July 30, 2026, which includes the C23
`malloc` prototype fix. If older Flex sources were downloaded before the error, source
signatures detect the changed commit and automatically refresh `projects/flex/sources`.
Normally, simply rebuild:

```bash
./scripts/resolute-local-build.sh
```

This newer Flex commit also performs a two-stage bootstrap consistency check in native
host builds. During a highly parallel `make install`, two rules may generate
`stage1scan.o` simultaneously, producing:

```text
mv: cannot stat '.deps/stage1scan.Tpo': No such file or directory
Bootstrap comparison failure!
```

Host Flex is a prerequisite for later cross-compilation, so this project does not need
to validate upstream Flex bootstrapping. The host configuration uses upstream's
`--disable-bootstrap` option to eliminate that race. Android Flex cross-compilation
retains its existing configuration.


## 12. Suggested checks before and after building

Run configuration regression tests without an NDK, Docker, or an Android device. Python
3, Bash, Make, curl, and unzip are required:

```bash
python3 scripts/test-ndk-config.py
```

Inspect actual defaults and script help:

```bash
./scripts/resolute-local-build.sh --help
```

Verify the NDK:

```bash
source ./scripts/ndk-config.sh
ndk_path="/mnt/develop/android-ndk-$NDK_VERSION"
ndk_validate_revision "$ndk_path"
"$ndk_path/toolchains/llvm/prebuilt/$(ndk_host_tag)/bin/aarch64-linux-android${NDK_API}-clang" --version
```

Inspect outputs after building:

```bash
ls -lh out/bpftools-*.tar.gz out/bpftrace-arm64 out/bpftrace-x86_64
./scripts/verify-artifacts.sh
(cd out && sha256sum --check SHA256SUMS)
```

You can also invoke `android-smoke-test.sh` independently. By default, it exits
successfully with a skip when no single suitable device is available, so an unplugged
phone does not fail a local build:

```bash
./scripts/android-smoke-test.sh
DEVICE_TEST=required DEVICE_NETWORK_REQUIRED=1 \
    ./scripts/android-smoke-test.sh
```

Check that generated files have not unexpectedly appeared in Git status:

```bash
git status --short
```

Intentional changes to scripts, this document, or build configuration still appear in
Git status. `.gitignore` excludes downloaded sources, build directories, output
directories, and packaged outputs.


## 13. GitHub Actions build environment

Commit checks and tag releases have separate triggers:

- Branch pushes and pull requests run NDK configuration regression tests and Python formatting checks in `black.yml`, plus JDWP tests, type checks, and formatting checks in `jdwp.yml`. They do not build Android release outputs or publish a Release.
- Pushing a `v*` tag runs `release.yml`, which reuses both check workflows through `workflow_call`. Both checks must pass before Android builds for both architectures, output validation, and publication begin.
- Other tags do not trigger these workflows. Direct push triggers for check workflows match branches only, preventing duplicate checks outside the `v*` release workflow.

JDWP checks use `make THREADS=2 jdwp-check`. They prepare Buck2, host Python, and Python
packages needed for testing, but do not compile Android LLVM/bpftrace. Ordinary pushes
have no path filter, so documentation commits also run checks unless explicitly skipped.
A new commit on the same branch or pull request cancels older checks; tag releases are
not automatically canceled.

In `release.yml`, the `build` job waits for checks through `needs: [lint, jdwp]`; the
`publish` job waits for both architectures through `needs: build`. A failed check or
build skips the dependent compilation or publication steps. The former `bpftools.yml`,
which built Android archives on ordinary pushes and pull requests, has been removed to
avoid duplicate builds.

The release environment follows the local build configuration described above:

- GitHub runner: `ubuntu-26.04`.
- Android API: 35.
- Android NDK: r30.
- Build entry point: `scripts/resolute-local-build.sh`.
- Dependency installer: `scripts/resolute-install-deps.sh`.
- Architecture matrix: arm64 and x86_64.
- Parallelism: `THREADS=2` per build job; architectures use separate runners and can run concurrently.

Each Release retains six separate product files: full and minimal archives plus static
`bpftrace` for arm64 and x86_64. Build speed is not achieved by removing targets or
architectures.

The configuration uses standard runners rather than separately billed larger runners.
`THREADS=2` limits build parallelism per job, not the runner's CPU allocation. Local
scripts still default to `nproc`, and direct Make invocations default to 4,
independently of CI.

As of September 2026, GitHub lists `ubuntu-26.04` as Public Preview rather than GA in
its [image
documentation](https://github.com/actions/runner-images/blob/main/images/ubuntu/Ubuntu2604-Readme.md).
Image changes, temporary instability, or queueing issues may occur during preview. This
does not affect local Resolute builds. When diagnosing CI failures, distinguish runner
infrastructure issues from project compilation failures.

Each GitHub Actions job has an isolated environment. The workflow sets `NDK_TMP_DIR` to
`${{ runner.temp }}`, where `resolute-local-build.sh` selects the NDK. CI reads NDK
settings from `projects/versions.mk`; the cache key includes runner architecture,
version, and download checksum. The r30 directory is cached with `actions/cache`: a
cache miss downloads the NDK, while later builds can restore it. LLVM and complete build
directories are excluded from the cache to limit storage use and avoid reusing
incompatible CMake state across configurations.

Each architecture job builds these three Android targets together:

```text
bpftools
bpftools-min
bpftrace-static
```

Outputs are uploaded separately for arm64 and x86_64.

The three targets run in a single Make invocation:

```bash
./scripts/resolute-local-build.sh bpftools bpftools-min bpftrace-static
```

The full archive, minimal archive, and static bpftrace share one complete set of LLVM,
BCC, and other dependencies for each architecture, requiring only two Android matrix
jobs. Since CI jobs are isolated, each builds its own host LLVM and
architecture-specific Android LLVM. A local `all` build instead shares one set of host
LLVM tools across both architectures. Each matrix job uploads one temporary artifact
containing three product files and a SHA-256 manifest, with one-day retention. The
publish job downloads and verifies both artifacts, then merges the manifests. After
publication and Release asset digest verification, it deletes the temporary artifacts.
The one-day expiry remains a fallback if publication or cleanup fails. Cleanup requires
`actions: write` in the publish job; a rerun after cleanup must rebuild the artifacts.

Before upload, CI runs `verify-artifacts.sh` to check archive structure, the
architecture and shared-library dependency closure of every packaged ELF, Python TLS/pip
contents, and that static bpftrace does not depend on packaged LLVM/Clang/BCC shared
libraries. Upload is allowed only after these checks pass.

The final GitHub Release contains six product files and one combined `SHA256SUMS`. `CHANGELOG.md` records significant changes for release users.
