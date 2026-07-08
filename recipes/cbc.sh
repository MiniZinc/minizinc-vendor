#!/bin/bash
# Build COIN-OR CBC into $CI_PROJECT_DIR/vendor/cbc.
#
# Inputs (from the environment, injected by the build workflow from the manifest):
#   DEP_VERSION       CBC version, e.g. "2.10.13"       (was cbc-version.sh)
#   COINBREW_COMMIT   pinned coinbrew master commit     (was an unpinned master fetch)
#   MZNARCH           linux | linux-arm64 | osx | win64 | wasm
#   CI_PROJECT_DIR    build root (set to $PWD by the workflow)
set -e
set -x

: "${DEP_VERSION:?DEP_VERSION must be set}"
: "${COINBREW_COMMIT:?COINBREW_COMMIT must be set}"
: "${CI_PROJECT_DIR:?CI_PROJECT_DIR must be set}"

# Fetch the pinned coinbrew script (reproducible; replaces the old master download).
rm -rf coinbrew-src
git clone --quiet https://github.com/coin-or/coinbrew coinbrew-src
git -C coinbrew-src checkout --quiet "$COINBREW_COMMIT"
cp coinbrew-src/coinbrew ./coinbrew
chmod u+x coinbrew

# Base configure args
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
	# Use emconfigure and emmake
	sed -i 's/"$config_script"/emconfigure "$config_script"/g; s/$MAKE/emmake $MAKE/g' coinbrew
	config_opts+=" CXXFLAGS=-std=c++14"
elif [[ "$MZNARCH" == "win64" ]]; then
	config_opts+=" --enable-msvc --build=x86_64-w64-mingw32"
	export CI_PROJECT_DIR=`cygpath ${CI_PROJECT_DIR}`
else
	echo "Illegal MZNARCH value"
	exit 1
fi

config_opts+=" --prefix=${CI_PROJECT_DIR}/vendor/cbc"

# coinbrew requires bash >= 4; macOS ships bash 3.2, so use a modern bash there.
COINBREW_BASH="bash"
if [[ "$MZNARCH" == "osx" ]]; then
	brew list bash >/dev/null 2>&1 || brew install bash >/dev/null
	COINBREW_BASH="$(brew --prefix)/bin/bash"
fi

# Fetch and build CBC
"$COINBREW_BASH" ./coinbrew --no-prompt fetch --no-third-party Cbc@${DEP_VERSION}
"$COINBREW_BASH" ./coinbrew --no-prompt build Cbc ${config_opts}
