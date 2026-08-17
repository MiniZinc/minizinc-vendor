#!/bin/bash
# Build HiGHS into $BUILD_ROOT/vendor/highs.
#
# Env: DEP_VERSION, MZNARCH, CMAKEARCH, BUILD_ROOT
set -e
set -x

: "${DEP_VERSION:?DEP_VERSION must be set}"
: "${BUILD_ROOT:?BUILD_ROOT must be set}"

# Download HiGHS source at the pinned tag
git clone --depth 1 --branch "${DEP_VERSION}" https://github.com/ERGO-Code/HiGHS "${BUILD_ROOT}/highs"

mkdir -p {build,vendor}/highs
cd build/highs

if [[ "$MZNARCH" == "wasm" ]]; then
	# Static, minimum-size build under emscripten.
	emcmake cmake -G"Unix Makefiles" "$BUILD_ROOT/highs" \
		-DCMAKE_BUILD_TYPE=MinSizeRel \
		-DCMAKE_INSTALL_PREFIX="$BUILD_ROOT/vendor/highs" \
		-DBUILD_SHARED_LIBS=OFF -DFAST_BUILD=ON
	cmake --build . --config MinSizeRel
	cmake --build . --config MinSizeRel --target install
else
	cmake -G"$CMAKEARCH" -DCMAKE_BUILD_TYPE=Release \
		-DCMAKE_INSTALL_PREFIX="$BUILD_ROOT/vendor/highs" "$BUILD_ROOT/highs" \
		-DCMAKE_OSX_ARCHITECTURES="arm64" -DBUILD_SHARED_LIBS=ON -DFAST_BUILD=ON
	cmake --build . --config Release
	cmake --build . --config Release --target install
fi
