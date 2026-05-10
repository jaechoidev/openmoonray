#!/usr/bin/env bash
# Container-quirks setup for the gaffer-build container.
#
# Runs once per container provisioning (or after `docker rm`), before
# either session builds anything that includes USD or Moonray. Both
# the Moonray-side and Gaffer-side Claude sessions should invoke this.
#
# Idempotent. Safe to re-run.

set -euo pipefail

# -- Quirk #1: orphan TBB-2020 headers shadowing oneTBB 2021 -------------
#
# `ghcr.io/gafferhq/build/build:3.4.0` (Rocky Linux 8.8) ships
# /usr/local/include/tbb/ — a manually-installed legacy TBB 2020 header
# tree, not owned by any rpm package, not used by Gaffer's SConstruct
# (verified 2026-05-09: zero references in /work/gaffer/SConstruct or
# /work/gaffer/build/).
#
# The problem: USD 26's pxr/base/work/workTBB/taskGraph_impl.h does
#
#     #if __has_include(<tbb/tbb_stddef.h>)
#       include <tbb/tbb_stddef.h>           // legacy TBB
#     #elif __has_include(<tbb/version.h>)
#       include <tbb/version.h>              // oneTBB 2021+
#     #endif
#
# Since the legacy header IS findable via /usr/local/include, USD takes
# the legacy branch and emits references to tbb::task / tbb::empty_task /
# tbb::spawn — APIs that oneTBB 2021 removed. Every USD-using compile
# in hdMoonray then fails.
#
# Move the orphan header tree aside (don't delete — preserve the option
# to restore if a different consumer ever surfaces).
LEGACY_TBB=/usr/local/include/tbb
LEGACY_TBB_DISABLED=/usr/local/include/tbb.disabled-by-moonray-port

if [ -e "$LEGACY_TBB/tbb_stddef.h" ] && [ ! -e "$LEGACY_TBB_DISABLED" ]; then
    echo "Moving orphan TBB legacy headers aside:"
    echo "  $LEGACY_TBB -> $LEGACY_TBB_DISABLED"
    mv "$LEGACY_TBB" "$LEGACY_TBB_DISABLED"
elif [ -e "$LEGACY_TBB_DISABLED" ]; then
    echo "TBB legacy headers already moved aside (skip)."
else
    echo "No legacy TBB headers at $LEGACY_TBB (skip)."
fi

echo ""
echo "Container setup complete."
