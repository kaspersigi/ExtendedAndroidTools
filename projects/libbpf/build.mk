# Copyright (c) Meta Platforms, Inc. and affiliates.

LIBBPF_ANDROID_DEPS = elfutils
$(eval $(call project-define,libbpf))

LIBBPF_EXTRA_CFLAGS += "-D__user="
LIBBPF_EXTRA_CFLAGS += "-D__force="
# Current libbpf releases no longer need this compatibility definition.
# LIBBPF_EXTRA_CFLAGS += "-D__poll_t=unsigned"
LIBBPF_EXTRA_CFLAGS += "-Wno-tautological-constant-out-of-range-compare"

LIBBPF_ANDROID_MAKE_ARGS = \
	LIBSUBDIR=lib \
	PREFIX=$(abspath $(ANDROID_OUT_DIR)) \
	OBJDIR=$(abspath $(LIBBPF_ANDROID_BUILD_DIR)) \
	AR=$(abspath $(ANDROID_TOOLCHAIN_PATH)/llvm-ar) \
	CC=$(abspath $(ANDROID_TOOLCHAIN_PATH)/$(ANDROID_TRIPLE)$(NDK_API)-clang) \
	EXTRA_CFLAGS="$(LIBBPF_EXTRA_CFLAGS)" \
	EXTRA_LDFLAGS="-Wl,-z,max-page-size=$(ANDROID_MAX_PAGE_SIZE)"

LIBBPF_ANDROID_CONFIG_FILE := $(ANDROID_BUILD_DIR)/libbpf.config

$(LIBBPF_ANDROID): $(LIBBPF_ANDROID_CONFIG_FILE)
$(LIBBPF_ANDROID_CONFIG_FILE): force-config-signature projects/libbpf/sources
$(LIBBPF_ANDROID_CONFIG_FILE): projects/libbpf/build.mk projects/versions.mk
$(LIBBPF_ANDROID_CONFIG_FILE): scripts/update-signature.sh | $(ANDROID_BUILD_DIR)
	@scripts/update-signature.sh $@ \
		"PROJECT=libbpf-android" \
		"LIBBPF_VERSION=$(LIBBPF_TAG)" \
		"ELFUTILS_VERSION=$(ELFUTILS_VERSION)" \
		"SOURCE_REVISION=$(shell git -C $(LIBBPF_SRCS) rev-parse HEAD 2>/dev/null || echo unavailable)" \
		"EXTRA_CFLAGS=$(LIBBPF_EXTRA_CFLAGS)" \
		"BUILD_RULE_SHA256=$(shell sha256sum projects/libbpf/build.mk | cut -d ' ' -f 1)" \
		$(ANDROID_CONFIG_SIGNATURE_ARGS)

$(LIBBPF_ANDROID): \
    export PKG_CONFIG_LIBDIR=$(abspath $(ANDROID_OUT_DIR)/lib/pkgconfig)
$(LIBBPF_ANDROID): $(ANDROID_OUT_DIR)/lib/pkgconfig/zlib.pc
	cd $(LIBBPF_SRCS)/src && make -j $(THREADS) $(LIBBPF_ANDROID_MAKE_ARGS)
	$(call clean-android-library-families,libbpf.so*)
	cd $(LIBBPF_SRCS)/src && make install install_uapi_headers \
		-j $(THREADS) \
		$(LIBBPF_ANDROID_MAKE_ARGS)
	cp $(LIBBPF_SRCS)/LICENSE $(ANDROID_OUT_DIR)/licenses/libbpf
	touch $@

$(LIBBPF_ANDROID_BUILD_DIR):
	mkdir -p $@

LIBBPF_REPO = https://github.com/libbpf/libbpf
projects/libbpf/sources:
	@$(call source-transaction-begin,$@); \
	git clone $(LIBBPF_REPO) $@ --depth=1 -b $(LIBBPF_TAG); \
	$(source-transaction-commit)

$(eval $(call project-source-signature,libbpf,git:$(LIBBPF_REPO)@$(LIBBPF_TAG)))
