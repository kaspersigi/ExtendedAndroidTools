# Changelog

Notable changes to this independently maintained fork are recorded here.

## v2.0.3

### Changed

- Updated bpftrace to 0.27.1, libbpf to 1.8.0, elfutils to 0.197, OpenSSL to
  4.1.0, Python to 3.15.2 and its bundled pip to 26.2.2. LLVM/Clang remains
  locked at 21.1.8 and the NDK remains at r30.
- Updated CMake to 4.4.5, Buck2 to the 2026-10-15 release with its matching
  prelude, Black to 26.10.1 and setuptools to 84.2.1. Refreshed the Flex and
  Gnulib commit pins and the CMake, elfutils and Buck2 archive checksums.
- Fixed OpenSSL 4.1 builds outside the source tree with `no-apps`: create the
  generated app-header directory and patch error-state filename handling so
  source paths containing `projects` are preserved.
- Enabled Flex's bundled `ngettext` fallback for builds without translations,
  and kept Android pkg-config paths out of the host CMake bootstrap.
- Rebased the Android tracefs fallback patch onto the pristine bpftrace
  v0.27.1 tag. Added `make check-bpftrace-patches` to apply both patches and
  fault-test the attachment class; CI now gates tag releases on these checks.

## v2.0.2

### Changed

- Updated bpftrace to 0.27.0, OpenSSL to 4.0.2 and XZ to 5.8.4.
- Kept LLVM/Clang locked at 21.1.8 and clarified that NDK and dependency updates
  preserve this pin.
- Rebased the tracefs fallback onto bpftrace v0.27.0, with attachment-owned perf
  FDs, unique event names and rollback on partial failure. Build rules select
  the versioned patch from the manifest; added host fault-injection tests.
- Updated Gnulib to commit `4d97575dcb6a8a6a4a82cbdc78a672d371c022d1`
  and used Savannah's dedicated HTTPS endpoint for source retrieval.
- Upgraded to Android NDK r30 and unified the default API at 35. NDK release,
  revision, API and official Linux archive checksum are configured in
  `projects/versions.mk` for Make, local builds, Docker and CI.
- Selected the native Linux NDK host toolchain on x86_64 and AArch64; AArch64
  uses a self-built NDK. Docker follows the host CPU by default.
- Regenerated Autotools configuration and the bpftrace strip wrapper when NDK
  settings change, preventing stale tool paths after an upgrade.
- Updated the filesystem compatibility helper to use the configured Android
  API and C++26. Dependency language standards and artifact linkage stay as
  specified by their build rules.

## v2.0.1

### Changed

- Updated Gnulib to upstream commit
  `331c8d065a8a753de71f084f068473ccd5e4c34a`.
- Branch pushes and pull requests now run formatting and JDWP checks without
  building Android release artifacts.
- Tag releases reuse the same checks and require them to pass before the
  arm64/x86_64 build and publication jobs can run.
- Limited CI native builds to two parallel jobs on Ubuntu 26.04 and removed
  the duplicate branch-triggered Android build workflow.

## v2.0.0

### Added

- Ubuntu 26.04 local and Docker build environments using Android NDK r27d and
  API 35 by default.
- Six arm64/x86_64 release products: full and minimal bpftools archives plus a
  standalone bpftrace binary for each architecture.
- Android Python 3.14 with pip, packaged OpenSSL, Zstandard support, and a CA
  certificate bundle.
- Source and configuration signatures that invalidate incompatible incremental
  build state when versions, toolchains, or link modes change.
- Offline artifact verification, conditional adb device smoke tests, release
  checksums, and tag-driven GitHub Releases.

### Changed

- Centralized dependency selection in `projects/versions.mk`.
- Consolidated GitHub Actions builds to one LLVM build per architecture while
  retaining all six uploaded products.
- Added cryptographic verification for downloaded NDK, CMake, elfutils, and
  Buck2 archives.
- Made bpftools tar archive ordering and timestamps deterministic.
- Removed armv7 support; arm64 and x86_64 are the supported Android targets.
- Replaced inherited Meta/Facebook contribution and reporting directions with
  fork-specific governance guidance.

## v1.0.7

This was the last tagged release before the Ubuntu 26.04 and dependency-refresh
work summarized above. Consult the Git history for earlier changes.
