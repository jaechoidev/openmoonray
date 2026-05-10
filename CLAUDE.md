# Moonray fork for Gaffer integration

This is a soft fork of OpenMoonRay maintained for the Gaffer port.
**Do not push patches to upstream `dreamworksanimation/openmoonray`
without explicit user approval.**

## Goal

Build Moonray against Gaffer 1.6's dep stack so binaries are ABI-compatible
in the same process:

- Python 3.11.14 (upstream Moonray expects 3.9)
- OpenUSD 26.05 (upstream Moonray uses likely 24.x or 25.x)
- Boost 1.85.0 (upstream Moonray likely 1.78–1.82)
- oneTBB 2021.13.0
- OpenImageIO 3.0.6.1 (upstream Moonray likely 2.4–2.5)
- OpenEXR 3.3.6, Imath 3.1.12, Embree 4.4.0

## Strategy

Soft fork. Keep upstream Moonray clean. Patches live in
`dependencies/moonray-patches/*.patch`, applied at build time. Rebase
against new Moonray releases periodically (every 2–3 months).

## Plan

Full port plan and operational runbook live in the shared planning
directory (sibling to both repos, mounted at `/work/PLAN/` in the
container):

- Host:      `../PLAN/PLAN.md`, `../PLAN/WORKFLOW.md`
- Container: `/work/PLAN/PLAN.md`, `/work/PLAN/WORKFLOW.md`

PLAN.md is the canonical port plan; WORKFLOW.md is the Pattern A
operational runbook (container setup, `dexec` helper, daily commands).
Both are owned by neither session — they're shared so updates from
either side are immediately visible to the other.

This session owns **Phase 0 only** — porting Moonray's build to match
Gaffer's dep stack and producing a working install at
`/work/_install/moonray-gaffer` (visible from the host as
`<host work dir>/_install/moonray-gaffer`).

## Output

When Phase 0 is complete, hand off to the Gaffer session:

1. A working `MOONRAY_ROOT` install at `/work/_install/moonray-gaffer`
   containing libs, headers, and DSOs that the Gaffer SConstruct can
   link against.
2. The patch set in `dependencies/moonray-patches/*.patch`.
3. A short status report on what was patched, what's outstanding, and
   any known limitations.

## Branching

- All work happens on `feature/gaffer-deps-port`.
- Do NOT push to `dreamworksanimation/openmoonray`. Pushes only to this
  fork.

## Build commands

All builds run inside the `gaffer-build` Docker container via the
`dexec` wrapper on the host PATH (see `../PLAN/WORKFLOW.md`).
Example:

    dexec cmake --build /work/openmoonray/build --parallel

## Companion session

Gaffer-side work happens in a separate Claude session running against
the sibling `../gaffer` clone. Coordinate via the shared filesystem
(`/work/` inside the build container; sibling host paths outside it)
and PLAN.md updates.
