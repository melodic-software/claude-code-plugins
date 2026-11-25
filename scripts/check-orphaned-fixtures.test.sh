#!/usr/bin/env bash
set -uo pipefail

SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$SELF_DIR/check-orphaned-fixtures.sh"

# shellcheck source=lib/test-harness.sh
. "$SELF_DIR/lib/test-harness.sh"
# shellcheck source=lib/fixture-tree.sh
. "$SELF_DIR/lib/fixture-tree.sh"

repo=""

mk_repo() {
  local out="$1"
  fixture_tree::build "$out" --sut "$SCRIPT" || return 1
  printf '%s' "${2:-}" >"${!out}/scripts/orphaned-fixtures-baseline.txt"
}

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

run_check_out() {
  local repo="$1"
  (cd "$repo" && bash scripts/check-orphaned-fixtures.sh --check 2>&1)
}

mk_repo repo
seed_skill "$repo" "plugins/p/skills/s" '"evals/fixtures/used.md"'
printf 'x\n' >"$repo/plugins/p/skills/s/evals/fixtures/used.md"
if run_check "$repo" >/dev/null; then ok "files[]-referenced fixture passes --check"; else fail "files[]-referenced fixture wrongly flagged"; fi
rm -rf "$repo"

mk_repo repo
seed_skill "$repo" "plugins/p/skills/s" '"evals/fixtures/a.md", "evals/fixtures/b.md"'
printf 'x\n' >"$repo/plugins/p/skills/s/evals/fixtures/a.md"
printf 'x\n' >"$repo/plugins/p/skills/s/evals/fixtures/b.md"
if run_check "$repo" >/dev/null; then ok "two files[]-referenced fixtures in one grader both pass --check"; else fail "cached files[] extract missed a sibling fixture"; fi
rm -rf "$repo"

mk_repo repo
seed_skill "$repo" "plugins/p/skills/s" ''
printf 'x\n' >"$repo/plugins/p/skills/s/evals/fixtures/by-test.md"
mkdir -p "$repo/plugins/p/skills/s/scripts"
printf 'assert_on fixtures/by-test.md\n' >"$repo/plugins/p/skills/s/scripts/thing.test.sh"
if run_check "$repo" >/dev/null; then ok "test-asserted fixture passes --check"; else fail "test-asserted fixture wrongly flagged"; fi
rm -rf "$repo"

mk_repo repo
seed_skill "$repo" "plugins/p/skills/s" ''
printf 'x\n' >"$repo/plugins/p/skills/s/evals/fixtures/x\\b.json" # portability-ok: literal backslash in the fixture basename, not a GNU grep word boundary
mkdir -p "$repo/plugins/p/skills/s/scripts"
printf 'assert_on fixtures/x\\b.json\n' >"$repo/plugins/p/skills/s/scripts/thing.test.sh" # portability-ok: names the same literal-backslash basename
if run_check "$repo" >/dev/null; then ok "fixture basename with a single backslash is consumed when a same-skill test names it"; else fail "single-backslash basename not consumed (ere_escape_to missed a lone backslash)"; fi
rm -rf "$repo"

mk_repo repo
seed_skill "$repo" "plugins/p/skills/s" '"evals/fixtures/valid.json"'
printf 'x\n' >"$repo/plugins/p/skills/s/evals/fixtures/valid.json"
printf 'x\n' >"$repo/plugins/p/skills/s/evals/fixtures/valid.json.bak"
out="$(run_check_out "$repo")"
rc=$?
if [[ $rc -ne 0 && "$out" == *"ORPHANED FIXTURE"*"valid.json.bak"* && "$out" != *"ORPHANED FIXTURE"*"fixtures/valid.json is"* ]]; then ok "suffix sibling of a referenced fixture red-lines (bounded basename match)"; else fail "reference-name suffix sibling not caught: rc=$rc out='$out'"; fi
rm -rf "$repo"

mk_repo repo
seed_skill "$repo" "plugins/p/skills/s" '"evals/fixtures/valid.json.bak"'
printf 'x\n' >"$repo/plugins/p/skills/s/evals/fixtures/valid.json.bak"
printf 'x\n' >"$repo/plugins/p/skills/s/evals/fixtures/valid.json"
out="$(run_check_out "$repo")"
rc=$?
if [[ $rc -ne 0 && "$out" == *"ORPHANED FIXTURE"*"fixtures/valid.json is"* && "$out" != *"valid.json.bak is"* ]]; then ok "files[] path match is exact (substring of a longer referenced path does not consume)"; else fail "files[] substring path match not caught: rc=$rc out='$out'"; fi
rm -rf "$repo"

