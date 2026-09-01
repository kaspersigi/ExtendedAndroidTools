# Copyright (c) Meta Platforms, Inc. and affiliates.

BPFTRACE_ANDROID_DEPS = bcc cereal elfutils flex libbpf llvm stdc++fs xz
BPFTRACE_HOST_DEPS = cmake flex
$(eval $(call project-define,bpftrace))

BPFTRACE_EXTRA_LDFLAGS = "-L$(abspath $(ANDROID_OUT_DIR))/lib"
BPFTRACE_STATIC_LDFLAGS = "-L$(abspath $(ANDROID_OUT_DIR))/lib $(abspath $(ANDROID_OUT_DIR))/lib/liblzma.a"

ifeq ($(STATIC_LINKING),true)
BPFTRACE_EXTRA_CMAKE_FLAGS = -DSTATIC_LINKING=ON

# XXX: As od 925127c5 ("Make bcc depend on liblzma") we're building libbcc
# with lzma support, but bpftrace currently doesn't have a way to detect this
# dependency, which causes undefined symbol errors when linking statically.
# This fixes it by adding liblzma to the link line.
BPFTRACE_EXTRA_LDFLAGS += "$(abspath $(ANDROID_OUT_DIR))/lib/liblzma.a"
endif

STRIP_THUNK = $(HOST_OUT_DIR)/bpftrace-strip-thunk
BPFTRACE_ANDROID_CONFIG_FILE := $(ANDROID_BUILD_DIR)/bpftrace.config
BPFTRACE_ANDROID_CONFIGURED_FILE := $(BPFTRACE_ANDROID_BUILD_DIR)/.configured

$(BPFTRACE_ANDROID): $(BPFTRACE_ANDROID_CONFIGURED_FILE)
prepare-bpftrace: $(BPFTRACE_ANDROID_CONFIGURED_FILE)

$(BPFTRACE_ANDROID_CONFIG_FILE): force-config-signature projects/bpftrace/sources
$(BPFTRACE_ANDROID_CONFIG_FILE): projects/bpftrace/build.mk projects/versions.mk
$(BPFTRACE_ANDROID_CONFIG_FILE): scripts/update-signature.sh | $(ANDROID_BUILD_DIR)
	@scripts/update-signature.sh $@ \
		"PROJECT=bpftrace-android" \
		"BPFTRACE_VERSION=$(BPFTRACE_COMMIT)" \
		"BCC_VERSION=$(BCC_COMMIT)" \
		"LLVM_VERSION=$(LLVM_BRANCH_OR_TAG)" \
		"LIBBPF_VERSION=$(LIBBPF_TAG)" \
		"CEREAL_VERSION=$(CEREAL_TAG)" \
		"ELFUTILS_VERSION=$(ELFUTILS_VERSION)" \
		"FLEX_VERSION=$(FLEX_COMMIT_HASH)" \
		"XZ_VERSION=$(XZ_BRANCH_OR_TAG)" \
		"STDCXXFS_SOURCE_SHA256=$(shell sha256sum projects/stdc++fs/thunks.cpp | cut -d ' ' -f 1)" \
		"SOURCE_REVISION=$(shell git -C $(BPFTRACE_SRCS) rev-parse HEAD 2>/dev/null || echo unavailable)" \
		"BUILD_RULE_SHA256=$(shell sha256sum projects/bpftrace/build.mk | cut -d ' ' -f 1)" \
		$(ANDROID_CONFIG_SIGNATURE_ARGS)

$(BPFTRACE_ANDROID): $(ANDROID_OUT_DIR)/lib/libc++_shared.so $(LIBBPF_ANDROID)
ifeq ($(BUILD_TYPE), Debug)
	cd $(BPFTRACE_ANDROID_BUILD_DIR) && $(MAKE) install -j $(THREADS)
else
	cd $(BPFTRACE_ANDROID_BUILD_DIR) && $(MAKE) install/strip -j $(THREADS)
