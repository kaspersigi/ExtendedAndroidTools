# Copyright (c) Meta Platforms, Inc. and affiliates.

$(eval $(call project-define,gnulib))

$(GNULIB_ANDROID):
	echo "gnulib build is not supported"
	false

GNULIB_REPO = https://git.savannah.gnu.org/git/gnulib.git
projects/gnulib/sources:
	@$(call source-transaction-begin,$@); \
	git init $@; \
	git -C $@ remote add origin $(GNULIB_REPO); \
	git -C $@ fetch --depth=1 --no-tags origin $(GNULIB_COMMIT_HASH); \
	git -C $@ checkout --detach FETCH_HEAD; \
	$(source-transaction-commit)

$(eval $(call project-source-signature,gnulib,git:$(GNULIB_REPO)@$(GNULIB_COMMIT_HASH)))
