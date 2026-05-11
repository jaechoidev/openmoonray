# Phase 0 status — Moonray-against-Gaffer-deps port

Read this with `CLAUDE.md` (this fork) and the canonical
`../PLAN/PLAN.md` (shared planning dir at `/work/PLAN/PLAN.md` in the
container; previously lived at `gaffer/contrib/moonray/PLAN.md` on
branch `claude/moonray-gaffer-planning-deg3f`).

## TL;DR

Moonray builds and renders cleanly against the Gaffer 1.6 dep stack
(USD 26.03 / Boost 1.85 / Python 3.11.14 / OIIO 3.0.6.1 / OpenVDB 11.0.0
/ OCIO 2.4.2 / OpenSubdiv 3.6.1 / Imath 3.1.12 / OpenEXR 3.3.6 /
Embree 4.4.0 / oneTBB 2021.13.0).

- ✅ Configure succeeds (~26s)
- ✅ Build completes 100% with 0 errors
- ✅ Install populated at `/work/_install/moonray-gaffer/`
- ✅ Smoke render (CLI): `moonray -in testdata/rectangle.rdla -out
  /tmp/rectangle.exr` → 345 KB EXR, render time 6.5s
- ✅ Smoke render (Hydra): `hd_render -renderer "Moonray (debug)" -in
  testdata/sphere.usd -out /tmp/sphere.exr` → 36 KB EXR, render time
  14.2s. Confirms hdMoonray's in-process Rndr path works through the
  patched USD 26 / Boost 1.85 / Python 3.11 stack.

6 soft-fork patches under `dependencies/moonray-patches/` carry source-
level deltas. CMake-config shims at `/work/_install/gaffer-deps-shim/`
carry the dep-tarball-config deltas. Both are reproducible from
committed scripts.

## Strategy pivot from PLAN.md

PLAN.md called for "Build Moonray against Boost 1.85 / OIIO 3.0 /
OpenEXR 3.3" by patching `building/Rocky9/CMakeLists.txt`. We pivoted
to **consume Gaffer's pre-built dep tarball** instead:

- Source: `gafferDependencies-11.0.0a6-linux-platform25.tar.gz`
  (435 MB compressed, 1.7 GB extracted) from the GafferHQ/dependencies
  release attached to Gaffer 1.6.
- Extracted to `/work/_install/gaffer-deps`. Visible from the host
  at `<host work dir>/_install/gaffer-deps`.
- Saves an estimated 8–12 hours of from-source builds for Boost,
  Python, USD, OIIO, OpenVDB, OCIO, OpenSubdiv, OpenEXR, Imath,
  Embree, oneTBB, MaterialX, OSL.
- Crucially, both Moonray and Gaffer consume **identical .so
  artifacts**, eliminating the H2 ABI-clash hurdle byteforbyte (no
  same-version-different-flags ambiguity).

The Moonray-only deps that the tarball omits are built separately by
`building/gaffer/CMakeLists.txt` into the same prefix:

