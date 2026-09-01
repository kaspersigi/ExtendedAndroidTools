# SPDX-License-Identifier: Apache-2.0

$(eval $(call project-define,openssl))

ifeq ($(NDK_ARCH), arm64)
OPENSSL_ANDROID_TARGET := android-arm64
else ifeq ($(NDK_ARCH), x86_64)
OPENSSL_ANDROID_TARGET := android-x86_64
else
$(error unknown abi $(NDK_ARCH))
endif

ifeq ($(BUILD_TYPE), Debug)
OPENSSL_BUILD_TYPE_OPTION := --debug
else
OPENSSL_BUILD_TYPE_OPTION := --release
endif

OPENSSL_ANDROID_ENV = ANDROID_NDK_ROOT=$(abspath $(NDK_PATH))
OPENSSL_ANDROID_ENV += PATH=$(abspath $(ANDROID_TOOLCHAIN_PATH)):$(PATH)

OPENSSL_ANDROID_CONFIG_FILE := $(ANDROID_BUILD_DIR)/openssl.config
OPENSSL_ANDROID_CONFIGURED_FILE := $(OPENSSL_ANDROID_BUILD_DIR)/.configured

$(OPENSSL_ANDROID): $(OPENSSL_ANDROID_CONFIGURED_FILE)
prepare-openssl: $(OPENSSL_ANDROID_CONFIGURED_FILE)

$(OPENSSL_ANDROID_CONFIG_FILE): force-config-signature projects/openssl/sources
$(OPENSSL_ANDROID_CONFIG_FILE): projects/openssl/build.mk projects/versions.mk
$(OPENSSL_ANDROID_CONFIG_FILE): scripts/update-signature.sh | $(ANDROID_BUILD_DIR)
	@scripts/update-signature.sh $@ \
		"PROJECT=openssl-android" \
		"OPENSSL_VERSION=$(OPENSSL_VERSION)" \
		"SOURCE_REVISION=$(shell git -C $(OPENSSL_SRCS) rev-parse HEAD 2>/dev/null || echo unavailable)" \
		"OPENSSL_TARGET=$(OPENSSL_ANDROID_TARGET)" \
		"OPENSSL_BUILD_TYPE_OPTION=$(OPENSSL_BUILD_TYPE_OPTION)" \
		"BUILD_RULE_SHA256=$(shell sha256sum projects/openssl/build.mk | cut -d ' ' -f 1)" \
		$(ANDROID_CONFIG_SIGNATURE_ARGS)

$(OPENSSL_ANDROID):
	cd $(OPENSSL_ANDROID_BUILD_DIR) && \
		$(OPENSSL_ANDROID_ENV) make build_sw -j $(THREADS)
	$(call clean-android-library-families,libcrypto.so* libssl.so*)
	$(RM) -r $(ANDROID_OUT_DIR)/lib/engines-* $(ANDROID_OUT_DIR)/lib/ossl-modules
	cd $(OPENSSL_ANDROID_BUILD_DIR) && \
		$(OPENSSL_ANDROID_ENV) make install_sw
	cp $(OPENSSL_SRCS)/LICENSE.txt $(ANDROID_OUT_DIR)/licenses/openssl
	touch $@

$(OPENSSL_ANDROID_BUILD_DIR):
	mkdir -p $@

$(OPENSSL_ANDROID_CONFIGURED_FILE): $(OPENSSL_ANDROID_CONFIG_FILE)
$(OPENSSL_ANDROID_CONFIGURED_FILE): | $(OPENSSL_ANDROID_BUILD_DIR)
	cd $(OPENSSL_ANDROID_BUILD_DIR) && $(OPENSSL_ANDROID_ENV) $(OPENSSL_SRCS)/Configure \
		$(OPENSSL_ANDROID_TARGET) \
		$(OPENSSL_BUILD_TYPE_OPTION) \
		--prefix=$(abspath $(ANDROID_OUT_DIR)) \
		--openssldir=$(abspath $(ANDROID_OUT_DIR))/ssl \
		--libdir=lib \
		-D__ANDROID_API__=$(NDK_API) \
		-Wl,-z,max-page-size=$(ANDROID_MAX_PAGE_SIZE) \
		shared no-apps no-docs
	touch $@

OPENSSL_REPO := https://github.com/openssl/openssl.git
projects/openssl/sources:
	@$(call source-transaction-begin,$@); \
	git clone $(OPENSSL_REPO) $@ --depth=1 -b $(OPENSSL_BRANCH_OR_TAG); \
	$(source-transaction-commit)

$(eval $(call project-source-signature,openssl,git:$(OPENSSL_REPO)@$(OPENSSL_BRANCH_OR_TAG)))
