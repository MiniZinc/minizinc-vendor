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

# An administrative install unpacks the MSI without installing it. msiexec
# returns immediately, so it must be waited on explicitly or the extraction is
# still running when we look for the DLLs. TARGETDIR needs a Windows path.
MSI_WIN=$(cygpath -w "$WORK/openssl.msi")
OUT_WIN=$(cygpath -w "$WORK/out")
powershell -NoProfile -Command \
	"\$p = Start-Process msiexec.exe -ArgumentList @('/a','$MSI_WIN','/qn','TARGETDIR=$OUT_WIN') -Wait -PassThru -NoNewWindow; exit \$p.ExitCode"

# Show what was unpacked: if the DLL names ever change, the failure below is
# otherwise just an empty glob.
find "$WORK/out" -type f | head -30

# The DLL names carry the ABI version and the arch (e.g. libcrypto-3-x64.dll,
# libcrypto-3-arm64.dll), so copy whatever the installer produced.
find "$WORK/out" \( -name 'libcrypto-*.dll' -o -name 'libssl-*.dll' \) | while read -r f; do
	cp "$f" "$DST/"
done
find "$WORK/out" \( -iname 'LICENSE*' -o -iname '*license*.txt' \) | head -1 | while read -r f; do
	cp "$f" "$DST/LICENSE.txt"
done

if ! ls "$DST"/*.dll >/dev/null 2>&1; then
	echo "no OpenSSL DLLs extracted from $OPENSSL_MSI (see the file list above)" >&2
	exit 1
fi
