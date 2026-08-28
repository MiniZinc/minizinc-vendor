#!/bin/bash
# Build Gecode into $BUILD_ROOT/vendor/gecode (or vendor/gecode_gist with Gist).
# Usage: gecode.sh {build_with_gist:0/1}
#
# Env: DEP_VERSION, MZNARCH, CMAKEARCH, BUILD_ROOT
set -e
set -x

: "${DEP_VERSION:?DEP_VERSION must be set}"
: "${BUILD_ROOT:?BUILD_ROOT must be set}"

if [ ! -d "$BUILD_ROOT/gecode/.git" ]; then
	git clone --quiet https://github.com/Gecode/gecode "$BUILD_ROOT/gecode"
fi
git -C "$BUILD_ROOT/gecode" checkout --quiet "release-$DEP_VERSION"

DIR="gecode"
# Set per osx platform (arm64 or x86_64); harmless elsewhere, CMake ignores it
# on non-Apple targets.
ARCH="${CMAKE_OSX_ARCHITECTURES:-arm64}"
if [ "${1:-0}" = 1 ]; then
	ENABLE_GIST=TRUE
	ENABLE_QT=TRUE
	if [ ! -x "$(command -v qmake)" ]; then
		echo "!!!!!!!!!!!!!! CANNOT FIND QMAKE !!!!!!!!!!!!"
		exit 1
	fi
	DIR="gecode_gist"
else
	ENABLE_GIST=FALSE
	ENABLE_QT=FALSE
fi

mkdir -p {build,vendor}/$DIR
cd build/$DIR

# Gecode 6.4 renamed these options with a GECODE_ prefix; the unprefixed ones
# are silently ignored, which produced shared-only builds.
#
# GECODE_ENABLE_MPFR defaults to ON and is satisfied by whatever the runner
# happens to have, so the macOS builds silently picked up Homebrew's libmpfr and
# exported an MPFR::MPFR link requirement to downstream. Keep it off everywhere:
# MPFR only adds transcendental float constraints, and the artifacts must not
# depend on libraries we do not ship.
if [[ "$MZNARCH" == "wasm" ]]; then
	# Gist and CP-Profiler are unavailable under emscripten.
	emcmake cmake -G"Unix Makefiles" "$BUILD_ROOT/gecode" \
		-DCMAKE_BUILD_TYPE=MinSizeRel \
		-DCMAKE_INSTALL_PREFIX="$BUILD_ROOT/vendor/$DIR" \
		-DGECODE_BUILD_SHARED=OFF -DGECODE_BUILD_STATIC=ON \
		-DGECODE_ENABLE_GIST=FALSE -DGECODE_ENABLE_QT=FALSE \
		-DGECODE_ENABLE_CPPROFILER=FALSE -DGECODE_ENABLE_MPFR=FALSE \
		-DGECODE_ENABLE_EXAMPLES=FALSE -DBUILD_TESTING=OFF
	cmake --build . --config MinSizeRel
	cmake --build . --config MinSizeRel --target install
else
	cmake -G"$CMAKEARCH" "$BUILD_ROOT/gecode" \
		-DCMAKE_BUILD_TYPE=Release \
		-DCMAKE_INSTALL_PREFIX="$BUILD_ROOT/vendor/$DIR" \
		-DGECODE_BUILD_SHARED=OFF -DGECODE_BUILD_STATIC=ON \
		-DGECODE_ENABLE_GIST=${ENABLE_GIST} -DGECODE_ENABLE_QT=${ENABLE_QT} \
		-DGECODE_ENABLE_CPPROFILER=TRUE \
		-DGECODE_ENABLE_MPFR=FALSE -DGECODE_ENABLE_EXAMPLES=FALSE \
		-DBUILD_TESTING=OFF \
		-DCMAKE_OSX_ARCHITECTURES=${ARCH}
	cmake --build . --config Release
	cmake --build . --config Release --target install
fi
