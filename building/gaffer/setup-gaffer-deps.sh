#!/usr/bin/env bash
# One-shot setup for Moonray's "gaffer-release" CMake preset.
#
# Idempotent. Safe to re-run after re-extracting the tarball.
#
# What it does (in order):
#   1. Verifies /work/_install/gaffer-deps was extracted from
#      gafferDependencies-11.0.0a6-linux-platform25.tar.gz.
#   2. Rewrites the GitHub-Actions build paths embedded in the tarball
#      cmake target export files (one-time per fresh extract).
#   3. Generates an overlay prefix at /work/_install/gaffer-deps-shim
#      with corrected cmake configs that the broken/incomplete tarball
#      configs are missing or wrong about. The gaffer-release preset
#      prepends this prefix to CMAKE_PREFIX_PATH so it wins
#      find_package().
#
#   The shim contains:
#     - lib/cmake/pxr/  — synthetic pxrConfig.cmake + pxrTargets.cmake
#                         (tarball ships USD libs but no cmake config)
#     - lib/cmake/OpenImageIO/ — copy of the tarball cmake configs with
#                         entries for missing CLI tools removed
#                         (iconvert/idiff/igrep/iinfo/testtex).
#
# Why a shim instead of editing the tarball prefix in place:
#   - /work/_install/gaffer-deps is also consumed by the Gaffer session.
#     Mutating it invisibly changes shared state.
#   - Re-extracting the tarball would silently lose any in-place fixes.
#   - The shim is committed under building/gaffer/cmake-shim/ — fully
#     reproducible and discoverable in PRs.

set -euo pipefail

DEPS_PREFIX="${DEPS_PREFIX:-/work/_install/gaffer-deps}"
SHIM_PREFIX="${SHIM_PREFIX:-/work/_install/gaffer-deps-shim}"
SOURCE_DIR="$(cd "$(dirname "$0")"; pwd)"
SHIM_SOURCE="$SOURCE_DIR/cmake-shim"

# ---- Step 1: sanity-check the extracted tarball -------------------------

if [[ ! -d $DEPS_PREFIX/lib ]] || ! ls "$DEPS_PREFIX"/lib/libusd_*.so >/dev/null 2>&1; then
    cat >&2 <<EOF
ERROR: $DEPS_PREFIX is not a valid extraction of
gafferDependencies-11.0.0a6-linux-platform25.tar.gz.

Extract it first:

    cd /work/_install
    curl -fsSL -o /tmp/gd.tar.gz \\
        https://github.com/GafferHQ/dependencies/releases/download/11.0.0a6/gafferDependencies-11.0.0a6-linux-platform25.tar.gz
    rm -rf $DEPS_PREFIX
    tar xzf /tmp/gd.tar.gz
    mv gafferDependencies-11.0.0a6-linux-platform25 $(basename "$DEPS_PREFIX")
EOF
    exit 1
fi

# ---- Step 2: rewrite GitHub-Actions build paths -------------------------

OLD_BUILD_PATH=/__w/dependencies/dependencies/build/gafferDependencies-11.0.0a6-linux-platform25
# `grep -r` returns 1 when nothing matches; that combined with set -o
# pipefail would kill the script. Wrap to swallow the empty case.
fix_count=$({ grep -rl "$OLD_BUILD_PATH" "$DEPS_PREFIX" \
    --include="*.cmake" --include="*.pc" --include="*.json" 2>/dev/null \
    || true; } | wc -l)
if [ "$fix_count" -gt 0 ]; then
    echo "Rewriting $fix_count files: $OLD_BUILD_PATH -> $DEPS_PREFIX"
    grep -rl "$OLD_BUILD_PATH" "$DEPS_PREFIX" \
        --include="*.cmake" --include="*.pc" --include="*.json" 2>/dev/null \
        | xargs sed -i "s|$OLD_BUILD_PATH|$DEPS_PREFIX|g"
else
    echo "Build paths already rewritten (skip)."
fi

# ---- Step 3: build the shim overlay -------------------------------------

