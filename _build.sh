#!/usr/bin/env bash

# Copyright (C) Viktor Szakats. See LICENSE.md
# SPDX-License-Identifier: MIT

# shellcheck disable=SC3040,SC2039
set -o xtrace -o errexit -o nounset; [ -n "${BASH:-}${ZSH_NAME:-}" ] && set -o pipefail

# Build configuration environment variables:
#
# CW_BLD
#      List of components to build. E.g. 'curl' or 'zlib libssh2 curl' or 'zlib curl-cmake' or 'none'.
#      Optional. Default: (all)
#
# CW_GET
#      List of components to (re-)download. E.g. 'zlib curl' or 'none'.
#      Optional. Default: (all)
#
# CW_LLVM_MINGW_PATH
#      Point to LLVM MinGW installation (for win target).
#
# CW_CONFIG
#      Build configuration. Certain keywords select certain configurations. E.g.: 'main-micro'.
#      Optional. Default: 'main' (inherited from the active repo branch name)
#
#      Supported keywords:
#        main       production build
#        test       test build (.map files enabled by default, publishing disabled)
#        dev        development build (use source snapshots instead of stable releases)
#        noh3       build without HTTP/3 (QUIC) support (select stock OpenSSL instead of quictls)
#        nobrotli   build without brotli
#        nozstd     build without zstd
#        nozlib     build without zlib
#        noftp      build without FTP/FTPS support
#        awslc      build with AWS-LC
#        boringssl  build with BoringSSL
#        libressl   build with LibreSSL
#        schannel   build with Schannel
#        mbedtls    build with mbedTLS
#        wolfssl    build with wolfSSL (caveats!)
#        wolfssh    build with wolfSSH (requires wolfSSL)
#        libssh     build with libssh
#        big        build with more features, see README.md
#        mini       build with less features, see README.md
#        micro      build with less features, see README.md
#        nano       build with less features, see README.md
#        pico       build with less features, see README.md
#        bldtst     build without 3rd-party dependencies (except zlib) (for testing)
#        r64        build riscv64 target only (experimental)
#        a64        build arm64 target only
#        x64        build x86_64 target only
#        x86        build i686 target only (for win target)
#        msvcrt     build against msvcrt instead of UCRT (for win target)
#        gcc        build with GCC (including Apple clang aliased to gcc) (defaults to llvm, and "gcc" (= Apple clang) for mac target)
#        unicode    build curl in UNICODE mode (for win target) [EXPERIMENTAL]
#        werror     turn compiler warnings into errors
#        debug      debug build
#        win        build Windows target (default)
#        mac        build macOS target (requires macOS host)
#        linux      build Linux target (requires Linux host)
#        musl       build Linux target with musl CRT (for linux target) (default for Alpine)
#        macuni     build macOS universal (arm64 + x86_64) package (for mac target)
#
# CW_JOBS
#      Number of parallel make jobs. Default: 2
#
# CW_CCSUFFIX
#      llvm/clang and gcc suffix. E.g. '-8' for clang-8.
#      Optional. Default: (empty)
#
# CW_REVISION
#      Override the stable build revision number.
#
# SIGN_CODE_GPG_PASS, SIGN_CODE_KEY_PASS: for code signing
# SIGN_PKG_KEY_ID, SIGN_PKG_GPG_PASS, SIGN_PKG_KEY_PASS: for package signing
# DEPLOY_GPG_PASS, DEPLOY_KEY_PASS: for publishing results
#      Secrets used for the above operations.
#      Optional. Skipping any operation missing a secret.

# TODO:
#   - quictls: build with no-deprecated option (pending libssh2 support)
#   - delete curl-gnumake.sh and libssh2-gnumake.sh.
#   - publish curl tool as direct downloads:
#     curl-linux-musl / curl-mac / curl-x64.exe / curl-x86.exe / curl-a64.exe
#     (or similar)
#   - change default TLS to BoringSSL (with OPENSSL_SMALL?) or LibreSSL?
#   - prepare for Xcode 15 with new ld_prime (-Wl,-ld_new) linker (vs. -Wl,-ld_classic).
#     https://developer.apple.com/forums/thread/715385
#   - linux: musl alpine why need -static-pie and not -static?
#   - linux: musl libcurl.so.4.8.0 tweak to be also portable (possible?)
#     fix apps linked against musl libcurl.so. Or stop making/distributing it?
#     they require '/lib/ld-musl-x86_64.so.1' / '/lib/ld-musl-aarch64.so.1' now.
#     meaning e.g.: `apt install musl; LD_LIBRARY_PATH=. ./trurl`
#   - merge _ci-*.sh scripts into one.
#   - FIXME: curl-autotools: .map file support and clang builds broken.
#   - win: Drop x86 builds.
#       https://data.firefox.com/dashboard/hardware
#       https://gs.statcounter.com/windows-version-market-share
#     A hidden aspect of x86: The Chocolatey package manager installs x86
#     binaries on ARM systems to run them in emulated mode. Windows as of ~2021
#     got the ability to run x64 in emulated mode, but tooling support is
#     missing, just like support for native ARM binaries:
#       https://github.com/chocolatey/choco/issues/1803
#       https://github.com/chocolatey/choco/issues/2172
#     winget and scoop both support native ARM64.

# Resources:
#   - https://clang.llvm.org/docs/Toolchain.html
#   - https://blog.llvm.org/2019/11/deterministic-builds-with-clang-and-lld.html
#   - https://github.com/mstorsjo/llvm-mingw
#   - https://github.com/llvm/llvm-project
#   - https://salsa.debian.org/pkg-llvm-team
#   - https://git.code.sf.net/p/mingw-w64/mingw-w64
#     https://github.com/mirror/mingw-w64
#   - https://sourceware.org/git/binutils-gdb.git
#   - https://github.com/netwide-assembler/nasm

# Build times for windows (2023-10-25):
#   - cmake-unity:  27 min 22 sec   1642s   100%
#   - gnumake:      29 min 11 sec   1751s   107%   100%
#   - autotools:    35 min 20 sec   2120s   129%   121%

# Supported build tools:
#
#   zlib             cmake
#   zlibng           cmake
#   zstd             cmake
#   brotli           cmake
#   cares            cmake
#   libunistring     autotools
#   libiconv         autotools
#   libidn2          autotools
#   libpsl           autotools
#   gsasl            autotools
#   nghttp2          cmake
#   nghttp3          cmake
#   ngtcp2           cmake
#   wolfssl          autotools
#   mbedtls          cmake
#   openssl/quictls  proprietary
#   boringssl/awslc  cmake
#   libressl         autotools, cmake
#   wolfssh          autotools
#   libssh           cmake
#   libssh2          cmake-unity, autotools, gnumake [windows-only]
#   curl             cmake-unity, autotools, gnumake [windows-only]
#   trurl            gnumake

cd "$(dirname "$0")"

export LC_ALL=C
export LC_MESSAGES=C
export LANG=C

export GREP_OPTIONS=
export ZIPOPT=
export ZIP=

unamem="$(uname -m)"

readonly _LOG='logurl.txt'
readonly _SELF='curl-for-win'
if [ -n "${APPVEYOR_ACCOUNT_NAME:-}" ]; then
  # https://www.appveyor.com/docs/environment-variables/
  _SLUG="${APPVEYOR_REPO_NAME}"
  _LOGURL="${APPVEYOR_URL}/project/${APPVEYOR_ACCOUNT_NAME}/${APPVEYOR_PROJECT_SLUG}/build/${APPVEYOR_BUILD_VERSION}/job/${APPVEYOR_JOB_ID}?fullLog=true"
# _LOGURL="${APPVEYOR_URL}/api/buildjobs/${APPVEYOR_JOB_ID}/log"
  _COMMIT="${APPVEYOR_REPO_COMMIT}"
  _COMMIT_SHORT="$(printf '%.8s' "${_COMMIT}")"
elif [ -n "${GITHUB_RUN_ID:-}" ]; then
  # https://docs.github.com/actions/learn-github-actions/environment-variables
  _SLUG="${GITHUB_REPOSITORY}"
  _LOGURL="${GITHUB_SERVER_URL}/${_SLUG}/actions/runs/${GITHUB_RUN_ID}"
  _COMMIT="${GITHUB_SHA}"
  _COMMIT_SHORT="$(printf '%.8s' "${_COMMIT}")"
elif [ -n "${CI_JOB_ID:-}" ]; then
  # https://docs.gitlab.com/ce/ci/variables/index.html
  _SLUG="${CI_PROJECT_PATH}"
  _LOGURL="${CI_SERVER_URL}/${_SLUG}/-/jobs/${CI_JOB_ID}/raw"
  _COMMIT="${CI_COMMIT_SHA}"
  _COMMIT_SHORT="$(printf '%.8s' "${_COMMIT}")"
else
  _SLUG="curl/${_SELF}"
  _LOGURL=''
  _COMMIT="$(git rev-parse --verify HEAD || true)"
  _COMMIT_SHORT="$(git rev-parse --short=8 HEAD || true)"
fi
echo "${_LOGURL}" | tee "${_LOG}"

export _CONFIG
if [ -n "${CW_CONFIG:-}" ]; then
  _CONFIG="${CW_CONFIG}"
else
  _CONFIG="${APPVEYOR_REPO_BRANCH:-}${CI_COMMIT_REF_NAME:-}${GITHUB_REF_NAME:-}"
fi
[ -n "${_CONFIG}" ] || _CONFIG="$(git symbolic-ref --short --quiet HEAD || true)"
[ -n "${_CONFIG}" ] || _CONFIG='main'
if command -v git >/dev/null 2>&1; then
  # Broken on AppVeyor CI since around 2023-02:
  #   fatal: No remote configured to list refs from.
  _URL_BASE="$(git ls-remote --get-url | sed 's/\.git$//' || true)"
fi
if [ -z "${_URL_BASE}" ]; then
  _URL_BASE="https://github.com/${_SLUG}"
fi
if [ -n "${_COMMIT}" ]; then
# _URL_FULL="${_URL_BASE}/tree/${_COMMIT}"
  _TAR="${_URL_BASE}/archive/${_COMMIT}.tar.gz"
else
# _URL_FULL="${_URL_BASE}"
  _TAR="${_URL_BASE}/archive/refs/heads/${_CONFIG}.tar.gz"
fi

# Detect host OS
export _HOST
case "$(uname)" in
  *_NT*)   _HOST='win';;
  Linux*)  _HOST='linux';;
  Darwin*) _HOST='mac';;
  *BSD)    _HOST='bsd';;
  *)       _HOST='unrecognized';;
esac

export _DISTRO=''
if [ "${_HOST}" = 'linux' ] && [ -s /etc/os-release ]; then
  _DISTRO="$(grep -a '^ID=' /etc/os-release | cut -c 4- | tr -d '"' || true)"
  _DISTRO="${_DISTRO:-unrecognized}"
fi

export _OS='win'
[ ! "${_CONFIG#*mac*}" = "${_CONFIG}" ] && _OS='mac'
[ ! "${_CONFIG#*linux*}" = "${_CONFIG}" ] && _OS='linux'

export _CACERT='cacert.pem'

[ -n "${CW_CCSUFFIX:-}" ] || CW_CCSUFFIX=''

if [ "${_OS}" = 'mac' ]; then
  _CONFCC='gcc'  # = Apple clang
else
  _CONFCC='llvm'
