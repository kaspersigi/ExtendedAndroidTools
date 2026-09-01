# Copyright (c) Meta Platforms, Inc. and affiliates.

$(eval $(call project-define,flex))

$(FLEX_ANDROID):
	cd $(FLEX_ANDROID_BUILD_DIR) && make -j $(THREADS)
	cd $(FLEX_ANDROID_BUILD_DIR)/src && make install-libLTLIBRARIES install-binPROGRAMS install-includeHEADERS
	cp $(FLEX_SRCS)/COPYING $(ANDROID_OUT_DIR)/licenses/flex
	touch $@

$(FLEX_ANDROID_BUILD_DIR): $(ANDROID_CONFIG_SITE)
	mkdir -p $@
	cd $@ && $(FLEX_SRCS)/configure $(ANDROID_EXTRA_CONFIGURE_FLAGS)

$(HOST_OUT_DIR)/bin/flex: $(FLEX_HOST)

$(FLEX_HOST):
	cd $(FLEX_HOST_BUILD_DIR) && make install -j $(THREADS)
	touch $@

$(FLEX_HOST_BUILD_DIR):
	mkdir -p $@
	cd $@ && $(FLEX_SRCS)/configure --disable-bootstrap --prefix=$(abspath $(HOST_OUT_DIR))

FLEX_REPO = https://github.com/westes/flex.git
projects/flex/sources:
ifeq ($(shell whoami), vagrant)
	@set -eu; \
	tmp_sources="$$(mktemp -d /tmp/extended-android-tools-flex.XXXXXX)"; \
	source_target="$(abspath $@)"; \
	trap 'rm -rf -- "$$tmp_sources" "$$source_target"' 0 1 2 3 15; \
	rm -rf -- "$$source_target"; \
	git init "$$tmp_sources"; \
	git -C "$$tmp_sources" remote add origin $(FLEX_REPO); \
	git -C "$$tmp_sources" fetch --depth=1 --no-tags origin $(FLEX_COMMIT_HASH); \
	git -C "$$tmp_sources" checkout --detach FETCH_HEAD; \
	cd "$$tmp_sources" && ./autogen.sh; \
	mv "$$tmp_sources" "$$source_target"; \
	trap - 0 1 2 3 15
else
	@$(call source-transaction-begin,$@); \
	git init $@; \
	git -C $@ remote add origin $(FLEX_REPO); \
	git -C $@ fetch --depth=1 --no-tags origin $(FLEX_COMMIT_HASH); \
	git -C $@ checkout --detach FETCH_HEAD; \
	cd $@ && autoreconf -i -f; \
	$(source-transaction-commit)
endif

$(eval $(call project-source-signature,flex,git:$(FLEX_REPO)@$(FLEX_COMMIT_HASH)))
