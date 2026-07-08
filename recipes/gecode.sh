#!/bin/bash
# Build Gecode into $CI_PROJECT_DIR/vendor/gecode (or vendor/gecode_gist with Gist).
# Usage: gecode.sh {build_with_gist:0/1}
#
# Inputs (environment):
#   DEP_COMMIT     Gecode commit to build (was a git submodule gitlink)
#   MZNARCH        platform selector
#   CMAKEARCH      CMake generator (e.g. "Ninja") — unused on wasm
#   CI_PROJECT_DIR build root
set -e
set -x

: "${DEP_COMMIT:?DEP_COMMIT must be set}"
: "${CI_PROJECT_DIR:?CI_PROJECT_DIR must be set}"

# Fetch the pinned Gecode source (replaces the old submodule checkout).
if [ ! -d "$CI_PROJECT_DIR/gecode/.git" ]; then
	git clone --quiet https://github.com/Gecode/gecode "$CI_PROJECT_DIR/gecode"
fi
git -C "$CI_PROJECT_DIR/gecode" checkout --quiet "$DEP_COMMIT"

DIR="gecode"
ARCH="arm64"
if [ "${1:-0}" = 1 ]; then
	ENABLE_GIST=TRUE
	if [ ! -x "$(command -v qmake)" ]; then
		echo "!!!!!!!!!!!!!! CANNOT FIND QMAKE !!!!!!!!!!!!"
		exit 1
	fi
	DIR="gecode_gist"
else
	ENABLE_GIST=FALSE
fi

mkdir -p {build,vendor}/$DIR
cd build/$DIR

if [[ "$MZNARCH" == "wasm" ]]; then
	# Gist and CP-Profiler are unavailable under emscripten.
	emcmake cmake -G"Unix Makefiles" "$CI_PROJECT_DIR/gecode" \
		-DCMAKE_BUILD_TYPE=MinSizeRel \
		-DCMAKE_INSTALL_PREFIX="$CI_PROJECT_DIR/vendor/$DIR" \
		-DENABLE_GIST=FALSE -DENABLE_CPPROFILER=FALSE
	cmake --build . --config MinSizeRel
	cmake --build . --config MinSizeRel --target install
else
	cmake -G"$CMAKEARCH" "$CI_PROJECT_DIR/gecode" \
		-DCMAKE_BUILD_TYPE=Release \
		-DCMAKE_INSTALL_PREFIX="$CI_PROJECT_DIR/vendor/$DIR" \
		-DENABLE_GIST=${ENABLE_GIST} -DENABLE_CPPROFILER=TRUE \
		-DCMAKE_OSX_ARCHITECTURES=${ARCH}
	cmake --build . --config Release
	cmake --build . --config Release --target install
fi
