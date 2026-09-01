# Copyright (c) Meta Platforms, Inc. and affiliates.

$(eval $(call project-define,gnulib))

$(GNULIB_ANDROID):
	echo "gnulib build is not supported"
	false

GNULIB_REPO = https://git.savannah.gnu.org/git/gnulib.git
projects/gnulib/sources:
	git clone $(GNULIB_REPO) $@
	cd $@ && git checkout --detach $(GNULIB_COMMIT_HASH)
