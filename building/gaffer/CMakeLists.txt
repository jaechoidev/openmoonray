# Copyright 2023-2026 DreamWorks Animation LLC
# SPDX-License-Identifier: Apache-2.0
#
# Build the Moonray-only deps that Gaffer's pre-built dep tarball
# (gafferDependencies-11.0.0a6) does NOT include.
#
# Everything else (Boost, Python, USD, OIIO, OpenVDB, OCIO, OpenSubdiv,
# OpenEXR, Imath, Embree, oneTBB) is consumed straight from
# /work/_install/gaffer-deps so Moonray and Gaffer share identical ABI
# in the same process.
#
# This file installs into ${InstallRoot}, which defaults to the same
# /work/_install/gaffer-deps prefix so a single CMAKE_PREFIX_PATH covers
# both layers. Override -DInstallRoot=... to install elsewhere.
#
# Usage from inside the gaffer-build container:
#   mkdir -p /work/_build/moonray-deps && cd /work/_build/moonray-deps
#   cmake /work/openmoonray/building/gaffer
#   cmake --build . -j $(nproc)

cmake_minimum_required (VERSION 3.23.1)
project(openmoonray_gaffer_deps)

include(ExternalProject)

set(InstallRoot /work/_install/gaffer-deps CACHE FILEPATH "Install prefix")

# ISPC — Moonray's ISPC compiler. Binary release; just drop in bin/.
#
# Why bin-only (not the full release tree): the ispc binary ships
# stdlib + per-ISA codegen built into the binary itself (verified via
# `strings ispc | grep stdlib` shows the bitcode strings inline, and
# all ISA targets sse2/sse4/avx/avx2/avx512* respond to --target=...
# without needing the release's lib/ directory). The lib/ tree in the
# tarball is examples/docs/license, not runtime-required. Copying
# bin/ispc alone is sufficient for compilation.
ExternalProject_Add(ISPC
    URL https://github.com/ispc/ispc/releases/download/v1.21.0/ispc-v1.21.0-linux.tar.gz
    BUILD_IN_SOURCE 1
    CONFIGURE_COMMAND ""
    BUILD_COMMAND ""
    INSTALL_COMMAND ${CMAKE_COMMAND} -E copy <SOURCE_DIR>/bin/ispc ${InstallRoot}/bin/ispc
)

# Random123 — header-only DEShaw counter-based PRNG.
ExternalProject_Add(Random123
    GIT_REPOSITORY https://github.com/DEShawResearch/random123
    GIT_TAG 726a093cd9a73f3ec3c8d7a70ff10ed8efec8d13 # v1.14.0
    BUILD_IN_SOURCE 1
    CONFIGURE_COMMAND ""
    BUILD_COMMAND ""
    INSTALL_COMMAND make install-include prefix=${InstallRoot}
)

# log4cplus 2.0.5 — Rocky Linux 8 EPEL only ships log4cplus 1.2.0,
# which lacks the file:line log() overload Moonray's render_logging
# code uses. Moonray expects 2.x (matches the Rocky9 dnf version
# upstream targets). Build from source and overlay on the system one.
ExternalProject_Add(log4cplus
    URL https://github.com/log4cplus/log4cplus/releases/download/REL_2_0_5/log4cplus-2.0.5.tar.gz
    INSTALL_DIR ${InstallRoot}
    CMAKE_ARGS
        -DCMAKE_INSTALL_PREFIX:PATH=<INSTALL_DIR>
        -DCMAKE_BUILD_TYPE=Release
        -DBUILD_SHARED_LIBS=ON
        -DLOG4CPLUS_BUILD_TESTING=OFF
        -DLOG4CPLUS_BUILD_LOGGINGSERVER=OFF
        -DUNICODE=OFF
)

# libmicrohttpd 0.9.75 — Rocky 8 dnf ships 0.9.59, which lacks the
# `MHD_Result` enum that Moonray's arras4_network/HttpServer.cc uses
# (added upstream in 0.9.71). Build a newer release from source.
ExternalProject_Add(libmicrohttpd
    URL https://ftp.gnu.org/gnu/libmicrohttpd/libmicrohttpd-0.9.75.tar.gz
    INSTALL_DIR ${InstallRoot}
    CONFIGURE_COMMAND <SOURCE_DIR>/configure
        --prefix=<INSTALL_DIR>
        --disable-static
        --enable-shared
        --disable-doc
        --disable-examples
        --disable-curl
)

# OpenImageDenoise — Moonray's denoiser. Not in the Gaffer tarball
# (Gaffer doesn't denoise final renders). Built from upstream release.
ExternalProject_Add(OpenImageDenoise
    URL https://github.com/OpenImageDenoise/oidn/releases/download/v2.3.3/oidn-2.3.3.src.tar.gz
    INSTALL_DIR ${InstallRoot}
    CMAKE_ARGS
        -DCMAKE_INSTALL_PREFIX:PATH=<INSTALL_DIR>
        -DCMAKE_PREFIX_PATH:PATH=${InstallRoot}
        -DISPC_EXECUTABLE=${InstallRoot}/bin/ispc
        -DOIDN_APPS=OFF
    DEPENDS ISPC
)

# OptiX/CUDA: deliberately omitted. Phase 0 builds Moonray with
# -DMOONRAY_USE_OPTIX=NO. Add OptiX 7.6 headers here in v2 Phase 7.
