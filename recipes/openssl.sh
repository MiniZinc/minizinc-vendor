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

# Unpack with 7-Zip rather than `msiexec /a`: the administrative install returns
# success on these MSIs but writes nothing. 7z is preinstalled on the runners and
# is synchronous. The payload sits in an embedded CAB, so extract that too.
SEVENZIP=7z
command -v "$SEVENZIP" >/dev/null || SEVENZIP=7za
"$SEVENZIP" x -y -o"$WORK/out" "$WORK/openssl.msi" >/dev/null
find "$WORK/out" -iname '*.cab' | while read -r c; do
	"$SEVENZIP" x -y -o"$WORK/out" "$c" >/dev/null
done

# Show what was unpacked: if the DLL names ever change, the failure below is
# otherwise just an empty glob.
find "$WORK/out" -type f | head -30

# Names embed the ABI version and arch (libcrypto-3-x64.dll, libcrypto-3-arm64.dll)
# and 7-Zip may rewrite them, so match loosely.
find "$WORK/out" \( -iname '*crypto*.dll' -o -iname '*ssl*.dll' \) | while read -r f; do
	cp "$f" "$DST/"
done
find "$WORK/out" \( -iname 'LICENSE*' -o -iname '*license*.txt' \) | head -1 | while read -r f; do
	cp "$f" "$DST/LICENSE.txt"
done

if ! ls "$DST"/*.dll >/dev/null 2>&1; then
	echo "no OpenSSL DLLs extracted from $OPENSSL_MSI (see the file list above)" >&2
	exit 1
fi
