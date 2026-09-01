// Copyright (c) Meta Platforms, Inc. and affiliates.

#ifndef ARGP_WRAPPER_H
#define ARGP_WRAPPER_H

// Current gnulib headers require the including project to include gnulib's
// private config.h first.  Consumers of this standalone argp package have
// their own config.h, so mark the compatibility definitions below as the
// equivalent public-header setup instead.
#ifndef _GL_CONFIG_H_INCLUDED
#  define _GL_CONFIG_H_INCLUDED 1
#endif

#ifndef ARGP_EI
#  define ARGP_EI inline
#endif

// since ece81a73b64483a68f5157420836d84beb3a1680 argp.h as distributed with
// gnulib requires _GL_INLINE_HEADER_BEGIN macro to be defined.
#ifndef _GL_INLINE_HEADER_BEGIN
#  define _GL_INLINE_HEADER_BEGIN
#  define _GL_INLINE_HEADER_END
#endif

#ifndef _GL_ATTRIBUTE_FORMAT
#  define _GL_ATTRIBUTE_FORMAT(spec) __attribute__ ((__format__ spec))
#endif

#ifndef _GL_ATTRIBUTE_SPEC_PRINTF_SYSTEM
#  define _GL_ATTRIBUTE_SPEC_PRINTF_SYSTEM __printf__
#endif

#include "argp-real.h"
#endif