fi
[ ! "${_CONFIG#*gcc*}" = "${_CONFIG}" ] && _CONFCC='gcc'
[ ! "${_CONFIG#*llvm*}" = "${_CONFIG}" ] && _CONFCC='llvm'

export _CRT
if [ "${_OS}" = 'win' ]; then
  _CRT='ucrt'
  [ ! "${_CONFIG#*msvcrt*}" = "${_CONFIG}" ] && _CRT='msvcrt'
elif [ "${_OS}" = 'linux' ]; then
  if [ "${_HOST}" = 'mac' ]; then
    # Assume musl-cross toolchain via Homebrew, based on musl-cross-make
    # https://github.com/richfelker/musl-cross-make
    # https://github.com/FiloSottile/homebrew-musl-cross
    # https://words.filippo.io/easy-windows-and-linux-cross-compilers-for-macos/
    _CONFCC='gcc'
    _CRT='musl'
  elif [ "${_DISTRO}" = 'alpine' ]; then
    _CRT='musl'
  else
    # TODO: make musl the default (once all issues are cleared)
    _CRT='gnu'
    [ ! "${_CONFIG#*musl*}" = "${_CONFIG}" ] && _CRT='musl'
  fi
else
  # macOS: /usr/lib/libSystem.B.dylib
  _CRT='sys'
fi

export DYN_DIR
export DYN_EXT
export BIN_EXT
if [ "${_OS}" = 'win' ]; then
  DYN_DIR='bin'
  DYN_EXT='.dll'
  BIN_EXT='.exe'
elif [ "${_OS}" = 'mac' ]; then
  DYN_DIR='lib'
  DYN_EXT='.dylib'
  BIN_EXT=''
elif [ "${_OS}" = 'linux' ]; then
  DYN_DIR='lib'
  DYN_EXT='.so'
  BIN_EXT=''
fi

if [ -z "${CW_MAP:-}" ]; then
  export CW_MAP='0'
  [ "${_CONFIG#*main*}" = "${_CONFIG}" ] && CW_MAP='1'
fi

export _JOBS=2
[ -n "${CW_JOBS:-}" ] && _JOBS="${CW_JOBS}"

my_time='time'
[ -n "${CW_NOTIME:-}" ] && my_time=

# Form suffix for alternate builds
export _FLAV=''
if [ "${_CONFIG#*bldtst*}" != "${_CONFIG}" ]; then
  _FLAV='-bldtst'
elif [ "${_CONFIG#*pico*}" != "${_CONFIG}" ]; then
  _FLAV='-pico'
elif [ "${_CONFIG#*nano*}" != "${_CONFIG}" ]; then
  _FLAV='-nano'
elif [ "${_CONFIG#*micro*}" != "${_CONFIG}" ]; then
  _FLAV='-micro'
elif [ "${_CONFIG#*mini*}" != "${_CONFIG}" ]; then
  _FLAV='-mini'
elif [ "${_CONFIG#*noh3*}" != "${_CONFIG}" ]; then
  _FLAV='-noh3'
elif [ "${_CONFIG#*big*}" != "${_CONFIG}" ]; then
  _FLAV='-big'
fi

# For 'configure'-based builds.
# This is more or less guesswork and this warning remains:
#    `configure: WARNING: using cross tools not prefixed with host triplet`
# Even with `_CCPREFIX` provided.
# https://clang.llvm.org/docs/CrossCompilation.html
case "${_HOST}" in
  win)   _HOST_TRIPLET="${unamem}-pc-mingw32";;
  linux) _HOST_TRIPLET="${unamem}-pc-linux";;
  bsd)   _HOST_TRIPLET="${unamem}-pc-bsd";;
  mac)   _HOST_TRIPLET="${unamem}-apple-darwin";;
  *)     _HOST_TRIPLET="${unamem}-pc-$(uname -s | tr '[:upper:]' '[:lower:]')";;  # lazy guess
esac

if [ "${_HOST}" = 'linux' ]; then
  # Short triplet used on the filesystem
  _HOST_TRIPLETSH="${unamem}-linux-gnu"
else
  _HOST_TRIPLETSH="${_HOST_TRIPLET}"
fi

export _PKGOS
if [ "${_OS}" = 'win' ]; then
  _PKGOS='mingw'
elif [ "${_OS}" = 'mac' ]; then
  _PKGOS='macos'
else
  _PKGOS="${_OS}"
fi

export PUBLISH_PROD_FROM
if [ "${APPVEYOR_REPO_PROVIDER:-}" = 'gitHub' ] || \
   [ -n "${GITHUB_RUN_ID:-}" ]; then
  PUBLISH_PROD_FROM='linux'
else
  PUBLISH_PROD_FROM=''
fi

export _BLD='build.txt'
export _URLS='urls.txt'

