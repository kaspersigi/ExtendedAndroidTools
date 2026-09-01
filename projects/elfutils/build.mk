# Copyright (c) Meta Platforms, Inc. and affiliates.

ELFUTILS_ANDROID_DEPS = argp obstack
$(eval $(call project-define,elfutils))

ELFUTILS_EXTRA_CFLAGS += -I$(abspath projects/elfutils/android_fixups)
ELFUTILS_EXTRA_CFLAGS += -Dprogram_invocation_short_name=\\\"no-program_invocation_short_name\\\"

ELFUTILS_ANDROID_CONFIG_FILE := $(ANDROID_BUILD_DIR)/elfutils.config
ELFUTILS_ANDROID_CONFIGURED_FILE := $(ELFUTILS_ANDROID_BUILD_DIR)/.configured

$(ELFUTILS_ANDROID): $(ELFUTILS_ANDROID_CONFIGURED_FILE)
prepare-elfutils: $(ELFUTILS_ANDROID_CONFIGURED_FILE)

$(ELFUTILS_ANDROID_CONFIG_FILE): force-config-signature projects/elfutils/sources
$(ELFUTILS_ANDROID_CONFIG_FILE): projects/elfutils/build.mk projects/versions.mk
$(ELFUTILS_ANDROID_CONFIG_FILE): scripts/update-signature.sh | $(ANDROID_BUILD_DIR)
	@scripts/update-signature.sh $@ \
		"PROJECT=elfutils-android" \
		"ELFUTILS_VERSION=$(ELFUTILS_VERSION)" \
		"GNULIB_VERSION=$(GNULIB_COMMIT_HASH)" \
		"SOURCE_ARCHIVE_SHA256=$(ELFUTILS_SOURCE_SHA256)" \
		"ZSTD_SUPPORT=false" \
		"BUILD_RULE_SHA256=$(shell sha256sum projects/elfutils/build.mk | cut -d ' ' -f 1)" \
		$(ANDROID_CONFIG_SIGNATURE_ARGS)

$(ELFUTILS_ANDROID):
	cd $(ELFUTILS_ANDROID_BUILD_DIR)/lib && make -j $(THREADS)
	cd $(ELFUTILS_ANDROID_BUILD_DIR)/libelf && make -j $(THREADS)
	$(call clean-android-library-families,libelf*.so*)
	cd $(ELFUTILS_ANDROID_BUILD_DIR)/libelf && make install -j $(THREADS)
	# libelf.a absorbs every private libeu object.  Its crc32 implementation is
	# unused by libelf itself and conflicts with zlib's crc32 in static links.
	$(ANDROID_TOOLCHAIN_PATH)/llvm-ar d \
		$(ANDROID_OUT_DIR)/lib/libelf.a crc32.o crc32_file.o
	cd $(ELFUTILS_ANDROID_BUILD_DIR)/config && make
	cp $(ELFUTILS_ANDROID_BUILD_DIR)/config/libelf.pc $(ANDROID_OUT_DIR)/lib/pkgconfig
	cp $(ELFUTILS_SRCS)/COPYING-LGPLV3 $(ANDROID_OUT_DIR)/licenses/elfutils-libs
	touch $@

$(ANDROID_BUILD_DIR)/elfutils: $(ANDROID_CONFIG_SITE)
$(ANDROID_BUILD_DIR)/elfutils: $(ANDROID_OUT_DIR)/lib/pkgconfig/zlib.pc
	mkdir -p $@

$(ELFUTILS_ANDROID_CONFIGURED_FILE): $(ELFUTILS_ANDROID_CONFIG_FILE)
$(ELFUTILS_ANDROID_CONFIGURED_FILE): $(ANDROID_CONFIG_SITE)
$(ELFUTILS_ANDROID_CONFIGURED_FILE): $(ANDROID_OUT_DIR)/lib/pkgconfig/zlib.pc
$(ELFUTILS_ANDROID_CONFIGURED_FILE): | $(ELFUTILS_ANDROID_BUILD_DIR)
	cd $(ELFUTILS_ANDROID_BUILD_DIR) && \
		EXTRA_CFLAGS="$(ELFUTILS_EXTRA_CFLAGS)" $(ELFUTILS_SRCS)/configure \
		$(ANDROID_EXTRA_CONFIGURE_FLAGS) \
		--disable-debuginfod \
		--disable-libdebuginfod \
		--without-zstd \
		--enable-install-elfh
	touch $@

ELFUTILS_URL = https://sourceware.org/elfutils/ftp/$(ELFUTILS_VERSION)/elfutils-$(ELFUTILS_VERSION).tar.bz2
ELFUTILS_ARCHIVE = $(DOWNLOADS_DIR)/elfutils-$(ELFUTILS_VERSION).tar.bz2

$(ELFUTILS_ARCHIVE): | $(DOWNLOADS_DIR)
	@set -eu; \
	tmp_file="$@.tmp"; \
	trap 'rm -f "$$tmp_file"' 0 1 2 3 15; \
	curl --fail --location --retry 3 $(ELFUTILS_URL) --output "$$tmp_file"; \
	printf '%s  %s\n' '$(ELFUTILS_SOURCE_SHA256)' "$$tmp_file" | sha256sum --check --status; \
	mv "$$tmp_file" "$@"; \
	trap - 0 1 2 3 15

projects/elfutils/sources: $(ELFUTILS_ARCHIVE)
	@printf '%s  %s\n' '$(ELFUTILS_SOURCE_SHA256)' '$<' | sha256sum --check || \
		{ rm -f -- '$<'; echo 'error: removed corrupt elfutils download; retry the build' >&2; exit 1; }
	@$(call source-transaction-begin,$@); \
	mkdir $@; \
	tar xf $(ELFUTILS_ARCHIVE) -C $@ \
		--strip-components=1; \
	$(source-transaction-commit)

$(eval $(call project-source-signature,elfutils,archive:$(ELFUTILS_URL)#sha256=$(ELFUTILS_SOURCE_SHA256)))
