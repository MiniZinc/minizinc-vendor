#!/bin/bash
# Build Chuffed into $BUILD_ROOT/vendor/chuffed.
#
# Env: DEP_VERSION, MZNARCH, CMAKEARCH, BUILD_ROOT
set -e
set -x

: "${DEP_VERSION:?DEP_VERSION must be set}"
: "${BUILD_ROOT:?BUILD_ROOT must be set}"

if [ ! -d "$BUILD_ROOT/chuffed/.git" ]; then
	git clone --quiet https://github.com/Chuffed/chuffed "$BUILD_ROOT/chuffed"
fi
git -C "$BUILD_ROOT/chuffed" checkout --quiet "$DEP_VERSION"

mkdir -p {build,vendor}/chuffed
cd build/chuffed

if [[ "$MZNARCH" == "wasm" ]]; then
	emcmake cmake -G"Unix Makefiles" "$BUILD_ROOT/chuffed" \
		-DCMAKE_BUILD_TYPE=MinSizeRel \
		-DCMAKE_INSTALL_PREFIX="$BUILD_ROOT/vendor/chuffed"
	cmake --build . --config MinSizeRel
	cmake --build . --config MinSizeRel --target install
else
	cmake -G"$CMAKEARCH" -DCMAKE_BUILD_TYPE=Release \
		-DCMAKE_INSTALL_PREFIX="$BUILD_ROOT/vendor/chuffed" "$BUILD_ROOT/chuffed" \
		-DCMAKE_OSX_ARCHITECTURES="${CMAKE_OSX_ARCHITECTURES:-arm64}"
	cmake --build . --config Release
	cmake --build . --config Release --target install
fi
