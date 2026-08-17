#!/bin/bash
# Build COIN-OR CBC into $BUILD_ROOT/vendor/cbc.
#
# Env: DEP_VERSION, MZNARCH, BUILD_ROOT; COINBREW_COMMIT (source builds), CBC_MSVC_ASSET (win64)
set -e
set -x

: "${DEP_VERSION:?DEP_VERSION must be set}"
: "${COINBREW_COMMIT:?COINBREW_COMMIT must be set}"
: "${BUILD_ROOT:?BUILD_ROOT must be set}"

# Windows uses COIN-OR's own MSVC build rather than coinbrew: the autotools build
# under MSVC hits a libtool bug that mis-combines convenience libraries, dropping
# objects from libCgl (LNK4014) and leaving cbc unlinkable. The published package
# is the same version, built for VS2022 against the dynamic CRT, and unpacks to
# the same prefix layout coinbrew would install.
if [[ "$MZNARCH" == "win64" ]]; then
	: "${CBC_MSVC_ASSET:?CBC_MSVC_ASSET must be set}"
	dst="$BUILD_ROOT/vendor/cbc"
	rm -rf "$dst" && mkdir -p "$dst"
	curl -fsSLo cbc-msvc.zip \
		"https://github.com/coin-or/Cbc/releases/download/releases/${DEP_VERSION}/${CBC_MSVC_ASSET}"
	unzip -q cbc-msvc.zip -d "$dst"
	rm -f cbc-msvc.zip
	# Fail here, not later in libminizinc, if the archive layout ever changes.
	test -f "$dst/lib/libCbc.lib"
	test -f "$dst/include/coin/CbcConfig.h"
	exit 0
fi

rm -rf coinbrew-src
git clone --quiet https://github.com/coin-or/coinbrew coinbrew-src
git -C coinbrew-src checkout --quiet "$COINBREW_COMMIT"
cp coinbrew-src/coinbrew ./coinbrew
chmod u+x coinbrew

config_opts="--verbosity=4 \
--parallel-jobs=2 \
--enable-static --disable-shared \
--without-blas --without-lapack --without-mumps --disable-bzlib \
--no-third-party \
--skip-update \
--tests none"

if [[ "$MZNARCH" == "linux" ]]; then
	config_opts+=" --enable-cbc-parallel"
elif [[ "$MZNARCH" == "linux-arm64" ]]; then
	config_opts+=" --enable-cbc-parallel --build=aarch64-unknown-linux-gnu"
elif [[ "$MZNARCH" == "osx" ]]; then
	config_opts+=" --enable-cbc-parallel"
elif [[ "$MZNARCH" == "wasm" ]]; then
	sed -i 's/"$config_script"/emconfigure "$config_script"/g; s/$MAKE/emmake $MAKE/g' coinbrew
	config_opts+=" CXXFLAGS=-std=c++14"
else
	echo "Illegal MZNARCH value"
	exit 1
fi

config_opts+=" --prefix=${BUILD_ROOT}/vendor/cbc"

# coinbrew requires bash >= 4; macOS ships bash 3.2, so use a modern bash there.
COINBREW_BASH="bash"
if [[ "$MZNARCH" == "osx" ]]; then
	brew list bash >/dev/null 2>&1 || brew install bash >/dev/null
	COINBREW_BASH="$(brew --prefix)/bin/bash"
fi

# Fetch CBC and all its COIN-OR dependencies.
"$COINBREW_BASH" ./coinbrew --no-prompt fetch --no-third-party Cbc@${DEP_VERSION}

# Build CBC.
"$COINBREW_BASH" ./coinbrew --no-prompt build Cbc ${config_opts}
