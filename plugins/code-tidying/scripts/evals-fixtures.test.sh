#!/usr/bin/env bash
# Contract: every fixture the dissolve-comments eval suite seeds still parses in
# its own language and still self-certifies through change-shape.py, so a case
# that scores 0 means the skill regressed rather than the corpus rotting. The
# UNPROVABLE excerpt is named here because its exit 21 is the point of the case
# it feeds, not a defect.
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
plugin="$(cd "$here/.." && pwd)"
fixtures="$plugin/evals/fixtures"
change_shape="$plugin/scripts/change-shape.py"
rc=0

ok() { printf 'ok: %s\n' "$1"; }
fail() {
  printf 'FAIL: %s\n' "$1" >&2
  rc=1
}

shell_fixtures=(
  check-markers.sh.txt
  class-a.sh.txt
  class-b.sh.txt
  class-b.test.sh.txt
  class-c.sh.txt
  edge-marker.sh.txt
  edge-paired.sh.txt
  edge-paired.test.sh.txt
  hook-utils-header.sh.txt
  silent-revert-design.sh.txt
  statusline-stamp.sh.txt
)
python_fixtures=(edge_docstring.py.txt exempt.py.txt)
other_fixtures=(Makefile.txt dc-notes.md.txt restoration-markers.txt.txt)
unprovable_fixture=hook-utils-unprovable.sh.txt

scratch="$(mktemp -d)"
trap 'rm -rf "$scratch"' EXIT

check_self_certifies() {
  local src="$1" name="$2" lang="$3" want="$4" got=0
  cp "$src" "$scratch/$name"
  python3 "$change_shape" --lang "$lang" "$scratch/$name" "$scratch/$name" >/dev/null 2>&1 || got=$?
  [[ "$got" == "$want" ]] || fail "$name: change-shape exit $got, expected $want"
}

for file in "${shell_fixtures[@]}"; do
  src="$fixtures/$file"
  [[ -f "$src" ]] || {
    fail "$file is missing"
    continue
  }
  bash -n "$src" || fail "$file does not parse as bash"
  check_self_certifies "$src" "${file%.txt}" bash 0
  ok "$file parses and self-certifies COMMENT-ONLY"
done

for file in "${python_fixtures[@]}"; do
  src="$fixtures/$file"
  [[ -f "$src" ]] || {
    fail "$file is missing"
    continue
  }
  cp "$src" "$scratch/${file%.txt}"
  python3 -m py_compile "$scratch/${file%.txt}" || fail "$file does not compile"
  check_self_certifies "$src" "${file%.txt}" python 0
  ok "$file compiles and self-certifies COMMENT-ONLY"
done

check_self_certifies "$fixtures/$unprovable_fixture" "${unprovable_fixture%.txt}" bash 21
ok "$unprovable_fixture still reads UNPROVABLE (exit 21)"

for file in "${other_fixtures[@]}"; do
  [[ -f "$fixtures/$file" ]] || fail "$file is missing"
done
ok "the non-source fixtures are present"

# Every fixture ships to feed a case: a scaffold must seed it by name.
for src in "$fixtures"/*.txt; do
  base="$(basename "$src" .txt)"
  grep -rqF -- "$base" "$plugin"/evals/*/scaffold.sh "$fixtures/seed.sh" ||
    fail "$base is seeded by no scaffold"
done
ok "every fixture is seeded by a scaffold"

exit "$rc"
