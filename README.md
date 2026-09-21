# ExtendedAndroidTools
Extended Android Tools is a set of makefiles and build environment cross compiling Linux tools we all love for Android. All tools are built using their native build systems (autotools, cmake, etc) and Android NDK. Reference build environment is provided via Docker.

**LLVM/Clang is intentionally locked to 21.1.8 (`llvmorg-21.1.8`)** in
[projects/versions.mk](projects/versions.mk). Keep this version when updating
the NDK or other dependencies. The lock applies to the LLVM/Clang sources built
by this project, including host tools and Android libraries; the NDK compiler
is supplied by the separately configured NDK release.

# List of supported software
- [bpftrace](https://github.com/iovisor/bpftrace)
- [bcc](https://github.com/iovisor/bcc)
- [llvm & clang](https://github.com/llvm/llvm-project)
- [python](https://github.com/python/cpython)
- [pip](https://pip.pypa.io/)
- [OpenSSL](https://openssl-library.org/)
- [libffi](https://github.com/libffi/libffi)
- [flex](https://github.com/westes/flex)
- [libelf (part of elfutils)](https://sourceware.org/elfutils/)
- [argp (part of gnulib)](https://www.gnu.org/software/gnulib/)
- [XZ Utils](https://tukaani.org/xz/)
- [Zstandard](https://github.com/facebook/zstd)

# Build environment
## Docker (recommended)
The provided [Dockerfile](docker/Dockerfile) defines the Ubuntu 26.04 reference build environment and installs Android NDK r30. You can access it using the following commands:
```
# Build the Docker image
./scripts/build-docker-image.sh

# Run the environment
./scripts/run-docker-build-env.sh

# Build a target of your choice from within the container
> make python
> make bpftools

# Build and run host tools
> make python-host
> eval `make setup-env`
> python3
```

`run-docker-build-env.sh` defaults to Android API 35 and the number of logical CPUs reported by `nproc`. Both values can be overridden when starting the container:

```
THREADS=8 NDK_API=35 ./scripts/run-docker-build-env.sh
```

NDK release selection is centralized in [projects/versions.mk](projects/versions.mk):
`NDK_VERSION`, `NDK_REVISION`, `NDK_API`, and `NDK_LINUX_X86_64_SHA256`.
Make, the local scripts, Docker, and CI all read that manifest. After changing
it, rebuild the Docker image before running it. `IMAGE_NAME` overrides the
image name for both scripts (default: `extended-android-tools`).

The Docker platform follows the host CPU: `linux/amd64` on x86_64 and
`linux/arm64` on AArch64. `DOCKER_PLATFORM` can select either explicitly.
Google supplies the Linux x86_64 NDK; an AArch64 image requires your self-built
Linux AArch64 NDK ZIP via `NDK_DOWNLOAD_URL` and `NDK_DOWNLOAD_SHA256`.
A custom URL always requires its own checksum. The ZIP must extract to
`android-ndk-r30/` and contain the toolchain for the selected image platform.

## Setting up an Ubuntu 26.04 environment directly
For builds outside Docker, use the dedicated Ubuntu 26.04 scripts. The dependency
script installs the required host packages; the build script first selects
`/mnt/develop/android-ndk-r30` (or an explicit
`NDK_PATH`). On Linux x86_64 it can download the official NDK to temporary
storage. Linux AArch64 uses your self-built NDK with the `linux-aarch64` host
toolchain; an automatic download requires a custom URL and checksum.

```
./scripts/resolute-install-deps.sh

# Build all six release artifacts for arm64 and x86_64
./scripts/resolute-local-build.sh all

# Or build one target for the selected NDK_ARCH
./scripts/resolute-local-build.sh python
./scripts/resolute-local-build.sh bpftools

# Build and run host tools
./scripts/resolute-local-build.sh python-host
eval `make setup-env`
python3
```

An `all` build verifies the six release products, writes `out/SHA256SUMS`, and
runs full, minimal, and standalone-bpftrace device smoke tests only when adb can
select exactly one authorized arm64 or x86_64 device. With no suitable device,
the device step is reported as skipped and the local build remains successful.

When migrating an existing build from an older NDK, run `make clean` first to
remove old objects and installed libraries; fetched project sources are kept.

See [scripts/README.md](scripts/README.md) for configuration, cleanup, NDK selection, and troubleshooting details.

## GitHub Actions

Branch pushes and pull requests run NDK configuration regression tests, Black
formatting checks, and the JDWP test, type-check, and format-check suite. JDWP prepares its required host tools, but
these checks do not build Android release artifacts or publish a Release.

Pushing a `v*` tag runs the same checks first. Only after both checks pass does
the release workflow build and verify the arm64 and x86_64 artifacts, then
publish all six product files and `SHA256SUMS` to GitHub Releases. All jobs use
Ubuntu 26.04; native builds use `THREADS=2` per job.

See [the CI documentation](scripts/README.md#13-github-actions-build-environment) for the
workflow dependencies, artifacts, and caching policy.

# Sysroots
When projects are built the resulting binaries/libraries are placed in `bin` and `lib` subdirectories of `out/android/$ARCH/` directory. To run a particular tool on an Android device it needs to be pushed together with all the libraries it depends on to the device. In addition the shell environment needs to be configured appropriately for the runtime loader to be able to locate and load those libraries when the tool is executed. To help automate these steps ExtendedAndroidTools provides helper targets preparing sysroot archives consisting of selected executables and libraries, together with scripts setting up the environment. Those archives can be pushed to a device, extracted, and used without any further setup.

```
# build bpftools, sysroot containing bpftrace, python and bcc
# see the 'Build environment' section for more details on building
make bpftools

adb push out/bpftools-arm64.tar.gz /data/local/tmp
adb shell "cd /data/local/tmp && tar xf bpftools-arm64.tar.gz"

# enjoy new tools
adb shell /data/local/tmp/bpftools/bpftrace -e 'uprobe:/system/lib64/libc.so:malloc { @ = hist(arg0); }'

# Python HTTPS and pip use the packaged OpenSSL and CA bundle
adb shell /data/local/tmp/bpftools/python3 -c 'import ssl; print(ssl.OPENSSL_VERSION)'
adb shell /data/local/tmp/bpftools/pip3 install --target /data/local/tmp/python-packages rich
```

The full `bpftools` archive includes pip and HTTPS support. Pure-Python wheels
can be installed directly on the device. Packages that publish compatible
Android wheels can also work; packages available only as native source
distributions still require their own Android cross-compilation environment
and are outside the scope of the runtime archive.

# Android device requirements
Some of the tools require root privileges to run. In addition BPF tools require Linux kernel to provide BPF capabilities: BPF, Kprobes and Uprobes. Most of Android kernels are based on Linux versions that are either too old, or have some or all of the necessary features disabled. The most straigtforward way to access Android environment providing root access and some BPF capabilities (BPF + Uprobes) is to use an Android emulator **without** Google Play Store. The default API 35 artifacts require Android 15 (API 35) or newer. To read more on preparing other devices see [dedicated documentation](docs/phone_setup.md).

# Variables impacting build process
- `THREADS` - number of jobs to run simultaneously. This value is passed to nested make invocations via `-j` option. The Docker and Resolute entry scripts default to `nproc`; invoking Make directly without either wrapper retains the Makefile default of 4.
- `NDK_API` - Android API level used by the NDK toolchain. Make, Docker and the Resolute entry script default to API 35 from `projects/versions.mk`.
- `NDK_PATH` - NDK installation directory; Make defaults to `/mnt/develop/android-ndk-$(NDK_VERSION)`. Linux x86_64 selects `linux-x86_64`, and Linux AArch64 selects `linux-aarch64`.
- `NDK_ARCH` - x86_64 or arm64. Architecture to cross compile for. The default value is arm64
- `BUILD_TYPE` - Release or Debug, controlls amount of debug info to be included in resulting libs and binaries. The default value is Release.

```
# The following builds debug version of bpftools sysroot for x86_64
# Warning: this takes very long and resulting binaries are big, prepare ~100GB of disk space

make bpftools NDK_ARCH=x86_64 BUILD_TYPE=Debug THREADS=1
```

# Variables impacting execution of tools
- `BPFTRACE_KERNEL_SOURCE` - if set indicates directory bpftrace should read kernel headers from
- `BCC_KERNEL_SOURCE` - if set indicates directory bcc should read kernel headers from
- `BCC_SYMFS` - if set indicates directory containing unstripped elf binaries for better stack symbolication

## Contributing
See the [CONTRIBUTING.md](CONTRIBUTING.md) file.

## License
See the [LICENSE](LICENSE) file.
