# SPDX-License-Identifier: Apache-2.0

$(eval $(call project-define,openssl))

ifeq ($(NDK_ARCH), arm64)
OPENSSL_ANDROID_TARGET := android-arm64
else ifeq ($(NDK_ARCH), x86_64)
OPENSSL_ANDROID_TARGET := android-x86_64
else ifeq ($(NDK_ARCH), armv7)
OPENSSL_ANDROID_TARGET := android-arm
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

$(OPENSSL_ANDROID):
	cd $(OPENSSL_ANDROID_BUILD_DIR) && \
		$(OPENSSL_ANDROID_ENV) make build_sw -j $(THREADS)
	cd $(OPENSSL_ANDROID_BUILD_DIR) && \
		$(OPENSSL_ANDROID_ENV) make install_sw
	cp $(OPENSSL_SRCS)/LICENSE.txt $(ANDROID_OUT_DIR)/licenses/openssl
	touch $@

$(OPENSSL_ANDROID_BUILD_DIR):
	mkdir -p $@
	cd $@ && $(OPENSSL_ANDROID_ENV) $(OPENSSL_SRCS)/Configure \
		$(OPENSSL_ANDROID_TARGET) \
		$(OPENSSL_BUILD_TYPE_OPTION) \
		--prefix=$(abspath $(ANDROID_OUT_DIR)) \
		--openssldir=$(abspath $(ANDROID_OUT_DIR))/ssl \
		--libdir=lib \
		-D__ANDROID_API__=$(NDK_API) \
		-Wl,-z,max-page-size=$(ANDROID_MAX_PAGE_SIZE) \
		shared no-apps no-docs

OPENSSL_REPO := https://github.com/openssl/openssl.git
projects/openssl/sources:
	git clone $(OPENSSL_REPO) $@ --depth=1 -b $(OPENSSL_BRANCH_OR_TAG)
