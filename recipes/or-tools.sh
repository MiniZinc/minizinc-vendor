#!/bin/bash
# Build the OR-Tools CP-SAT FlatZinc solver (fzn-cp-sat) into
# $BUILD_ROOT/vendor/or-tools using Bazel.
#
# Env: DEP_VERSION, MZNARCH, BUILD_ROOT, BAZEL_VERSION, BAZELISK_VERSION, BAZELISK_ASSET,
#      RULES_PKG_VERSION
set -e
set -x

: "${DEP_VERSION:?DEP_VERSION must be set}"
: "${BUILD_ROOT:?BUILD_ROOT must be set}"
: "${BAZEL_VERSION:?BAZEL_VERSION must be set}"

export USE_BAZEL_VERSION="${BAZEL_VERSION}"
OVERLAY="${BUILD_ROOT}/resources/or-tools"

# -- Install a pinned Bazel launcher (bazelisk), or apk bazel8 on Alpine/musl ---
# Alpine packages no bazel9, so musl ignores BAZEL_VERSION and builds with 8.
if [ -f /etc/alpine-release ]; then
	apk --no-cache add linux-headers python3
	apk add --no-cache -X https://dl-cdn.alpinelinux.org/alpine/edge/testing bazel8
	# provide a `bazel` alias for the invocation below
	command -v bazel >/dev/null || ln -sf "$(command -v bazel8)" /usr/local/bin/bazel
else
	: "${BAZELISK_ASSET:?BAZELISK_ASSET must be set on non-alpine platforms}"
	mkdir -p "${BUILD_ROOT}/.bin"
	ext=""; [[ "$BAZELISK_ASSET" == windows-* ]] && ext=".exe"
	url="https://github.com/bazelbuild/bazelisk/releases/download/${BAZELISK_VERSION}/bazelisk-${BAZELISK_ASSET}${ext}"
	curl -fL -o "${BUILD_ROOT}/.bin/bazel${ext}" "$url"
	chmod +x "${BUILD_ROOT}/.bin/bazel${ext}"
	export PATH="${BUILD_ROOT}/.bin:${PATH}"
fi

# -- Download OR-Tools source at the pinned tag --------------------------------
git clone --depth 1 --branch "${DEP_VERSION}" https://github.com/google/or-tools "${BUILD_ROOT}/or-tools"

if [[ "$MZNARCH" == "win64" ]]; then
	# MSVC does not support -Wno-implicit-fallthrough
	sed -i 's/"-Wno-implicit-fallthrough",//g' "${BUILD_ROOT}/or-tools/ortools/flatzinc/BUILD.bazel"
fi

# -- Apply the packaging overlay (adds a pkg_install target + cp-sat.msc) -------
sed "s|@RULES_PKG_VERSION@|${RULES_PKG_VERSION:?RULES_PKG_VERSION must be set}|" \
	"${OVERLAY}/MODULE.bazel.in" >> "${BUILD_ROOT}/or-tools/MODULE.bazel"
cat "${OVERLAY}/BUILD.bazel"  >> "${BUILD_ROOT}/or-tools/ortools/flatzinc/BUILD.bazel"

# Make sure the musl build uses the right python toolchain
extra_opts=
if [ -f /etc/alpine-release ]; then
	extra_opts="--extra_toolchains=@bazel_tools//tools/python:autodetecting_toolchain"
fi

# -- Build --------------------------------------------------------------------
# Persist a disk cache under the build root so CI can restore it across runs
# (see the Bazel cache step in build.yml).
cd "${BUILD_ROOT}/or-tools"
bazel --batch "--bazelrc=${OVERLAY}/.bazelrc" run ${extra_opts} \
	"--disk_cache=${BUILD_ROOT}/.bazel-disk" \
	-- //ortools/flatzinc:fzn_cp_sat --destdir="${BUILD_ROOT}/vendor/or-tools"
