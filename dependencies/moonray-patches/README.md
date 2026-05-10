# Moonray patches for the Gaffer 1.6 dep stack

Soft-fork patches applied at build time so that this fork can be rebased
cleanly against upstream Moonray every 2–3 months. Direct edits to the
source tree are avoided where feasible — patches go here instead.

## Naming

Each patch is named `NN-<scope>-<one-line-summary>.patch`.

- `NN` — two-digit ordering. Lower numbers apply first.
- `<scope>` — the submodule the patch targets, or `building` for the
  top-level `building/Rocky9/CMakeLists.txt`. Examples: `scene_rdl2`,
  `moonshine`, `hdMoonray`, `building`.
- The trailing slug is for human readability only; the apply order is
  controlled by `NN`.

Each patch is generated with `git diff --no-prefix` from the working
tree of the relevant submodule (or the top-level repo for `building`),
so it can be applied with `patch -p0` from inside the target directory.
Use `git format-patch` or `git diff` flavoured for the corresponding
target — the apply script normalizes both forms.

## Apply (manual, before re-running CMake)

From the top-level openmoonray dir:

```bash
./scripts/apply-gaffer-patches.sh
```

That script (added in the same Phase 0 changeset) iterates
`dependencies/moonray-patches/*.patch` in lexical order and applies
each into its target submodule.

Re-running the script is idempotent: already-applied patches are
detected via `git apply --check` and skipped.

## Categories

- **building** — patches to the top-level `building/Rocky9/CMakeLists.txt`
  that bump the dep version pins (USD 23.08 → v26.03, Embree v4.2.0 →
  v4.4.0, OIIO 2.4.8.0 → 3.0.6.1, etc.) and add new ExternalProject
  entries (Imath, Boost, OpenVDB).
- **scene_rdl2** / **moonray** / **moonshine** / **hdMoonray** — source
  patches to handle API drift in the bumped deps. OIIO 2 → 3 and USD
  23 → 26 are the most likely sources.

## Out of scope (no patches here)

- log4cplus, ISPC, Random123 stay at Moonray's pins (Gaffer doesn't
  load these in-process; ABI-irrelevant).
- OptiX / CUDA: kept off via CMake gates (`-DMOONRAY_USE_OPTIX=NO`),
  not via source deletion. v2 Phase 7 work flips that flag.
- Qt / `moonray_gui`: kept off via `-DBUILD_QT_APPS=NO`. Source intact
  so a future Moonray-side debugging session can flip the gate without
  reconstructing the GUI integration.

## Rebase workflow

Every 2–3 months when upstream Moonray cuts a release:

1. `git submodule update --remote --merge` per submodule on a fresh branch.
2. Re-run `./scripts/apply-gaffer-patches.sh`.
3. For each patch that fails to apply: hand-resolve, re-export with
   `git diff --no-prefix > dependencies/moonray-patches/<same-name>.patch`.
4. Build, smoke-test against a reference scene, commit.
