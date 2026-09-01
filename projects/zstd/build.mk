# SPDX-License-Identifier: Apache-2.0

ZSTD_HOST_DEPS = cmake
$(eval $(call project-define,zstd))

ZSTD_ANDROID_CONFIG_FILE := $(ANDROID_BUILD_DIR)/zstd.config
ZSTD_ANDROID_CONFIGURED_FILE := $(ZSTD_ANDROID_BUILD_DIR)/.configured

$(ZSTD_ANDROID): $(ZSTD_ANDROID_CONFIGURED_FILE)
$(ZSTD_ANDROID_CONFIG_FILE): force-config-signature projects/zstd/sources
$(ZSTD_ANDROID_CONFIG_FILE): projects/zstd/build.mk projects/versions.mk
$(ZSTD_ANDROID_CONFIG_FILE): scripts/update-signature.sh | $(ANDROID_BUILD_DIR)
	@scripts/update-signature.sh $@ \
		"PROJECT=zstd-android" \
		"ZSTD_VERSION=$(ZSTD_TAG)" \
		"CMAKE_VERSION=$(CMAKE_VERSION)" \
		"SOURCE_REVISION=$(shell git -C $(ZSTD_SRCS) rev-parse HEAD 2>/dev/null || echo unavailable)" \
		"BUILD_RULE_SHA256=$(shell sha256sum projects/zstd/build.mk | cut -d ' ' -f 1)" \
		$(ANDROID_CONFIG_SIGNATURE_ARGS)

$(ZSTD_ANDROID):
	cd $(ZSTD_ANDROID_BUILD_DIR) && $(CMAKE) --build . --parallel $(THREADS)
	$(call clean-android-library-families,libzstd.so*)
	cd $(ZSTD_ANDROID_BUILD_DIR) && $(CMAKE) --install .
	cp $(ZSTD_SRCS)/LICENSE $(ANDROID_OUT_DIR)/licenses/zstd
	touch $@

$(ZSTD_ANDROID_BUILD_DIR):
	mkdir -p $@

$(ZSTD_ANDROID_CONFIGURED_FILE): $(ZSTD_ANDROID_CONFIG_FILE)
$(ZSTD_ANDROID_CONFIGURED_FILE): | $(ZSTD_ANDROID_BUILD_DIR)
	cd $(ZSTD_ANDROID_BUILD_DIR) && $(CMAKE) $(ZSTD_SRCS)/build/cmake \
		$(ANDROID_EXTRA_CMAKE_FLAGS) \
		-DCMAKE_INSTALL_LIBDIR=lib \
		-DZSTD_BUILD_PROGRAMS=OFF \
		-DZSTD_BUILD_TESTS=OFF \
		-DZSTD_BUILD_CONTRIB=OFF \
		-DZSTD_BUILD_SHARED=ON \
		-DZSTD_BUILD_STATIC=ON
	touch $@

ZSTD_REPO = https://github.com/facebook/zstd.git
projects/zstd/sources:
	@$(call source-transaction-begin,$@); \
	git clone $(ZSTD_REPO) $@ --depth=1 -b $(ZSTD_TAG); \
	$(source-transaction-commit)

$(eval $(call project-source-signature,zstd,git:$(ZSTD_REPO)@$(ZSTD_TAG)))
