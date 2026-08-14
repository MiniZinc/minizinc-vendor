#!/bin/bash
# Stage the OpenSSL runtime DLLs the MiniZinc IDE's Windows installer bundles.
#
# Downloads the "Light" installer from slproweb.com (the de-facto Windows OpenSSL
# build; upstream ships no binaries) and takes just the two DLLs out of it.
#
# Note slproweb only keeps the newest patch release per branch, so a pinned
# version eventually 404s and has to be bumped; the update bot tracks this.
#
# Env: DEP_VERSION, MZNARCH, OPENSSL_EXE, CI_PROJECT_DIR
set -e
set -x

: "${DEP_VERSION:?DEP_VERSION must be set}"
: "${OPENSSL_EXE:?OPENSSL_EXE must be set}"
: "${CI_PROJECT_DIR:?CI_PROJECT_DIR must be set}"

DST="$CI_PROJECT_DIR/vendor/openssl"
WORK="$CI_PROJECT_DIR/.openssl"
rm -rf "$WORK" && mkdir -p "$WORK" "$DST"

curl -fsSLo "$WORK/openssl.exe" "https://slproweb.com/download/${OPENSSL_EXE}"

# Install into $WORK/out rather than unpacking: the .msi form cannot be extracted
# (`msiexec /a` writes nothing and 7-Zip only yields an opaque `MainInstaller`),
# but the .exe is an Inno Setup installer that takes a target directory. Flags via
# the Chocolatey package; `/SP-` drops the "this will install" prompt. Run through
# Start-Process -Wait because Inno's setup.exe returns before its work is done,
# and via PowerShell so MSYS does not rewrite the /FLAG arguments into paths.
powershell -NoProfile -Command \
	"\$p = Start-Process -FilePath '$(cygpath -w "$WORK/openssl.exe")' \
	  -ArgumentList '/VERYSILENT','/SUPPRESSMSGBOXES','/NORESTART','/SP-','/DIR=$(cygpath -w "$WORK/out")' \
	  -Wait -PassThru; exit \$p.ExitCode"

# Show what was installed: if the DLL names ever change, the failure below is
# otherwise just an empty glob.
find "$WORK/out" -type f | head -30

# Names embed the ABI version and arch (libcrypto-3-x64.dll, libcrypto-3-arm64.dll).
find "$WORK/out" \( -iname '*crypto*.dll' -o -iname '*ssl*.dll' \) -exec cp {} "$DST/" \;
find "$WORK/out" \( -iname 'LICENSE*' -o -iname '*license*.txt' \) | head -1 | while read -r f; do
	cp "$f" "$DST/LICENSE.txt"
done

if ! ls "$DST"/*.dll >/dev/null 2>&1; then
	echo "no OpenSSL DLLs found after installing $OPENSSL_EXE (see the file list above)" >&2
	exit 1
fi
