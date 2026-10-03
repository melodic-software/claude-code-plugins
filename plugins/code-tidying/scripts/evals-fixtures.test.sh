#!/usr/bin/env bash
# Contract: every seeded eval fixture parses and self-certifies through
# change-shape.py, so a 0-score case is a skill regression. The UNPROVABLE
# excerpt's exit 21 is the point of the case it feeds, not a defect.
# When tree-sitter (or its grammar) is absent the self-certify checks skip
# visibly, matching test_change_shape.py. CI sets
# CODE_TIDYING_REQUIRE_TREE_SITTER=1 so a missing dependency fails there.
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
  if [[ "$got" != "$want" ]]; then
    fail "$name: change-shape exit $got, expected $want"
    return 1
  fi
}

# One probe. Exit 3 is change-shape's EXIT_NO_TOOLING (package or grammar).
self_certify=1
probe_src="$fixtures/${shell_fixtures[0]}"
if [[ -f "$probe_src" ]]; then
  cp "$probe_src" "$scratch/probe.sh"
  probe_rc=0
  python3 "$change_shape" --lang bash "$scratch/probe.sh" "$scratch/probe.sh" >"$scratch/probe.out" 2>"$scratch/probe.err" || probe_rc=$?
  if [[ "$probe_rc" -eq 3 ]]; then
    reason=""
    while IFS= read -r line; do
      case "$line" in
        "change-shape: UNAVAILABLE: "*) reason="${line#change-shape: UNAVAILABLE: }" ;;
        *) ;;
      esac
    done <"$scratch/probe.err"
    [[ -n "$reason" ]] || reason="tree-sitter is not installed"
    notice="change-shape tooling unavailable: ${reason}; install the locked set with: pip install -r .github/requirements-ci.txt"
    if [[ -n "${CODE_TIDYING_REQUIRE_TREE_SITTER:-}" ]]; then
      fail "$notice"
    else
      printf 'SKIP: %s\n' "$notice"
    fi
    self_certify=0
  fi
fi

for file in "${shell_fixtures[@]}"; do
  src="$fixtures/$file"
  [[ -f "$src" ]] || {
    fail "$file is missing"
    continue
  }
  passed=1
  bash -n "$src" || {
    fail "$file does not parse as bash"
    passed=0
  }
  if [[ "$self_certify" -eq 1 ]]; then
    set +e
    check_self_certifies "$src" "${file%.txt}" bash 0
    cert_rc=$?
    set -e
    [[ "$cert_rc" -eq 0 ]] || passed=0
  fi
  if [[ "$passed" -eq 1 ]]; then
    if [[ "$self_certify" -eq 1 ]]; then
      ok "$file parses and self-certifies COMMENT-ONLY"
    else
      ok "$file parses"
    fi
  fi
done

for file in "${python_fixtures[@]}"; do
  src="$fixtures/$file"
  [[ -f "$src" ]] || {
    fail "$file is missing"
    continue
  }
  passed=1
  cp "$src" "$scratch/${file%.txt}"
  python3 -m py_compile "$scratch/${file%.txt}" || {
    fail "$file does not compile"
    passed=0
  }
  if [[ "$self_certify" -eq 1 ]]; then
    set +e
    check_self_certifies "$src" "${file%.txt}" python 0
    cert_rc=$?
    set -e
    [[ "$cert_rc" -eq 0 ]] || passed=0
  fi
  if [[ "$passed" -eq 1 ]]; then
    if [[ "$self_certify" -eq 1 ]]; then
      ok "$file compiles and self-certifies COMMENT-ONLY"
    else
      ok "$file compiles"
    fi
  fi
done

if [[ "$self_certify" -eq 1 ]]; then
  set +e
  check_self_certifies "$fixtures/$unprovable_fixture" "${unprovable_fixture%.txt}" bash 21
  cert_rc=$?
  set -e
  if [[ "$cert_rc" -eq 0 ]]; then
    ok "$unprovable_fixture still reads UNPROVABLE (exit 21)"
  fi
fi

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
