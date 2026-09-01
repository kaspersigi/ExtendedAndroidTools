# Copyright (c) Meta Platforms, Inc. and affiliates.

LLVM_ANDROID_DEPS = zstd
LLVM_HOST_DEPS =
$(eval $(call project-define,llvm))

ifeq ($(NDK_ARCH), arm64)
LLVM_DEFAULT_TARGET = AArch64
LLVM_HOST_TRIPLE = aarch64-linux-android
LLVM_TARGET_TRIPLE = aarch64-linux-android
else ifeq ($(NDK_ARCH), x86_64)
LLVM_DEFAULT_TARGET = X86
LLVM_HOST_TRIPLE = x86_64-linux-android
LLVM_TARGET_TRIPLE = x86_64-linux-android
else
$(error unknown abi $(NDK_ARCH))
endif

LLVM_COMMON_CMAKE_FLAGS = -DLLVM_ENABLE_PROJECTS="clang"
LLVM_COMMON_CMAKE_FLAGS += -DLLVM_BUILD_TOOLS=OFF
LLVM_COMMON_CMAKE_FLAGS += -DCLANG_BUILD_TOOLS=OFF
LLVM_COMMON_CMAKE_FLAGS += -DLLVM_INCLUDE_BENCHMARKS=OFF
LLVM_COMMON_CMAKE_FLAGS += -DLLVM_INCLUDE_EXAMPLES=OFF
LLVM_EXTRA_CMAKE_FLAGS = $(LLVM_COMMON_CMAKE_FLAGS)
LLVM_EXTRA_HOST_FLAGS = -DLLVM_TEMPORARILY_ALLOW_OLD_TOOLCHAIN=1
LLVM_HOST_TARGETS = AArch64;BPF;X86

# Dynamic Android tools must share one LLVM instance with libclang-cpp.
# Otherwise bpftrace and libclang-cpp each embed separate static LLVM registries,
# and Clang cannot see the BPF target registered by bpftrace.
LLVM_ANDROID_EXTRA_CMAKE_FLAGS = -DLLVM_BUILD_LLVM_DYLIB=ON
LLVM_ANDROID_EXTRA_CMAKE_FLAGS += -DLLVM_LINK_LLVM_DYLIB=ON
LLVM_ANDROID_EXTRA_CMAKE_FLAGS += -DCLANG_LINK_CLANG_DYLIB=ON
ifeq ($(STATIC_LINKING),true)
LLVM_ANDROID_EXTRA_CMAKE_FLAGS = -DLLVM_BUILD_LLVM_DYLIB=OFF
LLVM_ANDROID_EXTRA_CMAKE_FLAGS += -DLLVM_LINK_LLVM_DYLIB=OFF
LLVM_ANDROID_EXTRA_CMAKE_FLAGS += -DCLANG_LINK_CLANG_DYLIB=OFF
endif

# LLVM's exported CMake targets must refer to the same zstd target in both
# dynamic and static bpftrace configurations. Linking zstd statically into
# LLVM makes that dependency unambiguous while Python can still use libzstd.so.
LLVM_ANDROID_EXTRA_CMAKE_FLAGS += -DLLVM_USE_STATIC_ZSTD=ON

# The shared LLVM installation serves both the dynamic archives and the
# standalone bpftrace build. Always install libclang.so and libclang.a so this
# configuration stays independent of the Make goals used for a given run.
LLVM_CONFIG_LIBCLANG_STATIC = ON
LLVM_EXTRA_CMAKE_FLAGS += -DLIBCLANG_BUILD_STATIC=$(LLVM_CONFIG_LIBCLANG_STATIC)

ifeq ($(LLVM_BPF_ONLY),true)
LLVM_EXTRA_CMAKE_FLAGS += -DLLVM_TARGETS_TO_BUILD=BPF
LLVM_CONFIG_TARGETS = BPF
else
LLVM_EXTRA_CMAKE_FLAGS += -DLLVM_TARGETS_TO_BUILD="$(LLVM_DEFAULT_TARGET);BPF"
LLVM_CONFIG_TARGETS = $(LLVM_DEFAULT_TARGET);BPF
endif

# A directory timestamp cannot describe the CMake options that produced it.
# Keep a stable, human-readable configuration signature next to each Android
# LLVM build tree so incompatible caches are reconfigured automatically.
LLVM_ANDROID_CONFIG_FILE = $(ANDROID_BUILD_DIR)/llvm.config
LLVM_ANDROID_CONFIGURED_FILE = $(LLVM_ANDROID_BUILD_DIR)/.configured
LLVM_HOST_CONFIG_FILE = $(HOST_BUILD_DIR)/llvm.config
LLVM_HOST_CONFIGURED_FILE = $(LLVM_HOST_BUILD_DIR)/.configured
LLVM_NDK_REVISION = $(shell sed -n \
	's/^[[:space:]]*Pkg\.Revision[[:space:]]*=[[:space:]]*//p' \
	$(NDK_PATH)/source.properties 2>/dev/null | head -n 1)