mk_repo repo
seed_skill "$repo" "plugins/p/skills/a" ''
seed_skill "$repo" "plugins/p/skills/b" ''
printf 'x\n' >"$repo/plugins/p/skills/a/evals/fixtures/shared.md"
printf 'x\n' >"$repo/plugins/p/skills/b/evals/fixtures/shared.md"
mkdir -p "$repo/plugins/p/skills/a/scripts"
printf 'assert_on fixtures/shared.md\n' >"$repo/plugins/p/skills/a/scripts/thing.test.sh"
out="$(run_check_out "$repo")"
rc=$?
if [[ $rc -ne 0 && "$out" == *"ORPHANED FIXTURE"*"skills/b/evals/fixtures/shared.md"* && "$out" != *"skills/a/evals/fixtures/shared.md is"* ]]; then ok "sibling skill's same-named fixture is not conflated (test basename scoped to owning skill)"; else fail "sibling-skill basename conflation not caught: rc=$rc out='$out'"; fi
rm -rf "$repo"

mk_repo repo
seed_skill "$repo" "plugins/p/skills/b" ''
printf 'x\n' >"$repo/plugins/p/skills/b/evals/fixtures/by-plugin-test.md"
mkdir -p "$repo/plugins/p/tools"
printf 'assert_on skills/b/evals/fixtures/by-plugin-test.md\n' >"$repo/plugins/p/tools/suite.test.sh"
if run_check "$repo" >/dev/null; then ok "plugin-root test consuming by plugin-relative path passes --check"; else fail "plugin-relative path consumption wrongly flagged"; fi
rm -rf "$repo"

mk_repo repo
mkdir -p "$repo/plugins/p/skills/s/evals/fixtures"
cat >"$repo/plugins/p/skills/s/evals/evals.json" <<'JSON'
{ "evals": [ { "id": 1, "prompt": "open evals/fixtures/prose-only.md and grade the summary", "files": [] } ] }
JSON
printf 'x\n' >"$repo/plugins/p/skills/s/evals/fixtures/prose-only.md"
out="$(run_check_out "$repo")"
rc=$?
if [[ $rc -ne 0 && "$out" == *"ORPHANED FIXTURE"*"prose-only.md"* ]]; then ok "fixture named only in an eval prompt (empty files[]) is an orphan (consumption scoped to files[])"; else fail "prose-mention wrongly consumed: rc=$rc out='$out'"; fi
rm -rf "$repo"

mk_repo repo
mkdir -p "$repo/plugins/p/evals/case-a" "$repo/plugins/p/evals/fixtures"
printf 'bash ../fixtures/seed.sh direct.sh=src/direct.sh\n' >"$repo/plugins/p/evals/case-a/scaffold.sh"
printf 'cp fixtures/via-seed.md.txt docs/via-seed.md\n' >"$repo/plugins/p/evals/fixtures/seed.sh"
printf 'x\n' >"$repo/plugins/p/evals/fixtures/direct.sh.txt"
printf 'x\n' >"$repo/plugins/p/evals/fixtures/via-seed.md.txt"
if run_check "$repo" >/dev/null; then ok "fixtures seeded by a case scaffold or seed script pass --check"; else fail "scaffold- or seed-seeded fixture wrongly flagged: $(run_check_out "$repo")"; fi
printf 'x\n' >"$repo/plugins/p/evals/fixtures/unnamed.md.txt"
out="$(run_check_out "$repo")"
rc=$?
if [[ $rc -ne 0 && "$out" == *"ORPHANED FIXTURE"*"unnamed.md.txt"* ]]; then ok "a fixture no scaffold or seed names is still an orphan"; else fail "unnamed fixture not caught: rc=$rc out='$out'"; fi
rm -f "$repo/plugins/p/evals/fixtures/unnamed.md.txt"
printf 'cp fixtures/stray.md.txt docs/stray.md\n' >"$repo/plugins/p/evals/fixtures/unused-seed.sh"
printf 'x\n' >"$repo/plugins/p/evals/fixtures/stray.md.txt"
out="$(run_check_out "$repo")"
rc=$?
if [[ $rc -ne 0 && "$out" == *"ORPHANED FIXTURE"*"stray.md.txt"* ]]; then ok "a fixture named only by a seed no scaffold runs is an orphan"; else fail "unused-seed fixture not caught: rc=$rc out='$out'"; fi
rm -rf "$repo"

