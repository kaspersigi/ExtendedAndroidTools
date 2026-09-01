# Copyright (c) Meta Platforms, Inc. and affiliates.

# Definitions of licensing macros

LGPL_FILE := $(abspath licenses/lgpl-3.0.txt)

fetch-license = cp $($(2)_FILE) $(ANDROID_OUT_DIR)/licenses/$(1)
