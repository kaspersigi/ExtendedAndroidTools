# Copyright (c) Meta Platforms, Inc. and affiliates.

$(eval $(call project-define,cmake))

$(CMAKE_HOST):
	cd $(CMAKE_HOST_BUILD_DIR) && make install -j $(THREADS)
	touch $@

$(CMAKE_HOST_BUILD_DIR):
	mkdir -p $@
	cd $@ && $(CMAKE_SRCS)/bootstrap \
		--parallel=$(THREADS) \
		--prefix=$(abspath $(HOST_OUT_DIR))

CMAKE_URL = https://github.com/Kitware/CMake/releases/download/v$(CMAKE_VERSION)/cmake-$(CMAKE_VERSION).tar.gz
$(DOWNLOADS_DIR)/cmake-$(CMAKE_VERSION).tar.gz: | $(DOWNLOADS_DIR)
	@set -eu; \
	tmp_file="$@.tmp"; \
	trap 'rm -f "$$tmp_file"' 0 1 2 3 15; \
	curl --fail --location --retry 3 --output "$$tmp_file" $(CMAKE_URL); \
	printf '%s  %s\n' '$(CMAKE_SOURCE_SHA256)' "$$tmp_file" | sha256sum --check --status; \
	mv "$$tmp_file" $@; \
	trap - 0 1 2 3 15

projects/cmake/sources: $(DOWNLOADS_DIR)/cmake-$(CMAKE_VERSION).tar.gz
	@printf '%s  %s\n' '$(CMAKE_SOURCE_SHA256)' '$<' | sha256sum --check || \
		{ rm -f -- '$<'; echo 'error: removed corrupt CMake download; retry the build' >&2; exit 1; }
	@$(call source-transaction-begin,$@); \
	mkdir $@; \
	tar xf $(DOWNLOADS_DIR)/cmake-$(CMAKE_VERSION).tar.gz -C $@ \
		--strip-components=1; \
	$(source-transaction-commit)

$(eval $(call project-source-signature,cmake,archive:$(CMAKE_URL)#sha256=$(CMAKE_SOURCE_SHA256)))