endif
	cp $(BPFTRACE_SRCS)/LICENSE $(ANDROID_OUT_DIR)/licenses/bpftrace
	touch $@

$(BPFTRACE_ANDROID_BUILD_DIR): $(HOST_OUT_DIR)/bin/flex $(STRIP_THUNK) $(LIBBPF_ANDROID)
	mkdir -p $@

$(BPFTRACE_ANDROID_CONFIGURED_FILE): $(BPFTRACE_ANDROID_CONFIG_FILE)
$(BPFTRACE_ANDROID_CONFIGURED_FILE): $(HOST_OUT_DIR)/bin/flex $(STRIP_THUNK) $(LIBBPF_ANDROID)
$(BPFTRACE_ANDROID_CONFIGURED_FILE): | $(BPFTRACE_ANDROID_BUILD_DIR)
	cd $(BPFTRACE_ANDROID_BUILD_DIR) && LDFLAGS="$(BPFTRACE_EXTRA_LDFLAGS)" $(CMAKE) $(BPFTRACE_SRCS) \
		$(ANDROID_EXTRA_CMAKE_FLAGS) \
		$(BPFTRACE_EXTRA_CMAKE_FLAGS) \
		-DBUILD_TESTING=OFF \
		-DENABLE_MAN=OFF \
		-DFLEX_EXECUTABLE=$(abspath $(HOST_OUT_DIR)/bin/flex) \
		-DUSE_SYSTEM_BPF_BCC=ON \
		-DUSE_SYSTEM_LIBBPF=ON \
		-DALLOW_UNSAFE_PROBE=ON \
		-DCMAKE_STRIP=$(abspath $(STRIP_THUNK)) \
		-DLIBBPF_INCLUDE_DIRS=$(abspath $(ANDROID_OUT_DIR))/include \
		-DLIBBPF_LIBRARIES=$(abspath $(ANDROID_OUT_DIR))/lib/libbpf.a
	touch $@

$(STRIP_THUNK): projects/bpftrace/strip-thunk | $(HOST_OUT_DIR)
	@sed -e "s+<STRIP_PATH>+$(ANDROID_TOOLCHAIN_STRIP_PATH)+g" $< > $@
	chmod +x $@

BPFTRACE_REPO = https://github.com/iovisor/bpftrace.git/
projects/bpftrace/sources:
	@$(call source-transaction-begin,$@); \
	git clone $(BPFTRACE_REPO) $@ --depth=1 -b $(BPFTRACE_COMMIT); \
	cd $@; \
	git apply --verbose ../tracefs_fallback_v0.26.1.patch; \
	git apply --verbose ../version_from_git_tag.patch; \
	$(source-transaction-commit)

$(eval $(call project-source-signature,bpftrace,git:$(BPFTRACE_REPO)@$(BPFTRACE_COMMIT),projects/bpftrace/tracefs_fallback_v0.26.1.patch projects/bpftrace/version_from_git_tag.patch))

# Build a standalone static bpftrace without replacing the dynamic bpftrace
# installed under out/android/<arch>. Its dependencies and LLVM installation
# are shared with bpftools/bpftools-min, while its CMake cache stays isolated.
BPFTRACE_STATIC_BUILD_DIR = $(ANDROID_BUILD_DIR)/bpftrace-static
BPFTRACE_STATIC_ARTIFACT = $(OUT_DIR)/bpftrace-$(NDK_ARCH)
BPFTRACE_STATIC_CONFIG_FILE = $(ANDROID_BUILD_DIR)/bpftrace-static.config
BPFTRACE_STATIC_CONFIGURED_FILE = $(BPFTRACE_STATIC_BUILD_DIR)/.configured

.PHONY: bpftrace-static
bpftrace-static: $(BPFTRACE_STATIC_CONFIGURED_FILE)
	cd $(BPFTRACE_STATIC_BUILD_DIR) && $(MAKE) bpftrace -j $(THREADS)
	cp $(BPFTRACE_STATIC_BUILD_DIR)/src/bpftrace $(BPFTRACE_STATIC_ARTIFACT)
