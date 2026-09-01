# Copyright (c) Meta Platforms, Inc. and affiliates.

$(eval $(call project-define,obstack))

$(OBSTACK_ANDROID): $(LGPL_FILE)
$(OBSTACK_ANDROID):
	$(MAKE) -C $(OBSTACK_ANDROID_BUILD_DIR)/gllib -j $(THREADS) all
	cp $(OBSTACK_ANDROID_BUILD_DIR)/gllib/libobstack.a $(ANDROID_OUT_DIR)/lib/.
	cp $(OBSTACK_ANDROID_BUILD_DIR)/gllib/obstack.h $(ANDROID_OUT_DIR)/include/obstack.h
	$(call fetch-license,obstack,LGPL)
	touch $@

$(OBSTACK_ANDROID_BUILD_DIR): $(ANDROID_CONFIG_SITE)
	mkdir -p $@
	cd $@ && $(OBSTACK_SRCS)/configure $(ANDROID_EXTRA_CONFIGURE_FLAGS)

projects/obstack/sources: $(call project-optional-sources-target,gnulib)
	@$(call source-transaction-begin,$@); \
	cd $(call project-sources,gnulib) && ./gnulib-tool --create-testdir \
		--without-tests --lgpl --lib="libobstack" --dir=$(abspath $@) obstack; \
	$(source-transaction-commit)

$(eval $(call project-source-signature,obstack,gnulib:$(GNULIB_COMMIT_HASH):obstack,projects/obstack/build.mk))