mk_repo repo
mkdir -p "$repo/plugins/p/evals/case-b" "$repo/plugins/p/skills/s/evals/fixtures/cfg"
printf 'au_copy cfg/test_plugin_case.py test_plugin_case.py\n' >"$repo/plugins/p/evals/case-b/scaffold.sh"
printf 'x\n' >"$repo/plugins/p/skills/s/evals/fixtures/cfg/test_plugin_case.py"
if run_check "$repo" >/dev/null; then ok "a skill fixture a plugin-level case scaffold copies passes --check"; else fail "plugin-scaffold fixture wrongly flagged: $(run_check_out "$repo")"; fi
printf 'au_copy other/test_plugin_case.py test_plugin_case.py\n' >"$repo/plugins/p/evals/case-b/scaffold.sh"
out="$(run_check_out "$repo")"
rc=$?
if [[ $rc -ne 0 && "$out" == *"ORPHANED FIXTURE"*"test_plugin_case.py"* ]]; then ok "a plugin-level scaffold naming only the basename under another path does not consume a skill fixture"; else fail "basename-only plugin scaffold wrongly consumed: rc=$rc out='$out'"; fi
rm -f "$repo/plugins/p/evals/case-b/scaffold.sh"
out="$(run_check_out "$repo")"
rc=$?
if [[ $rc -ne 0 && "$out" == *"ORPHANED FIXTURE"*"test_plugin_case.py"* ]]; then ok "control: the same skill fixture with no scaffold naming it is an orphan"; else fail "unnamed skill fixture not caught: rc=$rc out='$out'"; fi
rm -rf "$repo"

mk_repo repo
seed_skill "$repo" "plugins/p/skills/s" ''
printf 'x\n' >"$repo/plugins/p/skills/s/evals/fixtures/orphan.md"
out="$(run_check_out "$repo")"
rc=$?
if [[ $rc -ne 0 && "$out" == *"ORPHANED FIXTURE"*"orphan.md"* ]]; then ok "un-consumed fixture fails --check (synthetic orphan caught)"; else fail "synthetic orphan not caught: rc=$rc out='$out'"; fi
rm -rf "$repo"

mk_repo repo $'plugins/p/skills/s/evals/fixtures/orphan.md\n'
seed_skill "$repo" "plugins/p/skills/s" ''
printf 'x\n' >"$repo/plugins/p/skills/s/evals/fixtures/orphan.md"
if run_check "$repo" >/dev/null; then ok "grandfathered orphan (exact path) passes --check"; else fail "grandfathered orphan wrongly failed"; fi
rm -rf "$repo"

mk_repo repo $'plugins/p/skills/s/evals/fixtures/valid.json\n'
seed_skill "$repo" "plugins/p/skills/s" ''
printf 'x\n' >"$repo/plugins/p/skills/s/evals/fixtures/valid.json"
printf 'x\n' >"$repo/plugins/p/skills/s/evals/fixtures/valid.json.bak"
printf 'x\n' >"$repo/plugins/p/skills/s/evals/fixtures/valid.jsonl"
out="$(run_check_out "$repo")"
rc=$?
if [[ $rc -ne 0 && "$out" == *"valid.json.bak"* && "$out" == *"valid.jsonl"* ]]; then ok "prefix-sibling of a baselined path red-lines (exact-match, no grandfather leak)"; else fail "baseline prefix-leak not caught: rc=$rc out='$out'"; fi
rm -rf "$repo"

mk_repo repo $'plugins/p/skills/s/evals/fixtures/gone.md\n'
seed_skill "$repo" "plugins/p/skills/s" '"evals/fixtures/used.md"'
printf 'x\n' >"$repo/plugins/p/skills/s/evals/fixtures/used.md"
out="$(run_check_out "$repo")"
rc=$?
if [[ $rc -ne 0 && "$out" == *"STALE BASELINE"* ]]; then ok "stale baseline entry fails --check"; else fail "stale baseline not caught: rc=$rc out='$out'"; fi
rm -rf "$repo"

mk_repo repo
seed_skill "$repo" "plugins/p/skills/s" '"evals/fixtures/used.md"'
printf 'x\n' >"$repo/plugins/p/skills/s/evals/fixtures/used.md"
printf 'x\n' >"$repo/plugins/p/skills/s/evals/fixtures/orphan.md"
out="$(cd "$repo" && bash scripts/check-orphaned-fixtures.sh discover 2>/dev/null)"
if [[ "$out" == *"CONSUMED"*"used.md"* && "$out" == *"ORPHAN"*"orphan.md"* ]]; then ok "discover labels CONSUMED and ORPHAN"; else fail "discover mislabels: '$out'"; fi
rm -rf "$repo"

mk_repo repo
(cd "$repo" && bash scripts/check-orphaned-fixtures.sh --nonsense >/dev/null 2>&1)
if [[ $? -eq 2 ]]; then ok "bad mode -> exit 2"; else fail "bad mode did not exit 2"; fi
rm -rf "$repo"

test_harness::report
