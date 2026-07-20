#!/usr/bin/env bash
# Unit tests for check-orphaned-fixtures.sh. Each scenario builds a throwaway
# plugins/ tree, runs the detector, and asserts the outcome. The negative cases
# (a fixture no grader consumes) are the synthetic proof the gate catches the
# "looks-tested but graded by nothing" class it exists for.
set -uo pipefail

SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$SELF_DIR/check-orphaned-fixtures.sh"

PASS=0
FAIL=0
fail() {
  echo "FAIL: $*" >&2
  FAIL=$((FAIL + 1))
}
ok() {
  echo "ok: $*"
  PASS=$((PASS + 1))
}

# mk_repo <baseline-content>: throwaway repo with the detector installed and a
# baseline file at scripts/orphaned-fixtures-baseline.txt.
mk_repo() {
  local dir
  dir="$(mktemp -d)"
  mkdir -p "$dir/scripts"
  cp "$SCRIPT" "$dir/scripts/check-orphaned-fixtures.sh"
  printf '%s' "${1:-}" >"$dir/scripts/orphaned-fixtures-baseline.txt"
  printf '%s' "$dir"
}

# seed a skill's evals.json with an optional files[] entry
seed_skill() {
  local repo="$1" skill="$2" files_entry="$3"
  mkdir -p "$repo/$skill/evals/fixtures"
  cat >"$repo/$skill/evals/evals.json" <<JSON
{ "skill_name": "s", "evals": [ { "id": 1, "prompt": "p", "files": [$files_entry] } ] }
JSON
}

run_check() {
  local repo="$1"
  (cd "$repo" && bash scripts/check-orphaned-fixtures.sh --check 2>/dev/null)
}

# --- consumed via an eval files[] entry -> not an orphan --------------------
repo="$(mk_repo)"
seed_skill "$repo" "plugins/p/skills/s" '"evals/fixtures/used.md"'
printf 'x\n' >"$repo/plugins/p/skills/s/evals/fixtures/used.md"
if run_check "$repo" >/dev/null; then ok "files[]-referenced fixture passes --check"; else fail "files[]-referenced fixture wrongly flagged"; fi
rm -rf "$repo"

# --- consumed via a test file (basename) -> not an orphan ------------------
repo="$(mk_repo)"
seed_skill "$repo" "plugins/p/skills/s" ''
printf 'x\n' >"$repo/plugins/p/skills/s/evals/fixtures/by-test.md"
mkdir -p "$repo/plugins/p/skills/s/scripts"
printf 'assert_on fixtures/by-test.md\n' >"$repo/plugins/p/skills/s/scripts/thing.test.sh"
if run_check "$repo" >/dev/null; then ok "test-asserted fixture passes --check"; else fail "test-asserted fixture wrongly flagged"; fi
rm -rf "$repo"

# --- REFERENCE-NAME SUFFIX SIBLING: a referenced valid.json must NOT consume
# a new valid.json.bak (grep -w treated "." as a word boundary; the bounded
# match rejects filename-character neighbors) -> .bak sibling is an orphan ---
repo="$(mk_repo)"
seed_skill "$repo" "plugins/p/skills/s" '"evals/fixtures/valid.json"'
printf 'x\n' >"$repo/plugins/p/skills/s/evals/fixtures/valid.json"
printf 'x\n' >"$repo/plugins/p/skills/s/evals/fixtures/valid.json.bak"
out="$(cd "$repo" && bash scripts/check-orphaned-fixtures.sh --check 2>&1)"
rc=$?
if [[ $rc -ne 0 && "$out" == *"ORPHANED FIXTURE"*"valid.json.bak"* && "$out" != *"ORPHANED FIXTURE"*"fixtures/valid.json is"* ]]; then ok "suffix sibling of a referenced fixture red-lines (bounded basename match)"; else fail "reference-name suffix sibling not caught: rc=$rc out='$out'"; fi
rm -rf "$repo"

