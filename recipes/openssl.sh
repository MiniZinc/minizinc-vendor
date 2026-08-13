#!/bin/bash
# Stage the OpenSSL runtime DLLs the MiniZinc IDE's Windows installer bundles.
#
# Downloads the "Light" MSI from slproweb.com (the de-facto Windows OpenSSL
# build; upstream ships no binaries) and extracts just the two DLLs. The MSI is
# verified against a sha256 pinned in dependencies.toml.
#
# Note slproweb only keeps the newest patch release per branch, so a pinned
# version eventually 404s and has to be bumped; the update bot tracks this.
#
# Env: DEP_VERSION, MZNARCH, OPENSSL_MSI, OPENSSL_SHA256, CI_PROJECT_DIR
set -e
set -x

: "${DEP_VERSION:?DEP_VERSION must be set}"
: "${OPENSSL_MSI:?OPENSSL_MSI must be set}"
: "${OPENSSL_SHA256:?OPENSSL_SHA256 must be set}"
: "${CI_PROJECT_DIR:?CI_PROJECT_DIR must be set}"

DST="$CI_PROJECT_DIR/vendor/openssl"
WORK="$CI_PROJECT_DIR/.openssl"
rm -rf "$WORK" && mkdir -p "$WORK" "$DST"

curl -sSLo "$WORK/openssl.msi" "https://slproweb.com/download/${OPENSSL_MSI}"

echo "${OPENSSL_SHA256} *$WORK/openssl.msi" | sha256sum -c -

# An administrative install unpacks the MSI without installing it. TARGETDIR
# must be a Windows-style path.
msiexec //a "$(cygpath -w "$WORK/openssl.msi")" //qn TARGETDIR="$(cygpath -w "$WORK/out")"

# The DLL names carry the ABI version and the arch (e.g. libcrypto-3-x64.dll,
# libcrypto-3-arm64.dll), so copy whatever the installer produced.
find "$WORK/out" -name 'libcrypto-*.dll' -o -name 'libssl-*.dll' | while read -r f; do
	cp "$f" "$DST/"
done
find "$WORK/out" -iname 'LICENSE*' -o -iname '*license*.txt' | head -1 | while read -r f; do
	cp "$f" "$DST/LICENSE.txt"
done

ls "$DST"/*.dll >/dev/null
