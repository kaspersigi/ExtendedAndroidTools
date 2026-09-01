# Copyright (c) Meta Platforms, Inc. and affiliates.

CEREAL_HOST_DEPS = cmake
$(eval $(call project-define,cereal))

$(CEREAL_ANDROID):
	cd $(CEREAL_ANDROID_BUILD_DIR) && make install -j $(THREADS)
	cp $(CEREAL_SRCS)/LICENSE $(ANDROID_OUT_DIR)/licenses/cereal
	touch $@

$(CEREAL_ANDROID_BUILD_DIR):
	mkdir -p $@
	cd $@ && $(CMAKE) $(CEREAL_SRCS) \
		$(ANDROID_EXTRA_CMAKE_FLAGS) \
		-DBUILD_TESTS=OFF \
		-DBUILD_DOC=OFF \
		-DBUILD_SANDBOX=OFF \
		-DSKIP_PERFORMANCE_COMPARISON=ON

CEREAL_REPO = https://github.com/USCiLab/cereal
projects/cereal/sources:
	@$(call source-transaction-begin,$@); \
	git clone $(CEREAL_REPO) --depth=1 -b $(CEREAL_TAG) $@; \
	$(source-transaction-commit)

$(eval $(call project-source-signature,cereal,git:$(CEREAL_REPO)@$(CEREAL_TAG)))
