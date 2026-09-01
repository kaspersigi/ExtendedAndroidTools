# Copyright (c) Meta Platforms, Inc. and affiliates.

$(eval $(call project-define,cmake))

$(CMAKE_HOST):
	cd $(CMAKE_HOST_BUILD_DIR) && make install -j $(THREADS)
	touch $@

$(CMAKE_HOST_BUILD_DIR):
	-mkdir $@
	cd $@ && $(CMAKE_SRCS)/bootstrap \
		--parallel=$(THREADS) \
		--prefix=$(abspath $(HOST_OUT_DIR))

CMAKE_URL = https://github.com/Kitware/CMake/releases/download/v$(CMAKE_VERSION)/cmake-$(CMAKE_VERSION).tar.gz
$(DOWNLOADS_DIR)/cmake-$(CMAKE_VERSION).tar.gz: | $(DOWNLOADS_DIR)
	curl --fail --location --retry 3 --output $@ $(CMAKE_URL)

projects/cmake/sources: $(DOWNLOADS_DIR)/cmake-$(CMAKE_VERSION).tar.gz
	-mkdir $@
	tar xf $(DOWNLOADS_DIR)/cmake-$(CMAKE_VERSION).tar.gz -C $@ \
		--transform="s|^cmake-$(CMAKE_VERSION)/||"
