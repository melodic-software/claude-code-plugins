#!/usr/bin/env bash
# Regenerate a pull request's shared-library copies on a clean merge of the
# pinned base, with the base's tooling only: pr-unblock's sync-shared-copies
# activity, after pr-merge refused the head as shared-copy-sources-changed.
#
#   sync-shared-copies.sh <base-dir> <head-dir> <base-sha> <out-patch>
#
# <base-dir> is the default branch tip checkout, <head-dir> the PR head with
# <base-sha> merged into it and not committed (merge-base/prepare.sh's clean
# state). No head code runs:
# - the head's merged scripts/sync-shared-copies.sh, scripts/shared-copies.txt
#   and scripts/lib must equal <base-sha>'s, or it refuses
#   shared-copy-tooling-changed;
# - the base's script and scripts/lib are copied outside the checkout and run
#   from there, so the registry they read is the base's (checked above);
# - every path the run writes must be a copy the base-tip
#   scripts/shared-copies.txt registers, or it refuses
#   shared-copy-path-unregistered and writes no patch.
# Writes <out-patch> (a binary diff against the merge) and prints
# state=written|empty, sha256=<hex> and paths=<n>, or refused=<reason>.
# Empty means the merge already holds current copies, which
# apply-shared-copies then pushes as the merge alone.
# Exit 0, 3 on a refusal, 2 on a usage error.
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

# The registry's copy column, from the base checkout: `<canonical> <copy>`,
# everything from a `#` on stripped as scripts/sync-shared-copies.sh strips it.
declare -A registered=()
while IFS= read -r line || [[ -n $line ]]; do
  line=${line%%#*}
  src="" copy="" extra=""
  read -r src copy extra <<<"$line" || true
  [[ -n $src && -n $copy && -z $extra ]] || continue
  registered[$copy]=1
done <"$base_dir/scripts/shared-copies.txt"

bin=$(mktemp -d)
trap 'rm -rf "$bin"' EXIT
mkdir -p "$bin/scripts"
cp "$base_dir/scripts/sync-shared-copies.sh" "$bin/scripts/"
cp -R "$base_dir/scripts/lib" "$bin/scripts/lib"
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
