#!/usr/bin/env bash
# Black-box contract test for check-docs-naming.sh.
#
# Self-contained and cwd-independent: builds a throwaway git repository with a
# fixture docs/ tree, runs the checker against it, and asserts on exit code +
# output. Mutates only its own mktemp dir. The SUT resolves the repository root
# relative to its own location, so the fixture tree carries a copy of it under
# scripts/ and every case commits its files so `git ls-files` sees them.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SUT_SRC="$SCRIPT_DIR/check-docs-naming.sh"

# shellcheck source=lib/test-harness.sh
. "$SCRIPT_DIR/lib/test-harness.sh"
# shellcheck source=lib/fixture-tree.sh
. "$SCRIPT_DIR/lib/fixture-tree.sh"

# mk_repo <out-var>: a throwaway repo with a committed, rule-abiding docs/ tree.
# The builder assigns through a nameref, which shellcheck cannot follow.
mk_repo() {
  local dir
  fixture_tree::build "$1" --sut "$SUT_SRC" --git || return 1
  dir="${!1}"
  mkdir -p "$dir/docs/conventions/standards" "$dir/docs/adr"
  printf 'seed\n' >"$dir/docs/README.md"
  printf 'seed\n' >"$dir/docs/plugin-philosophy.md"
  printf 'seed\n' >"$dir/docs/conventions/standards/README.md"
  printf 'seed\n' >"$dir/docs/adr/0001-first.md"
  git_test_config "$dir" add -A >/dev/null
  git_test_config "$dir" commit -qm base
}