LLVM_SOURCE_REVISION = $(shell git -C $(LLVM_SRCS) rev-parse HEAD 2>/dev/null || echo unavailable)
LLVM_BUILD_RULE_SHA256 = $(shell sha256sum projects/llvm/build.mk | cut -d ' ' -f 1)
LLVM_CMAKE_RULE_SHA256 = $(shell sha256sum toolchains/cmake.mk | cut -d ' ' -f 1)
LLVM_NDK_TOOLCHAIN_SHA256 = $(shell sha256sum $(ANDROID_CMAKE_TOOLCHAIN_FILE) 2>/dev/null | cut -d ' ' -f 1)

ifeq ($(STATIC_LINKING),true)
LLVM_CONFIG_BUILD_DYLIB = OFF
LLVM_CONFIG_LINK_DYLIB = OFF
LLVM_CONFIG_LINK_CLANG_DYLIB = OFF
else
LLVM_CONFIG_BUILD_DYLIB = ON
LLVM_CONFIG_LINK_DYLIB = ON
LLVM_CONFIG_LINK_CLANG_DYLIB = ON
endif

.PHONY: force-llvm-android-config
force-llvm-android-config:

$(LLVM_ANDROID_CONFIG_FILE): force-llvm-android-config projects/llvm/sources
$(LLVM_ANDROID_CONFIG_FILE): projects/llvm/build.mk projects/versions.mk
$(LLVM_ANDROID_CONFIG_FILE): | $(ANDROID_BUILD_DIR)
	@set -eu; \
	tmp_file="$@.tmp.$$$$"; \
	trap 'rm -f "$$tmp_file"' 0 1 2 3 15; \
	{ \
		printf '%s\n' \
			"LLVM_BRANCH_OR_TAG=$(LLVM_BRANCH_OR_TAG)" \
			"LLVM_SOURCE_REVISION=$(LLVM_SOURCE_REVISION)" \
			"CONFIG_SCHEMA=llvm-android-v1" \
			"LLVM_BUILD_RULE_SHA256=$(LLVM_BUILD_RULE_SHA256)" \
			"LLVM_CMAKE_RULE_SHA256=$(LLVM_CMAKE_RULE_SHA256)" \
			"CMAKE_VERSION=$(CMAKE_VERSION)" \
			"PYTHON_VERSION=$(PYTHON_VERSION)" \
			"ZSTD_VERSION=$(ZSTD_TAG)" \
			"NDK_PATH=$(abspath $(NDK_PATH))" \
			"NDK_REVISION=$(LLVM_NDK_REVISION)" \
			"NDK_TOOLCHAIN_SHA256=$(LLVM_NDK_TOOLCHAIN_SHA256)" \
			"NDK_ARCH=$(NDK_ARCH)" \
			"NDK_API=$(NDK_API)" \
			"CMAKE_ABI=$(CMAKE_ABI)" \
			"ANDROID_MAX_PAGE_SIZE=$(ANDROID_MAX_PAGE_SIZE)" \
			"ANDROID_OUT_DIR=$(abspath $(ANDROID_OUT_DIR))" \
			"BUILD_TYPE=$(BUILD_TYPE)" \
			"STATIC_LINKING=$(STATIC_LINKING)" \
			"LLVM_BPF_ONLY=$(LLVM_BPF_ONLY)" \
			"LLVM_TARGETS_TO_BUILD=$(LLVM_CONFIG_TARGETS)" \
			"LLVM_HOST_TRIPLE=$(LLVM_HOST_TRIPLE)" \
			"LLVM_TARGET_TRIPLE=$(LLVM_TARGET_TRIPLE)" \
			"LIBCLANG_BUILD_STATIC=$(LLVM_CONFIG_LIBCLANG_STATIC)" \
			"LLVM_BUILD_LLVM_DYLIB=$(LLVM_CONFIG_BUILD_DYLIB)" \
			"LLVM_LINK_LLVM_DYLIB=$(LLVM_CONFIG_LINK_DYLIB)" \
			"CLANG_LINK_CLANG_DYLIB=$(LLVM_CONFIG_LINK_CLANG_DYLIB)" \
			"LLVM_USE_STATIC_ZSTD=ON"; \
	} > "$$tmp_file"; \
	if test -f "$@" && cmp -s "$@" "$$tmp_file"; then \
		rm -f "$$tmp_file"; \
	else \
		if test -f "$@"; then \
			echo "LLVM configuration changed for $(NDK_ARCH); reconfiguring the existing build tree:"; \
			diff -u "$@" "$$tmp_file" || true; \
		else \
			echo "Recording LLVM configuration for $(NDK_ARCH) in $@"; \
		fi; \
		mv "$$tmp_file" "$@"; \
	fi

