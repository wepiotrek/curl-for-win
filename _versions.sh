#!/bin/sh

# NOTE: Bump nghttp3 and ngtcp2 together with curl.

export CURL_VER_='7.84.0'
export CURL_HASH=2d118b43f547bfe5bae806d8d47b4e596ea5b25a6c1f080aef49fbcd817c5db8
export BROTLI_VER_='1.0.9'
export BROTLI_HASH=f9e8d81d0405ba66d181529af42a3354f838c939095ff99930da6aa9cdf6fe46
export CARES_VER_='1.17.2'
export CARES_HASH=4803c844ce20ce510ef0eb83f8ea41fa24ecaae9d280c468c582d2bb25b3913d
export LIBGSASL_VER_='1.10.0'
export LIBGSASL_HASH=f1b553384dedbd87478449775546a358d6f5140c15cccc8fb574136fdc77329f
export LIBUNISTRING_VER_='1.0'
export LIBUNISTRING_HASH=5bab55b49f75d77ed26b257997e919b693f29fd4a1bc22e0e6e024c246c72741
export LIBICONV_VER_='1.17'
export LIBICONV_HASH=8f74213b56238c85a50a5329f77e06198771e70dd9a739779f4c02f65d971313
export LIBIDN2_VER_='2.3.3'
export LIBIDN2_HASH=f3ac987522c00d33d44b323cae424e2cffcb4c63c6aa6cd1376edacbf1c36eb0
export LIBPSL_VER_='0.21.1'
export LIBPSL_HASH=ac6ce1e1fbd4d0254c4ddb9d37f1fa99dec83619c1253328155206b896210d4c
export WOLFSSH_VER_='1.4.10'
export WOLFSSH_HASH=56d0720415070e293fa7e6e83c683653db9a56344d751536ce616a11b905e6ce
export LIBSSH_VER_='0.9.6'
export LIBSSH_HASH=86bcf885bd9b80466fe0e05453c58b877df61afa8ba947a58c356d7f0fab829b
export LIBSSH2_VER_='1.10.0'
export LIBSSH2_HASH=2d64e90f3ded394b91d3a2e774ca203a4179f69aebee03003e5a6fa621e41d51
export NGHTTP2_VER_='1.49.0'
export NGHTTP2_HASH=b0cfd492bbf0b131c472e8f6501c9f4ee82b51b68130f47b278c0b7c9848a66e
export NGHTTP3_VER_='0.6.0'
export NGHTTP3_HASH=6a8fea4cdc5387458d274f66efde65681e36209f6cae038393e04cdcf9c1036f
export NGTCP2_VER_='0.7.0'
export NGTCP2_HASH=cccdf0381acc82bf8e2a3a2fe99de66b6123c5a01798db4b2a4f35bbdf606bd3
#export NGHTTP3_VER_='0.7.0'
#export NGHTTP3_HASH=05153840d9986790c00fc66037ac2fb2ed644789f4fb47568e2410ec5b1f2315
#export NGTCP2_VER_='0.8.0'
#export NGTCP2_HASH=c032715f7075cc6228f9de1ee87a3e334a17783f1ffecc6180855a1b3af5cde4
export WOLFSSL_VER_='5.4.0'
export WOLFSSL_HASH=dc36cc19dad197253e5c2ecaa490c7eef579ad448706e55d73d79396e814098b
export MBEDTLS_VER_='3.2.1'
export MBEDTLS_HASH=d0e77a020f69ad558efc660d3106481b75bd3056d6301c31564e04a0faae88cc
export OPENSSL_QUIC_VER_='3.0.5'
export OPENSSL_QUIC_HASH=766878d2c97d13ea36254ae3b1bf553939ac111f3f1b3449b8d777aca7671366
export OPENSSL_VER_='3.0.5'
export OPENSSL_HASH=aa7d8d9bef71ad6525c55ba11e5f4397889ce49c2c9349dcea6d3e4f0b024a7a
export BORINGSSL_VER_='adaa322b63d1bfbd1abcf4a308926a9a83a6acbe'
export BORINGSSL_HASH=d0f86ed5eed60fd8e5b2705806e7242b38e628767f3afdf1f19e751ecc848a48
export LIBRESSL_VER_='3.5.3'
export LIBRESSL_HASH=3ab5e5eaef69ce20c6b170ee64d785b42235f48f2e62b095fca5d7b6672b8b28
export ZLIBNG_VER_='2.0.6'
export ZLIBNG_HASH=8258b75a72303b661a238047cb348203d88d9dddf85d480ed885f375916fcab6
export ZLIB_VER_='1.2.12'
export ZLIB_HASH=7db46b8d7726232a621befaab4a1c870f00a90805511c0e0090441dac57def18
export ZSTD_VER_='1.5.2'
export ZSTD_HASH=7c42d56fac126929a6a85dbc73ff1db2411d04f104fae9bdea51305663a83fd0
export LLVM_MINGW_LINUX_VER_='20220323'
export LLVM_MINGW_LINUX_HASH=6d69ab28a3a9a2b7159178ff11cae8545fd44c9343573900fcf60434539695d8
export LLVM_MINGW_MAC_VER_="${LLVM_MINGW_LINUX_VER_}"
export LLVM_MINGW_MAC_HASH=5ccfd9ebe3ecf4b1f682cc3303af93e70b7977c86e32faa8e0c212e8f674b8cd
export LLVM_MINGW_WIN_VER_="${LLVM_MINGW_LINUX_VER_}"
export LLVM_MINGW_WIN_HASH=3014a95e4ec4d5c9d31f52fbd6ff43174a0d9c422c663de7f7be8c2fcc9d837a
export PEFILE_VER_='2022.5.30'

# Create revision string
# NOTE: Set _REV to empty after bumping CURL_VER_, and
#       set it to 1 then increment by 1 each time bumping a dependency
#       version or pushing a CI rebuild for the main branch.
export _REV='10'