# Sanity-guard the rm -rf: SHIM_PREFIX is env-overridable, and an
# accidental override to a parent dir (e.g. SHIM_PREFIX=/work) would
# wipe huge amounts of unrelated state. Require the path to end in
# /gaffer-deps-shim before nuking.
case "$SHIM_PREFIX" in
    */gaffer-deps-shim) ;;
    *)
        echo "ERROR: refusing to rm -rf '$SHIM_PREFIX' — does not end in /gaffer-deps-shim." >&2
        echo "       If this is a deliberate override, rename the dir to end in /gaffer-deps-shim." >&2
        exit 1
        ;;
esac

rm -rf "$SHIM_PREFIX"
mkdir -p "$SHIM_PREFIX/lib/cmake"

# 3a. pxr shim — synthesize pxrConfig.cmake + pxrTargets.cmake from
#     whichever libusd_*.so files are actually present in the tarball.
mkdir -p "$SHIM_PREFIX/lib/cmake/pxr"

cat > "$SHIM_PREFIX/lib/cmake/pxr/pxrConfig.cmake" <<'CONFIG_EOF'
# Synthetic pxrConfig.cmake for gafferDependencies-11.0.0a6 USD v26.03.
# Mirrors upstream pxrConfig.cmake but binds to the Gaffer dep tarball's
# libusd_*.so naming. Triggered by find_package(pxr) in hdMoonray and
# moonray_sdr_plugins.

get_filename_component(PXR_CMAKE_DIR "${CMAKE_CURRENT_LIST_FILE}" PATH)
include("${PXR_CMAKE_DIR}/pxrTargets.cmake")

set(PXR_MAJOR_VERSION 0)
set(PXR_MINOR_VERSION 26)
set(PXR_PATCH_VERSION 3)
set(PXR_VERSION       2603)

# Real libs live in the gaffer-deps prefix, not the shim prefix.
set(PXR_INCLUDE_DIRS "${_PXR_DEPS_PREFIX}/include")

set(PXR_LIBRARIES "")
get_property(_imp_targets DIRECTORY PROPERTY IMPORTED_TARGETS)
foreach(_t ${_imp_targets})
    get_target_property(_loc "${_t}" IMPORTED_LOCATION)
    if(_loc AND "${_loc}" MATCHES "/libusd_")
        list(APPEND PXR_LIBRARIES "${_t}")
        set(PXR_${_t}_LIBRARY "${_loc}")
    endif()
endforeach()
unset(_imp_targets)
unset(_t)
unset(_loc)

set(pxr_FOUND TRUE)
CONFIG_EOF

