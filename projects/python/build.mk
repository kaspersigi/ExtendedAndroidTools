# Copyright (c) Meta Platforms, Inc. and affiliates.

PYTHON_ANDROID_DEPS = ffi openssl xz zstd
PYTHON_HOST_DEPS = ffi
$(eval $(call project-define,python))

PYTHON_BUILD_TRIPLE := x86_64-pc-linux-gnu
PYTHON_ANDROID_EXTRA_CONFIG_OPTIONS = --build=$(PYTHON_BUILD_TRIPLE) --without-ensurepip
PYTHON_ANDROID_EXTRA_CONFIG_OPTIONS += --with-build-python=$(PYTHON_HOST_EXECUTABLE)
PYTHON_ANDROID_EXTRA_CONFIG_OPTIONS += --enable-shared
PYTHON_ANDROID_EXTRA_CONFIG_OPTIONS += --without-static-libpython
PYTHON_ANDROID_EXTRA_CONFIG_OPTIONS += --with-openssl=$(abspath $(ANDROID_OUT_DIR))
PYTHON_ANDROID_EXTRA_CONFIG_OPTIONS += --with-openssl-rpath=no
PYTHON_ANDROID_EXTRA_CONFIG_OPTIONS += "EXTRA_CPPFLAGS=-I$(ANDROID_SYSROOT_INCLUDE_PATH)"
PYTHON_ANDROID_EXTRA_CONFIG_OPTIONS += "EXTRA_LDFLAGS=-L$(ANDROID_SYSROOT_LIB_PATH)"
PYTHON_ANDROID_EXTRA_CONFIG_OPTIONS += ac_cv_file__dev_ptmx=no
PYTHON_ANDROID_EXTRA_CONFIG_OPTIONS += ac_cv_file__dev_ptc=no

PYTHON_ANDROID_CONFIG_FILE := $(ANDROID_BUILD_DIR)/python.config
PYTHON_ANDROID_CONFIGURED_FILE := $(PYTHON_ANDROID_BUILD_DIR)/.configured
PYTHON_HOST_CONFIG_FILE := $(HOST_BUILD_DIR)/python.config
PYTHON_HOST_CONFIGURED_FILE := $(PYTHON_HOST_BUILD_DIR)/.configured

# CPython installs several ABI-versioned paths outside lib/pythonX.Y. Remove
# the complete project-owned install surface before reinstalling so a minor
# version upgrade cannot leave headers, tools, pkg-config files, or manuals
# from the previous interpreter in the shared output prefix.
define clean-python-install
	$(RM) -r $(1)/include/python3.* $(1)/lib/python3.*
	$(RM) $(1)/lib/libpython3.*
	$(RM) $(1)/lib/pkgconfig/python-3.*.pc
	$(RM) $(1)/lib/pkgconfig/python3.pc $(1)/lib/pkgconfig/python3-embed.pc
	$(RM) $(1)/bin/2to3 $(1)/bin/2to3-3.*
	$(RM) $(1)/bin/idle3 $(1)/bin/idle3.*
	$(RM) $(1)/bin/pip3 $(1)/bin/pip3.*
	$(RM) $(1)/bin/pydoc3 $(1)/bin/pydoc3.*
	$(RM) $(1)/bin/python3 $(1)/bin/python3-config $(1)/bin/python3.*
	$(RM) $(1)/share/man/man1/python3.1 $(1)/share/man/man1/python3.*.1
endef

$(PYTHON_ANDROID): $(PYTHON_ANDROID_CONFIGURED_FILE)
$(PYTHON_HOST): $(PYTHON_HOST_CONFIGURED_FILE)
prepare-python: $(PYTHON_ANDROID_CONFIGURED_FILE)
prepare-python-host: $(PYTHON_HOST_CONFIGURED_FILE)

