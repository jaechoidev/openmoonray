#!/usr/bin/env bash
# Apply dependencies/moonray-patches/*.patch to this repo and submodules.
# Idempotent: already-applied patches are skipped.
#
# Patch naming: NN-<scope>-<slug>.patch
#   - NN     : two-digit ordering, lower applies first
#   - scope  : the submodule the patch targets, OR "building" / "scripts"
#              for top-level files in the openmoonray repo itself.
#
# A patch's scope determines its target dir. Mapping:
#   building  -> .   (top-level openmoonray)
#   scripts   -> .   (top-level openmoonray)
#   <other>   -> first matching submodule path containing that segment
#                (e.g. scene_rdl2 -> moonray/scene_rdl2)

set -euo pipefail

cd "$(git rev-parse --show-toplevel)"
patch_dir="dependencies/moonray-patches"

if [[ ! -d $patch_dir ]]; then
    echo "No patch dir at $patch_dir — nothing to do." >&2
    exit 0
fi

shopt -s nullglob
patches=( "$patch_dir"/*.patch )
shopt -u nullglob

if (( ${#patches[@]} == 0 )); then
    echo "No patches in $patch_dir — nothing to do." >&2
    exit 0
fi

resolve_target() {
    local scope=$1
    case "$scope" in
        building|scripts|toplevel) echo "."; return 0 ;;
    esac
    # Walk submodule list for first path with this scope as basename or
    # one of its trailing path components.
    local match
    match=$(git config --file .gitmodules --get-regexp '\.path$' \
            | awk -v s="$scope" '$2 ~ ("(^|/)" s "$") { print $2; exit }')
    if [[ -z $match ]]; then
        echo "ERROR: no submodule path matches scope '$scope'" >&2
        return 1
    fi
    echo "$match"
}

for p in "${patches[@]}"; do
    fname=$(basename "$p")
    # Expect NN-scope-...
    if [[ ! $fname =~ ^[0-9]{2}-([^-]+)- ]]; then
        echo "Skipping malformed patch name: $fname" >&2
        continue
    fi
    scope=${BASH_REMATCH[1]}
    target=$(resolve_target "$scope")
    abs_patch=$(cd "$(dirname "$p")" && pwd)/$fname

    pushd "$target" >/dev/null
    if git apply --check --reverse "$abs_patch" >/dev/null 2>&1; then
        echo "[skip]  $fname (already applied in $target)"
    elif git apply --check "$abs_patch" >/dev/null 2>&1; then
        echo "[apply] $fname -> $target"
        git apply "$abs_patch"
    else
        echo "[FAIL]  $fname -> $target (rejects below)" >&2
        git apply --reject "$abs_patch" || true
        popd >/dev/null
        exit 1
    fi
    popd >/dev/null
done

echo "All patches applied."
