#!/bin/bash
# "Build" OpenSSL for Windows: the runtime DLLs are prebuilt and checked in under
# resources/openssl-win64, so this recipe only stages them into the vendor tree.
#
# They are published as an ordinary per-dependency release asset because the
# MiniZinc IDE's Windows installer needs libssl/libcrypto next to the compiler.
# The old GitLab pipeline injected them into `bundle-win64` during a compose
# step; per-dependency releases have no compose step, so without this the DLLs
# would never reach any consumer.
#
# Inputs (environment):
#   DEP_VERSION    OpenSSL version the checked-in DLLs correspond to
#   CI_PROJECT_DIR build root
set -e
set -x

: "${DEP_VERSION:?DEP_VERSION must be set}"
: "${CI_PROJECT_DIR:?CI_PROJECT_DIR must be set}"

SRC="$CI_PROJECT_DIR/resources/openssl-win64"
DST="$CI_PROJECT_DIR/vendor/openssl"

[ -d "$SRC" ] || { echo "missing $SRC" >&2; exit 1; }

mkdir -p "$DST"
cp -a "$SRC/." "$DST/"

# Fail loudly rather than publishing an empty archive.
ls "$DST"/*.dll >/dev/null
