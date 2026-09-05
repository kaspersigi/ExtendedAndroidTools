# Changelog

Notable changes to this independently maintained fork are recorded here.

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
