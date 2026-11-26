#!/usr/bin/env bash
# Exit 0, 3 on a refusal, 2 on a usage error or a malformed base registry.
set -euo pipefail

if (($# != 4)); then
  echo "usage: sync-shared-copies.sh <base-dir> <head-dir> <base-sha> <out-patch>" >&2
  exit 2
fi
base_dir=$1 head_dir=$2 base_sha=$3 out=$4
[[ $base_sha =~ ^[0-9a-f]{40}$ ]] || {
  echo "error: <base-sha> is not a commit id" >&2
  exit 2
}
export GIT_NO_REPLACE_OBJECTS=1

refuse() {
  echo "refused=$1"
  echo "::error::$2" >&2
  exit 3
}

tooling=(scripts/sync-shared-copies.sh scripts/shared-copies.txt scripts/lib)
if ! git -C "$head_dir" diff --quiet "$base_sha" -- "${tooling[@]}" ||
  [[ -n $(git -C "$head_dir" ls-files --others -- "${tooling[@]}") ]]; then
  refuse shared-copy-tooling-changed "the head changes the sync script, its registry or scripts/lib; a person regenerates the copies"
fi

bin=$(mktemp -d)
trap 'rm -rf "$bin"' EXIT
mkdir -p "$bin/scripts"
cp "$base_dir/scripts/sync-shared-copies.sh" "$bin/scripts/"
cp -R "$base_dir/scripts/lib" "$bin/scripts/lib"

manifest=$(cd "$base_dir" && bash "$bin/scripts/sync-shared-copies.sh" --print-manifest)
declare -A registered=()
while IFS=$'\t' read -r kind path; do
  [[ $kind == copy ]] && registered[$path]=1
done <<<"$manifest"

(cd "$head_dir" && bash "$bin/scripts/sync-shared-copies.sh") >&2

mapfile -t written < <(
  git -C "$head_dir" diff --name-only
  git -C "$head_dir" ls-files --others
)
for path in "${written[@]}"; do
  [[ -n ${registered[$path]:-} ]] ||
    refuse shared-copy-path-unregistered "the sync wrote $path, which the base registry lists as no copy"
done

if ((${#written[@]} == 0)); then
  : >"$out"
  echo "state=empty"
  echo "paths=0"
  exit 0
fi
git -C "$head_dir" add --intent-to-add -- "${written[@]}"
git -C "$head_dir" diff --binary -- "${written[@]}" >"$out"
sum=$(sha256sum <"$out")
echo "state=written"
echo "sha256=${sum%% *}"
echo "paths=${#written[@]}"
