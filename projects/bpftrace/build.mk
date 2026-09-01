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

$(BPFTRACE_ANDROID): $(ANDROID_OUT_DIR)/lib/libc++_shared.so $(LIBBPF_ANDROID)
ifeq ($(BUILD_TYPE), Debug)
	cd $(BPFTRACE_ANDROID_BUILD_DIR) && $(MAKE) install -j $(THREADS)
else
	cd $(BPFTRACE_ANDROID_BUILD_DIR) && $(MAKE) install/strip -j $(THREADS)
endif
	cp $(BPFTRACE_SRCS)/LICENSE $(ANDROID_OUT_DIR)/licenses/bpftrace
	touch $@

$(BPFTRACE_ANDROID_BUILD_DIR): $(HOST_OUT_DIR)/bin/flex $(STRIP_THUNK) $(LIBBPF_ANDROID)
	-mkdir $@
	cd $@ && LDFLAGS="$(BPFTRACE_EXTRA_LDFLAGS)" $(CMAKE) $(BPFTRACE_SRCS) \
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

$(STRIP_THUNK): projects/bpftrace/strip-thunk | $(HOST_OUT_DIR)
	@sed -e "s+<STRIP_PATH>+$(ANDROID_TOOLCHAIN_STRIP_PATH)+g" $< > $@
	chmod +x $@

BPFTRACE_REPO = https://github.com/iovisor/bpftrace.git/
projects/bpftrace/sources:
	git clone $(BPFTRACE_REPO) $@ --depth=1 -b $(BPFTRACE_COMMIT) && \
	cd $@ && \
	{ git apply --verbose ../tracefs_fallback_v0.26.1.patch && \
	  git apply --verbose ../version_from_git_tag.patch || \
	  (echo "Patch failed to apply, stopping build!" && exit 1); }

# Build a standalone static bpftrace without replacing the dynamic bpftrace
# installed under out/android/<arch>. Its dependencies and LLVM installation
# are shared with bpftools/bpftools-min, while its CMake cache stays isolated.
BPFTRACE_STATIC_BUILD_DIR = $(ANDROID_BUILD_DIR)/bpftrace-static
BPFTRACE_STATIC_ARTIFACT = $(OUT_DIR)/bpftrace-$(NDK_ARCH)

.PHONY: bpftrace-static
bpftrace-static: $(BPFTRACE_STATIC_BUILD_DIR)
	cd $(BPFTRACE_STATIC_BUILD_DIR) && $(MAKE) bpftrace -j $(THREADS)
	cp $(BPFTRACE_STATIC_BUILD_DIR)/src/bpftrace $(BPFTRACE_STATIC_ARTIFACT)
ifeq ($(BUILD_TYPE), Debug)
	@true
else
	$(STRIP_THUNK) $(BPFTRACE_STATIC_ARTIFACT)
endif

$(BPFTRACE_STATIC_BUILD_DIR): projects/bpftrace/sources
$(BPFTRACE_STATIC_BUILD_DIR): $(STRIP_THUNK)
$(BPFTRACE_STATIC_BUILD_DIR): $(ANDROID_OUT_DIR)/lib/libclang.a
$(BPFTRACE_STATIC_BUILD_DIR): \
	$(foreach dep,$(BPFTRACE_ANDROID_DEPS),$(call project-android-target,$(dep)))
$(BPFTRACE_STATIC_BUILD_DIR): \
	$(foreach dep,$(BPFTRACE_HOST_DEPS),$(call project-host-target,$(dep)))
	mkdir -p $@
	cd $@ && LDFLAGS=$(BPFTRACE_STATIC_LDFLAGS) $(CMAKE) $(BPFTRACE_SRCS) \
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
