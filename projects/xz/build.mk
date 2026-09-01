# Copyright (c) Meta Platforms, Inc. and affiliates.

$(eval $(call project-define,xz))

$(XZ_ANDROID):
	cd $(XZ_ANDROID_BUILD_DIR) && make install -j $(THREADS)
	cp $(XZ_SRCS)/COPYING $(ANDROID_OUT_DIR)/licenses/xz
	touch $@

$(XZ_ANDROID_BUILD_DIR): $(ANDROID_CONFIG_SITE)
	mkdir -p $@
	cd $@ && $(XZ_SRCS)/configure $(ANDROID_EXTRA_CONFIGURE_FLAGS)

XZ_REPO = https://github.com/tukaani-project/xz.git
projects/xz/sources:
ifeq ($(shell whoami), vagrant)
	@set -eu; \
	tmp_sources="$$(mktemp -d /tmp/extended-android-tools-xz.XXXXXX)"; \
	source_target="$(abspath $@)"; \
	trap 'rm -rf -- "$$tmp_sources" "$$source_target"' 0 1 2 3 15; \
	rm -rf -- "$$source_target"; \
	git clone $(XZ_REPO) "$$tmp_sources" --depth=1 -b $(XZ_BRANCH_OR_TAG); \
	cd "$$tmp_sources" && ./autogen.sh; \
	mv "$$tmp_sources" "$$source_target"; \
	trap - 0 1 2 3 15
else
	@$(call source-transaction-begin,$@); \
	git clone $(XZ_REPO) $@ --depth=1 -b $(XZ_BRANCH_OR_TAG); \
	cd $@ && ./autogen.sh; \
	$(source-transaction-commit)
endif

$(eval $(call project-source-signature,xz,git:$(XZ_REPO)@$(XZ_BRANCH_OR_TAG)))
