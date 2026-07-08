#!/bin/bash
# Build HiGHS into $CI_PROJECT_DIR/vendor/highs.
#
# Inputs (environment):
#   DEP_VERSION    HiGHS git tag, e.g. "v1.15.1"   (was highs-version.sh)
#   MZNARCH        platform selector
#   CMAKEARCH      CMake generator (e.g. "Ninja")  — unused on wasm
#   CI_PROJECT_DIR build root
set -e
set -x

: "${DEP_VERSION:?DEP_VERSION must be set}"
: "${CI_PROJECT_DIR:?CI_PROJECT_DIR must be set}"

# Download HiGHS source at the pinned tag
git clone --depth 1 --branch "${DEP_VERSION}" https://github.com/ERGO-Code/HiGHS "${CI_PROJECT_DIR}/highs"

mkdir -p {build,vendor}/highs
cd build/highs

if [[ "$MZNARCH" == "wasm" ]]; then
	# Static, minimum-size build under emscripten.
	emcmake cmake -G"Unix Makefiles" "$CI_PROJECT_DIR/highs" \
		-DCMAKE_BUILD_TYPE=MinSizeRel \
		-DCMAKE_INSTALL_PREFIX="$CI_PROJECT_DIR/vendor/highs" \
		-DBUILD_SHARED_LIBS=OFF -DFAST_BUILD=ON
	cmake --build . --config MinSizeRel
	cmake --build . --config MinSizeRel --target install
else
	cmake -G"$CMAKEARCH" -DCMAKE_BUILD_TYPE=Release \
		-DCMAKE_INSTALL_PREFIX="$CI_PROJECT_DIR/vendor/highs" "$CI_PROJECT_DIR/highs" \
		-DCMAKE_OSX_ARCHITECTURES="arm64" -DBUILD_SHARED_LIBS=ON -DFAST_BUILD=ON
	cmake --build . --config Release
	cmake --build . --config Release --target install
fi