# run_case <label> <expected-rc> [<path-to-add>...]
# Adds each path (committed), runs `--check`, asserts the exit code, and on an
# expected failure asserts that every added path is named in the output.
run_case() {
  local label="$1" expected="$2"
  shift 2
  local repo p out rc
  mk_repo repo || {
    fail "$label: fixture build failed"
    return
  }
  for p in "$@"; do
    mkdir -p "$repo/$(dirname "$p")"
    printf 'seed\n' >"$repo/$p"
  done
  if (($# > 0)); then
    git_test_config "$repo" add -A >/dev/null
    git_test_config "$repo" commit -qm case >/dev/null
  fi
  out="$(bash "$repo/scripts/check-docs-naming.sh" --check 2>&1)"
  rc=$?
  if [[ $rc -ne $expected ]]; then
    fail "$label: expected rc=$expected, got rc=$rc: $out"
    return
  fi
  if [[ $expected -eq 1 ]]; then
    for p in "$@"; do
      if ! grep -qF "$p" <<<"$out"; then
        fail "$label: offender $p not named in output: $out"
        return
      fi
    done
  fi
  ok "$label"
}

# 1. A clean tree passes.
run_case "clean tree passes" 0

# 2. An uppercase basename fails and is named.
run_case "docs/NEW-FILE.md fails" 1 docs/NEW-FILE.md

# 3. The conventional uppercase names are exempt anywhere under docs/.
run_case "docs/x/README.md passes" 0 docs/x/README.md docs/x/CHANGELOG.md docs/x/INDEX.md

# 4. The branch-only topic slice is exempt.

# 5. Code files are judged by their language, not this rule.
run_case "docs/a/b_c.py passes" 0 docs/a/b_c.py docs/a/Run-Thing.ps1

# 6. Dotted stems and multi-part extensions are lower-kebab.
run_case "docs/a/v1.2.schema.json passes" 0 docs/a/v1.2.schema.json

# 7. Underscores and mixed case are not kebab.
run_case "docs/a/snake_case.md fails" 1 docs/a/snake_case.md

# 7b. Empty or trailing dot segments are not an extension.
run_case "docs/a/foo..md fails" 1 docs/a/foo..md
run_case "docs/a/foo.md. fails" 1 docs/a/foo.md.
run_case "docs/a/foo... fails" 1 docs/a/foo...

# 8. Two tracked paths that differ only by case fail even when each is a
#    conventional name on its own.
run_case "docs/Foo.md beside docs/foo.md fails" 1 docs/Foo.md docs/foo.md

# 8b. A case collision on a path git would quote. The shared non-ASCII byte
#     (UTF-8 C3 A9) makes `git ls-files` without -z C-quote the name, and the
#     ASCII C/c is what `tr` folds. A .py file is exempt from the basename
#     rule, so a failure here is the collision pass comparing the raw path.
repo=""
if mk_repo repo && [[ -n "$repo" ]]; then
  lower="docs/x/caf"$'\303\251'".py"
  upper="docs/x/Caf"$'\303\251'".py"
  mkdir -p "$repo/docs/x"
  printf 'seed\n' >"$repo/$lower"
  printf 'seed\n' >"$repo/$upper"
  git_test_config "$repo" add -A >/dev/null
  git_test_config "$repo" commit -qm case >/dev/null
  quoted="$(git_test_config "$repo" -c core.quotePath=true ls-files -- "$lower")"
  out="$(bash "$repo/scripts/check-docs-naming.sh" --check 2>&1)"
  rc=$?
  if [[ "$quoted" == "$lower" ]]; then
    fail "quoted-path collision: git did not quote $lower (got $quoted)"
  elif [[ $rc -eq 1 ]] && grep -qF "$lower" <<<"$out" && grep -qF "$upper" <<<"$out" && grep -qF "differs only by case" <<<"$out"; then
    ok "non-ASCII path git would quote fails on a case collision"
  else
    fail "quoted-path collision: expected rc=1 naming both raw paths as a case collision (rc=$rc): $out"
  fi
else
  fail "quoted-path collision: fixture build failed"
fi

# 8c. A case collision on a path holding a newline stays one finding per path:
#     two `%q` findings plus the summary line, never a split record.
repo=""
if mk_repo repo && [[ -n "$repo" ]]; then
  mkdir -p "$repo/docs/New"$'\n'"line" "$repo/docs/new"$'\n'"line"
  printf 'seed\n' >"$repo/docs/New"$'\n'"line/foo.md"
  printf 'seed\n' >"$repo/docs/new"$'\n'"line/foo.md"
  git_test_config "$repo" add -A >/dev/null
  git_test_config "$repo" commit -qm case >/dev/null
  out="$(bash "$repo/scripts/check-docs-naming.sh" --check 2>&1)"
  rc=$?
  if [[ $rc -eq 1 ]] && [[ "$(grep -c '' <<<"$out")" -eq 3 ]] && grep -qF "\$'docs/New\\nline/foo.md'" <<<"$out"; then
    ok "newline-bearing collision is one finding per path"
  else
    fail "newline collision: expected rc=1 and three lines (rc=$rc): $out"
  fi
else
  fail "newline collision: fixture build failed"
fi

# 9. Discover mode (no flag) lists offenders and still exits 1 on any.
# A failed fixture build leaves $repo empty, and `git -C ""` would then act on
# THIS checkout, so the build is checked before any git command runs.
repo=""
if mk_repo repo && [[ -n "$repo" ]]; then
  printf 'seed\n' >"$repo/docs/Bad-Name.md"
  git_test_config "$repo" add -A >/dev/null
  git_test_config "$repo" commit -qm case >/dev/null
  out="$(bash "$repo/scripts/check-docs-naming.sh" 2>&1)"
  rc=$?
  if [[ $rc -eq 1 ]] && grep -qF 'docs/Bad-Name.md' <<<"$out"; then
    ok "discover mode names the offender and exits 1"
  else
    fail "discover mode should name docs/Bad-Name.md and exit 1 (rc=$rc): $out"
  fi
else
  fail "discover mode: fixture build failed"
fi

# 10. Unknown mode is a usage error, not a silent pass.
bash "$SUT_SRC" --bogus >/dev/null 2>&1
rc=$?
if [[ $rc -eq 2 ]]; then
  ok "unknown mode exits 2"
else
  fail "unknown mode should exit 2 (rc=$rc)"
fi

# 11. No drift from the docs-naming template this gate was generalized into.
#     The emitter renders the template with THIS repository's
#     .claude/docs-naming.json, both gates run over one seeded tree, and their
#     exit codes, stdout, and stderr must agree. The comparison is behavioral,
#     not textual: the two differ by construction in the script's name and
#     path, in the rule's display name (`lower-kebab-case` here, the config's
#     `rule` there), in how the roots are spelled in the clean-run line, and in
#     that line's clause for the markdown scope outside docs/, which the
#     template has no key for, so exactly those literals are normalized and
#     nothing else is. The seeded tree therefore holds no markdown outside
#     docs/; cases 12 to 15 cover that scope. Every root and exemption the
#     config declares is seeded, so an entry added on one side only surfaces as
#     a finding the other side lacks.
EMITTER="$SCRIPT_DIR/../plugins/docs-naming/skills/generate-file-name-gate/scripts/emit-gate.sh"
REPO_CONFIG="$SCRIPT_DIR/../.claude/docs-naming.json"
EMITTED_RULE=""
EMITTED_ROOTS=""
DRIFT_REPORT=""
DRIFT_RC=""

# drift_norm <script-path> <rule> <roots> <file>: <file> with the four
# by-construction differences replaced by fixed tokens.
drift_norm() {
  local path="$1" rule="$2" roots="$3" s stem
  s="$(cat "$4" && printf x)"
  s="${s%x}"
  s="${s//", and so is every tracked .md file outside it."/.}"
  stem="${path##*/}"
  stem="${stem%.sh}"
  s="${s//"$path"/SCRIPT}"
  s="${s//"$stem"/GATE}"
  s="${s//"under $roots is $rule."/under ROOTS is RULE.}"
  s="${s//"basename is not $rule (rule:"/basename is not RULE (rule:}"
  s="${s//"rename to $rule (see"/rename to RULE (see}"
  printf '%s' "$s"
}

# drift_compare <repo> <emitted-script> [<arg>]: runs this gate and the emitted
# one with the same argument. Sets DRIFT_RC to this gate's exit code and
# DRIFT_REPORT to empty when both agree after normalization, or to what differs.
drift_compare() {
  local repo="$1" emitted="$2" tmp rc_a rc_b side a b
  shift 2
  tmp="$repo/.git/drift"
  mkdir -p "$tmp"
  bash "$repo/scripts/check-docs-naming.sh" "$@" >"$tmp/a.out" 2>"$tmp/a.err"
  rc_a=$?
  bash "$repo/$emitted" "$@" >"$tmp/b.out" 2>"$tmp/b.err"
  rc_b=$?
  DRIFT_RC=$rc_a
  DRIFT_REPORT=""
  ((rc_a == rc_b)) || DRIFT_REPORT+="exit $rc_a here, $rc_b emitted; "
  for side in out err; do
    a="$(drift_norm scripts/check-docs-naming.sh lower-kebab-case docs/ "$tmp/a.$side")"
    b="$(drift_norm "$emitted" "$EMITTED_RULE" "$EMITTED_ROOTS" "$tmp/b.$side")"
    [[ "$a" == "$b" ]] ||
      DRIFT_REPORT+="std$side differs:"$'\n'"$(diff <(printf '%s\n' "$a") <(printf '%s\n' "$b"))"$'\n'
  done
}

# drift_seed <repo> <path>...: writes and commits each path.
drift_seed() {
  local repo="$1" p
  shift
  for p in "$@"; do
    mkdir -p "$repo/$(dirname "$p")"
    printf 'seed\n' >"$repo/$p"
  done
  git_test_config "$repo" add -A >/dev/null
  git_test_config "$repo" commit -qm seed >/dev/null
}

drift_ready=1
if ! command -v jq >/dev/null 2>&1; then
  drift_ready=""
  fail "template drift: jq is required to emit the template gate, so the drift cases cannot run"
fi

exempt_seeds=()
offender_seeds=()
if [[ -n "$drift_ready" ]]; then
  EMITTED_RULE="$(jq -r '.file_names.rule' "$REPO_CONFIG")"
  EMITTED_ROOTS="$(jq -r '.file_names.roots | join(", ")' "$REPO_CONFIG")"
  while IFS= read -r one; do
    [[ -n "$one" ]] && exempt_seeds+=("docs/x/$one")
  done < <(jq -r '.file_names.exempt_basenames[]' "$REPO_CONFIG")
  while IFS= read -r one; do
    [[ -n "$one" ]] && exempt_seeds+=("docs/a/Bad_Name.$one")
  done < <(jq -r '.file_names.exempt_extensions[]' "$REPO_CONFIG")
  # A glob entry gets its literal prefix plus a name the rule rejects, the
  # same seed the emitter's own suite uses.
  while IFS= read -r one; do
    [[ "$one" == *'*' ]] || continue
    one="${one%%\**}"
    one="${one%/}"
    [[ -n "$one" ]] && exempt_seeds+=("$one/Exempt_By-PATH.md")
  done < <(jq -r '.file_names.exempt_paths[]' "$REPO_CONFIG")
  while IFS= read -r one; do
    [[ -n "$one" ]] && offender_seeds+=("$one/Root_Probe.md")
  done < <(jq -r '.file_names.roots[]' "$REPO_CONFIG")
  # Every offender shape the header names, the exemption boundaries (a case
  # variant of an exempt name, an exempt extension in the wrong case), case
  # collisions including one against an exempt name, and non-markdown files
  # outside docs/ that neither gate may judge.
  offender_seeds+=(
    docs/NEW-FILE.md docs/a/snake_case.md docs/a/Mixed.md docs/a/foo..md
    docs/a/foo.md. docs/a/foo... docs/a/noext docs/a/README.md.bak
    docs/a/v1.2.schema.json docs/Foo.md docs/foo.md
    docs/conventions/standards/readme.md docs/x/Readme.md
    docs/a/Bad_Name.PY "docs/x/caf"$'\303\251'".py" "docs/x/Caf"$'\303\251'".py"
    "docs/New"$'\n'"line/foo.md" "docs/new"$'\n'"line/foo.md"
    Top_Level.txt other/Bad_Name.json
  )
fi

# drift_emit <repo> <config> <out-dir>: renders the template into the fixture.
drift_emit() {
  bash "$EMITTER" --config "$2" --root "$1" --out-dir "$3" >/dev/null 2>"$1/.git/emit.err"
}

# 11a. A tree holding only exempt names is clean under both gates.
repo=""
if [[ -n "$drift_ready" ]] && mk_repo repo && [[ -n "$repo" ]]; then
  drift_seed "$repo" "${exempt_seeds[@]}"
  if drift_emit "$repo" "$REPO_CONFIG" scripts; then
    drift_compare "$repo" scripts/check-file-names.sh --check
    if [[ -z "$DRIFT_REPORT" && "$DRIFT_RC" -eq 0 ]]; then
      ok "template drift: exempt-only tree is clean under both gates"
    else
      fail "template drift: exempt-only tree (rc=$DRIFT_RC): $DRIFT_REPORT"
    fi
  else
    fail "template drift: emission failed: $(cat "$repo/.git/emit.err")"
  fi
elif [[ -n "$drift_ready" ]]; then
  fail "template drift: fixture build failed"
fi

# 11b. The seeded offending tree: same findings, streams, and exit code in
#      --check, discover, and usage-error modes.
repo=""
if [[ -n "$drift_ready" ]] && mk_repo repo && [[ -n "$repo" ]]; then
  drift_seed "$repo" "${exempt_seeds[@]}" "${offender_seeds[@]}"
  if drift_emit "$repo" "$REPO_CONFIG" scripts; then
    for mode in --check "" --bogus; do
      want=1
      [[ "$mode" == --bogus ]] && want=2
      if [[ -n "$mode" ]]; then
        drift_compare "$repo" scripts/check-file-names.sh "$mode"
      else
        drift_compare "$repo" scripts/check-file-names.sh
      fi
      if [[ -z "$DRIFT_REPORT" && "$DRIFT_RC" -eq "$want" ]]; then
        ok "template drift: offending tree agrees in ${mode:-discover} mode"
      else
        fail "template drift: offending tree in ${mode:-discover} mode (rc=$DRIFT_RC, want $want): $DRIFT_REPORT"
      fi
    done

    # 11c. The comparison has teeth: a config that loses one entry from any
    #      exemption list, or narrows the regex, emits a gate that must NOT
    #      agree with this one over the same tree.
    n=0
    for filter in \
      '.file_names.exempt_basenames |= .[1:]' \
      '.file_names.exempt_paths += ["docs/a/**"]' \
      '.file_names.exempt_extensions |= .[1:]' \
      '.file_names.regex = "^[a-z0-9]+(-[a-z0-9]+)*\\.[a-z0-9]+$"'; do
      n=$((n + 1))
      jq "$filter" "$REPO_CONFIG" >"$repo/.git/mutant-$n.json"
      if drift_emit "$repo" "$repo/.git/mutant-$n.json" "scripts/mutant-$n"; then
        drift_compare "$repo" "scripts/mutant-$n/check-file-names.sh" --check
        if [[ -n "$DRIFT_REPORT" ]]; then
          ok "template drift: mutant config ($filter) is caught"
        else
          fail "template drift: mutant config ($filter) agreed with this gate, so the comparison cannot see drift"
        fi
      else
        fail "template drift: mutant emission failed ($filter): $(cat "$repo/.git/emit.err")"
      fi
    done
  else
    fail "template drift: emission failed: $(cat "$repo/.git/emit.err")"
  fi
elif [[ -n "$drift_ready" ]]; then
  fail "template drift: fixture build failed"
fi

# 12. Markdown outside docs/ is held to the rule and named when it breaks it.
run_case "Top_Level.md fails" 1 Top_Level.md
run_case "plugins/p/skills/s/NOT_IMPLEMENTED.md fails" 1 plugins/p/skills/s/NOT_IMPLEMENTED.md
run_case "plugins/p/NOTES.md fails" 1 plugins/p/NOTES.md

# 13. Every listed role name passes anywhere; a case variant of one does not.
run_case "role names pass outside docs/" 0 AGENTS.md CLAUDE.md SECURITY.md REVIEW.md \
  LICENSE.md CONTRIBUTING.md CODE_OF_CONDUCT.md plugins/p/README.md plugins/p/CHANGELOG.md \
  plugins/p/skills/s/SKILL.md plugins/p/tools/t/CONTRACT.md plugins/p/styles/s/STYLE.md \
  plugins/p/skills/s/TODO.md plugins/p/reference/r/PLAN.md plugins/p/INDEX.md
run_case "plugins/p/Skill.md fails" 1 plugins/p/Skill.md

# 14. Fixture, eval, and vendor trees keep the names they reproduce, and
#     non-markdown files outside docs/ are out of scope.
run_case "fixture, eval, vendor trees and non-markdown pass" 0 \
  plugins/p/tests/fixtures/a/NOTES.md plugins/p/evals/workspaces/w/MISSION.md \
  plugins/p/vendor/v/TUNING.md plugins/p/scripts/Bad_Name.json

# 15. A case collision outside docs/ fails, inside an excluded tree too.
run_case "plugins/p/Foo.md beside plugins/p/foo.md fails" 1 plugins/p/Foo.md plugins/p/foo.md
run_case "collision inside a fixture tree fails" 1 p/fixtures/A.md p/fixtures/a.md

test_harness::report
