# Copyright (c) Meta Platforms, Inc. and affiliates.

$(ANDROID_OUT_DIR)/lib/pkgconfig/zlib.pc: | $(ANDROID_OUT_DIR)
	version=$$(sed -n 's/^#define ZLIB_VERSION "\([^"]*\)"/\1/p' \
		$(ANDROID_SYSROOT_INCLUDE_PATH)/zlib.h); \
	test -n "$$version"; \
	printf '%s\n' \
		'Name: zlib' \
		'Description: zlib supplied by the Android NDK sysroot' \
		"Version: $$version" \
		'Libs: -lz' > $@
