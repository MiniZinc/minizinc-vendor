#!/bin/bash
# Build Chuffed into $CI_PROJECT_DIR/vendor/chuffed.
#
# Inputs (environment):
#   DEP_COMMIT     Chuffed commit to build (was a git submodule gitlink)
#   MZNARCH        platform selector
#   CMAKEARCH      CMake generator (e.g. "Ninja") — unused on wasm
#   CI_PROJECT_DIR build root
set -e
set -x

: "${DEP_COMMIT:?DEP_COMMIT must be set}"
: "${CI_PROJECT_DIR:?CI_PROJECT_DIR must be set}"

# Fetch the pinned Chuffed source (replaces the old submodule checkout).
if [ ! -d "$CI_PROJECT_DIR/chuffed/.git" ]; then
	git clone --quiet https://github.com/Chuffed/chuffed "$CI_PROJECT_DIR/chuffed"
fi
git -C "$CI_PROJECT_DIR/chuffed" checkout --quiet "$DEP_COMMIT"

mkdir -p {build,vendor}/chuffed
cd build/chuffed

if [[ "$MZNARCH" == "wasm" ]]; then
	emcmake cmake -G"Unix Makefiles" "$CI_PROJECT_DIR/chuffed" \
		-DCMAKE_BUILD_TYPE=MinSizeRel \
		-DCMAKE_INSTALL_PREFIX="$CI_PROJECT_DIR/vendor/chuffed"
	cmake --build . --config MinSizeRel
	cmake --build . --config MinSizeRel --target install
else
	cmake -G"$CMAKEARCH" -DCMAKE_BUILD_TYPE=Release \
		-DCMAKE_INSTALL_PREFIX="$CI_PROJECT_DIR/vendor/chuffed" "$CI_PROJECT_DIR/chuffed" \
		-DCMAKE_OSX_ARCHITECTURES="arm64"
	cmake --build . --config Release
	cmake --build . --config Release --target install
fi