{
    echo '# Auto-generated by setup-gaffer-deps.sh from libusd_*.so'
    echo '# in '"$DEPS_PREFIX"'/lib. Do not edit by hand — re-run the'
    echo '# setup script if the tarball changes.'
    echo ''
    echo 'cmake_policy(PUSH)'
    echo 'cmake_policy(VERSION 3.5...3.27)'
    echo 'set(CMAKE_IMPORT_FILE_VERSION 1)'
    echo "set(_PXR_DEPS_PREFIX \"$DEPS_PREFIX\")"
    echo 'set(_PXR_LIB_DIR "${_PXR_DEPS_PREFIX}/lib")'
    echo 'set(_PXR_INC_DIR "${_PXR_DEPS_PREFIX}/include")'
    echo ''
    for so in "$DEPS_PREFIX"/lib/libusd_*.so; do
        name=$(basename "$so" .so)   # libusd_tf
        target=${name#libusd_}       # tf
        cat <<TGT_EOF
if(NOT TARGET ${target})
    add_library(${target} SHARED IMPORTED)
    set_target_properties(${target} PROPERTIES
        IMPORTED_LOCATION "\${_PXR_LIB_DIR}/${name}.so"
        IMPORTED_SONAME   "${name}.so"
        INTERFACE_INCLUDE_DIRECTORIES "\${_PXR_INC_DIR}"
    )
endif()
TGT_EOF
    done
    echo ''
    echo 'unset(_PXR_LIB_DIR)'
    echo 'unset(_PXR_INC_DIR)'
    echo 'set(CMAKE_IMPORT_FILE_VERSION)'
    echo 'cmake_policy(POP)'
} > "$SHIM_PREFIX/lib/cmake/pxr/pxrTargets.cmake"

pxr_count=$(grep -c '^if(NOT TARGET' "$SHIM_PREFIX/lib/cmake/pxr/pxrTargets.cmake")
echo "pxr shim: $pxr_count IMPORTED USD targets"

# 3b. OpenImageIO shim — copy the tarball cmake configs into the shim,
#     then strip entries for CLI tools that the tarball did not ship.
mkdir -p "$SHIM_PREFIX/lib/cmake/OpenImageIO"
cp "$DEPS_PREFIX"/lib/cmake/OpenImageIO/*.cmake "$SHIM_PREFIX/lib/cmake/OpenImageIO/"

# Re-anchor every relative path computation in the shim's OIIO config
# back to the real gaffer-deps prefix. Otherwise CMake walks
# ${CMAKE_CURRENT_LIST_DIR}/../../ and lands inside the shim, where
# include/ doesn't exist.
sed -i \
    -e "s|get_filename_component(PACKAGE_PREFIX_DIR.*|set(PACKAGE_PREFIX_DIR \"$DEPS_PREFIX\")|" \
    -e "s|get_filename_component(_CURR_INSTALL_LIBDIR .*|set(_CURR_INSTALL_LIBDIR \"$DEPS_PREFIX/lib\")|" \
    "$SHIM_PREFIX/lib/cmake/OpenImageIO/OpenImageIOConfig.cmake"

# Also re-anchor _IMPORT_PREFIX in the targets file (used by the
# IMPORTED_LOCATION strings).
sed -i \
    "s|get_filename_component(_IMPORT_PREFIX.*|set(_IMPORT_PREFIX \"$DEPS_PREFIX\")|" \
    "$SHIM_PREFIX/lib/cmake/OpenImageIO/OpenImageIOTargets.cmake"

# Drop the missing-tool entries so cmake's _cmake_import_check loop
# doesn't trip on the missing iconvert/idiff/igrep/iinfo/testtex.
MISSING_OIIO_TOOLS=(iconvert idiff igrep iinfo testtex)
for tool in "${MISSING_OIIO_TOOLS[@]}"; do
    # OpenImageIOTargets.cmake — drop the add_executable line.
    sed -i "/^add_executable(OpenImageIO::${tool} /d" \
        "$SHIM_PREFIX/lib/cmake/OpenImageIO/OpenImageIOTargets.cmake"
    # OpenImageIOTargets-release.cmake — drop the multi-line block.
    python3 - "$tool" "$SHIM_PREFIX/lib/cmake/OpenImageIO/OpenImageIOTargets-release.cmake" <<'PY'
import re, sys, pathlib
tool, path = sys.argv[1], pathlib.Path(sys.argv[2])
s = path.read_text()
pat = re.compile(
    rf"# Import target \"OpenImageIO::{tool}\".*?(?=\n# Import target|\Z)",
    re.DOTALL,
)
path.write_text(pat.sub("", s))
PY
done
# Strip the missing tools from the expected_target list at the top of
# OpenImageIOTargets.cmake too.
for tool in "${MISSING_OIIO_TOOLS[@]}"; do
    sed -i \
        -e "s| OpenImageIO::${tool} | |g" \
        -e "s| OpenImageIO::${tool})|)|g" \
        "$SHIM_PREFIX/lib/cmake/OpenImageIO/OpenImageIOTargets.cmake"
done
echo "OpenImageIO shim: dropped ${#MISSING_OIIO_TOOLS[@]} missing-tool targets"

# 3c. Drop in any pre-rendered shim files committed under
#     building/gaffer/cmake-shim/ (overrides what the script generated).
if [[ -d $SHIM_SOURCE ]]; then
    for entry in "$SHIM_SOURCE"/lib/cmake/*; do
        [[ -d $entry ]] || continue
        name=$(basename "$entry")
        echo "Pre-rendered shim: $name (overrides generated)"
        cp -r "$entry" "$SHIM_PREFIX/lib/cmake/"
    done
fi

echo ""
echo "Done. Shim at $SHIM_PREFIX (size: $(du -sh "$SHIM_PREFIX" | awk '{print $1}'))."
echo "Configure Moonray with: cmake --preset gaffer-release"
