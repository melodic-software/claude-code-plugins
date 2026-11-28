#!/usr/bin/env bash
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SUT_SRC="$SCRIPT_DIR/check-docs-naming.sh"

# shellcheck source=lib/test-harness.sh
. "$SCRIPT_DIR/lib/test-harness.sh"
# shellcheck source=lib/fixture-tree.sh
. "$SCRIPT_DIR/lib/fixture-tree.sh"

mk_repo() {
  local dir
  fixture_tree::build "$1" --sut "$SUT_SRC" --git || return 1
  dir="${!1}"
  mkdir -p "$dir/docs/contracts/standards" "$dir/docs/adr"
  printf 'seed\n' >"$dir/docs/README.md"
  printf 'seed\n' >"$dir/docs/plugin-philosophy.md"
  printf 'seed\n' >"$dir/docs/contracts/standards/README.md"
  printf 'seed\n' >"$dir/docs/adr/0001-first.md"
  git_test_config "$dir" add -A >/dev/null
  git_test_config "$dir" commit -qm base
}

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

run_case "clean tree passes" 0

run_case "docs/NEW-FILE.md fails" 1 docs/NEW-FILE.md

run_case "docs/x/README.md passes" 0 docs/x/README.md docs/x/CHANGELOG.md docs/x/INDEX.md

run_case "docs/a/b_c.py passes" 0 docs/a/b_c.py docs/a/Run-Thing.ps1

run_case "docs/a/v1.2.schema.json passes" 0 docs/a/v1.2.schema.json

run_case "docs/a/snake_case.md fails" 1 docs/a/snake_case.md

run_case "docs/a/foo..md fails" 1 docs/a/foo..md
run_case "docs/a/foo.md. fails" 1 docs/a/foo.md.
run_case "docs/a/foo... fails" 1 docs/a/foo...

run_case "docs/Foo.md beside docs/foo.md fails" 1 docs/Foo.md docs/foo.md

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

test_harness::assert_unknown_mode "$SUT_SRC"

EMITTER="$SCRIPT_DIR/../plugins/docs-naming/skills/generate-file-name-gate/scripts/emit-gate.sh"
ROOT_SCOPES="$SCRIPT_DIR/../plugins/docs-naming/scripts/root-scopes.jq"

script_exempt_names() {
  sed -n "s/^EXEMPT_NAMES=' \(.*\) '\$/\1/p" "$1" | tr ' ' '\n' | sed '/^$/d'
}

exempt_name_seeds() {
  {
    jq -r '.file_names.exempt_basenames[]' "$REPO_CONFIG"
    script_exempt_names "$1"
  } | sort -u | awk 'NF {print "docs/x/" $0; print "plugins/x/" $0}'
}
# shellcheck source=../plugins/docs-naming/lib/layer-yaml.sh
. "$SCRIPT_DIR/../plugins/docs-naming/lib/layer-yaml.sh"
REPO_YAML="$SCRIPT_DIR/../docs/conventions/docs-naming.yaml"
fixture_tree::build CONFIG_DIR --no-lib --label docs-naming-config
# The builder assigns CONFIG_DIR through a nameref, which shellcheck cannot follow.
# shellcheck disable=SC2154
REPO_CONFIG="$CONFIG_DIR/docs-naming.json"
if command -v jq >/dev/null 2>&1; then
  layer_yaml_to_json "$REPO_YAML" >"$REPO_CONFIG"
