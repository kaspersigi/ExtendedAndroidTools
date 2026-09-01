# Copyright (c) Meta Platforms, Inc. and affiliates.

NDK_API = 30
NDK_PATH = /opt/ndk/android-ndk-r27d
ANDROID_TOOLCHAIN_PATH = \
    $(abspath $(NDK_PATH)/toolchains/llvm/prebuilt/linux-x86_64/bin)
ANDROID_TOOLCHAIN_STRIP_PATH = $(ANDROID_TOOLCHAIN_PATH)/llvm-strip

ifeq ($(NDK_ARCH), arm64)
ANDROID_MAX_PAGE_SIZE = 16384
ANDROID_SYSROOT_LIB_SUBDIR = aarch64-linux-android
else ifeq ($(NDK_ARCH), x86_64)
ANDROID_MAX_PAGE_SIZE = 16384
ANDROID_SYSROOT_LIB_SUBDIR = x86_64-linux-android
else
$(error unknown abi $(NDK_ARCH))
endif

ANDROID_SYSROOT_PATH = \
    $(abspath $(NDK_PATH)/toolchains/llvm/prebuilt/linux-x86_64/sysroot)
ANDROID_SYSROOT_INCLUDE_PATH = \
    $(ANDROID_SYSROOT_PATH)/usr/include/
ANDROID_SYSROOT_LIB_PATH = \
    $(ANDROID_SYSROOT_PATH)/usr/lib/$(ANDROID_SYSROOT_LIB_SUBDIR)/$(NDK_API)/

ANDROID_NDK_REVISION = $(shell sed -n \
	's/^[[:space:]]*Pkg\.Revision[[:space:]]*=[[:space:]]*//p' \
	$(NDK_PATH)/source.properties 2>/dev/null | head -n 1)
ANDROID_NDK_TOOLCHAIN_SHA256 = $(shell sha256sum \
	$(NDK_PATH)/build/cmake/android.toolchain.cmake 2>/dev/null | cut -d ' ' -f 1)
ANDROID_BUILD_RULES_SHA256 = $(shell sha256sum \
	toolchains/toolchains.mk toolchains/autotools.mk toolchains/cmake.mk \
	| sha256sum | cut -d ' ' -f 1)
ANDROID_CONFIG_SIGNATURE_ARGS = \
	"NDK_PATH=$(abspath $(NDK_PATH))" \
	"NDK_REVISION=$(ANDROID_NDK_REVISION)" \
	"NDK_TOOLCHAIN_SHA256=$(ANDROID_NDK_TOOLCHAIN_SHA256)" \
	"NDK_ARCH=$(NDK_ARCH)" \
	"NDK_API=$(NDK_API)" \
	"CMAKE_ABI=$(CMAKE_ABI)" \
	"ANDROID_MAX_PAGE_SIZE=$(ANDROID_MAX_PAGE_SIZE)" \
	"ANDROID_OUT_DIR=$(abspath $(ANDROID_OUT_DIR))" \
	"BUILD_TYPE=$(BUILD_TYPE)" \
	"STATIC_LINKING=$(STATIC_LINKING)" \
	"LLVM_BPF_ONLY=$(LLVM_BPF_ONLY)" \
	"BUILD_RULES_SHA256=$(ANDROID_BUILD_RULES_SHA256)"

ANDROID_LIBCXX_SHARED_SOURCE = \
    $(ANDROID_SYSROOT_PATH)/usr/lib/$(ANDROID_SYSROOT_LIB_SUBDIR)/libc++_shared.so
ANDROID_LIBCXX_SHARED_TARGET = $(ANDROID_OUT_DIR)/lib/libc++_shared.so
ANDROID_LIBCXX_SHARED_CONFIG = $(ANDROID_BUILD_DIR)/libcxx-shared.config
ANDROID_LIBCXX_SHARED_SHA256 = $(shell sha256sum \
	$(ANDROID_LIBCXX_SHARED_SOURCE) 2>/dev/null | cut -d ' ' -f 1)

.PHONY: force-libcxx-shared-config
force-libcxx-shared-config:

$(ANDROID_LIBCXX_SHARED_CONFIG): force-libcxx-shared-config
$(ANDROID_LIBCXX_SHARED_CONFIG): scripts/update-signature.sh
$(ANDROID_LIBCXX_SHARED_CONFIG): | $(ANDROID_BUILD_DIR)
	@scripts/update-signature.sh $@ \
	    "PROJECT=libcxx-shared-android" \
	    "NDK_PATH=$(abspath $(NDK_PATH))" \
	    "NDK_REVISION=$(ANDROID_NDK_REVISION)" \
	    "NDK_ARCH=$(NDK_ARCH)" \
	    "SOURCE=$(ANDROID_LIBCXX_SHARED_SOURCE)" \
	    "SOURCE_SHA256=$(ANDROID_LIBCXX_SHARED_SHA256)"

$(ANDROID_LIBCXX_SHARED_TARGET): $(ANDROID_LIBCXX_SHARED_CONFIG)
$(ANDROID_LIBCXX_SHARED_TARGET): | $(ANDROID_OUT_DIR)
	cp $(ANDROID_LIBCXX_SHARED_SOURCE) $@

include toolchains/autotools.mk
include toolchains/cmake.mk
