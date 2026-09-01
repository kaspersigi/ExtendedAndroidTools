# Copyright (c) Meta Platforms, Inc. and affiliates.

jdwp-host-prepare: \
  black-host \
  buck2-host \
  python-host \
  pyre-host

JDWP_BUCK2_HOME := $(abspath $(HOST_BUILD_DIR)/buck2-home)
JDWP_BUCK2 := HOME=$(JDWP_BUCK2_HOME) $(abspath $(HOST_OUT_DIR)/bin/buck2)
JDWP_PYTHON := HOME=$(JDWP_BUCK2_HOME) PYTHONNOUSERSITE=1 $(PYTHON_HOST_EXECUTABLE) -s

$(JDWP_BUCK2_HOME):
	mkdir -p $@

jdwp-check: jdwp-host-prepare | $(JDWP_BUCK2_HOME)
	$(JDWP_BUCK2) run //projects/jdwp:main
	$(JDWP_BUCK2) test //projects/jdwp/...
	$(JDWP_PYTHON) $(abspath $(HOST_OUT_DIR)/bin/pyre) check
	$(JDWP_PYTHON) -m black projects/jdwp --check

jdwp-format: black-host | $(JDWP_BUCK2_HOME)
	$(JDWP_PYTHON) -m black projects/jdwp