fi
EMITTED_RULE=""
EMITTED_ROOTS=""
DRIFT_REPORT=""
DRIFT_RC=""

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
  s="${s//"rename each to $rule,"/rename each to RULE,}"
  s="${s//" or add it to EXEMPT_NAMES in SCRIPT and to exempt_basenames in docs/conventions/docs-naming.yaml."/ EXEMPT.}"
  s="${s//" or exempt it in the docs-naming file_names configuration and re-emit this gate."/ EXEMPT.}"
  printf '%s' "$s"
}

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
  EMITTED_ROOTS="$(jq -r -f "$ROOT_SCOPES" "$REPO_CONFIG" | jq -r 'map(.label) | join(", ")')"
  while IFS= read -r one; do
    [[ -n "$one" ]] && exempt_seeds+=("$one")
  done < <(exempt_name_seeds "$SUT_SRC")
  while IFS= read -r one; do
    [[ -n "$one" ]] && exempt_seeds+=("docs/a/Bad_Name.$one")
  done < <(jq -r '.file_names.exempt_extensions[]' "$REPO_CONFIG")
  while IFS= read -r one; do
    [[ "$one" == *'*' ]] || continue
    one="${one%%\**}"
    one="${one%/}"
    [[ -n "$one" ]] && exempt_seeds+=("$one/Exempt_By-PATH.md")
  done < <(jq -r '.file_names.exempt_paths[]' "$REPO_CONFIG")
  while IFS= read -r one; do
    [[ -n "$one" ]] && offender_seeds+=("$one")
  done < <(jq -r -f "$ROOT_SCOPES" "$REPO_CONFIG" |
    jq -r '.[] | (.path | rtrimstr("/") | if . == "." or . == "" then "" else . + "/" end) as $p
      | if .extensions == [] then $p + "Root_Probe.md"
        else .extensions[] | ($p + "Root_Probe." + .), ($p + "Root_Probe_Upper." + ascii_upcase) end')
  while IFS= read -r one; do
    one="${one#\*\*/}"
    one="${one%/\*\*}"
    [[ -n "$one" && "$one" != *'*'* ]] || continue
    exempt_seeds+=("p/$one/Exempt_By-ROOT.md")
    offender_seeds+=("docs/p/$one/Judged_By-DOCS.md")
  done < <(jq -r '.file_names.roots[] | objects | .exempt_paths[]?' "$REPO_CONFIG")
  offender_seeds+=(
    docs/NEW-FILE.md docs/a/snake_case.md docs/a/Mixed.md docs/a/foo..md
    docs/a/foo.md. docs/a/foo... docs/a/noext docs/a/README.md.bak
    docs/a/v1.2.schema.json docs/Foo.md docs/foo.md
    docs/contracts/standards/readme.md docs/x/Readme.md
    docs/a/Bad_Name.PY "docs/x/caf"$'\303\251'".py" "docs/x/Caf"$'\303\251'".py"
    "docs/New"$'\n'"line/foo.md" "docs/new"$'\n'"line/foo.md"
    Top_Level.txt other/Bad_Name.json
    plugins/p/NOTES.md plugins/p/skills/s/NOT_IMPLEMENTED.md plugins/p/Skill.md
    plugins/p/Foo.md plugins/p/foo.md p/fixtures/A.md p/fixtures/a.md
    plugins/p/NOTES.MD docs/x/fixtures/NOTES.md
  )
fi

drift_emit() {
  bash "$EMITTER" --config "$2" --root "$1" --out-dir "$3" >/dev/null 2>"$1/.git/emit.err"
}

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

    n=0
    for filter in \
      '.file_names.exempt_basenames |= .[1:]' \
      '.file_names.exempt_paths += ["docs/a/**"]' \
      '.file_names.exempt_extensions |= .[1:]' \
      '.file_names.regex = "^[a-z0-9]+(-[a-z0-9]+)*\\.[a-z0-9]+$"' \
      '.file_names.roots |= map(strings)' \
      '.file_names.roots |= map(if type == "object" then .exempt_paths |= .[:-1] else . end)' \
      '.file_names.roots |= map(if type == "object" then .extensions = ["txt"] else . end)'; do
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

    sed "s/^EXEMPT_NAMES=' /&MUTANT.md /" "$SUT_SRC" >"$repo/scripts/check-docs-naming.sh"
    if [[ -z "$(script_exempt_names "$SUT_SRC")" ]]; then
      fail "template drift: no names parsed from EXEMPT_NAMES in $SUT_SRC, so its exemptions are not seeded"
    elif ! grep -qx MUTANT.md < <(script_exempt_names "$repo/scripts/check-docs-naming.sh"); then
      fail "template drift: the script mutant did not take"
    else
      seeds=()
      while IFS= read -r one; do
        seeds+=("$one")
      done < <(exempt_name_seeds "$repo/scripts/check-docs-naming.sh")
      drift_seed "$repo" "${seeds[@]}"
      drift_compare "$repo" scripts/check-file-names.sh --check
      if [[ -n "$DRIFT_REPORT" ]]; then
        ok "template drift: a name exempt here but not in the config is caught"
      else
        fail "template drift: a name exempt here but not in the config agreed, so the comparison cannot see it"
      fi
    fi
  else
    fail "template drift: emission failed: $(cat "$repo/.git/emit.err")"
  fi
elif [[ -n "$drift_ready" ]]; then
  fail "template drift: fixture build failed"
fi

run_case "Top_Level.md fails" 1 Top_Level.md
run_case "plugins/p/skills/s/NOT_IMPLEMENTED.md fails" 1 plugins/p/skills/s/NOT_IMPLEMENTED.md
run_case "plugins/p/NOTES.md fails" 1 plugins/p/NOTES.md

run_case "role names pass outside docs/" 0 AGENTS.md CLAUDE.md SECURITY.md REVIEW.md \
  LICENSE.md CONTRIBUTING.md CODE_OF_CONDUCT.md plugins/p/README.md plugins/p/CHANGELOG.md \
  plugins/p/skills/s/SKILL.md plugins/p/tools/t/CONTRACT.md plugins/p/styles/s/STYLE.md \
  plugins/p/skills/s/TODO.md plugins/p/reference/r/PLAN.md plugins/p/INDEX.md
run_case "plugins/p/Skill.md fails" 1 plugins/p/Skill.md

run_case "fixture, eval, vendor trees and non-markdown pass" 0 \
  plugins/p/tests/fixtures/a/NOTES.md plugins/p/evals/workspaces/w/MISSION.md \
  plugins/p/vendor/v/TUNING.md plugins/p/scripts/Bad_Name.json
run_case "docs/x/fixtures/NOTES.md fails" 1 docs/x/fixtures/NOTES.md

run_case "plugins/p/Foo.md beside plugins/p/foo.md fails" 1 plugins/p/Foo.md plugins/p/foo.md
run_case "collision inside a fixture tree fails" 1 p/fixtures/A.md p/fixtures/a.md

run_case "plugins/p/NOTES.MD fails" 1 plugins/p/NOTES.MD
run_case "p/fixtures/foo.MD beside p/fixtures/foo.md fails" 1 p/fixtures/foo.MD p/fixtures/foo.md

run_case "p/fixtures/Ä.md beside p/fixtures/ä.md fails" 1 \
  "p/fixtures/"$'\303\204'".md" "p/fixtures/"$'\303\244'".md"

test_harness::report
