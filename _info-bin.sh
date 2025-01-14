#!/bin/sh

# Copyright (C) Viktor Szakats. See LICENSE.md
# SPDX-License-Identifier: MIT

# shellcheck disable=SC3040,SC2039
set -o xtrace -o errexit -o nounset; [ -n "${BASH:-}${ZSH_NAME:-}" ] && set -o pipefail

filetype=''
is_curl='0'

while [ "${1#--*}" != "${1:-}" ]; do
  if [ "$1" = '--filetype' ]; then
    shift; filetype="$1"; shift
  elif [ "$1" = '--is-curl' ]; then
    is_curl='1'; shift
  fi
done

while [ -n "${1:-}" ]; do

  f="$1"; shift

  if [ "${_OS}" = 'win' ]; then
    TZ=UTC "${_OBJDUMP}" --all-headers "${f}" | grep -a -E -i "(file format|DLL Name|Time/Date)" | sort -r -f
    if [ "${is_curl}" = '1' ]; then
      # Verify exported curl symbols
      if [ "${filetype}" = 'exe' ]; then
        "${_OBJDUMP}" --all-headers "${f}" | grep -a -F ' curl_' && false  # should not have any hits for statically linked curl
      else
        "${_OBJDUMP}" --all-headers "${f}" | grep -a -F ' curl_' || false  # show public libcurl APIs (in a well-defined order)
      fi
    fi
    # Dump 'DllCharacteristics' flags, e.g. HIGH_ENTROPY_VA, DYNAMIC_BASE, NX_COMPAT, GUARD_CF, TERMINAL_SERVICE_AWARE
    "${_OBJDUMP}" --all-headers "${f}" | grep -a -E -o '^\s+[A-Z_]{4,}$' | sort
    # Dump cfguard load configuration flags
    if [ "${_CC}" = 'llvm' ]; then  # binutils readelf (as of v2.40) does not recognize this option
      # CF_FUNCTION_TABLE_PRESENT, CF_INSTRUMENTED, CF_LONGJUMP_TABLE_PRESENT (optional)
      "${_READELF}" --coff-load-config "${f}" | grep -a -E 'CF_[A-Z_]' | sort || true
    fi
    if [ "${filetype}" = 'exe' ] && [ "${is_curl}" = '1' ]; then  # should be the same output for the DLL
      # regexp compatible with llvm and binutils output
      "${_OBJDUMP}" --all-headers "${f}" \
        | grep -a -E ' [0-9]{1,5} +[a-zA-Z_][a-zA-Z0-9_]*$' \
        | grep -a -E -o '\S+$' | sort || true
    fi
  elif [ "${_OS}" = 'mac' ]; then
    if [ "${_CC}" = 'gcc' ] || [ "${_TOOLCHAIN}" = 'llvm-apple' ]; then
      _prefix=''
    else
      _prefix='llvm-'  # standard llvm
    fi
    TZ=UTC "${_prefix}objdump" --arch=all --private-headers "${f}" | grep -a -i -F 'magic'
    # -dyld_info ignored by llvm-otool as of v16.0.6
    TZ=UTC "${_prefix}otool" -arch all -f -v -L -dyld_info "${f}"
    # Display `LC_BUILD_VERSION` / `LC_VERSION_MIN_MACOSX` info
    TZ=UTC "${_prefix}otool" -arch all -f -l "${f}" | grep -a -w -E '(\(architecture|^ *(minos|version|sdk))'
  elif [ "${_OS}" = 'linux' ]; then
    "${_READELF}" --file-header --dynamic "${f}"
    "${_READELF}" --program-headers "${f}"
    if command -v checksec >/dev/null 2>&1; then
      if [ "${_DISTRO}" = 'alpine' ]; then
        checksec --json --file "${f}" | jq  # checksec-rs
      else
        checksec --format=json --file="${f}" | jq
        # We have seen this fail in some cases, so ignore exit code
        checksec --format=xml --fortify-file="${f}" || true  # duplicate keys in json, cannot apply jq
      fi
    fi
    if [ "${is_curl}" = '1' ]; then
      # Show linked GLIBC versions
      # https://en.wikipedia.org/wiki/Glibc#Version_history
      if [ "${_CPU}" = 'a64' ] || \
         [ "${_CPU}" = 'r64' ]; then
        filter='@GLIBC_2\.(17|2[0-9])$'  # Exclude: 2.17 (2012-12) and 2.2x (2019-02)
      else
        filter='@GLIBC_([0-9]+\.[0-9]+\.[0-9]+|2\.([0-9]|1[0-9]))$'  # Exclude: x.y.z, 2.x, 2.1x (-2014-02)
      fi
      "${NM}" --dynamic --undefined-only "${f}" \
        | grep -E -v "${filter}" \
        | grep -E -o '@GLIBC_[0-9]+\.[0-9]+$' | sed 's/@GLIBC_//g' | sort -u -V || true
      "${NM}" --dynamic --undefined-only "${f}" \
        | grep -F '@GLIBC_' | grep -E -v "${filter}" || true
    fi
  fi
done
