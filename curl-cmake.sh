#!/bin/sh

# Copyright (C) Viktor Szakats. See LICENSE.md
# SPDX-License-Identifier: MIT

# https://cmake.org/cmake/help/latest/manual/cmake-properties.7.html
# https://cmake.org/cmake/help/latest/manual/cmake-variables.7.html

# shellcheck disable=SC3040,SC2039
set -o xtrace -o errexit -o nounset; [ -n "${BASH:-}${ZSH_NAME:-}" ] && set -o pipefail

export _NAM _VER _OUT _BAS _DST

_NAM="$(basename "$0" | cut -f 1 -d '.' | sed 's/-cmake//')"
_VER="$1"

(
  cd "${_NAM}"  # mandatory component

  [ "${CW_DEV_INCREMENTAL:-}" != '1' ] && rm -r -f "${_PKGDIR:?}" "${_BLDDIR:?}"

  # Build

  options=''
  CPPFLAGS=''

  [ "${CW_DEV_CROSSMAKE_REPRO:-}" = '1' ] && options="${options} -DCMAKE_AR=${AR_NORMALIZE}"

  LIBS=''
  LDFLAGS=''
  LDFLAGS_BIN="${_LDFLAGS_BIN_GLOBAL}"
  LDFLAGS_LIB=''

  [ "${_CONFIG#*main*}" = "${_CONFIG}" ] && LDFLAGS="${LDFLAGS} -v"  # also applies to compiler invocations

  if [ "${_OS}" = 'win' ] && [ "${_CONFIG#*unicode*}" != "${_CONFIG}" ]; then
    options="${options} -DENABLE_UNICODE=ON"
  fi

  if [ "${_OS}" = 'win' ]; then
    options="${options} -DCMAKE_SHARED_LIBRARY_SUFFIX_C=${_CURL_DLL_SUFFIX}.dll"
    _DEF_NAME="libcurl${_CURL_DLL_SUFFIX}.def"
    LDFLAGS_LIB="${LDFLAGS_LIB} -Wl,--output-def,${_DEF_NAME}"
  fi

  if [ "${CW_MAP}" = '1' ]; then
    _MAP_NAME_LIB="libcurl${_CURL_DLL_SUFFIX}.map"
    _MAP_NAME_BIN='curl.map'
    if [ "${_OS}" = 'mac' ]; then
      LDFLAGS_LIB="${LDFLAGS_LIB} -Wl,-map,${_MAP_NAME_LIB}"
      LDFLAGS_BIN="${LDFLAGS_BIN} -Wl,-map,${_MAP_NAME_BIN}"
    else
      LDFLAGS_LIB="${LDFLAGS_LIB} -Wl,-Map,${_MAP_NAME_LIB}"
      LDFLAGS_BIN="${LDFLAGS_BIN} -Wl,-Map,${_MAP_NAME_BIN}"
    fi
  fi

  # Ugly hack. Everything breaks without this due to the accidental ordering
  # of libs and objects, and offering no universal way to (re)insert libs at
  # specific positions. Linker complains about a missing --end-group, then
  # adds it automatically anyway.
  if [ "${_LD}" = 'ld' ]; then
    LDFLAGS="${LDFLAGS} -Wl,--start-group"
  fi

  if [ "${_OS}" = 'win' ]; then
    # Link lib dependencies in static mode. Implied by `-static` for curl,
    # but required for libcurl, which would link to shared libs by default.
    LDFLAGS="${LDFLAGS} -Wl,-Bstatic"
  fi

  if [ ! "${_CONFIG#*werror*}" = "${_CONFIG}" ]; then
    options="${options} -DCURL_WERROR=ON"
  fi

  if [ ! "${_CONFIG#*debug*}" = "${_CONFIG}" ]; then
    options="${options} -DENABLE_DEBUG=ON"
    # curl would only set this automatically for the 'Debug' configuration
    # Required for certain BUILD_TESTING=ON 'testdeps' build targets to link
    # correctly.
    # Officially we should use `-DCMAKE_BUILD_TYPE=Debug` which also enables
    # debug info, but it has the side-effect of adding a `-d` suffix to the
    # DLL and static lib names (`libcurl-d-x64.dll`, `libcurl-d.a`,
    # `libcurl-d.dll.a` on Windows) which breaks packaging logic. We also
    # strip debug info when making libs reproducible anyway.
    CPPFLAGS="${CPPFLAGS} -DDEBUGBUILD"
  fi

  if [ ! "${_CONFIG#*bldtst*}" = "${_CONFIG}" ] || \
     [ ! "${_CONFIG#*pico*}" = "${_CONFIG}" ] || \
     [ ! "${_CONFIG#*nano*}" = "${_CONFIG}" ]; then
    options="${options} -DCURL_DISABLE_ALTSVC=ON"
  fi

  if [ ! "${_CONFIG#*bldtst*}" = "${_CONFIG}" ] || \
     [ ! "${_CONFIG#*pico*}" = "${_CONFIG}" ]; then
    options="${options} -DCURL_DISABLE_BASIC_AUTH=ON -DCURL_DISABLE_BEARER_AUTH=ON -DCURL_DISABLE_DIGEST_AUTH=ON -DCURL_DISABLE_KERBEROS_AUTH=ON -DCURL_DISABLE_NEGOTIATE_AUTH=ON -DCURL_DISABLE_AWS=ON"
    options="${options} -DCURL_DISABLE_DICT=ON -DCURL_DISABLE_FILE=ON -DCURL_DISABLE_GOPHER=ON -DCURL_DISABLE_MQTT=ON -DCURL_DISABLE_RTSP=ON -DCURL_DISABLE_SMB=ON -DCURL_DISABLE_TELNET=ON -DCURL_DISABLE_TFTP=ON"
    options="${options} -DCURL_DISABLE_FTP=ON"
    options="${options} -DCURL_DISABLE_IMAP=ON -DCURL_DISABLE_POP3=ON -DCURL_DISABLE_SMTP=ON"
    options="${options} -DCURL_DISABLE_LDAP=ON -DCURL_DISABLE_LDAPS=ON"
  else
    [ "${_CONFIG#*noftp*}" != "${_CONFIG}" ] && options="${options} -DCURL_DISABLE_FTP=ON"
    if [ "${_OS}" = 'win' ]; then
      LIBS="${LIBS} -lwldap32"
    elif [ "${_OS}" != 'mac' ] || [ "${_OSVER}" -ge '1010' ]; then  # On macOS we use the built-in LDAP lib
      options="${options} -DCURL_DISABLE_LDAP=ON -DCURL_DISABLE_LDAPS=ON"
    fi
  fi

  if [ -n "${_ZLIB}" ]; then
    options="${options} -DZLIB_INCLUDE_DIR=${_TOP}/${_ZLIB}/${_PP}/include"
    options="${options} -DZLIB_LIBRARY=${_TOP}/${_ZLIB}/${_PP}/lib/libz.a"
  else
    options="${options} -DZLIB_INCLUDE_DIR="
  fi
  if [ -d ../brotli ] && [ "${_CONFIG#*nobrotli*}" = "${_CONFIG}" ]; then
    options="${options} -DCURL_BROTLI=ON"
    options="${options} -DBROTLI_INCLUDE_DIR=${_TOP}/brotli/${_PP}/include"
    options="${options} -DBROTLIDEC_LIBRARY=${_TOP}/brotli/${_PP}/lib/libbrotlidec.a"
    options="${options} -DBROTLICOMMON_LIBRARY=${_TOP}/brotli/${_PP}/lib/libbrotlicommon.a"
  else
    options="${options} -DCURL_BROTLI=OFF"
  fi
  if [ -d ../zstd ] && [ "${_CONFIG#*nozstd*}" = "${_CONFIG}" ]; then
    options="${options} -DCURL_ZSTD=ON"
    options="${options} -DZstd_INCLUDE_DIR=${_TOP}/zstd/${_PP}/include"
    options="${options} -DZstd_LIBRARY=${_TOP}/zstd/${_PP}/lib/libzstd.a"
    if [ "${CURL_VER_}" = '8.4.0' ]; then
      options="${options} -DHAVE_ZSTD_CREATEDSTREAM=1"  # fast-track configuration. Introduced in v1.0.0 2016-08-31.
    fi
  else
    options="${options} -DCURL_ZSTD=OFF"
  fi

  h3=0

  mainssl=''  # openssl, wolfssl, mbedtls, schannel, secure-transport, gnutls, bearssl, rustls

  if [ -n "${_OPENSSL}" ]; then
    [ -n "${mainssl}" ] || mainssl='openssl'
    options="${options} -DCURL_USE_OPENSSL=ON"
    options="${options} -DOPENSSL_ROOT_DIR=${_TOP}/${_OPENSSL}/${_PP}"
    options="${options} -DCURL_DISABLE_OPENSSL_AUTO_LOAD_CONFIG=ON"
    if [ "${_OPENSSL}" = 'boringssl' ] || [ "${_OPENSSL}" = 'awslc' ]; then
      if [ "${_OPENSSL}" = 'boringssl' ]; then
        CPPFLAGS="${CPPFLAGS} -DCURL_BORINGSSL_VERSION=\\\"$(printf '%.8s' "${BORINGSSL_VER_}")\\\""
        options="${options} -DHAVE_BORINGSSL=1 -DHAVE_AWSLC=0"  # fast-track configuration
      else
        options="${options} -DHAVE_BORINGSSL=0 -DHAVE_AWSLC=1"  # fast-track configuration
      fi
      if [ "${_TOOLCHAIN}" = 'mingw-w64' ] && [ "${_CPU}" = 'x64' ] && [ "${_CRT}" = 'ucrt' ]; then  # FIXME
        # Non-production workaround for:
        # mingw-w64 x64 winpthread static lib incompatible with UCRT.
        # ```c
        # /*
        #    llvm/clang
        #    $ /usr/local/opt/llvm/bin/clang -fuse-ld=lld \
        #        -target x86_64-w64-mingw32 --sysroot /usr/local/opt/mingw-w64/toolchain-x86_64 \
        #        test.c -D_UCRT -Wl,-Bstatic -lpthread -Wl,-Bdynamic -lucrt
        #
        #    gcc
        #    $ x86_64-w64-mingw32-gcc -dumpspecs | sed 's/-lmsvcrt/-lucrt/g' > gcc-specs-ucrt
        #    $ x86_64-w64-mingw32-gcc -specs=gcc-specs-ucrt \
        #        test.c -D_UCRT -Wl,-Bstatic -lpthread -Wl,-Bdynamic -lucrt
        #
        #    ``` llvm/clang ->
        #    ld.lld: error: undefined symbol: _setjmp
        #    >>> referenced by ../src/thread.c:1518
        #    >>>               libpthread.a(libwinpthread_la-thread.o):(pthread_create_wrapper)
        #    clang-16: error: linker command failed with exit code 1 (use -v to see invocation)
        #    ```
        #    ``` gcc ->
        #    /usr/local/Cellar/mingw-w64/11.0.1/toolchain-x86_64/bin/x86_64-w64-mingw32-ld: /usr/local/Cellar/mingw-w64/11.0.1/toolchain-x86_64/lib/gcc/x86_64-w64-mingw32/13.2.0/../../../../x86_64-w64-mingw32/lib/../lib/libpthread.a(libwinpthread_la-thread.o): in function `pthread_create_wrapper':
        #    /private/tmp/mingw-w64-20230808-5242-1g3t1oo/mingw-w64-v11.0.1/mingw-w64-libraries/winpthreads/build-x86_64/../src/thread.c:1518:(.text+0xb78): undefined reference to `_setjmp'
        #    collect2: error: ld returned 1 exit status
        #    ```
        #  */
        # #include <pthread.h>
        # int main(void) {
        #   pthread_rwlock_t lock;
        #   pthread_rwlock_init(&lock, NULL);
        #   return 0;
        # }
        # ```
        # Ref: https://github.com/niXman/mingw-builds/issues/498
        LIBS="${LIBS} -Wl,-Bdynamic -lpthread -Wl,-Bstatic"
      else
        LIBS="${LIBS} -lpthread"
      fi
      h3=1
    else
      options="${options} -DHAVE_BORINGSSL=0 -DHAVE_AWSLC=0"  # fast-track configuration
      if [ "${_OPENSSL}" = 'libressl' ]; then
        [ "${_OS}" = 'win' ] && CPPFLAGS="${CPPFLAGS} -DLIBRESSL_DISABLE_OVERRIDE_WINCRYPT_DEFINES_WARNING"
        h3=1
      elif [ "${_OPENSSL}" = 'quictls' ]; then
        h3=1
      fi
    fi
    [ "${_OPENSSL}" != 'libressl' ] && options="${options} -DHAVE_SSL_SET0_WBIO=1"  # fast-track configuration
    [ "${h3}" = '1' ] && options="${options} -DHAVE_SSL_CTX_SET_QUIC_METHOD=1"  # fast-track configuration
  else
    options="${options} -DCURL_USE_OPENSSL=OFF"
  fi

  # fast-track configuration
  if [ "${_OS}" = 'win' ]; then
    if [ "${CURL_VER_}" = '8.4.0' ]; then
      # THREADS_HAVE_PTHREAD_ARG is detected in arm64/x86 builds, then
      # referenced from the .map file even though not used in the binary.
      options="${options} -DTHREADS_HAVE_PTHREAD_ARG=0 -DCMAKE_HAVE_LIBC_PTHREAD=0 -DCMAKE_HAVE_PTHREADS_CREATE=0 -DCMAKE_HAVE_PTHREAD_CREATE=0"  # find_package(Threads)
      options="${options} -DHAVE_VARIADIC_MACROS_C99=1 -DHAVE_VARIADIC_MACROS_GCC=1"
    fi
    options="${options} -DHAVE_STDATOMIC_H=1 -DHAVE_ATOMIC=1 -DHAVE_STRTOK_R=1 -DHAVE_FILE_OFFSET_BITS=1"
  fi

  if [ -d ../wolfssl ]; then
    [ -n "${mainssl}" ] || mainssl='wolfssl'
    options="${options} -DCURL_USE_WOLFSSL=ON"
    options="${options} -DWolfSSL_INCLUDE_DIR=${_TOP}/wolfssl/${_PP}/include"
    options="${options} -DWolfSSL_LIBRARY=${_TOP}/wolfssl/${_PP}/lib/libwolfssl.a"
    CPPFLAGS="${CPPFLAGS} -DSIZEOF_LONG_LONG=8"
    h3=1
  fi

  if [ -d ../mbedtls ]; then
    [ -n "${mainssl}" ] || mainssl='mbedtls'
    options="${options} -DCURL_USE_MBEDTLS=ON"
    options="${options} -DMBEDTLS_INCLUDE_DIRS=${_TOP}/mbedtls/${_PP}/include"
    options="${options} -DMBEDCRYPTO_LIBRARY=${_TOP}/mbedtls/${_PP}/lib/libmbedcrypto.a"
    options="${options} -DMBEDTLS_LIBRARY=${_TOP}/mbedtls/${_PP}/lib/libmbedtls.a"
    options="${options} -DMBEDX509_LIBRARY=${_TOP}/mbedtls/${_PP}/lib/libmbedx509.a"
  fi

  if [ "${_OS}" = 'win' ]; then
    options="${options} -DCURL_USE_SCHANNEL=ON"
  elif [ "${_OS}" = 'mac' ] && [ "${_OSVER}" -lt '1015' ]; then
    # SecureTransport deprecated in 2019 (macOS 10.15 Catalina, iOS 13.0)
    # Another known deprecation issue:
    #   curl/lib/vtls/sectransp.c:1206:7: warning: 'CFURLCreateDataAndPropertiesFromResource' is deprecated: first deprecated in macOS 10.9 - For resource data, use the CFReadStream API. For file resource properties, use CFURLCopyResourcePropertiesForKeys. [-Wdeprecated-declarations]
    options="${options} -DCURL_USE_SECTRANSP=ON"
    # Without this, SecureTransport becomes the default TLS backend
    [ -n "${mainssl}" ] && options="${options} -DCURL_DEFAULT_SSL_BACKEND=${mainssl}"
  fi
  CPPFLAGS="${CPPFLAGS} -DHAS_ALPN"

# options="${options} -DCURL_CA_FALLBACK=ON"

  options="${options} -DCURL_DISABLE_SRP=ON"

  if [ -d ../wolfssh ] && [ -d ../wolfssl ]; then
    # No native support, enable it manually.
    options="${options} -DCURL_USE_WOLFSSH=ON"
    CPPFLAGS="${CPPFLAGS} -DUSE_WOLFSSH"
    CPPFLAGS="${CPPFLAGS} -I${_TOP}/wolfssh/${_PP}/include"
    LDFLAGS="${LDFLAGS} -L${_TOP}/wolfssh/${_PP}/lib"
    LIBS="${LIBS} -lwolfssh"
  elif [ -d ../libssh ]; then
    # Detection picks OS-native copy. Only a manual configuration worked
    # to defeat CMake's wisdom.
    options="${options} -DCURL_USE_LIBSSH=OFF"
    options="${options} -DCURL_USE_LIBSSH2=OFF"
    CPPFLAGS="${CPPFLAGS} -DUSE_LIBSSH"
    CPPFLAGS="${CPPFLAGS} -DLIBSSH_STATIC"
    CPPFLAGS="${CPPFLAGS} -I${_TOP}/libssh/${_PPS}/include"
    LDFLAGS="${LDFLAGS} -L${_TOP}/libssh/${_PPS}/lib"
    LIBS="${LIBS} -lssh"
  elif [ -d ../libssh2 ]; then
    options="${options} -DCURL_USE_LIBSSH2=ON"
    options="${options} -DCURL_USE_LIBSSH=OFF"
    options="${options} -DLIBSSH2_INCLUDE_DIR=${_TOP}/libssh2/${_PPS}/include"
    options="${options} -DLIBSSH2_LIBRARY=${_TOP}/libssh2/${_PPS}/lib/libssh2.a"

    if [ "${CW_DEV_CROSSMAKE_REPRO:-}" = '1' ]; then
      # By passing -lssh2 _before_ -lcrypto (of openssl/libressl) to the
      # linker, DLL size becomes closer/identical to autotools/gnumake-built
      # DLLs. Otherwise this is not necessary, and there should not be any
      # functional difference. Could not find the reason for it.
      # File-offset-stripped-then-sorted .map files are identical either way.
      # It would be useful to have a linker option to sort object/lib inputs
      # to make output deterministic (these builds do not rely on ordering
      # side-effects.)
      LDFLAGS="${LDFLAGS} -L${_TOP}/libssh2/${_PPS}/lib"
      LIBS="${LIBS} -lssh2"
    fi
  else
    options="${options} -DCURL_USE_LIBSSH=OFF"
    options="${options} -DCURL_USE_LIBSSH2=OFF"
  fi

  if [ -d ../nghttp2 ]; then
    options="${options} -DUSE_NGHTTP2=ON"
    options="${options} -DNGHTTP2_INCLUDE_DIR=${_TOP}/nghttp2/${_PP}/include"
    options="${options} -DNGHTTP2_LIBRARY=${_TOP}/nghttp2/${_PP}/lib/libnghttp2.a"
    CPPFLAGS="${CPPFLAGS} -DNGHTTP2_STATICLIB"
  else
    options="${options} -DUSE_NGHTTP2=OFF"
  fi

  [ "${_CONFIG#*noh3*}" = "${_CONFIG}" ] || h3=0

  if [ "${h3}" = '1' ] && [ -d ../nghttp3 ] && [ -d ../ngtcp2 ]; then
    options="${options} -DUSE_NGHTTP3=ON"
    options="${options} -DNGHTTP3_INCLUDE_DIR=${_TOP}/nghttp3/${_PP}/include"
    options="${options} -DNGHTTP3_LIBRARY=${_TOP}/nghttp3/${_PP}/lib/libnghttp3.a"
    CPPFLAGS="${CPPFLAGS} -DNGHTTP3_STATICLIB"

    options="${options} -DUSE_NGTCP2=ON"
    options="${options} -DNGTCP2_INCLUDE_DIR=${_TOP}/ngtcp2/${_PPS}/include"
    options="${options} -DNGTCP2_LIBRARY=${_TOP}/ngtcp2/${_PPS}/lib/libngtcp2.a"
    options="${options} -DCMAKE_LIBRARY_PATH=${_TOP}/ngtcp2/${_PPS}/lib"
    CPPFLAGS="${CPPFLAGS} -DNGTCP2_STATICLIB"
  else
    options="${options} -DUSE_NGHTTP3=OFF"
    options="${options} -DUSE_NGTCP2=OFF"
  fi
  if [ -d ../cares ]; then
    options="${options} -DENABLE_ARES=ON"
    options="${options} -DCARES_INCLUDE_DIR=${_TOP}/cares/${_PP}/include"
    options="${options} -DCARES_LIBRARY=${_TOP}/cares/${_PP}/lib/libcares.a"
    CPPFLAGS="${CPPFLAGS} -DCARES_STATICLIB"
  fi
  if [ -d ../gsasl ]; then
    CPPFLAGS="${CPPFLAGS} -DUSE_GSASL"
    CPPFLAGS="${CPPFLAGS} -I${_TOP}/gsasl/${_PPS}/include"
    LDFLAGS="${LDFLAGS} -L${_TOP}/gsasl/${_PPS}/lib"
    LIBS="${LIBS} -lgsasl"
  elif [ "${_OS}" = 'mac' ]; then
    # GSS API deprecated in 2012-2013 (OS X 10.8 Mountain Lion / 10.9 Mavericks, iOS 7.0)
  # options="${options} -DCURL_USE_GSSAPI=ON"
    :
  fi
  if [ -d ../libidn2 ]; then
    options="${options} -DUSE_LIBIDN2=ON"
    CPPFLAGS="${CPPFLAGS} -I${_TOP}/libidn2/${_PP}/include"
    LDFLAGS="${LDFLAGS} -L${_TOP}/libidn2/${_PP}/lib"
    LIBS="${LIBS} -lidn2"

    if [ -d ../libpsl ] && [ -d ../libiconv ] && [ -d ../libunistring ]; then
      options="${options} -DUSE_LIBPSL=ON"
      options="${options} -DLIBPSL_INCLUDE_DIR=${_TOP}/libpsl/${_PP}/include"
      options="${options} -DLIBPSL_LIBRARY=${_TOP}/libpsl/${_PP}/lib/libpsl.a;${_TOP}/libiconv/${_PP}/lib/libiconv.a;${_TOP}/libunistring/${_PP}/lib/libunistring.a"
    fi

    if [ -d ../libiconv ]; then
      LDFLAGS="${LDFLAGS} -L${_TOP}/libiconv/${_PP}/lib"
      LIBS="${LIBS} -liconv"
    fi
    if [ -d ../libunistring ]; then
      LDFLAGS="${LDFLAGS} -L${_TOP}/libunistring/${_PP}/lib"
      LIBS="${LIBS} -lunistring"
    fi
  else
    options="${options} -DUSE_LIBIDN2=OFF"
    options="${options} -DCURL_USE_LIBPSL=OFF"
    if [ "${_CONFIG#*pico*}" = "${_CONFIG}" ] && \
       [ "${_OS}" = 'win' ]; then
      options="${options} -DUSE_WIN32_IDN=ON"
    fi
  fi

  # Official method correctly enables the manual, but with the side-effect
  # of rebuilding tool_hugehelp.c (with empty content). We work around this
  # by enabling the manual directly via its C flag.
  # options="${options} -DUSE_MANUAL=ON"
  CPPFLAGS="${CPPFLAGS} -DUSE_MANUAL=1"

  if [ "${CW_DEV_LLD_REPRODUCE:-}" = '1' ] && [ "${_LD}" = 'lld' ]; then
    LDFLAGS_BIN="${LDFLAGS_BIN} -Wl,--reproduce=$(pwd)/$(basename "$0" .sh)-bin.tar"
    LDFLAGS_LIB="${LDFLAGS_LIB} -Wl,--reproduce=$(pwd)/$(basename "$0" .sh)-dyn.tar"
  fi

  if [ "${_OS}" = 'linux' ] || [ "${_OS}" = 'mac' ]; then
    # We build with -fPIC by default, build lib objects once to save build time.
    options="${options} -DSHARE_LIB_OBJECT=ON"
  fi

  if [ "${_OS}" != 'win' ]; then
    # Workaround to suppress warning about unused `CMAKE_RC_FLAGS`.
    # Could not figure how to pass it with an argument with spaces by
    # appending it to `options`, or via the environment.
    #   CMake Warning: Manually-specified variables were not used by the project: CMAKE_RC_FLAGS
    options="${options} --no-warn-unused-cli"
  fi

  [ "${CW_DEV_CROSSMAKE_REPRO:-}" = '1' ] || options="${options} -DCMAKE_UNITY_BUILD=ON"

  if [ "${CW_DEV_INCREMENTAL:-}" != '1' ] || [ ! -d "${_BLDDIR}" ]; then
    # shellcheck disable=SC2086
    cmake -B "${_BLDDIR}" ${_CMAKE_GLOBAL} ${options} \
      '-DCURL_CA_PATH=none' \
      '-DCURL_CA_BUNDLE=none' \
      '-DBUILD_SHARED_LIBS=ON' \
      '-DBUILD_STATIC_LIBS=ON' \
      '-DBUILD_CURL_EXE=ON' \
      '-DBUILD_STATIC_CURL=ON' \
      '-DENABLE_THREADED_RESOLVER=ON' \
      '-DBUILD_TESTING=OFF' \
      '-DCURL_HIDDEN_SYMBOLS=ON' \
      '-DENABLE_WEBSOCKETS=ON' \
      "-DCMAKE_RC_FLAGS=${_RCFLAGS_GLOBAL}" \
      "-DCMAKE_C_FLAGS=${_CFLAGS_GLOBAL_CMAKE} ${_CFLAGS_GLOBAL} ${_CPPFLAGS_GLOBAL} ${CPPFLAGS} ${_LDFLAGS_GLOBAL} ${_LIBS_GLOBAL}" \
      "-DCMAKE_C_STANDARD_LIBRARIES=${LIBS}" \
      "-DCMAKE_EXE_LINKER_FLAGS=${LDFLAGS} ${LDFLAGS_BIN} ${LIBS}" \
      "-DCMAKE_SHARED_LINKER_FLAGS=${LDFLAGS} ${LDFLAGS_LIB} ${LIBS}"  # --debug-find --debug-trycompile
  fi

  # When doing an out of tree build, this is necessary to avoid make
  # re-generating the embedded manual with blank content.
  if [ -f src/tool_hugehelp.c ]; then
    cp -p src/tool_hugehelp.c "${_BLDDIR}/src/"
  elif [ -f src/tool_hugehelp.c.cvs ]; then
    # Copy the dummy replacement when building from a raw source tree.
    cp -p src/tool_hugehelp.c.cvs "${_BLDDIR}/src/tool_hugehelp.c"
  fi

  make --directory="${_BLDDIR}" --jobs="${_JOBS}" install "DESTDIR=$(pwd)/${_PKGDIR}" VERBOSE=1
  # Needs BUILD_TESTING=ON to build everything
# make --directory="${_BLDDIR}" --jobs="${_JOBS}" testdeps

  # Manual copy to DESTDIR

  if [ "${_OS}" = 'win' ]; then
    cp -p "${_BLDDIR}/lib/${_DEF_NAME}" "${_PP}"/bin/
  fi

  if [ "${CW_MAP}" = '1' ]; then
    cp -p "${_BLDDIR}/lib/${_MAP_NAME_LIB}" "${_PP}/${DYN_DIR}/"
    cp -p "${_BLDDIR}/src/${_MAP_NAME_BIN}" "${_PP}"/bin/
  fi

  . ../curl-pkg.sh
)
