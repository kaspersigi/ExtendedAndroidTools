# Copyright (c) Meta Platforms, Inc. and affiliates.

ifeq ($(HOST_OS),GNU/Linux)
BUCK2_ARCHIVE_SUFFIX := unknown-linux-gnu
else
BUCK2_ARCHIVE_SUFFIX := apple-darwin
endif

ifneq ($(filter arm64 aarch64,$(HOST_MACHINE)),)
BUCK2_ARCHIVE_INFIX := aarch64
BUCK2_CHECKSUM_ARCH := AARCH64
else ifeq ($(HOST_MACHINE),x86_64)
BUCK2_ARCHIVE_INFIX := $(HOST_MACHINE)
BUCK2_CHECKSUM_ARCH := X86_64
else
BUCK2_ARCHIVE_INFIX := $(HOST_MACHINE)
BUCK2_CHECKSUM_ARCH := UNSUPPORTED
endif

ifeq ($(HOST_OS),GNU/Linux)
BUCK2_CHECKSUM_OS := LINUX
else
BUCK2_CHECKSUM_OS := DARWIN
endif

BUCK2_ARCHIVE_SHA256 := $(BUCK2_$(BUCK2_CHECKSUM_ARCH)_$(BUCK2_CHECKSUM_OS)_SHA256)

BUCK2_RELEASE_ARCHIVE := buck2-$(BUCK2_ARCHIVE_INFIX)-$(BUCK2_ARCHIVE_SUFFIX).zst
# Buck2 release assets reuse the same upstream filename for every release.
# Keep a versioned local filename so changing BUCK2_VERSION cannot silently
# reuse the previous release from the downloads cache.
BUCK2_ARCHIVE := buck2-$(BUCK2_VERSION)-$(BUCK2_ARCHIVE_INFIX)-$(BUCK2_ARCHIVE_SUFFIX).zst
BUCK2_URL := https://github.com/facebook/buck2/releases/download/$(BUCK2_VERSION)/$(BUCK2_RELEASE_ARCHIVE)

$(HOST_OUT_DIR)/bin/buck2: $(DOWNLOADS_DIR)/$(BUCK2_ARCHIVE) | $(HOST_OUT_DIR)
# commands to unpack $(BUCK2_ARCHIVE) and set the executable flag
	@printf '%s  %s\n' '$(BUCK2_ARCHIVE_SHA256)' '$<' | sha256sum --check || \
		{ rm -f -- '$<'; echo 'error: removed corrupt Buck2 download; retry the build' >&2; exit 1; }
	@if [ -x '$@' ]; then HOME='$(abspath $(HOST_BUILD_DIR)/buck2-home)' '$@' kill >/dev/null 2>&1 || true; fi
	zstd --decompress --force $(DOWNLOADS_DIR)/$(BUCK2_ARCHIVE) -o $@
	touch $@
	chmod +x $@

$(DOWNLOADS_DIR)/$(BUCK2_ARCHIVE): | $(DOWNLOADS_DIR)
# instructions to download the archive
	@test -n '$(BUCK2_ARCHIVE_SHA256)' || \
		{ echo 'error: no Buck2 checksum is configured for $(BUCK2_ARCHIVE)' >&2; exit 1; }
	@set -eu; \
	tmp_file="$@.tmp"; \
	trap 'rm -f "$$tmp_file"' 0 1 2 3 15; \
	curl --fail --location --retry 3 --output "$$tmp_file" $(BUCK2_URL); \
	printf '%s  %s\n' '$(BUCK2_ARCHIVE_SHA256)' "$$tmp_file" | sha256sum --check --status; \
	mv "$$tmp_file" $@; \
	trap - 0 1 2 3 15

# Phony target for host
.PHONY: buck2-host
buck2-host: $(HOST_OUT_DIR)/bin/buck2
