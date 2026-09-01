# Copyright (c) Meta Platforms, Inc. and affiliates.

STDCXXFS_ANDROID := $(ANDROID_BUILD_DIR)/stdc++fs.done
STDCXXFS_ANDROID_BUILD_DIR := $(ANDROID_BUILD_DIR)/stdc++fs
STDCXXFS_ANDROID_CONFIG_FILE := $(ANDROID_BUILD_DIR)/stdc++fs.config

stdc++fs: $(STDCXXFS_ANDROID)

$(STDCXXFS_ANDROID): $(STDCXXFS_ANDROID_CONFIG_FILE)
$(STDCXXFS_ANDROID): | $(STDCXXFS_ANDROID_BUILD_DIR) $(ANDROID_OUT_DIR)
	$(ANDROID_TOOLCHAIN_PATH)/clang++ -target $(ANDROID_TRIPLE) -c -std=c++17 projects/stdc++fs/thunks.cpp -o $(ANDROID_BUILD_DIR)/thunks.o
	$(ANDROID_TOOLCHAIN_PATH)/llvm-ar rc $(ANDROID_OUT_DIR)/lib/libstdc++fs.a $(ANDROID_BUILD_DIR)/thunks.o
	touch $@

$(STDCXXFS_ANDROID_CONFIG_FILE): force-config-signature
$(STDCXXFS_ANDROID_CONFIG_FILE): projects/stdc++fs/build.mk projects/stdc++fs/thunks.cpp
$(STDCXXFS_ANDROID_CONFIG_FILE): scripts/update-signature.sh | $(ANDROID_BUILD_DIR)
	@scripts/update-signature.sh $@ \
		"PROJECT=stdc++fs-android" \
		"BUILD_RULE_SHA256=$(shell sha256sum projects/stdc++fs/build.mk | cut -d ' ' -f 1)" \
		"SOURCE_SHA256=$(shell sha256sum projects/stdc++fs/thunks.cpp | cut -d ' ' -f 1)" \
		$(ANDROID_CONFIG_SIGNATURE_ARGS)

$(STDCXXFS_ANDROID_BUILD_DIR): | $(ANDROID_BUILD_DIR)
	mkdir -p $@
