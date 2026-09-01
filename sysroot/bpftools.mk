# Copyright (c) Meta Platforms, Inc. and affiliates.

ifeq ($(NDK_ARCH), arm64)
TARGET_ARCH_ENV_VAR = arm64
else ifeq ($(NDK_ARCH), x86_64)
TARGET_ARCH_ENV_VAR = x86
else
$(error unknown abi $(NDK_ARCH))
endif

GEN_SETUP_SCRIPT = sed -e "s+<TARGET_ARCH_ENV_VAR>+$(TARGET_ARCH_ENV_VAR)+" sysroot/setup.sh > $@/setup.sh
gen-wrapper = sed -e "s+<BIN>+$(1)+" sysroot/wrapper.sh.template > $@/$(1) && chmod +x $@/$(1)
gen-python-module-wrapper = sed \
	-e "s+<PYTHON_BINARY>+$(PYTHON_BINARY)+" \
	-e "s+<PYTHON_MODULE>+$(1)+" \
	sysroot/python-module-wrapper.sh.template > $@/$(1) && chmod +x $@/$(1)

BPFTOOLS = $(ANDROID_SYSROOTS_OUT_DIR)/bpftools
BPFTOOLS_TAR = $(OUT_DIR)/bpftools-$(NDK_ARCH).tar.gz
bpftools: $(BPFTOOLS_TAR)

BPFTOOLS_MIN = $(ANDROID_SYSROOTS_OUT_DIR)/bpftools-min
BPFTOOLS_MIN_TAR = $(OUT_DIR)/bpftools-min-$(NDK_ARCH).tar.gz
bpftools-min: $(BPFTOOLS_MIN_TAR)

.PHONY: bpftools bpftools-min

$(BPFTOOLS_TAR): $(BPFTOOLS)
$(BPFTOOLS_MIN_TAR): $(BPFTOOLS_MIN)
$(BPFTOOLS_TAR) $(BPFTOOLS_MIN_TAR):
	tar --create --file=$@ --use-compress-program='gzip -n' \
		--sort=name --mtime='@$(SOURCE_DATE_EPOCH)' \
		--owner=0 --group=0 --numeric-owner \
		--transform="s|^$(ANDROID_SYSROOTS_OUT_DIR)/||" $^

$(BPFTOOLS) $(BPFTOOLS_MIN): $(ANDROID_SYSROOTS_OUT_DIR)
$(BPFTOOLS) $(BPFTOOLS_MIN): sysroot/setup.sh
$(BPFTOOLS) $(BPFTOOLS_MIN): sysroot/run.sh
$(BPFTOOLS) $(BPFTOOLS_MIN): sysroot/wrapper.sh.template
$(BPFTOOLS) $(BPFTOOLS_MIN): sysroot/bpftools.mk
$(BPFTOOLS): sysroot/python-module-wrapper.sh.template
$(BPFTOOLS) $(BPFTOOLS_MIN): $(call project-android-target,bcc)
$(BPFTOOLS) $(BPFTOOLS_MIN): $(call project-android-target,bpftrace)
$(BPFTOOLS) $(BPFTOOLS_MIN): $(call project-android-target,xz)
$(BPFTOOLS) $(BPFTOOLS_MIN): $(ANDROID_OUT_DIR)/lib/libc++_shared.so
$(BPFTOOLS): $(call project-android-target,python)