$(PYTHON_ANDROID_CONFIG_FILE): force-config-signature projects/python/sources
$(PYTHON_ANDROID_CONFIG_FILE): projects/python/build.mk projects/versions.mk
$(PYTHON_ANDROID_CONFIG_FILE): scripts/update-signature.sh | $(ANDROID_BUILD_DIR)
	@scripts/update-signature.sh $@ \
		"PROJECT=python-android" \
		"PYTHON_VERSION=$(PYTHON_VERSION)" \
		"PIP_VERSION=$(PIP_VERSION)" \
		"FFI_VERSION=$(FFI_BRANCH_OR_TAG)" \
		"OPENSSL_VERSION=$(OPENSSL_VERSION)" \
		"XZ_VERSION=$(XZ_BRANCH_OR_TAG)" \
		"ZSTD_VERSION=$(ZSTD_TAG)" \
		"SOURCE_REVISION=$(shell git -C $(PYTHON_SRCS) rev-parse HEAD 2>/dev/null || echo unavailable)" \
		"CONFIG_SCHEMA=python-android-v1" \
		"BUILD_RULE_SHA256=$(shell sha256sum projects/python/build.mk | cut -d ' ' -f 1)" \
		"BUILD_TRIPLE=$(PYTHON_BUILD_TRIPLE)" \
		"BUILD_PYTHON=$(abspath $(PYTHON_HOST_EXECUTABLE))" \
		"ENSUREPIP=false" \
		"SHARED=true" \
		"STATIC_LIBPYTHON=false" \
		"OPENSSL_PREFIX=$(abspath $(ANDROID_OUT_DIR))" \
		"OPENSSL_RPATH=false" \
		"EXTRA_CPPFLAGS=-I$(ANDROID_SYSROOT_INCLUDE_PATH)" \
		"EXTRA_LDFLAGS=-L$(ANDROID_SYSROOT_LIB_PATH)" \
		"PKG_CONFIG_LIBDIR=$(abspath $(ANDROID_OUT_DIR)/lib/pkgconfig)" \
		"AC_CV_FILE_DEV_PTMX=false" \
		"AC_CV_FILE_DEV_PTC=false" \
		$(ANDROID_CONFIG_SIGNATURE_ARGS)

$(PYTHON_HOST_CONFIG_FILE): force-config-signature projects/python/sources
$(PYTHON_HOST_CONFIG_FILE): projects/python/build.mk projects/versions.mk
$(PYTHON_HOST_CONFIG_FILE): scripts/update-signature.sh | $(HOST_BUILD_DIR)
	@scripts/update-signature.sh $@ \
		"PROJECT=python-host" \
		"PYTHON_VERSION=$(PYTHON_VERSION)" \
		"SETUPTOOLS_VERSION=$(SETUPTOOLS_VERSION)" \
		"FFI_VERSION=$(FFI_BRANCH_OR_TAG)" \
		"SOURCE_REVISION=$(shell git -C $(PYTHON_SRCS) rev-parse HEAD 2>/dev/null || echo unavailable)" \
		"CONFIG_SCHEMA=python-host-v1" \
		"BUILD_RULE_SHA256=$(shell sha256sum projects/python/build.mk | cut -d ' ' -f 1)" \
		"PKG_CONFIG_LIBDIR=$(abspath $(HOST_OUT_DIR)/lib/pkgconfig)" \
		$(HOST_CONFIG_SIGNATURE_ARGS)

$(PYTHON_ANDROID):
	$(call clean-python-install,$(ANDROID_OUT_DIR))
	cd $(PYTHON_ANDROID_BUILD_DIR) && make -j $(THREADS)
	cd $(PYTHON_ANDROID_BUILD_DIR) && make install
	test -f $(PYTHON_BUNDLED_PIP_WHEEL)
	$(RM) -r $(PYTHON_ANDROID_SITE_PACKAGES)/pip
	$(RM) -r $(PYTHON_ANDROID_SITE_PACKAGES)/pip-*.dist-info
	mkdir -p $(PYTHON_ANDROID_SITE_PACKAGES)
	unzip -q $(PYTHON_BUNDLED_PIP_WHEEL) -d $(PYTHON_ANDROID_SITE_PACKAGES)
	mkdir -p $(ANDROID_OUT_DIR)/share/certs
	unzip -p $(PYTHON_BUNDLED_PIP_WHEEL) \
		pip/_vendor/certifi/cacert.pem > \
		$(ANDROID_OUT_DIR)/share/certs/cacert.pem
	cp $(PYTHON_SRCS)/LICENSE $(ANDROID_OUT_DIR)/licenses/python
	unzip -p $(PYTHON_BUNDLED_PIP_WHEEL) \
		pip-$(PIP_VERSION).dist-info/licenses/LICENSE.txt > \
		$(ANDROID_OUT_DIR)/licenses/pip
	touch $@

