#!/bin/sh

# Copyright (C) Viktor Szakats. See LICENSE.md
# SPDX-License-Identifier: MIT

# shellcheck disable=SC3040,SC2039
set -o xtrace -o errexit -o nounset; [ -n "${BASH:-}${ZSH_NAME:-}" ] && set -o pipefail

export _NAM _VER _OUT _BAS _DST

_NAM="$(basename "$0" | cut -f 1 -d '.' | sed 's/-cmake//')"
_VER="$1"

(
  cd "${_NAM}" || exit 0

  rm -r -f "${_PKGDIR:?}" "${_BLDDIR:?}"

  CFLAGS="-ffile-prefix-map=$(pwd)="

  if [ "${_CC}" = 'llvm' ]; then
    CFLAGS="${CFLAGS} -Wa,--noexecstack"
  else
    CFLAGS="${CFLAGS} -Wno-attributes"
  fi

  [ "${_CPU}" = 'x86' ] && cpu='x86'
  [ "${_CPU}" = 'x64' ] && cpu='x86_64'
  [ "${_CPU}" = 'a64' ] && cpu='arm64'
  [ "${_CPU}" = 'r64' ] && cpu='riscv64'

  # shellcheck disable=SC2086
  cmake -B "${_BLDDIR}" ${_CMAKE_GLOBAL} \
    "-DCMAKE_SYSTEM_PROCESSOR=${cpu}" \
    '-DBUILD_SHARED_LIBS=OFF' \
    '-DLIBRESSL_APPS=OFF' \
    '-DLIBRESSL_TESTS=OFF' \
    "-DCMAKE_C_FLAGS=${_CFLAGS_GLOBAL_CMAKE} ${_CFLAGS_GLOBAL} ${_CPPFLAGS_GLOBAL} ${CFLAGS} ${_LDFLAGS_GLOBAL} ${_LIBS_GLOBAL}"

  make --directory="${_BLDDIR}" --jobs="${_JOBS}" install "DESTDIR=$(pwd)/${_PKGDIR}"

  # Delete .pc files
  rm -r -f "${_PP}"/lib/pkgconfig

  . ../libressl-pkg.sh
)