$(LLVM_ANDROID): $(LLVM_ANDROID_CONFIGURED_FILE)
prepare-llvm: $(LLVM_ANDROID_CONFIGURED_FILE)

$(LLVM_ANDROID):
	cd $(LLVM_ANDROID_BUILD_DIR) && $(MAKE) -j $(THREADS)
	$(call clean-android-library-families,libLLVM*.so* libclang.so* libclang-cpp.so*)
ifeq ($(BUILD_TYPE), Debug)
	cd $(LLVM_ANDROID_BUILD_DIR) && $(CMAKE) --install .
else
	cd $(LLVM_ANDROID_BUILD_DIR) && $(CMAKE) --install . --strip
endif
	cp $(LLVM_SRCS)/clang/LICENSE.TXT $(ANDROID_OUT_DIR)/licenses/clang
	cp $(LLVM_SRCS)/llvm/LICENSE.TXT $(ANDROID_OUT_DIR)/licenses/llvm
	touch $@

$(LLVM_ANDROID_BUILD_DIR): | $(HOST_OUT_DIR)/bin/llvm-config
$(LLVM_ANDROID_BUILD_DIR): | $(HOST_OUT_DIR)/bin/llvm-tblgen
$(LLVM_ANDROID_BUILD_DIR): | $(HOST_OUT_DIR)/bin/clang-tblgen
	mkdir -p $@

$(LLVM_ANDROID_CONFIGURED_FILE): $(LLVM_ANDROID_CONFIG_FILE)
$(LLVM_ANDROID_CONFIGURED_FILE): | $(LLVM_ANDROID_BUILD_DIR)
$(LLVM_ANDROID_CONFIGURED_FILE): | $(HOST_OUT_DIR)/bin/llvm-config
$(LLVM_ANDROID_CONFIGURED_FILE): | $(HOST_OUT_DIR)/bin/llvm-tblgen
$(LLVM_ANDROID_CONFIGURED_FILE): | $(HOST_OUT_DIR)/bin/clang-tblgen
	cd $(LLVM_ANDROID_BUILD_DIR) && $(CMAKE) $(LLVM_SRCS)/llvm \
		$(ANDROID_EXTRA_CMAKE_FLAGS) \
		$(LLVM_EXTRA_CMAKE_FLAGS) \
		$(LLVM_ANDROID_EXTRA_CMAKE_FLAGS) \
		-DLLVM_CONFIG_PATH=$(abspath $(HOST_OUT_DIR)/bin/llvm-config) \
		-DLLVM_TABLEGEN=$(abspath $(HOST_OUT_DIR)/bin/llvm-tblgen) \
		-DCLANG_TABLEGEN=$(abspath $(HOST_OUT_DIR)/bin/clang-tblgen) \
		-DLLVM_HOST_TRIPLE=$(LLVM_HOST_TRIPLE) \
		-DLLVM_DEFAULT_TARGET_TRIPLE=$(LLVM_TARGET_TRIPLE) \
		-DLLVM_ENABLE_RTTI=yes \
		-DLLVM_INCLUDE_GO_TESTS=OFF \
		-DLLVM_INCLUDE_TESTS=OFF \
		-DLLVM_INCLUDE_UTILS=OFF \
		-DLLVM_ENABLE_LIBXML2=OFF \
		-DLLVM_TOOL_LLVM_RTDYLD_BUILD=OFF \
		-DPython3_EXECUTABLE=$(PYTHON_HOST_EXECUTABLE)
	touch $@

# Older incremental build trees may have been configured before
# LIBCLANG_BUILD_STATIC was enabled. Reconfigure them in place rather than
# rebuilding LLVM from scratch.
ifeq ($(BUILD_TYPE), Debug)
LLVM_STATIC_INSTALL_TARGET = install-libclang_static
else
LLVM_STATIC_INSTALL_TARGET = install-libclang_static-stripped
endif

$(ANDROID_OUT_DIR)/lib/libclang.a: $(LLVM_ANDROID)
	@if ! test -f $@; then \
		cd $(LLVM_ANDROID_BUILD_DIR) && \
		$(CMAKE) -DLIBCLANG_BUILD_STATIC=ON . && \
		$(MAKE) $(LLVM_STATIC_INSTALL_TARGET) -j $(THREADS) && \
		touch $(abspath $(LLVM_ANDROID)); \
	fi
	test -f $@

