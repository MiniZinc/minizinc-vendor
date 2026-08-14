#!/bin/bash
# Build the OR-Tools CP-SAT FlatZinc solver (fzn-cp-sat) into
# $CI_PROJECT_DIR/vendor/or-tools using Bazel.
#
# Env: DEP_VERSION, MZNARCH, CI_PROJECT_DIR, BAZEL_VERSION, BAZELISK_VERSION, BAZELISK_ASSET
set -e
set -x

: "${DEP_VERSION:?DEP_VERSION must be set}"
: "${CI_PROJECT_DIR:?CI_PROJECT_DIR must be set}"
: "${BAZEL_VERSION:?BAZEL_VERSION must be set}"

export USE_BAZEL_VERSION="${BAZEL_VERSION}"
OVERLAY="${CI_PROJECT_DIR}/resources/or-tools"

# -- Install a pinned Bazel launcher (bazelisk), or apk bazel8 on Alpine/musl ---
# Alpine packages no bazel9, so musl ignores BAZEL_VERSION and builds with 8.
if [ -f /etc/alpine-release ]; then
	apk --no-cache add linux-headers python3
	apk add --no-cache -X https://dl-cdn.alpinelinux.org/alpine/edge/testing bazel8
	# provide a `bazel` alias for the invocation below
	command -v bazel >/dev/null || ln -sf "$(command -v bazel8)" /usr/local/bin/bazel
else
	: "${BAZELISK_ASSET:?BAZELISK_ASSET must be set on non-alpine platforms}"
	mkdir -p "${CI_PROJECT_DIR}/.bin"
	ext=""; [[ "$BAZELISK_ASSET" == windows-* ]] && ext=".exe"
	url="https://github.com/bazelbuild/bazelisk/releases/download/${BAZELISK_VERSION}/bazelisk-${BAZELISK_ASSET}${ext}"
	curl -fL -o "${CI_PROJECT_DIR}/.bin/bazel${ext}" "$url"
	chmod +x "${CI_PROJECT_DIR}/.bin/bazel${ext}"
	export PATH="${CI_PROJECT_DIR}/.bin:${PATH}"
fi

# -- Download OR-Tools source at the pinned tag --------------------------------
git clone --depth 1 --branch "${DEP_VERSION}" https://github.com/google/or-tools "${CI_PROJECT_DIR}/or-tools"

if [[ "$MZNARCH" == "win64" ]]; then
	# MSVC does not support -Wno-implicit-fallthrough
	sed -i 's/"-Wno-implicit-fallthrough",//g' "${CI_PROJECT_DIR}/or-tools/ortools/flatzinc/BUILD.bazel"
fi

# -- Apply the packaging overlay (adds a pkg_install target + cp-sat.msc) -------
cat "${OVERLAY}/MODULE.bazel" >> "${CI_PROJECT_DIR}/or-tools/MODULE.bazel"
cat "${OVERLAY}/BUILD.bazel"  >> "${CI_PROJECT_DIR}/or-tools/ortools/flatzinc/BUILD.bazel"

# Make sure the musl build uses the right python toolchain
extra_opts=
if [ -f /etc/alpine-release ]; then
	extra_opts="--extra_toolchains=@bazel_tools//tools/python:autodetecting_toolchain"
fi

# -- Build --------------------------------------------------------------------
# Persist a disk cache under the build root so CI can restore it across runs
# (see the Bazel cache step in build.yml).
cd "${CI_PROJECT_DIR}/or-tools"
bazel --batch "--bazelrc=${OVERLAY}/.bazelrc" run ${extra_opts} \
	"--disk_cache=${CI_PROJECT_DIR}/.bazel-disk" \
	-- //ortools/flatzinc:fzn_cp_sat --destdir="${CI_PROJECT_DIR}/vendor/or-tools"
