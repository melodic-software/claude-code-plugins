#!/usr/bin/env bash
# build-fixture.sh — materialize the committed fixture tree as a throwaway repo.
#
# The three suites beside it drive their scripts against a real git repository,
# because the scripts ask the INDEX what exists rather than the filesystem. This
# builder is what makes each suite's cases start from the same tree.
#
# Fixture git isolation: an inherited GIT_DIR/GIT_WORK_TREE/GIT_CONFIG would
# redirect `git init` / `git config` into the caller's repository.
set -uo pipefail
unset GIT_DIR GIT_WORK_TREE GIT_CONFIG

# build-fixture.sh <destination> [--variant collision|clean]
dest="${1:?usage: build-fixture.sh <destination> [--variant <name>]}"
variant="clean"
if [[ "${2:-}" == "--variant" ]]; then
  variant="${3:?--variant needs a name}"
fi

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

mkdir -p "$dest"
cp -R "$here/tree/." "$dest/"
mkdir -p "$dest/.claude"
cp "$here/config.json" "$dest/.claude/docs-hygiene.json"
chmod +x "$dest/tools/gen.sh"

case "$variant" in
collision)
  # A lowercase twin of an offender's proposed name already exists, so the plan
  # would put two paths differing only by case into one tree.
  printf '# beta\n\nThe lowercase twin that makes the BETA.md proposal a collision.\n' >"$dest/docs/beta.md"
  ;;
clean) ;;
*)
  printf 'build-fixture: unknown variant %s\n' "$variant" >&2
  exit 2
  ;;
esac

git init -q "$dest"
git -C "$dest" config user.email fixture@example.invalid
git -C "$dest" config user.name "Fixture"
git -C "$dest" config commit.gpgsign false
git -C "$dest" config core.autocrlf false
git -C "$dest" add -A >/dev/null
git -C "$dest" commit -qm "fixture tree" >/dev/null
printf '%s\n' "$dest"