# rules building host llvm-tblgen and clang-tblgen binaries necessary to
# cross compile llvm and clang for Android
$(HOST_OUT_DIR)/bin/llvm-config: $(LLVM_HOST_CONFIGURED_FILE) | $(HOST_OUT_DIR)
$(HOST_OUT_DIR)/bin/llvm-tblgen: $(LLVM_HOST_CONFIGURED_FILE) | $(HOST_OUT_DIR)
$(HOST_OUT_DIR)/bin/clang-tblgen: $(LLVM_HOST_CONFIGURED_FILE) | $(HOST_OUT_DIR)
$(HOST_OUT_DIR)/bin/llvm-config $(HOST_OUT_DIR)/bin/llvm-tblgen $(HOST_OUT_DIR)/bin/clang-tblgen:
	cd $(LLVM_HOST_BUILD_DIR) && $(MAKE) -j $(THREADS) $(notdir $@)
	cp $(LLVM_HOST_BUILD_DIR)/bin/$(notdir $@) $@

# Record the host LLVM configuration independently from the Android
# configuration. The host table generators are shared by both Android
# architectures, so build all required backends once and do not invalidate
# them merely because a dependency's timestamp changed.
$(LLVM_HOST_CONFIG_FILE): force-config-signature projects/llvm/sources
$(LLVM_HOST_CONFIG_FILE): projects/llvm/build.mk projects/versions.mk
$(LLVM_HOST_CONFIG_FILE): scripts/update-signature.sh | $(HOST_BUILD_DIR)
	@scripts/update-signature.sh $@ \
		"PROJECT=llvm-host" \
		"LLVM_BRANCH_OR_TAG=$(LLVM_BRANCH_OR_TAG)" \
		"LLVM_SOURCE_REVISION=$(LLVM_SOURCE_REVISION)" \
		"CONFIG_SCHEMA=llvm-host-v1" \
		"LLVM_BUILD_RULE_SHA256=$(LLVM_BUILD_RULE_SHA256)" \
		"CMAKE_VERSION=$(CMAKE_VERSION)" \
		"PYTHON_VERSION=$(PYTHON_VERSION)" \
		"LLVM_TARGETS_TO_BUILD=$(LLVM_HOST_TARGETS)" \
		"LLVM_ENABLE_PROJECTS=clang" \
		"LLVM_BUILD_TOOLS=false" \
		"CLANG_BUILD_TOOLS=false" \
		"LLVM_INCLUDE_BENCHMARKS=false" \
		"LLVM_INCLUDE_EXAMPLES=false" \
		"LLVM_TEMPORARILY_ALLOW_OLD_TOOLCHAIN=true" \
		$(HOST_CONFIG_SIGNATURE_ARGS)

# Generates LLVM build files for the host. CMake and Python are order-only
# prerequisites because their semantic versions are captured above.
$(LLVM_HOST_BUILD_DIR):
	mkdir -p $@

$(LLVM_HOST_BUILD_DIR): | $(call project-host-target,cmake)
$(LLVM_HOST_BUILD_DIR): | $(call project-host-target,python)

$(LLVM_HOST_CONFIGURED_FILE): $(LLVM_HOST_CONFIG_FILE)
$(LLVM_HOST_CONFIGURED_FILE): | $(LLVM_HOST_BUILD_DIR)
$(LLVM_HOST_CONFIGURED_FILE): | $(call project-host-target,cmake)
$(LLVM_HOST_CONFIGURED_FILE): | $(call project-host-target,python)
	cd $(LLVM_HOST_BUILD_DIR) && $(CMAKE) $(LLVM_SRCS)/llvm \
		$(LLVM_COMMON_CMAKE_FLAGS) \
		-DLIBCLANG_BUILD_STATIC=OFF \
		-DLLVM_TARGETS_TO_BUILD="$(LLVM_HOST_TARGETS)" \
		$(LLVM_EXTRA_HOST_FLAGS) \
		-DCMAKE_BUILD_TYPE=Release
	touch $@

LLVM_REPO = https://github.com/llvm/llvm-project
projects/llvm/sources:
	@$(call source-transaction-begin,$@); \
	git clone $(LLVM_REPO) $@ --depth=1 -b $(LLVM_BRANCH_OR_TAG); \
	$(source-transaction-commit)

$(eval $(call project-source-signature,llvm,git:$(LLVM_REPO)@$(LLVM_BRANCH_OR_TAG)))