ifeq ($(BUILD_TYPE), Debug)
	@true
else
	$(STRIP_THUNK) $(BPFTRACE_STATIC_ARTIFACT)
endif

$(BPFTRACE_STATIC_CONFIG_FILE): force-config-signature projects/bpftrace/sources
$(BPFTRACE_STATIC_CONFIG_FILE): projects/bpftrace/build.mk projects/versions.mk
$(BPFTRACE_STATIC_CONFIG_FILE): scripts/update-signature.sh | $(ANDROID_BUILD_DIR)
	@scripts/update-signature.sh $@ \
		"PROJECT=bpftrace-static-android" \
		"BPFTRACE_VERSION=$(BPFTRACE_COMMIT)" \
		"BCC_VERSION=$(BCC_COMMIT)" \
		"LLVM_VERSION=$(LLVM_BRANCH_OR_TAG)" \
		"LIBBPF_VERSION=$(LIBBPF_TAG)" \
		"CEREAL_VERSION=$(CEREAL_TAG)" \
		"ELFUTILS_VERSION=$(ELFUTILS_VERSION)" \
		"FLEX_VERSION=$(FLEX_COMMIT_HASH)" \
		"XZ_VERSION=$(XZ_BRANCH_OR_TAG)" \
		"STDCXXFS_SOURCE_SHA256=$(shell sha256sum projects/stdc++fs/thunks.cpp | cut -d ' ' -f 1)" \
		"SOURCE_REVISION=$(shell git -C $(BPFTRACE_SRCS) rev-parse HEAD 2>/dev/null || echo unavailable)" \
		"EFFECTIVE_STATIC_LINKING=true" \
		"BUILD_RULE_SHA256=$(shell sha256sum projects/bpftrace/build.mk | cut -d ' ' -f 1)" \
		$(ANDROID_CONFIG_SIGNATURE_ARGS)

$(BPFTRACE_STATIC_BUILD_DIR): projects/bpftrace/sources
$(BPFTRACE_STATIC_BUILD_DIR): $(STRIP_THUNK)
$(BPFTRACE_STATIC_BUILD_DIR): $(ANDROID_OUT_DIR)/lib/libclang.a
$(BPFTRACE_STATIC_BUILD_DIR): \
	$(foreach dep,$(BPFTRACE_ANDROID_DEPS),$(call project-android-target,$(dep)))
$(BPFTRACE_STATIC_BUILD_DIR): \
	$(foreach dep,$(BPFTRACE_HOST_DEPS),$(call project-host-target,$(dep)))
	mkdir -p $@

$(BPFTRACE_STATIC_CONFIGURED_FILE): $(BPFTRACE_STATIC_CONFIG_FILE)
$(BPFTRACE_STATIC_CONFIGURED_FILE): | $(BPFTRACE_STATIC_BUILD_DIR)
	cd $(BPFTRACE_STATIC_BUILD_DIR) && LDFLAGS=$(BPFTRACE_STATIC_LDFLAGS) $(CMAKE) $(BPFTRACE_SRCS) \
		$(ANDROID_EXTRA_CMAKE_FLAGS) \
		-DSTATIC_LINKING=ON \
		-DBUILD_TESTING=OFF \
		-DENABLE_MAN=OFF \
		-DFLEX_EXECUTABLE=$(abspath $(HOST_OUT_DIR)/bin/flex) \
		-DUSE_SYSTEM_BPF_BCC=ON \
		-DUSE_SYSTEM_LIBBPF=ON \
		-DALLOW_UNSAFE_PROBE=ON \
		-DCMAKE_STRIP=$(abspath $(STRIP_THUNK)) \
		-DLIBBPF_INCLUDE_DIRS=$(abspath $(ANDROID_OUT_DIR))/include \
		-DLIBBPF_LIBRARIES=$(abspath $(ANDROID_OUT_DIR))/lib/libbpf.a
	touch $@