rm -f ./*-*-"${_PKGOS}"*.*
rm -f hashes.txt "${_BLD}" "${_URLS}"

touch hashes.txt "${_BLD}" "${_URLS}"

. ./_versions.sh

# Revision suffix used in package filenames
export _REVSUFFIX="${_REV}"; [ -z "${_REVSUFFIX}" ] || _REVSUFFIX="_${_REVSUFFIX}"

# Download sources
. ./_dl.sh

# Install required component
if [ "${_OS}" = 'win' ] && [ "${_HOST}" = 'mac' ]; then
  if [ ! -d .venv ]; then
    python3 -m venv .venv
    PIP_PROGRESS_BAR=off .venv/bin/python3 -m pip --disable-pip-version-check --no-cache-dir --require-virtualenv install pefile
  fi
  export PATH; PATH="$(pwd)/.venv/bin:${PATH}"
fi

# Find and setup llvm-mingw downloaded above.
if [ "${_OS}" = 'win' ] && \
   [ -z "${CW_LLVM_MINGW_PATH:-}" ] && \
   [ -d 'llvm-mingw' ]; then
  export CW_LLVM_MINGW_PATH; CW_LLVM_MINGW_PATH="$(pwd)/llvm-mingw"
  export CW_LLVM_MINGW_VER_; CW_LLVM_MINGW_VER_="$(cat 'llvm-mingw/version.txt')"
  echo "! Using llvm-mingw: '${CW_LLVM_MINGW_PATH}' (${CW_LLVM_MINGW_VER_})"
fi

# Decrypt package signing key
SIGN_PKG_KEY='sign-pkg.gpg.asc'
if [ -s "${SIGN_PKG_KEY}" ] && \
   [ -n "${SIGN_PKG_KEY_ID:-}" ] && \
   [ -n "${SIGN_PKG_GPG_PASS:+1}" ]; then
  gpg --batch --yes --no-tty --quiet \
    --pinentry-mode loopback --passphrase-fd 0 \
    --decrypt "${SIGN_PKG_KEY}" 2>/dev/null <<EOF | \
  gpg --batch --quiet --import
${SIGN_PKG_GPG_PASS}
EOF
fi

# decrypt code signing key
export SIGN_CODE_KEY; SIGN_CODE_KEY="$(pwd)/sign-code.p12"
if [ -s "${SIGN_CODE_KEY}.asc" ] && \
   [ -n "${SIGN_CODE_GPG_PASS:+1}" ]; then
  install -m 600 /dev/null "${SIGN_CODE_KEY}"
  gpg --batch --yes --no-tty --quiet \
    --pinentry-mode loopback --passphrase-fd 0 \
    --decrypt "${SIGN_CODE_KEY}.asc" 2>/dev/null >> "${SIGN_CODE_KEY}" <<EOF || true
${SIGN_CODE_GPG_PASS}
EOF
fi

if [ "${_OS}" = 'win' ] && \
   [ -s "${SIGN_CODE_KEY}" ]; then
  osslsigncode --version  # We need 2.2 or newer
fi

_ori_path="${PATH}"

bld() {
  bldtools='(cmake|autotools|gnumake)'
  pkg="$1"
  if [ -z "${CW_BLD:-}" ] || echo " ${CW_BLD} " | grep -q -E -- " ${pkg}(-${bldtools})? "; then
    shift

    export _BLDDIR="${_PKGDIR}"

    pkgori="${pkg}"
    [ -n "${2:-}" ] && pkg="$2"
    # allow selecting an alternate build tool
    withbuildtool="$(echo "${CW_BLD:-}" | \
      grep -a -o -E -- "${pkg}-${bldtools}" || true)"
    if [ -n "${withbuildtool}" ] && [ -f "${withbuildtool}.sh" ]; then
      pkg="${withbuildtool}"

      bldtool="$(echo "${pkg}" | \
        grep -a -o -E -- "-${bldtools}")"
      _BLDDIR="${_BLDDIR}${bldtool}-${_CC}"
    fi

    _BLDDIR="${_BLDDIR}-bld"

    ${my_time} "./${pkg}.sh" "$1" "${pkgori}"

    if [ "${CW_DEV_MOVEAWAY:-}" = '1' ] && [ "${pkg}" != "${pkgori}" ]; then
      mv -n "${pkgori}" "${pkg}"
    fi
  fi
}

build_single_target() {
  export _CPU="$1"
  export _CC="${_CONFCC}"

  # Select and advertise a single copy of components having multiple
  # implementations.
  export _ZLIB=''
  if   [ -d zlibng ]; then
    _ZLIB='zlibng'
  elif [ -d zlib ]; then
    _ZLIB='zlib'
  fi
  export _OPENSSL=''; boringssl=0
  if   [ -d libressl ]; then
    _OPENSSL='libressl'
  elif [ -d awslc ]; then
    _OPENSSL='awslc'; boringssl=1
  elif [ -d boringssl ]; then
    _OPENSSL='boringssl'; boringssl=1
  elif [ -d quictls ]; then
    _OPENSSL='quictls'
  elif [ -d openssl ]; then
    _OPENSSL='openssl'
  fi

  use_llvm_mingw=0
  versuffix_llvm_mingw=''
  versuffix_non_llvm_mingw=''
  if [ "${_OS}" = 'win' ]; then
    if [ "${CW_LLVM_MINGW_ONLY:-}" = '1' ]; then
      use_llvm_mingw=1
    # llvm-mingw is required for x64 (to avoid pthread link bug with BoringSSL),
    # but for consistency, use it for all targets when building with BoringSSL.
    elif [ "${boringssl}" = '1' ] && [ "${_CRT}" = 'ucrt' ]; then
      use_llvm_mingw=1
    elif [ "${_CPU}" = 'a64' ]; then
      use_llvm_mingw=1
      versuffix_llvm_mingw=' (ARM64)'
    fi
  fi

  # Toolchain
  export _TOOLCHAIN=''
  if [ "${_OS}" = 'win' ]; then
    if [ "${use_llvm_mingw}" = '1' ]; then
      if [ "${_CC}" != 'llvm' ] || \
         [ "${_CRT}" != 'ucrt' ] || \
         [ -z "${CW_LLVM_MINGW_PATH:-}" ]; then
        echo "! WARNING: '${_CONFIG}/${_CPU}' builds require llvm/clang, UCRT and CW_LLVM_MINGW_PATH. Skipping."
        return
      fi
      _TOOLCHAIN='llvm-mingw'
    else
      _TOOLCHAIN='mingw-w64'
    fi
  elif [ "${_OS}" = 'mac' ] && [ "${_CC}" = 'gcc' ]; then
    if "${_CC}${CW_CCSUFFIX}" --version | grep -q -a -E '(Apple clang|Apple LLVM|based on LLVM)'; then
      _CC='llvm'
      _TOOLCHAIN='llvm-apple'  # Apple clang
    fi
  fi

  export _TRIPLET=''
  _SYSROOT=''

  _CCPREFIX=
  _CCSUFFIX=
  export _MAKE='make'
  export _RUN_BIN=''

  if [ "${_TOOLCHAIN}" != 'llvm-mingw' ]; then
    _CCSUFFIX="${CW_CCSUFFIX}"
  fi

  # GCC-specific machine selection option
  [ "${_CPU}" = 'x86' ] && _OPTM='-m32'
  [ "${_CPU}" = 'x64' ] && _OPTM='-m64'
  [ "${_CPU}" = 'a64' ] && _OPTM='-marm64pe'

  [ "${_CPU}" = 'x86' ] && _machine='i686'
  [ "${_CPU}" = 'x64' ] && _machine='x86_64'
  [ "${_CPU}" = 'a64' ] && _machine='aarch64'
  [ "${_CPU}" = 'r64' ] && _machine='riscv64'

  if [ "${_OS}" = 'mac' ] && [ "${_machine}" = 'aarch64' ] && [ "${_CC}" = 'llvm' ]; then
    # llvm-apple supports multiple archs separated by ';', e.g. 'arm64e;x86_64'
    # It also understands arm64e (vs arm64)
    _machines='arm64e'
  else
    _machines="${_machine}"
  fi

  export _CURL_DLL_SUFFIX=''
  export _CURL_DLL_SUFFIX_NODASH=''
  if [ "${_OS}" = 'win' ]; then
    [ "${_CPU}" = 'x64' ] && _CURL_DLL_SUFFIX_NODASH="${_CPU}"
    [ "${_CPU}" = 'a64' ] && _CURL_DLL_SUFFIX_NODASH='arm64'
    [ -n "${_CURL_DLL_SUFFIX_NODASH}" ] && _CURL_DLL_SUFFIX="-${_CURL_DLL_SUFFIX_NODASH}"
  fi

  if [ "${_OS}" = 'win' ]; then
    [ "${_CPU}" = 'x86' ] && pkgcpu='win32'
    [ "${_CPU}" = 'x64' ] && pkgcpu='win64'
    [ "${_CPU}" = 'a64' ] && pkgcpu='win64a'
  else
    # TODO: add support for macOS universal (multi-CPU) builds?
    pkgcpu="${_machine}"
  fi
  export _PKGSUFFIX="-${pkgcpu}-${_PKGOS}"

  # Reset for each target
  PATH="${_ori_path}"

  if [ "${_HOST}" = 'mac' ]; then
    brew_root="$(brew --prefix)"
    _MAC_LLVM_PATH="${brew_root}/opt/llvm/bin"  # or "$(brew --prefix llvm)/bin"
  fi

  if [ "${_OS}" = 'win' ]; then
    if [ "${_HOST}" = 'win' ]; then
      export PATH
      if [ "${_TOOLCHAIN}" = 'llvm-mingw' ]; then
        PATH="${CW_LLVM_MINGW_PATH}/bin:${_ori_path}"
      else
        [ "${_CPU}" = 'x86' ] && _MSYSROOT='/mingw32'
        [ "${_CPU}" = 'x64' ] && _MSYSROOT='/mingw64'
        [ "${_CPU}" = 'a64' ] && _MSYSROOT='/clangarm64'

        [ -n "${_MSYSROOT}" ] && PATH="${_MSYSROOT}/bin:${_ori_path}"
      fi
      _MAKE='mingw32-make'
    else
      if [ "${_TOOLCHAIN}" = 'llvm-mingw' ]; then
        export PATH="${CW_LLVM_MINGW_PATH}/bin:${_ori_path}"
      elif [ "${_CC}" = 'llvm' ] && [ "${_HOST}" = 'mac' ]; then
        export PATH="${_MAC_LLVM_PATH}:${_ori_path}"
      fi
      _TRIPLET="${_machine}-w64-mingw32"
      # Prefixes do not work with MSYS2/mingw-w64, because `ar`, `nm` and
      # `ranlib` are missing from them. They are accessible either _without_
      # one, or as prefix + `gcc-ar`, `gcc-nm`, `gcc-runlib`.
      _CCPREFIX="${_TRIPLET}-"
      # mingw-w64 sysroots
      if [ "${_TOOLCHAIN}" != 'llvm-mingw' ]; then
        if [ "${_HOST}" = 'mac' ]; then
          _SYSROOT="${brew_root}/opt/mingw-w64/toolchain-${_machine}"
        elif [ "${_HOST}" = 'linux' ]; then
          _SYSROOT="/usr/${_TRIPLET}"
        fi
      fi

      _RUN_BIN='echo'
      if [ "${_HOST}" = 'linux' ] || \
         [ "${_HOST}" = 'bsd' ]; then
        # Run x64 targets on same CPU:
        if [ "${_CPU}" = 'x64' ] && \
           [ "${unamem}" = 'x86_64' ]; then
          if command -v wine64 >/dev/null 2>&1; then
            _RUN_BIN='wine64'
          elif command -v wine >/dev/null 2>&1; then
            _RUN_BIN='wine'
          fi
        fi
      elif [ "${_HOST}" = 'mac' ]; then
        # Run x64 targets on Intel and ARM (requires Wine 6.0.1):
        if [ "${_CPU}" = 'x64' ] && \
           command -v wine64 >/dev/null 2>&1; then
          _RUN_BIN='wine64'
        fi
      elif [ "${_HOST}" = 'win' ]; then
        # Skip ARM64 target on 64-bit Intel, run all targets on ARM64:
        if [ "${unamem}" = 'x86_64' ] && \
           [ "${_CPU}" != 'a64' ]; then
          _RUN_BIN=
        elif [ "${unamem}" = 'aarch64' ]; then
          _RUN_BIN=
        fi
      fi
    fi
  else
    if [ "${_CC}" = 'llvm' ] && [ "${_TOOLCHAIN}" != 'llvm-apple' ] && [ "${_HOST}" = 'mac' ]; then
      export PATH="${_MAC_LLVM_PATH}:${_ori_path}"
    fi

    if [ "${_OS}" = 'linux' ]; then
      # Include CRT type in Linux triplets, to make it visible in
      # the curl version banner.
      if [ "${_HOST}" = 'mac' ]; then
        _TRIPLET="${_machine}-linux-musl"
        _CCPREFIX="${_TRIPLET}-"
      elif [ "${_DISTRO}" = 'alpine' ]; then
        # E.g. x86_64-alpine-linux-musl
        _TRIPLET="${_machine}-${_DISTRO}-linux-${_CRT}"
        _TRIPLETSH="${_TRIPLET}"
      else
        if [ "${_CRT}" = 'musl' ]; then
          # E.g. x86_64-unknown-linux-musl
          _TRIPLET="${_machine}-unknown-linux-${_CRT}"
        else
          _TRIPLET="${_machine}-pc-linux-${_CRT}"
        fi
        # Short triplet used on the filesystem
        _TRIPLETSH="${_machine}-linux-gnu"
      fi

      if [ "${_DISTRO}" = 'debian' ] && \
         [ "${_CC}" = 'gcc' ] && \
         [ "${unamem}" != "${_machine}" ] && \
         [ ! -d "/usr/lib/gcc-cross/${_TRIPLETSH}" ]; then
        echo "! WARNING: '${_CONFIG}/${_CPU}' build requires gcc-cross package. Skipping."
        return
      fi

      if [ "${unamem}" != "${_machine}" ] && [ "${_CC}" = 'gcc' ]; then
        # https://packages.debian.org/testing/arm64/gcc-x86-64-linux-gnu/filelist
        # https://packages.debian.org/testing/arm64/binutils-x86-64-linux-gnu/filelist
        # /usr/bin/x86_64-linux-gnu-gcc
        # https://packages.debian.org/testing/amd64/gcc-aarch64-linux-gnu/filelist
        # https://packages.debian.org/testing/amd64/binutils-aarch64-linux-gnu/filelist
        # /usr/bin/aarch64-linux-gnu-gcc
        _CCPREFIX="${_TRIPLETSH}-"
      fi

      _RUN_BIN='echo'
      if [ "${_HOST}" = 'linux' ] && [ "${_OS}" = 'linux' ]; then
        # Skip running non-native builds
        if [ "${unamem}" = "${_machine}" ]; then
          _RUN_BIN=''
        elif [ "${_DISTRO}" = 'debian' ]; then
          _RUN_BIN="qemu-${_machine}-static"
        fi
      fi
    elif [ "${_OS}" = 'mac' ]; then
      _TRIPLET="${_machine}-apple-darwin"

      _RUN_BIN='echo'
      if [ "${_HOST}" = 'mac' ]; then
        # Skip running arm64 on x86_64
        if [ "${_CPU}" = 'x64' ] || \
           [ "${unamem}" = 'aarch64' ]; then
          _RUN_BIN=''
        fi
      fi
    fi
  fi

  if [ "${_CC}" = 'llvm' ]; then
    ccver="$("clang${_CCSUFFIX}" -dumpversion)"
  else
    ccver="$("${_CCPREFIX}gcc${_CCSUFFIX}" -dumpversion)"

    if [ "${_CRT}" = 'ucrt' ]; then
      # Create specs files that overrides msvcrt with ucrt. We need this
      # for gcc when building against UCRT.
      #   https://stackoverflow.com/questions/57528555/how-do-i-build-against-the-ucrt-with-mingw-w64
      _GCCSPECS="$(pwd)/gcc-specs-ucrt"
      "${_CCPREFIX}gcc${_CCSUFFIX}" -dumpspecs | sed 's/-lmsvcrt/-lucrt/g' > "${_GCCSPECS}"
    fi
  fi

  export _CCVER
  _CCVER="$(printf '%02d' \
    "$(printf '%s' "${ccver}" | grep -a -o -E '^[0-9]+')")"

  export _OSVER='0000'

  # Setup common toolchain configuration options

  export _TOP; _TOP="$(pwd)"  # Must be an absolute path
  export _PKGDIR="_${_CPU}-${_OS}-${_CRT}"
  export _PKGDIRS="${_PKGDIR}"
  [ -n "${_OPENSSL}" ] && _PKGDIRS="${_PKGDIRS}-${_OPENSSL}"
  _PREFIX='/usr'
  export _PP="${_PKGDIR}${_PREFIX}"
  export _PPS="${_PKGDIRS}${_PREFIX}"
  export _CC_GLOBAL=''
  export _CFLAGS_GLOBAL=''
  export _CFLAGS_GLOBAL_CMAKE=''
  export _CPPFLAGS_GLOBAL=''
  export _CXXFLAGS_GLOBAL=''
  export _RCFLAGS_GLOBAL=''
  export _LDFLAGS_GLOBAL=''
  export _LDFLAGS_GLOBAL_AUTOTOOLS=''
  export _LDFLAGS_BIN_GLOBAL=''
  export _LDFLAGS_CXX_GLOBAL=''  # CMake uses this
  export _LIBS_GLOBAL=''
  export _CONFIGURE_GLOBAL=''
  export _CMAKE_GLOBAL='-DCMAKE_BUILD_TYPE=Release'
  export _CMAKE_CXX_GLOBAL=''

  # Suppress CMake warnings meant for upstream developers
  _CMAKE_GLOBAL="-Wno-dev ${_CMAKE_GLOBAL}"

  # for CMake and openssl
  unset CC

  if [ "${_OS}" = 'win' ]; then

    _CPPFLAGS_GLOBAL="${_CPPFLAGS_GLOBAL} -D_WIN32_WINNT=0x0600"  # Windows Vista

    if [ "${_HOST}" != "${_OS}" ]; then
      _CMAKE_GLOBAL="-DCMAKE_SYSTEM_NAME=Windows ${_CMAKE_GLOBAL}"
    fi

    [ "${_CPU}" = 'x86' ] && _RCFLAGS_GLOBAL="${_RCFLAGS_GLOBAL} --target=pe-i386"
    [ "${_CPU}" = 'x64' ] && _RCFLAGS_GLOBAL="${_RCFLAGS_GLOBAL} --target=pe-x86-64"
    [ "${_CPU}" = 'a64' ] && _RCFLAGS_GLOBAL="${_RCFLAGS_GLOBAL} --target=${_TRIPLET}"  # llvm-windres supports triplets here. https://github.com/llvm/llvm-project/blob/main/llvm/tools/llvm-rc/llvm-rc.cpp

    if [ "${_HOST}" = 'win' ]; then
      # '-G MSYS Makefiles' command-line option is problematic due to spaces
      # and unwanted escaping/splitting. Pass it via envvar instead.
      export CMAKE_GENERATOR='MSYS Makefiles'
      # Without this, the value '/usr/local' becomes 'msys64/usr/local'
      export MSYS2_ARG_CONV_EXCL='-DCMAKE_INSTALL_PREFIX='
    fi

    if [ "${_CRT}" = 'ucrt' ]; then
      _CPPFLAGS_GLOBAL="${_CPPFLAGS_GLOBAL} -D_UCRT"
      _LIBS_GLOBAL="${_LIBS_GLOBAL} -lucrt"
      if [ "${_CC}" = 'gcc' ]; then
        _LDFLAGS_GLOBAL="${_LDFLAGS_GLOBAL} -specs=${_GCCSPECS}"
      fi
    fi
  elif [ "${_OS}" = 'mac' ]; then
    if [ "${_HOST}" != "${_OS}" ]; then
      _CMAKE_GLOBAL="-DCMAKE_SYSTEM_NAME=Darwin ${_CMAKE_GLOBAL}"
    fi
    # macOS 10.9 Mavericks 2013-10-22. Seems to work for arm64 builds,
    # though arm64 was released in macOS 11.0 Big Sur 2020-11-12.
    # Bump to macOS 10.13 High Sierra 2017-09-25 if we decide to disable
    # LDAP/LDAPS for macOS builds.
    # NOTE: 10.8 (and older) trigger C++ issues with Xcode and CMake.
    macminver='10.9'
    _CMAKE_GLOBAL="${_CMAKE_GLOBAL} -DCMAKE_OSX_DEPLOYMENT_TARGET=${macminver}"
    _CFLAGS_GLOBAL="${_CFLAGS_GLOBAL} -mmacosx-version-min=${macminver}"
    _CXXFLAGS_GLOBAL="${_CXXFLAGS_GLOBAL} -mmacosx-version-min=${macminver}"
    _OSVER="$(printf '%02d%02d' \
      "$(printf '%s' "${macminver}" | cut -d '.' -f 1)" \
      "$(printf '%s' "${macminver}" | cut -d '.' -f 2)")"
    _CMAKE_GLOBAL="${_CMAKE_GLOBAL} -DCMAKE_OSX_ARCHITECTURES=${_machines}"
  elif [ "${_OS}" = 'linux' ]; then
    if [ "${_HOST}" != "${_OS}" ]; then
      _CMAKE_GLOBAL="-DCMAKE_SYSTEM_NAME=Linux ${_CMAKE_GLOBAL}"
    fi

    # Override defaults such as: 'lib/aarch64-linux-gnu'
    _CMAKE_GLOBAL="${_CMAKE_GLOBAL} -DCMAKE_INSTALL_LIBDIR=lib"

    # With musl, this relies on package `fortify-headers` (Alpine)
    _CPPFLAGS_GLOBAL="${_CPPFLAGS_GLOBAL} -D_FORTIFY_SOURCE=2"
    # Requires glibc 2.34, gcc 12 (2022)
    #   https://developers.redhat.com/articles/2023/02/06/how-improve-application-security-using-fortifysource3
    #   https://developers.redhat.com/articles/2022/09/17/gccs-new-fortification-level
  # _CPPFLAGS_GLOBAL="${_CPPFLAGS_GLOBAL} -D_FORTIFY_SOURCE=3"

    # https://en.wikipedia.org/wiki/Position-independent_code#PIE
    _CFLAGS_GLOBAL="${_CFLAGS_GLOBAL} -fPIC"
    _CXXFLAGS_GLOBAL="${_CXXFLAGS_GLOBAL} -fPIC"

    # With musl, this seems to be a no-op as of Alpine v3.18
    # https://en.wikipedia.org/wiki/Buffer_overflow_protection
    _CFLAGS_GLOBAL="${_CFLAGS_GLOBAL} -fstack-protector-all"
    _CXXFLAGS_GLOBAL="${_CXXFLAGS_GLOBAL} -fstack-protector-all"

    _LDFLAGS_GLOBAL="${_LDFLAGS_GLOBAL} -Wl,-z,relro,-z,now"

    if [ "${_CRT}" = 'musl' ]; then
      if [ "${_HOST}" = 'mac' ]; then
        _LDFLAGS_BIN_GLOBAL="${_LDFLAGS_BIN_GLOBAL} -static"
      elif [ "${_DISTRO}" = 'alpine' ]; then
        _LDFLAGS_BIN_GLOBAL="${_LDFLAGS_BIN_GLOBAL} -static-pie"
      else
        _LDFLAGS_BIN_GLOBAL="${_LDFLAGS_BIN_GLOBAL} -static"
      fi
    fi
  fi

  _CMAKE_GLOBAL="${_CMAKE_GLOBAL} -DCMAKE_INSTALL_MESSAGE=NEVER"
  _CMAKE_GLOBAL="${_CMAKE_GLOBAL} -DCMAKE_INSTALL_PREFIX=${_PREFIX}"

  # 'configure' naming conventions:
  # - '--build' is the host we are running the build on.
  #   We call it '_HOST_TRIPLET' (and `_HOST` for our short name).
  # - '--host' is the host we are building the binaries for.
  #   We call it '_TRIPLET' (and '_OS' for our short name).
  _CONFIGURE_GLOBAL="${_CONFIGURE_GLOBAL} --build=${_HOST_TRIPLET} --host=${_TRIPLET}"
  [ "${_CPU}" = 'x86' ] && _CFLAGS_GLOBAL="${_CFLAGS_GLOBAL} -fno-asynchronous-unwind-tables"

  _CCRT='libgcc'  # compiler runtime, 'libgcc' (for libgcc and libstdc++) or 'clang-rt' (for compiler-rt and libc++)
  if [ "${_TOOLCHAIN}" = 'llvm-apple' ] || \
     [ "${_TOOLCHAIN}" = 'llvm-mingw' ]; then
    # Not an option
    _CCRT='clang-rt'
  elif [ "${_CC}" = 'llvm' ]; then
    if [ "${_DISTRO}" = 'alpine' ]; then
      _CCRT='clang-rt'
    # Debian does not support clang-rt for cross-builds easily,
    # it requires manually installing package `libclang-rt-16-dev` or `libclang-common-15-dev`.
    elif [ "${_DISTRO}" = 'debian' ] && [ -d 'my-pkg/usr/lib/clang' ]; then
      # FIXME: This combination fails to link with clang-rt, due to:
      #        ld.lld-16: error: relocation R_RISCV_PCREL_HI20 cannot be used against symbol '__global_pointer$'; recompile with -fPIC
      #        >>> defined in /usr/riscv64-linux-gnu/lib/Scrt1.o
      #        >>> referenced by /usr/riscv64-linux-gnu/lib/Scrt1.o:(.text+0x2C)
      #        Our workaround is to fall back to gcc parts for this.
      if [ "${_CRT}" = 'gnu' ] && [ "${_CPU}" = 'r64' ]; then
        :
      else
        _CCRT='clang-rt'
      fi
    fi
  fi

  export _LD
  _BINUTILS_PREFIX="${_CCPREFIX}"
  _BINUTILS_SUFFIX=''
  if [ "${_CC}" = 'llvm' ]; then
    if [ "${_TOOLCHAIN}" = 'llvm-apple' ]; then
      # --target= works too, but prefer -arch for its multi-arch support (we are not using it yet)
      _CC_GLOBAL="clang${_CCSUFFIX} -arch ${_machines}"
    else
      _CC_GLOBAL="clang${_CCSUFFIX} --target=${_TRIPLET}"
    fi
    _CONFIGURE_GLOBAL="${_CONFIGURE_GLOBAL} --target=${_TRIPLET}"
    if [ -n "${_SYSROOT}" ]; then
      _CC_GLOBAL="${_CC_GLOBAL} --sysroot=${_SYSROOT}"
      _CONFIGURE_GLOBAL="${_CONFIGURE_GLOBAL} --with-sysroot=${_SYSROOT}"
    fi
    if [ "${_HOST}" = 'linux' ] && [ "${_OS}" = 'win' ]; then
      # We used to pass this via CFLAGS for CMake to make it detect llvm/clang,
      # so we need to pass this via CMAKE_C_FLAGS, though meant for the linker.
      if [ "${_TOOLCHAIN}" = 'llvm-mingw' ]; then
        _LDFLAGS_GLOBAL="${_LDFLAGS_GLOBAL} -L${CW_LLVM_MINGW_PATH}/${_TRIPLET}/lib"
      elif [ "${_CCRT}" = 'libgcc' ]; then
        # https://packages.debian.org/testing/amd64/gcc-mingw-w64-x86-64-posix/filelist
        # https://packages.debian.org/testing/amd64/gcc-mingw-w64-x86-64-win32/filelist
        # /usr/lib/gcc/x86_64-w64-mingw32/10-posix/
        # /usr/lib/gcc/x86_64-w64-mingw32/10-win32/
        # /usr/lib/gcc/x86_64-w64-mingw32/12/
        tmp="$(find "/usr/lib/gcc/${_TRIPLET}" -mindepth 1 -maxdepth 1 -type d | head -n 1 || true)"
        if [ -z "${tmp}" ]; then
          >&2 echo '! Error: Failed to detect mingw-w64 dev env root.'
          exit 1
        fi
        _LDFLAGS_GLOBAL="${_LDFLAGS_GLOBAL} -L${tmp}"
        _CXXFLAGS_GLOBAL="${_CXXFLAGS_GLOBAL} -I${tmp}/include/c++"
        _CXXFLAGS_GLOBAL="${_CXXFLAGS_GLOBAL} -I${tmp}/include/c++/${_TRIPLET}"
        _CXXFLAGS_GLOBAL="${_CXXFLAGS_GLOBAL} -I${tmp}/include/c++/backward"
      fi
    elif [ "${_HOST}" = 'linux' ] && [ "${_OS}" = 'linux' ] && [ "${unamem}" != "${_machine}" ] && [ "${_CC}" = 'llvm' ] && [ "${_CRT}" != 'musl' ]; then
      _CFLAGS_GLOBAL="${_CFLAGS_GLOBAL} -isystem /usr/${_TRIPLETSH}/include"
      _LDFLAGS_GLOBAL="${_LDFLAGS_GLOBAL} -L/usr/${_TRIPLETSH}/lib"
      if [ "${_CCRT}" = 'libgcc' ]; then
        # https://packages.debian.org/testing/all/libgcc-13-dev-arm64-cross/filelist
        # /usr/lib/gcc-cross/aarch64-linux-gnu/13/
        tmp="$(find "/usr/lib/gcc-cross/${_TRIPLETSH}" -mindepth 1 -maxdepth 1 -type d | head -n 1 || true)"
        if [ -z "${tmp}" ]; then
          >&2 echo '! Error: Failed to detect gcc-cross env root.'
          exit 1
        fi
        _LDFLAGS_GLOBAL="${_LDFLAGS_GLOBAL} -L${tmp}"
        # https://packages.debian.org/testing/all/libstdc++-13-dev-arm64-cross/filelist
        # /usr/aarch64-linux-gnu/include/c++/13/
        tmp="$(find "/usr/${_TRIPLETSH}/include/c++" -mindepth 1 -maxdepth 1 -type d | head -n 1 || true)"
        if [ -z "${tmp}" ]; then
          >&2 echo '! Error: Failed to detect g++-cross env root.'
          exit 1
        fi
        _CXXFLAGS_GLOBAL="${_CXXFLAGS_GLOBAL} -I${tmp}/include/c++"
        _CXXFLAGS_GLOBAL="${_CXXFLAGS_GLOBAL} -I${tmp}/include/c++/${_TRIPLETSH}"
        _CXXFLAGS_GLOBAL="${_CXXFLAGS_GLOBAL} -I${tmp}/include/c++/backward"
      fi
    fi

    if [ "${_TOOLCHAIN}" = 'llvm-mingw' ]; then
      # Requires llvm v16 and mingw-w64 v11 built with `--enable-cfguard`.
      # As of 2023-08, only llvm-mingw satisfies this.
      #
      # Refs:
      #   https://github.com/mstorsjo/llvm-mingw/issues/301
      #   https://gist.github.com/alvinhochun/a65e4177e2b34d551d7ecb02b55a4b0a
      #   https://github.com/mstorsjo/llvm-mingw/compare/master...alvinhochun:llvm-mingw:alvin/cfguard.diff
      #   https://github.com/mingw-w64/mingw-w64/compare/master...alvinhochun:mingw-w64:alvin/cfguard.diff
      #
      # The build is successful with standard distro llvm 16 + mingw-w64 11,
      # but executables fail to run. The linker shows this warning:
      #   ld.lld: warning: Control Flow Guard is enabled but '_load_config_used' is missing
      # Omitting linker option `-mguard=cf` makes the warning disappear, but
      # the executables fail to run anyway. It means that cfguard needs
      # llvm-mingw with all objects compiled with cfguard, and cfguard enabled
      # at link time to end up with a runnable exe.
      _CFLAGS_GLOBAL="${_CFLAGS_GLOBAL} -mguard=cf"
      _LDFLAGS_GLOBAL="${_LDFLAGS_GLOBAL} -mguard=cf"
    fi

    if [ -n "${_SYSROOT}" ]; then
      _CMAKE_GLOBAL="${_CMAKE_GLOBAL} -DCMAKE_SYSROOT=${_SYSROOT}"
    fi
    _CMAKE_GLOBAL="${_CMAKE_GLOBAL} -DCMAKE_C_COMPILER=clang${_CCSUFFIX}"
    _CMAKE_CXX_GLOBAL="${_CMAKE_CXX_GLOBAL} -DCMAKE_CXX_COMPILER=clang++${_CCSUFFIX}"

    if [ "${_TOOLCHAIN}" = 'llvm-apple' ]; then
      _LD='ld-apple'
    else
      _LD='lld'
    fi

    if [ "${_TOOLCHAIN}" != 'llvm-mingw' ] && \
       [ "${_TOOLCHAIN}" != 'llvm-apple' ]; then
      _BINUTILS_PREFIX='llvm-'
      _BINUTILS_SUFFIX="${_CCSUFFIX}"
      _LDFLAGS_GLOBAL="${_LDFLAGS_GLOBAL} -fuse-ld=lld${_CCSUFFIX}"
      if [ "${_HOST}" = 'mac' ] && [ "${_OS}" = 'win' ]; then
        _RCFLAGS_GLOBAL="${_RCFLAGS_GLOBAL} -I${_SYSROOT}/${_TRIPLET}/include"
      fi
    fi
    # Avoid warning, as seen on macOS when doing native builds with Homebrew
    # llvm v16:
    #   ld64.lld: warning: Option `-s' is obsolete. Please modernize your usage.
    #   ld: warning: option -s is obsolete and being ignored
    if [ "${_HOST}" != 'mac' ] || [ "${_OS}" != 'mac' ]; then
      _LDFLAGS_GLOBAL="${_LDFLAGS_GLOBAL} -Wl,-s"  # Omit .buildid segment with the timestamp in it
    fi

    if [ "${_OS}" = 'linux' ]; then
      _LDFLAGS_GLOBAL="${_LDFLAGS_GLOBAL} -Wl,--build-id=none"  # Omit build-id
    fi

    # Avoid warnings when passing C compiler options to the linker.
    # Use it with CMake and OpenSSL's proprietary build system.
    _CFLAGS_GLOBAL_CMAKE="${_CFLAGS_GLOBAL_CMAKE} -Wno-unused-command-line-argument"
  else
    _CC_GLOBAL="${_CCPREFIX}gcc${_CCSUFFIX}"

    if [ "${_OS}" = 'win' ]; then
      # Also accepted on linux, but does not seem to make any difference
      _CC_GLOBAL="${_CC_GLOBAL} -static-libgcc"
    fi

    if [ "${_OS}" = 'win' ]; then
      _LDFLAGS_GLOBAL="${_OPTM} ${_LDFLAGS_GLOBAL}"
      # https://lists.ffmpeg.org/pipermail/ffmpeg-devel/2015-September/179242.html
      if [ "${_CPU}" = 'x86' ]; then
        _LDFLAGS_BIN_GLOBAL="${_LDFLAGS_BIN_GLOBAL} -Wl,--pic-executable,-e,_mainCRTStartup"
      else
        _LDFLAGS_BIN_GLOBAL="${_LDFLAGS_BIN_GLOBAL} -Wl,--pic-executable,-e,mainCRTStartup"
      fi
      _CFLAGS_GLOBAL="${_OPTM} ${_CFLAGS_GLOBAL}"
    fi

    _CMAKE_GLOBAL="${_CMAKE_GLOBAL} -DCMAKE_C_COMPILER=${_CCPREFIX}gcc${_CCSUFFIX}"
    _CMAKE_CXX_GLOBAL="${_CMAKE_CXX_GLOBAL} -DCMAKE_CXX_COMPILER=${_CCPREFIX}g++${_CCSUFFIX}"

    if [ "${_OS}" = 'mac' ]; then
      _LD='ld-apple'
    else
      _LD='ld'
    fi

    _BINUTILS_SUFFIX="${_CCSUFFIX}"
  fi

  if [ "${_OS}" = 'mac' ]; then
    # Explicitly set the SDK root. This forces clang to drop /usr/local
    # from the list of default header search paths. This is necessary
    # to avoid ./configure picking up e.g. installed Homebrew package
    # headers instead of the explicitly specified custom package headers,
    # e.g. with OpenSSL.
    # We set it for all build tools for macOS to gain control over this.
    _SYSROOT="$(xcrun -sdk macosx --show-sdk-path)"  # E.g. /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk

    # Standard gcc (as of v13.2.0) fails to compile some headers in macOS SDK 13.x.
    # Issue: https://github.com/curl/curl/issues/10356
    # Revert to SDK 12.x as a workaround, e.g. /Library/Developer/CommandLineTools/SDKs/MacOSX12.sdk
    if [ "${_CC}" = 'gcc' ]; then
      tmp="$(echo "${_SYSROOT}" | sed -E 's/[0-9\.]+\.sdk$/12.sdk/g')"
      if [ -d "${tmp}" ]; then
        _SYSROOT="${tmp}"
      fi
    fi

    if [ -n "${_SYSROOT}" ]; then
      _CMAKE_GLOBAL="${_CMAKE_GLOBAL} -DCMAKE_OSX_SYSROOT=${_SYSROOT}"
      _CC_GLOBAL="${_CC_GLOBAL} --sysroot=${_SYSROOT}"
      _CONFIGURE_GLOBAL="${_CONFIGURE_GLOBAL} --with-sysroot=${_SYSROOT}"
    fi
  fi

  if [ "${_CRT}" = 'musl' ] && [ "${_DISTRO}" = 'debian' ]; then
    if [ "${_OPENSSL}" = 'quictls' ] || \
       [ "${_OPENSSL}" = 'openssl' ]; then
      # Workaround for:
      #   ../crypto/mem_sec.c:60:13: fatal error: linux/mman.h: No such file or directory
      # Based on: https://github.com/openssl/openssl/issues/7207#issuecomment-880121450
      _my_incdir='_sys_include'; rm -r -f "${_my_incdir}"; mkdir "${_my_incdir}"; _my_incdir="$(pwd)/${_my_incdir}"
      ln -s -f "/usr/include/${_HOST_TRIPLETSH}/asm" "${_my_incdir}/asm"
      ln -s -f '/usr/include/asm-generic'            "${_my_incdir}/asm-generic"
      ln -s -f '/usr/include/linux'                  "${_my_incdir}/linux"
      _CPPFLAGS_GLOBAL="${_CPPFLAGS_GLOBAL} -isystem ${_my_incdir}"
    fi
  fi

  _CMAKE_GLOBAL="${_CMAKE_GLOBAL} -DCMAKE_C_COMPILER_TARGET=${_TRIPLET}"
  _CMAKE_CXX_GLOBAL="${_CMAKE_CXX_GLOBAL} -DCMAKE_CXX_COMPILER_TARGET=${_TRIPLET}"

  # Needed to exclude compiler info from objects, but for our Windows COFF
  # outputs this seems to be a no-op as of llvm/clang 13.x/14.x.
  # Still necessary with GCC 12.1.0 though.
  if [ "${_CC}" = 'gcc' ]; then
    _CFLAGS_GLOBAL="${_CFLAGS_GLOBAL} -fno-ident"
  fi

  export _CFLAGS_GLOBAL_WPICKY
  # Picky compiler warnings as seen in curl CMake/autotools.
  # builds with llvm/clang 15 and gcc 12.2:
  #   https://clang.llvm.org/docs/DiagnosticsReference.html
  #   https://gcc.gnu.org/onlinedocs/gcc/Warning-Options.html
  _CFLAGS_GLOBAL_WPICKY='-pedantic -Wcast-align -Wconversion -Wdeclaration-after-statement -Wdouble-promotion -Wempty-body -Wendif-labels -Wenum-conversion -Wfloat-equal -Wignored-qualifiers -Winline -Wmissing-declarations -Wmissing-prototypes -Wnested-externs -Wno-format-nonliteral -Wno-long-long -Wno-multichar -Wno-sign-conversion -Wno-system-headers -Wpointer-arith -Wshadow -Wsign-compare -Wstrict-prototypes -Wtype-limits -Wundef -Wunused -Wunused-const-variable -Wvla -Wwrite-strings'
  [ "${_CC}" = 'llvm' ] && _CFLAGS_GLOBAL_WPICKY="${_CFLAGS_GLOBAL_WPICKY} -Wassign-enum -Wcomma -Wextra-semi-stmt -Wshift-sign-overflow -Wshorten-64-to-32"
  [ "${_CC}" = 'gcc'  ] && _CFLAGS_GLOBAL_WPICKY="${_CFLAGS_GLOBAL_WPICKY} -Walloc-zero -Warith-conversion -Warray-bounds=2 -Wduplicated-branches -Wduplicated-cond -Wformat-overflow=2 -Wformat-truncation=1 -Wformat=2 -Wmissing-parameter-type -Wno-pedantic-ms-format -Wnull-dereference -Wold-style-declaration -Wrestrict -Wshift-negative-value -Wshift-overflow=2 -Wstrict-aliasing=3 -fdelete-null-pointer-checks -ftree-vrp"

  # for boringssl
  export _STRIP_BINUTILS=''
  if [ "${_OS}" = 'win' ] && [ "${_CC}" = 'llvm' ]; then
    if [ "${_CPU}" = 'x64' ] || \
       [ "${_CPU}" = 'x86' ]; then
      # Make sure to pick the prefixed binutils strip tool from an unmodified
      # PATH. This avoids picking the llvm-mingw copy using the same name.
      tmp="${_CCPREFIX}strip"
      if command -v "${tmp}" >/dev/null 2>&1; then
        _STRIP_BINUTILS="$(PATH="${_ori_path}" command -v "${tmp}" 2>/dev/null)"
      else
        echo "! Warning: binutils strip tool '${tmp}' not found. BoringSSL libs may not be reproducible."
      fi
    fi
  fi

  # Used for ar, nm, ranlib
  _BINCORE_PREFIX="${_BINUTILS_PREFIX}"
  _BINCORE_SUFFIX="${_BINUTILS_SUFFIX}"

  if [ "${_CC}" = 'gcc' ] && [ -n "${_BINUTILS_SUFFIX}" ]; then
    _BINCORE_PREFIX="${_BINCORE_PREFIX}gcc-"
    _BINUTILS_SUFFIX=''
  fi

  export _STRIP_BIN
  export _STRIPFLAGS_BIN
  export _STRIPFLAGS_DYN
  export _STRIP_LIB
  export _STRIPFLAGS_LIB
  # All mac except standard llvm which uses a standard strip tool.
  # It means _CC + _TOOLCHAIN must be 'llvm' + 'llvm-apple' or 'gcc' + 'llvm-apple' or 'gcc' + '',
  # but not 'llvm' + ''.
  if [ "${_OS}" = 'mac' ] && [ "${_CC}${_TOOLCHAIN}" != 'llvm' ]; then
    # Xcode strip command-line interface is different than GNU/llvm strip.
    # Binaries are by default reproducible. After strip, they lose some
    # debug data and remain reproducible.
    _STRIP_BIN='strip'
    _STRIPFLAGS_BIN='-D'
    _STRIPFLAGS_DYN='-x'
    if [ -d "${brew_root}/opt/llvm/bin" ]; then  # check for Homebrew package
      _STRIP_LIB="${brew_root}/opt/llvm/bin/llvm-strip"
      # GNU binutils `--strip-debug` ends up outputting a static lib that is
      # unlinkable, with this error:
      #   ld: in ./libcurl.a(unity_0_c.c.o), section __DATA/__bss address out of range file './libcurl.a' for architecture x86_64
      # To prevent `strip` actually stripping anything and breaking the library,
      # I tried `--strip-dwo` instead. This strips DWARF objects, which these
      # libraries do not have. This in turn aborted with arm64 (tested with
      # arm64e) input files with this error:
      #   /usr/local/opt/binutils/bin/strip: unity_0_c.c.o: invalid operation
      # `llvm-strip` seems to work with both x86_64 and arm64e inputs. Its
      # option `--no-strip-all` results in the same output as `--strip-debug`
      # (tested with `libcurl.a`):
      _STRIPFLAGS_LIB='--enable-deterministic-archives --strip-debug'
    else
      # FIXME (upstream):
      # Apple's own strip tool chokes on arm64 static libs, with error
      #   strip: error: symbols referenced by relocation entries that can't be stripped in: [...]/usr/lib/liba.a(libcommon-lib-tls_pad.o) (for architecture arm64)
      # and then tens of thousands of lines of bogus output.
      # This was only seen on arm64 (only tested cross-builds) and quictls.
      # Replacing `strip -D` with `strip -S` fixes it, however, this does not
      # strip timestamps and other info, so we must also call `libtool -D` on
      # that. Then it turns out that `libtool -D` does a shoddy job and strips
      # these info from a couple of objects only and leaves it there for most
      # of the others. This is broken for x86_64 inputs as well, where the
      # timestamp is stripped, but not the local gid/uid. It means making a
      # macOS static lib reproducible likely needs a manual script. Well, no,
      # that method fails because `ar` always bakes the on-disk timestamp and
      # gid/uid into the .a output, with no option to disable this.
      # It means it does not seem possible to create reproducible static libs
      # with Xcode as of v14 (year 2023).
      _STRIP_LIB='echo'
      _STRIPFLAGS_LIB="${_STRIPFLAGS_BIN}"
      # Apple strip cannot create reproducible static libs due to a series of
      # bugs. Do not use.
      echo 'WARNING: Using Xcode strip. Static libraries CANNOT be made reproducible.'
    fi
  else
    _STRIP_BIN="${_BINUTILS_PREFIX}strip${_BINUTILS_SUFFIX}"
    _STRIPFLAGS_BIN='--enable-deterministic-archives --strip-all'
    _STRIPFLAGS_DYN="${_STRIPFLAGS_BIN}"
    _STRIP_LIB="${_STRIP_BIN}"
    _STRIPFLAGS_LIB='--enable-deterministic-archives --strip-debug'
  fi
  export _OBJDUMP="${_BINUTILS_PREFIX}objdump${_BINUTILS_SUFFIX}"
  export _READELF="${_BINUTILS_PREFIX}readelf${_BINUTILS_SUFFIX}"
  if [ "${_OS}" = 'win' ]; then
    export RC="${_BINUTILS_PREFIX}windres${_BINUTILS_SUFFIX}"
  fi
  if [ "${_OS}" = 'win' ] && \
     [ "${_CC}" = 'llvm' ] && \
     [ "${_TOOLCHAIN}" != 'llvm-mingw' ] && \
     [ "${_HOST}" = 'linux' ] && \
     [ -n "${_BINUTILS_SUFFIX}" ]; then
    # FIXME: llvm-windres present, but unable to find its clang counterpart
    #        when suffixed:
    #          llvm-windres-16 -O coff  --target=pe-x86-64 -I../include -i libcurl.rc -o x86_64-w64-windows-gnu/libcurl.res
    #          llvm-rc: Unable to find clang, skipping preprocessing.
    #          Pass --no-preprocess to disable preprocessing. This will be an error in the future.
    #          https://reviews.llvm.org/D100755
    #          https://github.com/llvm/llvm-project/blob/main/llvm/tools/llvm-rc/llvm-rc.cpp
    #          https://github.com/msys2/MINGW-packages/discussions/8736
    #        Partially fixed in v16.0.2, additional fix pending for v17.0.0:
    #          https://reviews.llvm.org/D157241
    #          https://github.com/curl/curl-for-win/commit/caaae171ac43af5b883403714dafd42030d8de61
    RC="$(pwd)/${RC}"
    ln -s -f "/usr/bin/${_BINUTILS_PREFIX}rc${_BINUTILS_SUFFIX}" "${RC}"
    # llvm-windres/llvm-rc wants to find clang on the same path as itself
    # (or in PATH), with the hard-wired name of clang (or <TRIPLET>-clang,
    # or clang-cl). Workaround: create an alias for it:
    ln -s -f "/usr/bin/clang${_CCSUFFIX}" "$(pwd)/clang"
  fi
  export AR="${_BINCORE_PREFIX}ar${_BINCORE_SUFFIX}"
  export NM="${_BINCORE_PREFIX}nm${_BINCORE_SUFFIX}"
  export RANLIB="${_BINCORE_PREFIX}ranlib${_BINCORE_SUFFIX}"

  # ar wrapper to normalize created libs
  if [ "${CW_DEV_CROSSMAKE_REPRO:-}" = '1' ]; then
    export AR_NORMALIZE
    AR_NORMALIZE="$(pwd)/ar-wrapper-normalize"
    {
      echo '#!/bin/sh -e'
      echo "'${AR}' \"\$@\""
      echo "'$(pwd)/_clean-lib.sh' --ar '${AR}' \"\$@\""
    } > "${AR_NORMALIZE}"
    chmod +x "${AR_NORMALIZE}"
  fi

  if [ "${_OS}" = 'win' ] && [ "${_HOST}" = 'mac' ]; then
    if [ "${_TOOLCHAIN}" = 'llvm-mingw' ]; then
      _CMAKE_GLOBAL="${_CMAKE_GLOBAL} -DCMAKE_AR=${CW_LLVM_MINGW_PATH}/bin/${AR}"
    elif [ "${_CC}" = 'llvm' ]; then
      _CMAKE_GLOBAL="${_CMAKE_GLOBAL} -DCMAKE_AR=${_MAC_LLVM_PATH}/${AR}"
    else
      _CMAKE_GLOBAL="${_CMAKE_GLOBAL} -DCMAKE_AR=${_SYSROOT}/bin/${AR}"
    fi
  fi

  # Workaround for gcc 13 mis-selecting its own dynamic linker, instead
  # of using the musl one:
  #   `-dynamic-linker /lib/ld-linux-riscv64-lp64d.so.1`
  if [ "${_CC}" = 'gcc' ] && [ "${_CRT}" = 'musl' ] && [ "${_DISTRO}" = 'debian' ] && [ "${_CPU}" = 'r64' ]; then
    _LDFLAGS_GLOBAL="${_LDFLAGS_GLOBAL} -Wl,--dynamic-linker=/lib/ld-musl-${_machine}.so.1"
  fi

  if [ "${_CCRT}" = 'libgcc' ] && [ "${_CRT}" = 'musl' ] && [ "${_DISTRO}" = 'debian' ]; then
    if [ "${_CC}" = 'gcc' ]; then
      ccrtlib="$("${_CCPREFIX}gcc${_CCSUFFIX}" -print-libgcc-file-name)"               # /usr/lib/gcc/aarch64-linux-gnu/12/libgcc.a
      ccrsdir="$(dirname "${ccrtlib}")"                                                # /usr/lib/gcc/aarch64-linux-gnu/12
      ccrtlib="$(basename "${ccrtlib}" | cut -c 4-)"  # delete 'lib' prefix
      ccrtlib="-l${ccrtlib%.*}"  # 'gcc'
      ccridir="${ccrsdir}"
    else
      if [ "${unamem}" = "${_machine}" ]; then
        gccroot="/usr/lib/gcc/${_TRIPLETSH}"        # /usr/lib/gcc/aarch64-linux-gnu/12
      else  # cross
        gccroot="/usr/lib/gcc-cross/${_TRIPLETSH}"  # /usr/lib/gcc-cross/x86_64-linux-gnu/12
      fi
      ccrtdir="$(find "${gccroot}" -mindepth 1 -maxdepth 1 -type d | sort | tail -n 1 || true)"
      if [ -z "${ccrtdir}" ]; then
        >&2 echo '! Error: Failed to detect gcc env root.'
        exit 1
      fi
      ccrsdir="${ccrtdir}"
      ccrtlib="-lgcc -lgcc_eh"
      _LDFLAGS_CXX_GLOBAL="${_LDFLAGS_CXX_GLOBAL} -nostdlib++"
      ccridir="$("clang${_CCSUFFIX}" -print-resource-dir)"                             # /usr/lib/llvm-13/lib/clang/13.0.1
    fi
    libprefix="/usr/lib/${_machine}-linux-musl"
    _CFLAGS_GLOBAL="${_CFLAGS_GLOBAL} -static -nostdinc -isystem ${ccridir}/include -isystem /usr/include/${_machine}-linux-musl"
    _LDFLAGS_GLOBAL="${_LDFLAGS_GLOBAL} -nostartfiles -L${libprefix} -Wl,${libprefix}/Scrt1.o -Wl,${libprefix}/crti.o -L${ccrsdir} -Wl,${libprefix}/crtn.o"
    _LIBS_GLOBAL="${_LIBS_GLOBAL} -lc ${ccrtlib}"
  fi

  if [ "${_CCRT}" = 'clang-rt' ]; then
    if [ "${_TOOLCHAIN}" != 'llvm-apple' ]; then
      if [ "${_CRT}" = 'musl' ] && [ "${_DISTRO}" = 'debian' ]; then
        # This method should also work to replace the `_CCPREFIX='musl-'` solution we use with gcc.
        ccrsdir="$("clang${_CCSUFFIX}" -print-resource-dir)"                           # /usr/lib/llvm-13/lib/clang/13.0.1
        if [ "${unamem}" = "${_machine}" ]; then
          ccrtdir="$("clang${_CCSUFFIX}" -print-runtime-dir)"                          # /usr/lib/llvm-13/lib/clang/13.0.1/lib/linux
          ccrtlib="$("clang${_CCSUFFIX}" -print-libgcc-file-name -rtlib=compiler-rt)"  # /usr/lib/llvm-13/lib/clang/13.0.1/lib/linux/libclang_rt.builtins-aarch64.a
          ccrtlib="$(basename "${ccrtlib}" | cut -c 4-)"  # delete 'lib' prefix
          ccrtlib="-l${ccrtlib%.*}"  # clang_rt.builtins-aarch64 or gcc
        elif [ -d 'my-pkg/usr/lib/clang' ]; then  # cross
          # If we have the target CPU's clang-rt package installed, use it:
          ccrtdir="$(find -L \
            "$(pwd)/my-pkg/usr/lib/clang" -mindepth 1 -maxdepth 1 -type d | sort | tail -n 1 || true)"  # ./my-pkg/usr/lib/clang/15/lib/linux
          if [ -z "${ccrtdir}" ]; then
            >&2 echo '! Error: Failed to detect cross-clang-rt env root.'
            exit 1
          fi
          ccrtdir="${ccrtdir}/lib/linux"
          ccrtlib="${ccrtdir}/libclang_rt.builtins-${_machine}.a"
          ccrtlib="$(basename "${ccrtlib}" | cut -c 4-)"  # delete 'lib' prefix
          ccrtlib="-l${ccrtlib%.*}"  # clang_rt.builtins-aarch64 or gcc
        else  # cross
          # Fall back to libgcc because I could not figure out how to install the
          # cross-clangrt package on Debian (providing `libclang_rt.builtins-x86_64.a`)
          # with `apt install libclang-common-15-dev:amd64`.
          # The error is:
          #   "The following packages have unmet dependencies"
          ccrtdir="$(find "/usr/lib/gcc-cross/${_TRIPLETSH}" -mindepth 1 -maxdepth 1 -type d | sort | tail -n 1 || true)"  # /usr/lib/gcc-cross/x86_64-linux-gnu/12
          if [ -z "${ccrtdir}" ]; then
            >&2 echo '! Error: Failed to detect gcc-cross env root.'
            exit 1
          fi
          ccrtlib="-lgcc -lgcc_eh"
        fi
        libprefix="/usr/lib/${_machine}-linux-musl"
        _CFLAGS_GLOBAL="${_CFLAGS_GLOBAL} -nostdinc -isystem ${ccrsdir}/include -isystem /usr/include/${_machine}-linux-musl"
        _LDFLAGS_GLOBAL="${_LDFLAGS_GLOBAL} -nostdlib -nodefaultlibs -nostartfiles -L${libprefix} ${libprefix}/crt1.o ${libprefix}/crti.o -L${ccrtdir} ${libprefix}/crtn.o"
        _LIBS_GLOBAL="${_LIBS_GLOBAL} -lc ${ccrtlib}"
      else
        if [ "${_DISTRO}" = 'debian' ] && [ "${unamem}" != "${_machine}" ] && [ -d 'my-pkg/usr/lib/clang' ]; then
          # If we have the target CPU's clang-rt package installed, use it:
          ccrtdir="$(find -L \
            "$(pwd)/my-pkg/usr/lib/clang" -mindepth 1 -maxdepth 1 -type d | sort | tail -n 1)"  # ./my-pkg/usr/lib/clang/15/lib/linux
          if [ -z "${ccrtdir}" ]; then
            >&2 echo '! Error: Failed to detect cross-clang-rt env root.'
            exit 1
          fi
          ccrtdir="${ccrtdir}/lib/linux"
          ccrtlib="${ccrtdir}/libclang_rt.builtins-${_machine}.a"
          ccrtlib="$(basename "${ccrtlib}" | cut -c 4-)"  # delete 'lib' prefix
          ccrtlib="-l${ccrtlib%.*}"  # clang_rt.builtins-aarch64 or gcc
          libprefix="/usr/${_TRIPLETSH}/lib"
          _LDFLAGS_GLOBAL="${_LDFLAGS_GLOBAL} -nodefaultlibs -L${libprefix} -L${ccrtdir}"
          # lld by default wants to load startfiles from:
          #   /usr/bin/../lib/gcc-cross/x86_64-linux-gnu/12/../../../../x86_64-linux-gnu/lib/
          # or similar. Manually specify the ones belonging to glibc.
          _LDFLAGS_GLOBAL="${_LDFLAGS_GLOBAL} -nostartfiles ${libprefix}/Scrt1.o ${libprefix}/crti.o ${libprefix}/crtn.o"
          _LIBS_GLOBAL="${_LIBS_GLOBAL} -lc ${ccrtlib}"
        fi
        _LDFLAGS_GLOBAL="${_LDFLAGS_GLOBAL} -rtlib=compiler-rt"
        # `-Wc,...` is necessary for libtool to pass this option to the compiler
        # at link-time. Otherwise libtool strips it.
        #   https://www.gnu.org/software/libtool/manual/html_node/Stripped-link-flags.html
        _LDFLAGS_GLOBAL_AUTOTOOLS="${_LDFLAGS_GLOBAL_AUTOTOOLS} -Wc,-rtlib=compiler-rt"
      fi
      _LDFLAGS_CXX_GLOBAL="${_LDFLAGS_CXX_GLOBAL} -nostdlib++"
    fi
  else
    if [ "${_OS}" = 'win' ]; then
      # Also accepted on linux, but does not seem to make any difference
      _LDFLAGS_GLOBAL="${_LDFLAGS_GLOBAL} -static-libgcc"
      _LDFLAGS_CXX_GLOBAL="${_LDFLAGS_CXX_GLOBAL} -static-libstdc++"
    fi
  fi

  _CONFIGURE_GLOBAL="${_CONFIGURE_GLOBAL} --prefix=${_PREFIX} --disable-dependency-tracking --disable-silent-rules"

  # Unified, per-target package: Initialize
  export _UNIPKG="curl-${CURL_VER_}${_REVSUFFIX}${_PKGSUFFIX}${_FLAV}"
  rm -r -f "${_UNIPKG:?}"
  mkdir -p "${_UNIPKG}"
  export _UNIMFT="${_UNIPKG}/BUILD-MANIFEST.txt"

  # Detect versions
  clangver=''
  if [ "${_TOOLCHAIN}" = 'llvm-apple' ]; then
    clangver="clang-apple ${ccver}"
  elif [ "${_CC}" = 'llvm' ]; then
    clangver="clang ${ccver}"
  fi

  mingwver=''
  mingwurl=''
  libgccver=''
  libcver=''
  versuffix=''
  if [ "${_OS}" = 'win' ]; then
    if [ "${_TOOLCHAIN}" = 'llvm-mingw' ]; then
      mingwver='llvm-mingw'
      [ -f "${mingwver}/__url__.txt" ] && mingwurl=" $(cat "${mingwver}/__url__.txt")"
      mingwver="${mingwver} ${CW_LLVM_MINGW_VER_:-?}"
      versuffix="${versuffix_llvm_mingw}"
    else
      case "${_HOST}" in
        mac)
          mingwver="$(HOMEBREW_NO_AUTO_UPDATE=1 HOMEBREW_NO_INSTALL_FROM_API=1 brew info --json=v2 --formula mingw-w64 | jq --raw-output '.formulae[] | select(.name == "mingw-w64") | .versions.stable')";;
        linux)
          [ -n "${mingwver}" ] || mingwver="$(dpkg-query --showformat='${Version}' --show mingw-w64-common || true)"
          [ -n "${mingwver}" ] || mingwver="$(rpm --query --queryformat '.%{VERSION}' mingw64-crt || true)"
          if [ -z "${mingwver}" ]; then
            [ -n "${mingwver}" ] || mingwver="$(pacman --query --info mingw-w64-crt || true)"
            [ -n "${mingwver}" ] || mingwver="$(apk    info --webpage mingw-w64-crt || true)"
            [ -n "${mingwver}" ] && mingwver="$(printf '%s' "${mingwver}" | grep -a -E '(^Version|webpage:)' | grep -a -m1 -o -E '[0-9][0-9.]*' | head -n 1 || true)"
          fi
          ;;
      esac
      [ -n "${mingwver}" ] && mingwver="mingw-w64 ${mingwver}"
      versuffix="${versuffix_non_llvm_mingw}"
    fi
  elif [ "${_OS}" = 'linux' ]; then
    if [ "${_CC}" = 'llvm' ] && [ "${_CCRT}" = 'libgcc' ]; then
      if [ "${unamem}" = "${_machine}" ]; then
        [ -n "${libgccver}" ] || libgccver="$(dpkg-query --showformat='${Version}' --show 'libgcc-*-dev' || true)"
        [ -n "${libgccver}" ] || libgccver="$(rpm --query --queryformat '.%{VERSION}' libgcc || true)"
        if [ -z "${libgccver}" ]; then
          [ -n "${libgccver}" ] || libgccver="$(pacman --query --info gcc-libs || true)"
          [ -n "${libgccver}" ] || libgccver="$(apk    info --webpage libgcc || true)"
          [ -n "${libgccver}" ] && libgccver="$(printf '%s' "${libgccver}" | grep -a -E '(^Version|webpage:)' | grep -a -m1 -o -E '[0-9][0-9.]*' | head -n 1 || true)"
        fi
      else
        [ -n "${libgccver}" ] || libgccver="$(dpkg-query --showformat='${Version}' --show 'libgcc-*-dev-*-cross' || true)"
      fi
      [ -n "${libgccver}" ] && libgccver="libgcc ${libgccver}"
    fi

    if [ "${_CRT}" = 'musl' ]; then
      if [ "${_HOST}" = 'mac' ]; then
        # Terrible hack to retrieve musl version
        libcver="$(grep -a -m1 -o -E '\x00[0-9]+\.[0-9]+\.[0-9]+\x00' "${brew_root}/opt/musl-cross/libexec/${_machine}-linux-musl/lib/libc.so" | head -n 1 || true)"
      fi
      [ -n "${libcver}" ] || libcver="$(dpkg-query --showformat='${Version}\n' --show musl | head -n -1 || true)"
      [ -n "${libcver}" ] || libcver="$(rpm --query --queryformat '.%{VERSION}' musl-devel || true)"
      if [ -z "${libcver}" ]; then
        [ -n "${libcver}" ] || libcver="$(pacman --query --info musl || true)"
        [ -n "${libcver}" ] || libcver="$(apk    info --webpage musl || true)"
        [ -n "${libcver}" ] && libcver="$(printf '%s' "${libcver}" | grep -a -E '(^Version|webpage:)' | grep -a -m1 -o -E '[0-9][0-9.]*' | head -n 1 || true)"
      fi
      [ -n "${libcver}" ] && libcver="musl ${libcver}"
    else
      # FIXME: Debian-specific
      # There is no installed glibc package. Check for the non-installed source package instead.
      libcver="$(apt-cache show --no-all-versions 'glibc-source' | grep -a -o -E 'Version: [0-9]+\.[0-9]+' | cut -c 10- || true)"
      [ -n "${libcver}" ] && libcver="glibc ${libcver}"
    fi
  fi

  binver=''
  if [ "${_CC}" = 'gcc' ]; then
    # '|| true' added to workaround 141 pipe failures on Alpine
    # after grep successfully parsing the version number.
    # https://stackoverflow.com/questions/19120263/why-exit-code-141-with-grep-q
    binver="binutils $("${_STRIP_BIN}" --version | grep -m1 -o -a -E '[0-9]+\.[0-9]+(\.[0-9]+)?' || true)"
  elif [ "${_TOOLCHAIN}" != 'llvm-apple' ] && \
       [ -n "${_STRIP_BINUTILS}" ] && \
       [ "${boringssl}" = '1' ]; then
    binver="binutils $("${_STRIP_BINUTILS}" --version | grep -m1 -o -a -E '[0-9]+\.[0-9]+(\.[0-9]+)?' || true)"
  elif [ "${_TOOLCHAIN}" = 'llvm-apple' ] && \
       [ "${_STRIP_LIB}" != "${_STRIP_BIN}" ] && \
       [ "${_STRIP_LIB}" != 'echo' ]; then
    # `llvm-strip` used on static libs as a replacement for Xcode strip
    binver="llvm-strip $("${_STRIP_LIB}" --version | grep -m1 -o -a -E '[0-9]+\.[0-9]+(\.[0-9]+)?' || true)"
  fi

  nasmver=''
  if [ "${boringssl}" = '1' ] && [ "${_OS}" = 'win' ]; then
    nasmver="nasm $(nasm --version | grep -o -a -E '[0-9]+\.[0-9]+(\.[0-9]+)?')"
  fi

  gccver=''
  [ "${_CC}" = 'llvm' ] || gccver="gcc ${ccver}"

  {
    [ -n "${_COMMIT}" ]   && echo ".${_SELF} ${_COMMIT_SHORT}"
    [ -n "${clangver}" ]  && echo ".${clangver}${versuffix}"
    [ -n "${gccver}" ]    && echo ".${gccver}${versuffix}"
    [ -n "${libgccver}" ] && echo ".${libgccver}"
    [ -n "${libcver}" ]   && echo ".${libcver}"
    [ -n "${mingwver}" ]  && echo ".${mingwver}${versuffix}"
    [ -n "${binver}" ]    && echo ".${binver}"
    [ -n "${nasmver}" ]   && echo ".${nasmver}"
  } >> "${_BLD}"

  {
    [ -n "${_COMMIT}" ]   && echo ".${_SELF} ${_COMMIT_SHORT} ${_TAR}"
    [ -n "${clangver}" ]  && echo ".${clangver}${versuffix}"
    [ -n "${gccver}" ]    && echo ".${gccver}${versuffix}"
    [ -n "${libgccver}" ] && echo ".${libgccver}"
    [ -n "${libcver}" ]   && echo ".${libcver}"
    [ -n "${mingwver}" ]  && echo ".${mingwver}${mingwurl}${versuffix}"
    [ -n "${binver}" ]    && echo ".${binver}"
    [ -n "${nasmver}" ]   && echo ".${nasmver}"
  } >> "${_URLS}"

  {
    [ -n "${clangver}" ]  && echo ".${clangver}"
    [ -n "${gccver}" ]    && echo ".${gccver}"
    [ -n "${libgccver}" ] && echo ".${libgccver}"
    [ -n "${libcver}" ]   && echo ".${libcver}"
    [ -n "${mingwver}" ]  && echo ".${mingwver}${mingwurl}"
  } >> "${_UNIMFT}"

  bld zlib                 "${ZLIB_VER_}"
  bld zlibng             "${ZLIBNG_VER_}" zlib
  bld zstd                 "${ZSTD_VER_}"
  bld brotli             "${BROTLI_VER_}"
  bld cares               "${CARES_VER_}"
  bld libunistring "${LIBUNISTRING_VER_}"
  bld libiconv         "${LIBICONV_VER_}"
  bld libidn2           "${LIBIDN2_VER_}"
  bld libpsl             "${LIBPSL_VER_}"
  bld nghttp3           "${NGHTTP3_VER_}"
  bld wolfssl           "${WOLFSSL_VER_}"
  bld mbedtls           "${MBEDTLS_VER_}"
  bld awslc               "${AWSLC_VER_}" boringssl
  bld boringssl       "${BORINGSSL_VER_}"
  bld libressl         "${LIBRESSL_VER_}"
  bld quictls           "${QUICTLS_VER_}" openssl
  bld openssl           "${OPENSSL_VER_}"
  bld gsasl               "${GSASL_VER_}"
  bld ngtcp2             "${NGTCP2_VER_}"
  bld nghttp2           "${NGHTTP2_VER_}"
  bld wolfssh           "${WOLFSSH_VER_}"
  bld libssh             "${LIBSSH_VER_}"
  bld libssh2           "${LIBSSH2_VER_}"
  bld cacert             "${CACERT_VER_}"
  bld curl                 "${CURL_VER_}"
  bld trurl               "${TRURL_VER_}"

  # Unified, per-target package: Build
  export _NAM="${_UNIPKG}"
  export _VER="${CURL_VER_}"
  export _OUT="${_UNIPKG}"
  export _BAS="${_UNIPKG}"
  export _DST="${_UNIPKG}"

  _ref='curl/CHANGES'

  if [ ! -f "${_ref}" ]; then
    # This can happen with CW_BLD partial builds.
    echo '! WARNING: curl build missing. Skip packaging.'
  else
    touch -c -r "${_ref}" "${_UNIMFT}"

    (
      cd "${_DST}"
      set +x
      _fn='BUILD-HASHES.txt'
      {
        find . -type f | grep -a -E '/(bin|include|lib)/' | sort | while read -r f; do
          openssl dgst -sha256 "${f}"
        done
      } | sed 's/^SHA256/SHA2-256/g' > "${_fn}"
      touch -c -r "../${_ref}" "${_fn}"
    )

    if [ "${_OS}" = 'win' ]; then
      _fn="${_DST}/BUILD-README.url"
      cat <<EOF | sed 's/$/\x0d/' > "${_fn}"
[InternetShortcut]
URL=${_URL_BASE}
EOF
    elif [ "${_OS}" = 'mac' ]; then
      _fn="${_DST}/BUILD-README.webloc"
      cat <<EOF > "${_fn}"
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>URL</key>
  <string>${_URL_BASE}</string>
</dict>
</plist>
EOF
    else
      _fn="${_DST}/BUILD-README-URL.txt"
      echo "${_URL_BASE}" > "${_fn}"
    fi
    touch -c -r "${_ref}" "${_fn}"

    ./_pkg.sh "${_ref}" 'unified'
  fi
}

# Build binaries
if [ "${_OS}" = 'win' ]; then
  if [ "${_CONFIG#*a64*}" = "${_CONFIG}" ] && \
     [ "${_CONFIG#*x86*}" = "${_CONFIG}" ]; then
    build_single_target x64
  fi
  if [ "${_CONFIG#*x64*}" = "${_CONFIG}" ] && \
     [ "${_CONFIG#*x86*}" = "${_CONFIG}" ]; then
    build_single_target a64
  fi
  if [ "${_CONFIG#*x64*}" = "${_CONFIG}" ] && \
     [ "${_CONFIG#*a64*}" = "${_CONFIG}" ]; then
    build_single_target x86
  fi
elif [ "${_OS}" = 'mac' ]; then
  # TODO: This method is suboptimal. We might want to build pure C
  #       projects in dual mode and only manual-merge libs that have
  #       ASM components.
  if [ "${_CONFIG#*x64*}" = "${_CONFIG}" ]; then
    build_single_target a64
  fi
  if [ "${_CONFIG#*a64*}" = "${_CONFIG}" ]; then
    build_single_target x64
  fi
  if [ "${_CONFIG#*x64*}" = "${_CONFIG}" ] && \
     [ "${_CONFIG#*a64*}" = "${_CONFIG}" ] && \
     [ "${_CONFIG#*macuni*}" != "${_CONFIG}" ]; then
    ./_macuni.sh
  fi
elif [ "${_OS}" = 'linux' ]; then
  if [ "${_HOST}" = 'mac' ]; then
    # Custom installs of musl-cross can support a64 and other targets
    if [ "${_CONFIG#*a64*}" = "${_CONFIG}" ] && \
       command -v x86_64-linux-musl-gcc >/dev/null 2>&1; then
      build_single_target x64
    fi
    if [ "${_CONFIG#*x64*}" = "${_CONFIG}" ] && \
       command -v aarch64-linux-musl-gcc >/dev/null 2>&1; then
      build_single_target a64
    fi
  elif [ "${_DISTRO}" = 'alpine' ]; then
    # No trivial cross-builds with alpine-musl
    if [ "${unamem}" = 'aarch64' ]; then
      build_single_target a64
    elif [ "${unamem}" = 'x86_64' ]; then
      build_single_target x64
    fi
  else
    if [ "${_CONFIG#*r64*}" != "${_CONFIG}" ]; then
      build_single_target r64  # Experimental
    fi
    if [ "${_CONFIG#*x64*}" = "${_CONFIG}" ] && \
       [ "${_CONFIG#*r64*}" = "${_CONFIG}" ]; then
      build_single_target a64
    fi
    if [ "${_CONFIG#*a64*}" = "${_CONFIG}" ] && \
       [ "${_CONFIG#*r64*}" = "${_CONFIG}" ]; then
      build_single_target x64
    fi
  fi
fi

case "${_HOST}" in
  mac)   rm -f -P "${SIGN_CODE_KEY}";;
  linux) [ -w "${SIGN_CODE_KEY}" ] && srm "${SIGN_CODE_KEY}";;
esac
rm -f "${SIGN_CODE_KEY}"

# Upload/deploy binaries
. ./_ul.sh
