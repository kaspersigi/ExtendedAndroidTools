# Copyright (c) Meta Platforms, Inc. and affiliates.

LLVM_HOST_DEPS = cmake python
$(eval $(call project-define,llvm))

ifeq ($(NDK_ARCH), arm64)
LLVM_DEFAULT_TARGET = AArch64
LLVM_HOST_TRIPLE = aarch64-linux-android
LLVM_TARGET_TRIPLE = aarch64-linux-android
else ifeq ($(NDK_ARCH), x86_64)
LLVM_DEFAULT_TARGET = X86
LLVM_HOST_TRIPLE = x86_64-linux-android
LLVM_TARGET_TRIPLE = x86_64-linux-android
else ifeq ($(NDK_ARCH), armv7)
LLVM_DEFAULT_TARGET = ARM
LLVM_HOST_TRIPLE = armv7a-linux-androideabi
LLVM_TARGET_TRIPLE = armv7a-linux-androideabi
else
$(error unknown abi $(NDK_ARCH))
endif

LLVM_EXTRA_CMAKE_FLAGS = -DLLVM_ENABLE_PROJECTS="clang"
LLVM_EXTRA_CMAKE_FLAGS += -DLLVM_BUILD_TOOLS=OFF
LLVM_EXTRA_CMAKE_FLAGS += -DCLANG_BUILD_TOOLS=OFF
LLVM_EXTRA_CMAKE_FLAGS += -DLLVM_INCLUDE_BENCHMARKS=OFF
LLVM_EXTRA_CMAKE_FLAGS += -DLLVM_INCLUDE_EXAMPLES=OFF
LLVM_EXTRA_HOST_FLAGS = -DLLVM_TEMPORARILY_ALLOW_OLD_TOOLCHAIN=1

# Dynamic Android tools must share one LLVM instance with libclang-cpp.
# Otherwise bpftrace and libclang-cpp each embed separate static LLVM registries,
# and Clang cannot see the BPF target registered by bpftrace.
LLVM_ANDROID_EXTRA_CMAKE_FLAGS = -DLLVM_BUILD_LLVM_DYLIB=ON
LLVM_ANDROID_EXTRA_CMAKE_FLAGS += -DLLVM_LINK_LLVM_DYLIB=ON
LLVM_ANDROID_EXTRA_CMAKE_FLAGS += -DCLANG_LINK_CLANG_DYLIB=ON

ifeq ($(STATIC_LINKING),true)
LLVM_ANDROID_EXTRA_CMAKE_FLAGS =
endif

ifeq ($(STATIC_LINKING),true)
LLVM_EXTRA_CMAKE_FLAGS += -DLIBCLANG_BUILD_STATIC=ON
endif

# The local bpftrace-static artifact is built alongside the dynamic archives.
# In that case LLVM must install both libclang.so and libclang.a so both
# link modes can reuse this one LLVM build.
ifneq ($(filter bpftrace-static,$(MAKECMDGOALS)),)
LLVM_EXTRA_CMAKE_FLAGS += -DLIBCLANG_BUILD_STATIC=ON
endif

ifeq ($(LLVM_BPF_ONLY),true)
LLVM_EXTRA_CMAKE_FLAGS += -DLLVM_TARGETS_TO_BUILD=BPF
else
LLVM_EXTRA_CMAKE_FLAGS += -DLLVM_TARGETS_TO_BUILD="$(LLVM_DEFAULT_TARGET);BPF"
endif

$(LLVM_ANDROID):
ifeq ($(BUILD_TYPE), Debug)
	cd $(LLVM_ANDROID_BUILD_DIR) && $(MAKE) install -j $(THREADS)
else
	cd $(LLVM_ANDROID_BUILD_DIR) && $(MAKE) install/strip -j $(THREADS)
endif
	cp $(LLVM_SRCS)/clang/LICENSE.TXT $(ANDROID_OUT_DIR)/licenses/clang
	cp $(LLVM_SRCS)/llvm/LICENSE.TXT $(ANDROID_OUT_DIR)/licenses/llvm
	touch $@

$(LLVM_ANDROID_BUILD_DIR): $(HOST_OUT_DIR)/bin/llvm-config
$(LLVM_ANDROID_BUILD_DIR): $(HOST_OUT_DIR)/bin/llvm-tblgen
$(LLVM_ANDROID_BUILD_DIR): $(HOST_OUT_DIR)/bin/clang-tblgen
	-mkdir $@
	cd $@ && $(CMAKE) $(LLVM_SRCS)/llvm \
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
$(HOST_OUT_DIR)/bin/llvm-config: $(LLVM_HOST_BUILD_DIR) | $(HOST_OUT_DIR)
$(HOST_OUT_DIR)/bin/llvm-tblgen: $(LLVM_HOST_BUILD_DIR) | $(HOST_OUT_DIR)
$(HOST_OUT_DIR)/bin/clang-tblgen: $(LLVM_HOST_BUILD_DIR) | $(HOST_OUT_DIR)
$(HOST_OUT_DIR)/bin/llvm-config $(HOST_OUT_DIR)/bin/llvm-tblgen $(HOST_OUT_DIR)/bin/clang-tblgen:
	cd $(LLVM_HOST_BUILD_DIR) && $(MAKE) -j $(THREADS) $(notdir $@)
	cp $(LLVM_HOST_BUILD_DIR)/bin/$(notdir $@) $@

# generates llvm build files for host
$(LLVM_HOST_BUILD_DIR):
	-mkdir $@
	cd $@ && $(CMAKE) $(LLVM_SRCS)/llvm \
		$(LLVM_EXTRA_CMAKE_FLAGS) \
		$(LLVM_EXTRA_HOST_FLAGS) \
		-DCMAKE_BUILD_TYPE=Release

LLVM_REPO = https://github.com/llvm/llvm-project
projects/llvm/sources:
	git clone $(LLVM_REPO) $@ --depth=1 -b $(LLVM_BRANCH_OR_TAG)
