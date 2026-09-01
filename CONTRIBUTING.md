# Contributing to ExtendedAndroidTools

Contributions are welcome. This repository is an independently maintained fork
of Meta's original ExtendedAndroidTools project; Meta's Contributor License
Agreement and support channels do not apply to this fork.

## Pull requests

1. Fork the repository and create a branch from `main`.
2. Keep dependency selections in `projects/versions.mk` instead of duplicating
   version strings in build rules.
3. Add or update tests and documentation when behavior changes.
4. Run `make jdwp-check` for JDWP changes.
5. For Android build changes, run
   `./scripts/resolute-local-build.sh all` when resources permit. The command
   verifies all six artifacts and conditionally tests a connected Android
   device.
6. Run `git diff --check` before submitting the pull request.

If a full LLVM build is impractical, document exactly which targets and checks
were run and which checks remain unverified.

## Licensing

By contributing, you agree that your contributions are licensed under the
Apache License 2.0 in the repository root. Preserve copyright and attribution
notices inherited from upstream files. New project-owned files should use the
SPDX identifier `Apache-2.0` unless another license is explicitly required.

## Issues and security reports

Use GitHub Issues for non-sensitive bugs and feature requests. Do not disclose
security vulnerabilities or private conduct reports in a public issue; follow
the private-reporting guidance in [SECURITY.md](SECURITY.md).
