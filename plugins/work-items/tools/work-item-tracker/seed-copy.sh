#!/usr/bin/env bash
# Copy an adapter seed (seeds/<provider>/) into the consuming repo's adapter directory,
# the step /work-items:setup apply runs for a seeded provider. seeds/README.md has the
# re-run table: an untouched copy fast-forwards, an edited one prints the diff and stops.
#
# Usage: seed-copy.sh <provider> [--root <repo-root>]
# stdout: one status word (copied | up-to-date | fast-forwarded | edited), then the diff
# when edited. Exit 0 = copy current, 1 = edited copy left as-is, 2 = usage or no seed.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/binding.sh
source "$SCRIPT_DIR/lib/binding.sh"

# WIT_SEEDS_DIR overrides the seed root, as WIT_ADAPTERS_DIR does the adapter root (tests).
readonly SEEDS_DIR="${WIT_SEEDS_DIR:-$SCRIPT_DIR/seeds}"
readonly HASH_FILE=".seed-hash"

usage() {
  printf 'usage: seed-copy.sh <provider> [--root <repo-root>]\n' >&2
  exit 2
}

# seed_files <dir>: the seed's copied files, relative and sorted. The offline tests and
# the linear schema check need this plugin's test helpers and conformance bindings, so
# they stay in the plugin.
seed_files() {
  (cd "$1" && find . -type f \
    ! -name '*.test.sh' ! -name 'mock.sh' ! -name "$HASH_FILE" \
    ! -path './schema-check/*' -print | LC_ALL=C sort)
}

# copy_files <dir>: every file in a copy except its hash record, relative and sorted.
copy_files() {
  (cd "$1" && find . -type f ! -path "./$HASH_FILE" -print | LC_ALL=C sort)
}

sha256_stdin() {
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum | cut -d' ' -f1
  else
    shasum -a 256 | cut -d' ' -f1
  fi
}

# tree_hash <dir>: one hash over each path read from stdin (relative to <dir>) and its content.
tree_hash() {
  local dir="$1" rel
  while IFS= read -r rel; do
    printf '%s %s\n' "$rel" "$(sha256_stdin <"$dir/$rel")"
  done | sha256_stdin
}

# stage_seed <seed-dir> <stage-dir>: the copied file set, modes kept, plus its hash record.
stage_seed() {
  local seed="$1" stage="$2" rel
  while IFS= read -r rel; do
    mkdir -p "$stage/$(dirname "$rel")" && cp -p "$seed/$rel" "$stage/$rel" || return 1
  done < <(seed_files "$seed")
  seed_files "$seed" | tree_hash "$seed" >"$stage/$HASH_FILE"
}

provider=""
root=""
while [[ $# -gt 0 ]]; do
  case "$1" in
  --root)
    [[ $# -ge 2 && -n "$2" ]] || usage
    root="$2"
    shift 2
    ;;
  -h | --help) usage ;;
  -*) usage ;;
  *)
    [[ -z "$provider" ]] || usage
    provider="$1"
    shift
    ;;
  esac
done
[[ -n "$provider" ]] || usage
# The name becomes a path segment: constrain it before any path is built from it.
[[ "$provider" =~ ^[a-z][a-z0-9-]*$ ]] || usage

seed="$SEEDS_DIR/$provider"
if [[ ! -d "$seed" ]]; then
  known=""
  for d in "$SEEDS_DIR"/*/; do
    known+="$(basename "$d") "
  done
  printf "seed-copy: no seed for provider '%s'; seeds: %s\n" "$provider" "$known" >&2
  exit 2
fi
if [[ -z "$root" ]]; then
  root="$(wit_project_root)" || {
    printf 'seed-copy: no repo root (set CLAUDE_PROJECT_DIR, run inside a git checkout, or pass --root)\n' >&2
    exit 2
  }
fi

fail() {
  printf 'seed-copy: %s\n' "$1" >&2
  exit 2
}

dest="$root/tools/work-item-tracker/adapters/$provider"
mkdir -p "$(dirname "$dest")" || fail "cannot create $(dirname "$dest")"
stage="$(mktemp -d "$(dirname "$dest")/.seed-$provider.XXXXXX")" && [[ -d "$stage" ]] ||
  fail "cannot create a staging directory beside $dest"
trap 'rm -rf "$stage"' EXIT
# mktemp -d makes the directory owner-only; the adapter directory it becomes is not.
chmod 755 "$stage"
stage_seed "$seed" "$stage" || fail "cannot stage the $provider seed"
seed_hash="$(<"$stage/$HASH_FILE")"

if [[ ! -d "$dest" ]]; then
  mv "$stage" "$dest" || fail "cannot move the staged seed to $dest"
  printf 'copied\n'
  exit 0
fi

recorded=""
[[ -f "$dest/$HASH_FILE" ]] && recorded="$(<"$dest/$HASH_FILE")"
if [[ -z "$recorded" || "$(copy_files "$dest" | tree_hash "$dest")" != "$recorded" ]]; then
  # No record means the directory was not copied from a seed; either way it is the
  # consumer's, so show how it differs from the current seed and write nothing.
  printf 'edited\n'
  diff -ru -x "$HASH_FILE" "$stage" "$dest"
  exit 1
fi

if [[ "$recorded" == "$seed_hash" ]]; then
  printf 'up-to-date\n'
  exit 0
fi

# Swap through a backup so a failed move leaves the old copy in place.
backup="$stage.old"
mv "$dest" "$backup" || fail "cannot move $dest aside"
if ! mv "$stage" "$dest"; then
  mv "$backup" "$dest"
  fail "cannot move the staged seed to $dest; the previous copy is back in place"
fi
rm -rf "$backup"
printf 'fast-forwarded\n'
exit 0