$(BPFTOOLS):
	rm -rf -- "$@"
	mkdir -p $@/bin
	cp $(ANDROID_OUT_DIR)/bin/bpftrace $@/bin/
	cp $(ANDROID_OUT_DIR)/bin/bpftrace-aotrt $@/bin/ || true
	cp -P $(ANDROID_OUT_DIR)/bin/python* $@/bin/
	cp $(ANDROID_OUT_DIR)/bin/xzcat $@/bin/

	mkdir -p $@/lib
	cp $(ANDROID_OUT_DIR)/lib/libbcc.so $@/lib/
	cp $(ANDROID_OUT_DIR)/lib/libbcc_bpf.so $@/lib/
	cp -a $(ANDROID_OUT_DIR)/lib/libbpf.so* $@/lib/
	cp -a $(ANDROID_OUT_DIR)/lib/libLLVM*.so* $@/lib/
	cp -a $(ANDROID_OUT_DIR)/lib/libclang.so* $@/lib/
	cp -a $(ANDROID_OUT_DIR)/lib/libclang-cpp.so* $@/lib/
	cp $(ANDROID_OUT_DIR)/lib/libc++_shared.so $@/lib/
	cp -a $(ANDROID_OUT_DIR)/lib/libelf*.so* $@/lib/
	cp $(ANDROID_OUT_DIR)/lib/libfl.so $@/lib/
	cp $(ANDROID_OUT_DIR)/lib/liblzma.so $@/lib/
	cp -a $(ANDROID_OUT_DIR)/lib/libzstd.so* $@/lib/
	cp -a $(ANDROID_OUT_DIR)/lib/libcrypto.so* $@/lib/
	cp -a $(ANDROID_OUT_DIR)/lib/libssl.so* $@/lib/
	cp -a $(ANDROID_OUT_DIR)/lib/python3* $@/lib/
	cp -a $(ANDROID_OUT_DIR)/lib/libpython*.so* $@/lib/
	cp $(ANDROID_OUT_DIR)/lib/libffi.so $@/lib/
	if [ -d $(ANDROID_OUT_DIR)/lib/ossl-modules ]; then \
		cp -a $(ANDROID_OUT_DIR)/lib/ossl-modules $@/lib/; \
	fi

	mkdir -p $@/share
	cp -a $(ANDROID_OUT_DIR)/share/bcc $@/share/
	cp -a $(ANDROID_OUT_DIR)/share/bpftrace $@/share/
	cp -a $(ANDROID_OUT_DIR)/share/certs $@/share/

	cp -r sysroot/run.sh $@/
	$(GEN_SETUP_SCRIPT)
	$(call gen-wrapper,bpftrace)
	$(call gen-wrapper,bpftrace-aotrt)
	$(call gen-wrapper,$(PYTHON_BINARY))
	cp $@/$(PYTHON_BINARY) $@/python3
	$(call gen-python-module-wrapper,pip)
	cp $@/pip $@/pip3
	$(call gen-wrapper,xzcat)

	rm -rf $@/licenses
	cp -r $(ANDROID_OUT_DIR)/licenses $@/licenses
	touch $@

$(BPFTOOLS_MIN):
	rm -rf -- "$@"
	mkdir -p $@/bin
	cp $(ANDROID_OUT_DIR)/bin/bpftrace $@/bin/
	cp $(ANDROID_OUT_DIR)/bin/xzcat $@/bin/

	mkdir -p $@/lib
	cp $(ANDROID_OUT_DIR)/lib/libbcc_bpf.so $@/lib/
	cp -a $(ANDROID_OUT_DIR)/lib/libbpf.so* $@/lib/
	cp -a $(ANDROID_OUT_DIR)/lib/libLLVM*.so* $@/lib/
	cp -a $(ANDROID_OUT_DIR)/lib/libclang.so* $@/lib/
	cp -a $(ANDROID_OUT_DIR)/lib/libclang-cpp.so* $@/lib/
	cp $(ANDROID_OUT_DIR)/lib/libc++_shared.so $@/lib/
	cp -a $(ANDROID_OUT_DIR)/lib/libelf*.so* $@/lib/
	cp $(ANDROID_OUT_DIR)/lib/liblzma.so $@/lib/

	mkdir -p $@/share
	cp -a $(ANDROID_OUT_DIR)/share/bpftrace $@/share/

	cp -r sysroot/run.sh $@/
	$(GEN_SETUP_SCRIPT)
	$(call gen-wrapper,bpftrace)
	$(call gen-wrapper,xzcat)

	rm -rf $@/licenses
	cp -r $(ANDROID_OUT_DIR)/licenses $@/licenses
	touch $@