- ISPC v1.21.0 (Moonray's vector compiler, install bin/ispc)
- Random123 v1.14.0 (DEShaw counter-based PRNG, header-only)
- OpenImageDenoise v2.3.3 (Moonray's denoiser)
- log4cplus 2.0.5 (Rocky 8 EPEL ships 1.2.0, which lacks the
  `log4cplus::Logger::log(int, std::string const&, char const*, int)`
  file/line overload Moonray's render_logging code uses)

- libmicrohttpd 0.9.75 (Rocky 8 dnf ships 0.9.59, which lacks the
  `MHD_Result` enum that arras4_network/HttpServer.cc uses — added
  upstream in 0.9.71)

System packages installed via dnf into the gaffer-build container:

- cppunit 1.14.0
- lua-devel 5.3.4
- jsoncpp 1.8.4
- libatomic 8.5.0 + gcc-toolset-11-libatomic-devel (provides
  `/opt/rh/gcc-toolset-11/.../libatomic.so` symlink — the bare libatomic
  rpm only installs the versioned `.so.1`)
- git-lfs 3.4.1

(log4cplus and libmicrohttpd are built from source — see "Moonray-only
deps" above — not installed via dnf, since RL8 ships them too old.)

(Boost, OpenVDB, oneTBB intentionally NOT installed via dnf — those
come from the tarball.)

### Container quirks (one-shot fix via `building/gaffer/setup-container.sh`)

- `/usr/local/include/tbb/` ships an orphan TBB-2020 header tree
  (manually installed in the gaffer-build container, not owned by any
  rpm, not used by Gaffer's build). USD 26's `pxr/base/work/workTBB/`
  uses `__has_include(<tbb/tbb_stddef.h>)` to detect legacy TBB; the
  orphan headers tripped this and led USD to use removed `tbb::task`
  APIs. The setup script moves them aside to
  `/usr/local/include/tbb.disabled-by-moonray-port/`.

## What was patched

### Direct commits to this fork

(Tracked in git, additive; do not interfere with upstream rebases.)

| File | Change |
|---|---|
| `CLAUDE.md` | Soft-fork constitution. |
| `dependencies/moonray-patches/README.md` | Patch convention. |
| `dependencies/moonray-patches/10-building-skip-rats-without-BUILD_TESTING.patch` | Gate `add_subdirectory(rats)` on `BUILD_TESTING` so the configure doesn't fail when OIIO's `idiff` CLI tool is unavailable. |
| `dependencies/moonray-patches/20-scene_rdl2-NumaUtil-container-fallbacks.patch` | NUMA topology fallbacks in `scene_rdl2/lib/common/grid_util/NumaUtil.cc` — fall back to single-node UMA defaults (sysconf-derived mem/cpu, distance=10) when `/sys/devices/system/node/` is absent (macOS Docker Desktop's Linux VM hides the topology), and treat `mbind()` rejection as non-fatal. |
| `dependencies/moonray-patches/21-moonray_sdr_plugins-usd-26-ndr-to-sdr.patch` | USD 26 dropped the `ndr` library and renamed types to `Sdr*`. Migrates `moonray_sdr_plugins`: `pxr/usd/ndr/*` → `pxr/usd/sdr/*` includes; `Ndr*` → `Sdr*` / `SdrShader*` types; `NDR_REGISTER_*_PLUGIN` → `SDR_REGISTER_*_PLUGIN`; `DiscoverNodes` → `DiscoverShaderNodes`; `Parse` → `ParseShaderNode`; `GetInvalidNode` → `GetInvalidShaderNode`; drop `ndr` from CMakeLists target_link_libraries; uncomment `Python::Module` to provide pyconfig.h via interface include. |
| `dependencies/moonray-patches/22-hdMoonray-usd-26-IsSupported-and-pxr-python-link.patch` | USD 26 added a new pure-virtual `IsSupported(HdRendererCreateArgs const&, std::string*)` on `HdRendererPlugin`. Adds the override to both `HdMoonrayRendererPlugin` and `HdMoonrayRendererDebugPlugin`, gated on `PXR_VERSION >= 2603`. Also adds the USD `python` library (libusd_python.so, USD 26's bundled boost::python) to `hd_render` and `hd_usd2rdl` target_link_libraries. |
| `dependencies/moonray-patches/23-arras4_core-log_client-Boost-headers-link.patch` | `arras4_client/lib/log_client/LogClient.cc` includes `boost/algorithm/string.hpp` but the CMakeLists didn't link `Boost::headers`. Once Boost moved out of system /usr/include into the gaffer-deps tarball, the header search broke. Add the link. |
| `dependencies/moonray-patches/24-hdMoonray-visibility-primvars-on-first-sync.patch` | `GeometryMixin::restoreVisibility` had an `if (!mForcedInvisible) return;` early-return guard that meant `moonray:visible_*` per-component visibility primvars were silently ignored on first-sync visible rprims (only honoured after an invisible→visible transition during IPR). Fix: drop the early-return so the visible-branch path always re-reads the primvars. Discovered during GafferMoonray Phase 5-A; pure correctness bug fix, upstream-acceptable. |
| `scripts/apply-gaffer-patches.sh` | Idempotent patch applier; iterates `dependencies/moonray-patches/*.patch` in lexical order. |
| `building/gaffer/CMakeLists.txt` | ExternalProject build for ISPC, Random123, OpenImageDenoise, log4cplus 2.0.5, libmicrohttpd 0.9.75 into the gaffer-deps prefix. |
| `building/gaffer/setup-gaffer-deps.sh` | One-shot setup: rewrites the GitHub Actions build paths embedded in the tarball cmake configs, generates the pxr shim, copies + corrects the OpenImageIO shim. |
| `building/gaffer/setup-container.sh` | Container-quirks fixup (currently moves `/usr/local/include/tbb/` aside). Both Moonray and Gaffer sessions should run this before their first build. |
| `building/gaffer/cmake-shim/README.md` | Documentation for the shim-overlay pattern. |
| `CMakeLinuxPresets.json` | Adds `gaffer-environment` (hidden) and `gaffer-release` (configure preset → install at `/work/_install/moonray-gaffer`). Untouched: `rocky9-*` presets. |

### Overlay shim at `/work/_install/gaffer-deps-shim/`

(Generated at setup time, NOT in this repo. Re-runnable.)

| `lib/cmake/pxr/{pxrConfig,pxrTargets}.cmake` | Synthetic pxr cmake config for USD v26.03 — Gaffer's tarball ships the libusd_*.so files but omits the cmake config. |
| `lib/cmake/OpenImageIO/{OpenImageIOConfig,OpenImageIOTargets,OpenImageIOTargets-release}.cmake` | Copy of the tarball OIIO configs with the missing CLI-tool entries (iconvert, idiff, igrep, iinfo, testtex) stripped, and `PACKAGE_PREFIX_DIR` / `_CURR_INSTALL_LIBDIR` re-anchored to the real gaffer-deps prefix. |

The `gaffer-release` preset's `CMAKE_PREFIX_PATH` puts the shim FIRST,
so its corrected configs win over the broken tarball ones via
find_package's first-match wins rule.

## Setup workflow (single-shot)

From a fresh `gaffer-build` container with this repo at
`/work/openmoonray`:

```bash
# 1. Initialize submodules from upstream dreamworksanimation/*
cd /work/openmoonray
git submodule init
git config --get-regexp '^submodule\..*\.url$' | while read key url; do
    name="${key#submodule.}"; name="${name%.url}"
    upstream="${url##*/}"; upstream="${upstream%.git}"
    git config "submodule.${name}.url" "https://github.com/dreamworksanimation/${upstream}.git"
done
git submodule update --recursive --depth 1

# 2. Apply the Phase 0 patch set
./scripts/apply-gaffer-patches.sh

# 3. Extract Gaffer dep tarball
cd /work/_install
curl -fsSL -o /tmp/gd.tar.gz \
    https://github.com/GafferHQ/dependencies/releases/download/11.0.0a6/gafferDependencies-11.0.0a6-linux-platform25.tar.gz
rm -rf gaffer-deps
tar xzf /tmp/gd.tar.gz
mv gafferDependencies-11.0.0a6-linux-platform25 gaffer-deps

# 4. Install minimum system packages (log4cplus, cppunit, lua-devel,
#    libmicrohttpd, jsoncpp, libatomic, git-lfs).
dnf install -y --setopt=install_weak_deps=False \
    log4cplus-devel cppunit-devel lua-devel libmicrohttpd-devel \
    jsoncpp-devel libatomic git-lfs

# 5. Build Moonray-only deps (ISPC, Random123, OpenImageDenoise) into
#    the gaffer-deps prefix.
mkdir -p /work/_build/moonray-deps && cd /work/_build/moonray-deps
cmake /work/openmoonray/building/gaffer
cmake --build . -j $(nproc)

# 6. Generate the cmake shim overlay.
/work/openmoonray/building/gaffer/setup-gaffer-deps.sh

# 7. Configure + build Moonray.
cd /work/openmoonray
cmake --preset gaffer-release
cmake --build --preset gaffer-release -- -j $(nproc)
# Install lands at /work/_install/moonray-gaffer
```

## Container / OS notes

The `gaffer-build` container (`ghcr.io/gafferhq/build/build:3.4.0`) is
**Rocky Linux 8.8**, NOT Rocky 9. Moonray's upstream `building/Rocky9/`
material assumes RL9; we sidestep most of it by sourcing deps from the
tarball. The few system packages we install via dnf are present on RL8
in compatible versions.

Container-side toolchain (already provisioned):

- gcc 11.2.1 from `/opt/rh/gcc-toolset-11`
- cmake 3.27.2
- CUDA 11.8 toolkit at `/usr/local/cuda-11.8` (matches OptiX 7.6 reqs
  for v2 Phase 7; we disable OptiX in Phase 0 via `MOONRAY_USE_OPTIX=NO`)

## Build status

- Configure: **OK** (~26s on emulated x86_64).
- Compile: **OK** — 100%, 0 errors. ~30 min full clean build under -j2
  (sharing the container with concurrent Gaffer builds; would be faster
  with full parallelism).
- Install: populated at `/work/_install/moonray-gaffer/{bin,coredata,
  include,lib64,plugin,python,rdl2dso,scripts,sessions,testSuite}`.
- Smoke render: `moonray -in testdata/rectangle.rdla -out
  /tmp/rectangle.exr` produces a 345 KB EXR with render time ~6.5s.

## Known limitations (Phase 0 scope)

| | Status | Notes |
|---|---|---|
| Standalone CLI render (`moonray -in rectangle.rdla`) | ✅ verified | Render time 6.5s, output 345 KB EXR. Phase 0 acceptance test per PLAN.md — passing. |
| `hd_render` via hdMoonray (`-renderer "Moonray (debug)"`) | ✅ verified | Hydra-routed render of `testdata/sphere.usd`; render time 14.2s, output 36 KB EXR. Confirms hdMoonray's in-process Rndr path works against the patched USD 26 / Boost 1.85 / Python 3.11 stack — the integration target Phase 2 (`IECoreSceneHydra`) will route through. Required env: `LD_LIBRARY_PATH`, `PXR_PLUGINPATH_NAME`, `RDL2_DSO_PATH`, `MOONRAY_CLASS_PATH`, `PYTHONHOME=/work/_install/gaffer-deps`, `ARRAS_SESSION_PATH`, `REZ_MOONRAY_ROOT`. |
| `hd_render` default Arras path (no `-renderer` flag) | Known limitation, narrow scope | Default path is `HdMoonrayRendererPlugin` (Arras-using). The original "Failed to exec mcrt" error was misdiagnosed: `mcrt` is a *computation name* (loads `libcomputation_progmcrt.so`), not a binary. The actual binary is `execComp` (`arras/distributed/arras4_node/lib/session/ComputationConfig.cc:82`) which IS shipped at `bin/execComp`. **Suspected** root cause: `execComp` not on PATH when `hd_render` was run in Phase 0 testing. `scripts/setup.sh:21` already prepends `${omr_root}/bin` to PATH; sourcing it should resolve. Verification deferred (multiple foreground attempts on Rosetta-emulated x86_64 hit harness/buffer issues; native-Linux re-run is the cheap definitive check, not scheduled per supervisor sign-off). Out of Phase 0 scope to bottom-out; Gaffer Phase 2 calls `HdRendererPlugin::CreateRenderDelegate()` directly via C++ API, bypassing both `hd_render` CLI and Arras worker forking. |
| `moonray_gui` (Qt5 viewer) | Disabled (`BUILD_QT_APPS=NO`) | Out of scope; Gaffer drives via hdMoonray. Source intact for future flip. |
| OptiX / XPU / CUDA path | Disabled (`MOONRAY_USE_OPTIX=NO`) | v2 Phase 7. CUDA 11.8 toolkit present in container; only OptiX 7.6 SDK install missing. |
| Arras distributed | Built as part of the install | Configuration deferred to v2 Phase 8. |
| Regression tests (`rats/`) | Disabled (`BUILD_TESTING=NO`) | Patched. Every test in `rats/tests/{hd_render,moonray}/**` invokes the `RatsTest()` cmake macro which uses OIIO `idiff` for pixel-reference pass/fail. The Gaffer tarball ships `oiiotool` and `maketx` but not `idiff`. There's no idiff-free test subset to enable. Re-enabling requires one of: (a) building `idiff` from OIIO source (~2 hr), (b) patching `rats/cmake/RatsTest.cmake` to substitute `oiiotool --diff` (OIIO 3.0's oiiotool subsumed most of idiff's behaviour; the diff tolerance flags map cleanly), or (c) patching `RatsTest.cmake` to add a no-diff variant. All three deferred to v2 if regression infra is wanted then. |
| OpenColorIO 2.4.2 vs Moonray's expected 2.2.1 | Functional, metadata-name drift only | Smoke render of `testdata/rectangle.rdla` succeeds with no API failures. EXR metadata tag is `oiio:ColorSpace: "lin_rec709"` (the OCIO 2.4 + ACES-v2.0 config name) where 2.2 + ACES-v1.3 would have produced `"linear"`. Pixel values **appear visually consistent**; no numerical reference comparison was performed (would require a sibling OCIO-2.2 build for a 1:1 EXR diff — deferred unless a downstream consumer reports a regression). Both names refer to scene-referred linear Rec.709 at the math level. Caveat: downstream tools that pattern-match the literal string `linear` (e.g. some Nuke gizmos) will miss `lin_rec709`; that's a downstream-integration concern, not a Moonray-side bug. |
| NUMA topology | Patched to fall back to single-node UMA | Required for macOS Docker Desktop (no `/sys/devices/system/node/` exposed). All four `/sys/devices/system/node/*` reads use `if (!probe.is_open()) { fallback } else { original }` — real Linux hosts hit the original code path unchanged. The `mbind()` syscall fallback (line 543 of NumaUtil.cc, post-patch) is unconditional once mbind returns nonzero; on real NUMA hosts mbind succeeds and the fallback path doesn't execute. On degraded-NUMA hosts (cgroup restrictions, unusual kernel), what was previously a hard throw is now a logged warn-once + default kernel page placement. Patch header documents the gating contract. |
| TBB orphan-headers move (`setup-container.sh`) is one-way | Documented restore command | The script renames `/usr/local/include/tbb` → `/usr/local/include/tbb.disabled-by-moonray-port` to unblock USD 26's `__has_include(<tbb/tbb_stddef.h>)` detection. There's no auto-restore. To restore (e.g. another container tenant who needs the legacy headers): `mv /usr/local/include/tbb.disabled-by-moonray-port /usr/local/include/tbb`. |
| `setup-gaffer-deps.sh` SHIM_PREFIX mutation has no cross-session lock | Documented race window | Each invocation `rm -rf $SHIM_PREFIX` then re-creates it. If the Gaffer-side build is mid-`find_package(pxr)` while the Moonray side re-runs setup, Gaffer may see a partial shim and error. Currently informal coordination — no lock file. Acceptable since setup is rare (after tarball re-extract or rebase) and recovery is just re-running the failed build. v2 polish item: add a flock around the rm + regen. |
| OpenImageIO tool-removal regex relies on a banner string | Documented — tested at v3.0.6.1 | The Python regex in `setup-gaffer-deps.sh` matches `# Import target "OpenImageIO::<tool>"` comment banners in the cmake target export file. If a future OIIO release changes that banner format, the shim regen silently no-ops and `find_package(OpenImageIO)` fails with "missing iconvert". The regex was tested against OIIO 3.0.6.1 (the gaffer-deps version). Worth a sanity-grep assertion at the end of the regen if we adopt newer OIIO. |
| Patch 23 (Boost::headers link) assumes ancestor `find_package(Boost ...)` is in scope | Documented | The arras4_core/log_client target inherits a `Boost::headers` IMPORTED target from a parent directory's `find_package(Boost REQUIRED COMPONENTS headers)`. Holds today via the gaffer-release preset; if a future arras refactor moves log_client outside that scope, patch 23 stops working silently (link error: undefined Boost::headers). |

## Hand-off to Gaffer session

Gaffer SConstruct should:

1. Set `MOONRAY_ROOT=/work/_install/moonray-gaffer` (where Phase 0
   installs).
2. Set `GAFFER_DEPS_ROOT=/work/_install/gaffer-deps` and use the
   *same* prefix for its own dep build (skip GafferHQ/dependencies
   download — the tarball is already extracted).
3. Prepend `/work/_install/gaffer-deps-shim` to its CMAKE_PREFIX_PATH
   (or the SCons equivalent) so the same OIIO/USD shims apply on
   the Gaffer side.
4. Verify Moonray's libs at `$MOONRAY_ROOT/lib/` are loadable from a
   process that already has gaffer-deps libs in scope:
   `ldd $MOONRAY_ROOT/lib/libmoonray_rendering_pbr.so` should show
   every NEEDED entry resolving inside `/work/_install/gaffer-deps`
   or `/usr/lib64`, never two copies of the same lib.

## Future-rebase notes

### Submodule pinning policy

Submodule pointers in this fork's index are **pinned to specific
upstream commits** (matching upstream tags). The `m` flag in `git
status` reflects working-tree content patches applied by
`scripts/apply-gaffer-patches.sh`, NOT pointer drift. A fresh clone
+ `git submodule update --init --recursive` (with the `insteadOf`
redirect from upstream `dreamworksanimation/*`) +
`apply-gaffer-patches.sh` reproduces this build's state exactly.

Pinned submodule SHAs at Phase 0 close-out (verbatim
`git submodule status --recursive` output):

```
 67803efe59fa3ca0012cefe6a4a6ff87fb5ee2dc arras/arras4_core (arras4_core-4.10.3.18)
 ac41d1510936fab8013d77b2cf3aac0ebd97aef0 arras/arras_render (arras_render-7.6.0.0)
 3196cb1f158d0f45a49b01d118c4b54838d9039e arras/distributed/arras4_node (arras4_node-4.7.1.9)
 a9e677ec2d91d22acf529848b4eb44e2d78853e6 arras/distributed/minicoord (heads/main)
 066c4cc6b1aba719b03ed39720a6fe82f94a958c cmake_modules (cmake_modules-1.1.0.0)
 6366b993e276708ee4289e236fccef47f3b89d30 moonray/hydra/hdMoonray (hdMoonray-7.6.0.0)
 77a0ed6dd3ff9389d46d0ca9e3471a56335b875a moonray/hydra/moonray_sdr_plugins (heads/main)
 e6a61476d44055090ae2b1b0e1770e436e718b1c moonray/mcrt_denoise (mcrt_denoise-7.2.0.0)
 2343dde0bae2f70141b1004371282405e2d82215 moonray/moonray (moonray-18.4.0.0)
 b079fba57a5c8ff25f9f27638baef81173f91f0b moonray/moonray_arras/mcrt_computation (mcrt_computation-16.4.0.0)
 90fd490429b5b238e44ec04d5364efc61d114022 moonray/moonray_arras/mcrt_dataio (mcrt_dataio-16.2.0.0)
 72f7af37576d4ce85d7930d83860200e5d3e752f moonray/moonray_arras/mcrt_messages (mcrt_messages-15.0.0.0)
 eda4e578a2adee2cd7478035e927e4b69c4f91bd moonray/moonray_dcc_plugins (heads/main)
 6836aa7aa581ea7c6a50b93add638861176de7ce moonray/moonray_gui (moonray_gui-18.5.0.0)
 32a6e64967677008bddf05ea2fc5fe5533c0f47b moonray/moonshine (moonshine-15.6.0.0)
 d3452328c52fa60d891b4d5d7fbd18a14d9ba632 moonray/moonshine_usd (moonshine_usd-15.6.0.0)
 2e68fc1aa618b545646ac7efb091fff38f347e1f moonray/render_profile_viewer (heads/main)
 b1309584b7340bc665fdbf0c2519e69b41b3a9f3 moonray/scene_rdl2 (scene_rdl2-16.2.0.0)
 f43a388d6e6b51a3437251454defea70b809a4a8 rats (heads/main)
```

The four entries showing `(heads/main)` instead of a tag are
DreamWorks repos that don't publish numbered releases — they're
pinned to specific upstream-main commits. If a future rebase needs
deterministic re-pinning of those, capture their `git log -1` SHA at
the time of the rebase.

### Rebase procedure

When rebasing this fork against a future upstream Moonray release:

1. `git submodule update --remote --merge` per submodule on a fresh
   branch. Verify the new pinned SHAs against the upstream-tag
   names in the table above.
2. Re-run `scripts/apply-gaffer-patches.sh`. Patches that fail to
   apply: hand-resolve, regenerate via `git diff > the.patch` from
   inside the submodule.
3. Re-run `building/gaffer/setup-gaffer-deps.sh` (regenerates the pxr
   shim from the actual `libusd_*.so` set, in case USD's lib roster
   changed).
4. Reconfigure + rebuild + smoke-render.
5. Update the SHA table above with the new pinned commits.
