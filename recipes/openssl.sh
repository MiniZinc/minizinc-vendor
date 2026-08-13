#!/bin/bash
# Stage the prebuilt Windows OpenSSL DLLs from resources/openssl-win64 into the
# vendor tree. Published as a normal dependency because the IDE's Windows
# installer needs libssl/libcrypto; the old pipeline injected them during the
# compose step, which per-dependency releases do not have.
#
# Env: DEP_VERSION, CI_PROJECT_DIR
set -e
set -x

: "${DEP_VERSION:?DEP_VERSION must be set}"
: "${CI_PROJECT_DIR:?CI_PROJECT_DIR must be set}"

SRC="$CI_PROJECT_DIR/resources/openssl-win64"
DST="$CI_PROJECT_DIR/vendor/openssl"

[ -d "$SRC" ] || { echo "missing $SRC" >&2; exit 1; }

mkdir -p "$DST"
cp -a "$SRC/." "$DST/"

ls "$DST"/*.dll >/dev/null
