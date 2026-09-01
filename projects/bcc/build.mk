# Copyright (c) Meta Platforms, Inc. and affiliates.

BCC_ANDROID_DEPS = llvm libbpf flex elfutils python xz
BCC_HOST_DEPS = cmake flex python
$(eval $(call project-define,bcc))

BCC_EXTRA_CFLAGS += "-I$(abspath $(ANDROID_OUT_DIR))/include" -include strings.h
BCC_EXTRA_LDFLAGS = "-L$(abspath $(ANDROID_OUT_DIR))/lib"

BCC_ANDROID_CONFIG_FILE := $(ANDROID_BUILD_DIR)/bcc.config
BCC_ANDROID_CONFIGURED_FILE := $(BCC_ANDROID_BUILD_DIR)/.configured

$(BCC_ANDROID): $(BCC_ANDROID_CONFIGURED_FILE)
prepare-bcc: $(BCC_ANDROID_CONFIGURED_FILE)

$(BCC_ANDROID_CONFIG_FILE): force-config-signature projects/bcc/sources
$(BCC_ANDROID_CONFIG_FILE): projects/bcc/build.mk projects/versions.mk
$(BCC_ANDROID_CONFIG_FILE): scripts/update-signature.sh | $(ANDROID_BUILD_DIR)
	@scripts/update-signature.sh $@ \
		"PROJECT=bcc-android" \
		"BCC_VERSION=$(BCC_COMMIT)" \
		"LLVM_VERSION=$(LLVM_BRANCH_OR_TAG)" \
		"LIBBPF_VERSION=$(LIBBPF_TAG)" \
		"PYTHON_VERSION=$(PYTHON_VERSION)" \
		"ELFUTILS_VERSION=$(ELFUTILS_VERSION)" \
		"FLEX_VERSION=$(FLEX_COMMIT_HASH)" \
		"XZ_VERSION=$(XZ_BRANCH_OR_TAG)" \
		"SOURCE_REVISION=$(shell git -C $(BCC_SRCS) rev-parse HEAD 2>/dev/null || echo unavailable)" \
		"BUILD_RULE_SHA256=$(shell sha256sum projects/bcc/build.mk | cut -d ' ' -f 1)" \
		$(ANDROID_CONFIG_SIGNATURE_ARGS)

$(BCC_ANDROID):
ifeq ($(BUILD_TYPE), Debug)
	cd $(ANDROID_BUILD_DIR)/bcc && $(MAKE) install -j $(THREADS)
else
	cd $(ANDROID_BUILD_DIR)/bcc && $(MAKE) install/strip -j $(THREADS)
endif
	cp $(BCC_SRCS)/LICENSE.txt $(ANDROID_OUT_DIR)/licenses/bcc
	touch $@

# generates bcc build files for Android
$(BCC_ANDROID_BUILD_DIR): $(HOST_OUT_DIR)/bin/flex $(PYTHON_XINSTALL)
	mkdir -p $@

$(BCC_ANDROID_CONFIGURED_FILE): $(BCC_ANDROID_CONFIG_FILE)
$(BCC_ANDROID_CONFIGURED_FILE): $(HOST_OUT_DIR)/bin/flex $(PYTHON_XINSTALL)
$(BCC_ANDROID_CONFIGURED_FILE): | $(BCC_ANDROID_BUILD_DIR)
	cd $(BCC_ANDROID_BUILD_DIR) && CFLAGS="$(BCC_EXTRA_CFLAGS)" CXXFLAGS="$(BCC_EXTRA_CFLAGS)" LDFLAGS="$(BCC_EXTRA_LDFLAGS)" \
		$(CMAKE) $(BCC_SRCS) \
		$(ANDROID_EXTRA_CMAKE_FLAGS) \
		-DFLEX_EXECUTABLE=$(abspath $(HOST_OUT_DIR)/bin/flex) \
		-DBPS_LINK_RT=OFF \
		-DENABLE_TESTS=OFF \
		-DCMAKE_USE_LIBBPF_PACKAGE=ON \
		-DPYTHON_CMD=$(PYTHON_XINSTALL)
	touch $@

BCC_REPO = https://github.com/iovisor/bcc
projects/bcc/sources:
	@$(call source-transaction-begin,$@); \
	git clone $(BCC_REPO) $@ --depth=1 -b $(BCC_COMMIT); \
	$(source-transaction-commit)

$(eval $(call project-source-signature,bcc,git:$(BCC_REPO)@$(BCC_COMMIT)))