$(PYTHON_HOST):
	$(call clean-python-install,$(HOST_OUT_DIR))
	cd $(PYTHON_HOST_BUILD_DIR) && make install -j $(THREADS)
	PYTHONNOUSERSITE=1 $(PYTHON_HOST_EXECUTABLE) -s -m pip install \
		--disable-pip-version-check \
		setuptools==$(SETUPTOOLS_VERSION)
	touch $@

$(PYTHON_XINSTALL): projects/python/python.xinstall.template projects/versions.mk
$(PYTHON_XINSTALL): | $(ANDROID_BUILD_DIR)
	cp $< $@
	sed -ibkp -e "s+<HOST_OUT_DIR>+$(abspath $(HOST_OUT_DIR))+g" $@
	sed -ibkp -e "s+<ANDROID_OUT_DIR>+$(abspath $(ANDROID_OUT_DIR))+g" $@
	sed -ibkp -e "s+<PYTHON_BINARY>+$(PYTHON_BINARY)+g" $@
	sed -ibkp -e "s+<PYTHON_ABI_VERSION>+$(PYTHON_ABI_VERSION)+g" $@
	chmod +x $@

$(PYTHON_ANDROID_BUILD_DIR): \
    export PKG_CONFIG_LIBDIR=$(abspath $(ANDROID_OUT_DIR)/lib/pkgconfig)
$(PYTHON_ANDROID_BUILD_DIR): $(ANDROID_CONFIG_SITE)
$(PYTHON_ANDROID_BUILD_DIR): $(PYTHON_HOST)
	mkdir -p $@

$(PYTHON_ANDROID_CONFIGURED_FILE): $(PYTHON_ANDROID_CONFIG_FILE)
$(PYTHON_ANDROID_CONFIGURED_FILE): $(ANDROID_CONFIG_SITE) $(PYTHON_HOST)
$(PYTHON_ANDROID_CONFIGURED_FILE): | $(PYTHON_ANDROID_BUILD_DIR)
	test "$$(PKG_CONFIG_LIBDIR=$(abspath $(ANDROID_OUT_DIR)/lib/pkgconfig) \
		PKG_CONFIG_PATH= pkg-config --variable=prefix libzstd)" = \
		"$(abspath $(ANDROID_OUT_DIR))"
	cd $(PYTHON_ANDROID_BUILD_DIR) && \
		PKG_CONFIG_LIBDIR=$(abspath $(ANDROID_OUT_DIR)/lib/pkgconfig) \
		PKG_CONFIG_PATH= $(PYTHON_SRCS)/configure \
		$(ANDROID_EXTRA_CONFIGURE_FLAGS) \
		$(PYTHON_ANDROID_EXTRA_CONFIG_OPTIONS)
	touch $@

$(PYTHON_HOST_BUILD_DIR): \
    export PKG_CONFIG_LIBDIR=$(abspath $(HOST_OUT_DIR)/lib/pkgconfig)
$(PYTHON_HOST_BUILD_DIR): $(HOST_CONFIG_SITE)
	mkdir -p $@

$(PYTHON_HOST_CONFIGURED_FILE): $(PYTHON_HOST_CONFIG_FILE) $(HOST_CONFIG_SITE)
$(PYTHON_HOST_CONFIGURED_FILE): | $(PYTHON_HOST_BUILD_DIR)
	cd $(PYTHON_HOST_BUILD_DIR) && $(PYTHON_SRCS)/configure \
		$(HOST_EXTRA_CONFIGURE_FLAGS)
	touch $@

PYTHON_REPO = https://github.com/python/cpython.git
projects/python/sources:
	@$(call source-transaction-begin,$@); \
	git clone $(PYTHON_REPO) $@ --depth=1 -b $(PYTHON_BRANCH_OR_TAG); \
	$(source-transaction-commit)

$(eval $(call project-source-signature,python,git:$(PYTHON_REPO)@$(PYTHON_BRANCH_OR_TAG)))