# --- SYNTHETIC ORPHAN: consumed by nothing -> --check fails ----------------
repo="$(mk_repo)"
seed_skill "$repo" "plugins/p/skills/s" ''
printf 'x\n' >"$repo/plugins/p/skills/s/evals/fixtures/orphan.md"
out="$(cd "$repo" && bash scripts/check-orphaned-fixtures.sh --check 2>&1)"
rc=$?
if [[ $rc -ne 0 && "$out" == *"ORPHANED FIXTURE"*"orphan.md"* ]]; then ok "un-consumed fixture fails --check (synthetic orphan caught)"; else fail "synthetic orphan not caught: rc=$rc out='$out'"; fi
rm -rf "$repo"

# --- orphan grandfathered by an exact baseline path -> passes --------------
repo="$(mk_repo $'plugins/p/skills/s/evals/fixtures/orphan.md\n')"
seed_skill "$repo" "plugins/p/skills/s" ''
printf 'x\n' >"$repo/plugins/p/skills/s/evals/fixtures/orphan.md"
if run_check "$repo" >/dev/null; then ok "grandfathered orphan (exact path) passes --check"; else fail "grandfathered orphan wrongly failed"; fi
rm -rf "$repo"

# --- baseline entry is EXACT, not a prefix: a .bak/.jsonl sibling of a
#     baselined file is NOT grandfathered and red-lines --------------------
repo="$(mk_repo $'plugins/p/skills/s/evals/fixtures/valid.json\n')"
seed_skill "$repo" "plugins/p/skills/s" ''
printf 'x\n' >"$repo/plugins/p/skills/s/evals/fixtures/valid.json"
printf 'x\n' >"$repo/plugins/p/skills/s/evals/fixtures/valid.json.bak"
printf 'x\n' >"$repo/plugins/p/skills/s/evals/fixtures/valid.jsonl"
out="$(cd "$repo" && bash scripts/check-orphaned-fixtures.sh --check 2>&1)"
rc=$?
if [[ $rc -ne 0 && "$out" == *"valid.json.bak"* && "$out" == *"valid.jsonl"* ]]; then ok "prefix-sibling of a baselined path red-lines (exact-match, no grandfather leak)"; else fail "baseline prefix-leak not caught: rc=$rc out='$out'"; fi
rm -rf "$repo"

# --- STALE baseline entry (shadows no orphan) -> fails ---------------------
repo="$(mk_repo $'plugins/p/skills/s/evals/fixtures/gone.md\n')"
seed_skill "$repo" "plugins/p/skills/s" '"evals/fixtures/used.md"'
printf 'x\n' >"$repo/plugins/p/skills/s/evals/fixtures/used.md"
out="$(cd "$repo" && bash scripts/check-orphaned-fixtures.sh --check 2>&1)"
rc=$?
if [[ $rc -ne 0 && "$out" == *"STALE BASELINE"* ]]; then ok "stale baseline entry fails --check"; else fail "stale baseline not caught: rc=$rc out='$out'"; fi
rm -rf "$repo"

# --- discover mode labels every fixture ------------------------------------
repo="$(mk_repo)"
seed_skill "$repo" "plugins/p/skills/s" '"evals/fixtures/used.md"'
printf 'x\n' >"$repo/plugins/p/skills/s/evals/fixtures/used.md"
printf 'x\n' >"$repo/plugins/p/skills/s/evals/fixtures/orphan.md"
out="$(cd "$repo" && bash scripts/check-orphaned-fixtures.sh discover 2>/dev/null)"
if [[ "$out" == *"CONSUMED"*"used.md"* && "$out" == *"ORPHAN"*"orphan.md"* ]]; then ok "discover labels CONSUMED and ORPHAN"; else fail "discover mislabels: '$out'"; fi
rm -rf "$repo"

# --- bad usage -> exit 2 ---------------------------------------------------
repo="$(mk_repo)"
(cd "$repo" && bash scripts/check-orphaned-fixtures.sh --nonsense >/dev/null 2>&1)
if [[ $? -eq 2 ]]; then ok "bad mode -> exit 2"; else fail "bad mode did not exit 2"; fi
rm -rf "$repo"

printf '\nPASS=%d FAIL=%d\n' "$PASS" "$FAIL"
((FAIL == 0))
