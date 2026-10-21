#!/usr/bin/env bash
# Black-box test for check-convention-yaml.sh.
#
# Each case builds a throwaway git repository holding a copy of the script,
# commits the YAML and schema files it needs, and runs the script against it.
# The validator is a stub named through CHECK_JSONSCHEMA_BIN: it records the
# arguments it was given and rejects any file holding a `reject: true` line, so
# the cases assert what the script owns (which schema it picks, which files it
# reads, how a rejection or a missing schema is reported) and not what
# check-jsonschema owns. The expected schema paths come from ADR 0064 Decision 6.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SUT_SRC="$SCRIPT_DIR/check-convention-yaml.sh"

# shellcheck source=lib/test-harness.sh
. "$SCRIPT_DIR/lib/test-harness.sh"
# shellcheck source=lib/fixture-tree.sh
. "$SCRIPT_DIR/lib/fixture-tree.sh"

# shellcheck disable=SC2016  # the stub's source; it expands when the stub runs
STUB_BODY='#!/usr/bin/env bash
printf "%s\n" "$*" >>"$STUB_LOG"
target="${!#}"
if grep -qx "reject: true" "$target"; then
  printf "stub: %s rejected\n" "$target"
  exit 1
fi
printf "stub: ok\n"'

repo=""
RC=0
OUT=""
ERR=""
LOG=""

# new_repo: a fresh fixture repo with the SUT and the stub validator.
new_repo() {
  fixture_tree::build repo --sut "$SUT_SRC" --git --label convention-yaml || return 1
  mkdir -p "$repo/.stub" "$repo/docs/conventions" "$repo/lib"
  cp "$SCRIPT_DIR/../lib/yaml-subset.awk" "$SCRIPT_DIR/../lib/resolve-convention-home.sh" "$repo/lib/"
  printf '%s\n' "$STUB_BODY" >"$repo/.stub/check-jsonschema"
  chmod +x "$repo/.stub/check-jsonschema"
  : >"$repo/.stub/log"
}

# put <relative-path> <content>: write a file and commit it.
put() {
  mkdir -p "$repo/$(dirname "$1")"
  printf '%s\n' "$2" >"$repo/$1"
  git_test_config "$repo" add -- "$1" >/dev/null
  git_test_config "$repo" commit -qm "add $1" >/dev/null
}

# run_sut [VAR=value...]: run the copied script with the stub, leaving RC, OUT,
# ERR and LOG.
run_sut() {
  local errf
  errf="$repo/.stub/stderr"
  OUT="$(env -u GITHUB_ACTIONS -u GITHUB_BASE_REF CHECK_JSONSCHEMA_BIN="$repo/.stub/check-jsonschema" STUB_LOG="$repo/.stub/log" "$@" \
    bash "$repo/scripts/check-convention-yaml.sh" --check 2>"$errf")"
  RC=$?
  ERR="$(cat "$errf")"
  LOG="$(cat "$repo/.stub/log")"
}

state() { printf 'rc=%s stdout=%s stderr=%s log=%s' "$RC" "$OUT" "$ERR" "$LOG"; }

# 1. No YAML under docs/conventions: clean, and the validator is never run.
label="no YAML files exits 0 without running the validator"
new_repo && put docs/conventions/source-control.md '# prose only'
run_sut
if [[ $RC -eq 0 && -n "$OUT" && -z "$LOG" ]]; then ok "$label"; else fail "$label: $(state)"; fi

# 2. A plugin concern validates against plugins/<concern>/schemas/<concern>.schema.json.
label="plugin concern uses the plugin schema"
new_repo && put docs/conventions/alpha.yaml 'mode: on' && put plugins/alpha/schemas/alpha.schema.json '{}'
run_sut
if [[ $RC -eq 0 && "$LOG" == "--schemafile plugins/alpha/schemas/alpha.schema.json -- docs/conventions/alpha.yaml" ]]; then
  ok "$label"
else
  fail "$label: $(state)"
fi

# 3. A cross-plugin convention validates against docs/conventions/<name>/<name>.schema.json.
label="cross-plugin convention uses the convention-folder schema"
new_repo && put docs/conventions/beta.yaml 'mode: on' && put docs/conventions/beta/beta.schema.json '{}'
run_sut
if [[ $RC -eq 0 && "$LOG" == "--schemafile docs/conventions/beta/beta.schema.json -- docs/conventions/beta.yaml" ]]; then
  ok "$label"
else
  fail "$label: $(state)"
fi

# 4. With both schemas present, the plugin schema wins.
label="plugin schema wins over a convention-folder schema"
new_repo && put docs/conventions/alpha.yaml 'mode: on' && put plugins/alpha/schemas/alpha.schema.json '{}' &&
  put docs/conventions/alpha/alpha.schema.json '{}'
run_sut
if [[ $RC -eq 0 && "$LOG" == "--schemafile plugins/alpha/schemas/alpha.schema.json -- docs/conventions/alpha.yaml" ]]; then
  ok "$label"
else
  fail "$label: $(state)"
fi

# 5. A YAML file with no schema is a finding, and the validator is not run for it.
label="missing schema exits 1 naming the file on stderr"
new_repo && put docs/conventions/gamma.yaml 'mode: on'
run_sut
if [[ $RC -eq 1 && "$ERR" == *"docs/conventions/gamma.yaml: no schema"* && "$OUT" != *gamma* && -z "$LOG" ]]; then
  ok "$label"
else
  fail "$label: $(state)"
fi

# 6. A file the validator rejects is a finding naming the file and the schema,
#    with the validator's report forwarded; a valid sibling does not hide it.
label="rejected file exits 1 with the validator report on stderr"
new_repo && put plugins/alpha/schemas/alpha.schema.json '{}' && put plugins/delta/schemas/delta.schema.json '{}' &&
  put docs/conventions/alpha.yaml 'reject: true' && put docs/conventions/delta.yaml 'mode: on'
run_sut
if [[ $RC -eq 1 && "$ERR" == *"docs/conventions/alpha.yaml: does not validate against plugins/alpha/schemas/alpha.schema.json"* &&
  "$ERR" == *"stub: docs/conventions/alpha.yaml rejected"* && "$ERR" != *delta.yaml:* && "$OUT" != *alpha* ]]; then
  ok "$label"
else
  fail "$label: $(state)"
fi

# 7. Only tracked files directly under docs/conventions/ are read: a folder's
#    examples and an untracked file are not team layers.
label="nested and untracked YAML are not read"
new_repo && put docs/conventions/beta/examples/sample.yaml 'reject: true'
printf 'mode: on\n' >"$repo/docs/conventions/untracked.yaml"
run_sut
if [[ $RC -eq 0 && -z "$LOG" ]]; then ok "$label"; else fail "$label: $(state)"; fi

# 8. A missing validator is an environment failure, not a finding.
label="missing validator exits 2"
new_repo && put docs/conventions/alpha.yaml 'mode: on' && put plugins/alpha/schemas/alpha.schema.json '{}'
run_sut CHECK_JSONSCHEMA_BIN="$repo/.stub/absent"
if [[ $RC -eq 2 && -n "$ERR" && -z "$OUT" ]]; then ok "$label"; else fail "$label: $(state)"; fi

# 9. A file name carrying a command substitution is data, never evaluated, also
#    under bash 5.1 expansion rules.
label="hostile file name is reported, not executed"
# shellcheck disable=SC2016  # the literal $(...) is the hostile file name
hostile='docs/conventions/$(touch PWNED).yaml'
new_repo && put "$hostile" 'mode: on'
run_sut BASH_COMPAT=51
pwned="$(find "$repo" -name PWNED)"
if [[ $RC -eq 1 && "$ERR" == *"$hostile: no schema"* && -z "$pwned" && ! -e PWNED ]]; then
  ok "$label"
else
  fail "$label: $(state) pwned=$pwned"
fi

# 10. YAML the schema validator accepts but the runtime parser rejects (an
#     anchor and alias, a tag, a block scalar: lib/yaml-subset.awk's header
#     names all three outside its subset) is a finding, the validator is not
#     run for it, and the summary counts the files checked.
names=(anchor tag 'block scalar')
bodies=($'a: &x 1\nb: *x' 'a: !!str 1' $'a: |\n  text')
for i in "${!names[@]}"; do
  name="${names[i]}" body="${bodies[i]}"
  label="runtime parser rejects a $name: exits 1 naming the file"
  new_repo && put plugins/alpha/schemas/alpha.schema.json '{}' && put plugins/delta/schemas/delta.schema.json '{}' &&
    put docs/conventions/alpha.yaml "$body" && put docs/conventions/delta.yaml 'mode: on'
  run_sut
  if [[ $RC -eq 1 && "$ERR" == *"docs/conventions/alpha.yaml: the runtime YAML parser (lib/yaml-subset.awk) rejects it"* &&
    "$LOG" != *alpha.yaml* && "$LOG" == *delta.yaml* &&
    "$ERR" == *"1 finding(s) across 2 file(s) checked"* ]]; then
    ok "$label"
  else
    fail "$label: $(state)"
  fi
done

# 10b. A control or line-separator character the unattended merge policy refuses
#      in a value (babysit_merge_policy.py `_SEPARATOR`: C0 and C1 controls,
#      U+2028, U+2029) is a finding even where the parser accepts the file,
#      a tab or a CR inside a value included; LF and a line-ending CR, which
#      the reader strips, are not. The policy reads only pr-pipeline.yaml, so
#      no other file is held to it. Bytes are written with printf so the
#      fixture holds the raw UTF-8.
names=('C0 control' 'C1 control' 'line separator' 'paragraph separator' 'tab inside a value' 'CR inside a value')
bodies=($'a: x\001y' $'a: x\302\205y' $'a: x\342\200\250y' $'a: x\342\200\251y' $'a: "x\ty"' $'a: x\ry')
for i in "${!names[@]}"; do
  name="${names[i]}" body="${bodies[i]}"
  label="a $name the policy refuses: exits 1 naming the file"
  new_repo && put plugins/pr-pipeline/schemas/pr-pipeline.schema.json '{}' && put docs/conventions/pr-pipeline.yaml "$body"
  run_sut
  if [[ $RC -eq 1 && "$ERR" == *"docs/conventions/pr-pipeline.yaml: line 1 carries a control or line-separator character"* &&
    "$LOG" != *pr-pipeline.yaml* ]]; then
    ok "$label"
  else
    fail "$label: $(state)"
  fi
done
label="CRLF line endings and plain UTF-8 text are not a separator finding"
# spellchecker:ignore-next-line
new_repo && put plugins/pr-pipeline/schemas/pr-pipeline.schema.json '{}' && put docs/conventions/pr-pipeline.yaml $'a: "x y"\r\nb: caf\303\251\r\n'
run_sut
if [[ $RC -eq 0 && "$LOG" == *pr-pipeline.yaml* ]]; then ok "$label"; else fail "$label: $(state)"; fi
label="a tab in a file the policy does not read is not a separator finding"
new_repo && put plugins/alpha/schemas/alpha.schema.json '{}' && put docs/conventions/alpha.yaml $'a: "x\ty"'
run_sut
if [[ $RC -eq 0 && "$LOG" == *alpha.yaml* ]]; then ok "$label"; else fail "$label: $(state)"; fi

# 10c. The source-control schema's pre_ready list, against the real validator:
#      a list of {step, enabled} mappings passes; an unknown step, a non-boolean
#      enabled, a missing enabled and a mapping keyed by step each fail.
if command -v check-jsonschema >/dev/null 2>&1; then
  schema_src="$SCRIPT_DIR/../plugins/source-control/schemas/source-control.schema.json"
  label="a valid pre_ready list validates against the source-control schema"
  new_repo && put plugins/source-control/schemas/source-control.schema.json "$(cat "$schema_src")" &&
    put docs/conventions/source-control.yaml $'pre_ready:\n  - step: code-review\n    enabled: false\n  - step: verify\n    enabled: true'
  run_sut CHECK_JSONSCHEMA_BIN=check-jsonschema
  if [[ $RC -eq 0 ]]; then ok "$label"; else fail "$label: $(state)"; fi
  names=('an unknown step' 'a non-boolean enabled' 'a missing enabled' 'a mapping keyed by step'
    'an identical duplicate step' 'a conflicting duplicate step')
  bodies=($'pre_ready:\n  - step: lint\n    enabled: false' $'pre_ready:\n  - step: verify\n    enabled: maybe'
    $'pre_ready:\n  - step: verify' $'pre_ready:\n  verify:\n    enabled: false'
    $'pre_ready:\n  - step: verify\n    enabled: false\n  - step: verify\n    enabled: false'
    $'pre_ready:\n  - step: verify\n    enabled: true\n  - step: verify\n    enabled: false')
  for i in "${!names[@]}"; do
    label="pre_ready with ${names[i]} fails the source-control schema"
    new_repo && put plugins/source-control/schemas/source-control.schema.json "$(cat "$schema_src")" &&
      put docs/conventions/source-control.yaml "${bodies[i]}"
    run_sut CHECK_JSONSCHEMA_BIN=check-jsonschema
    if [[ $RC -eq 1 && "$ERR" == *"docs/conventions/source-control.yaml: does not validate against plugins/source-control/schemas/source-control.schema.json"* ]]; then
      ok "$label"
    else
      fail "$label: $(state)"
    fi
  done
else
  printf 'skip: check-jsonschema not on PATH; the pre_ready schema cases did not run\n'
fi

# 11. A missing runtime parser is an environment failure.
label="missing lib/yaml-subset.awk exits 2"
new_repo && put docs/conventions/alpha.yaml 'mode: on' && put plugins/alpha/schemas/alpha.schema.json '{}'
rm "$repo/lib/yaml-subset.awk"
run_sut
if [[ $RC -eq 2 && "$ERR" == *yaml-subset.awk* && -z "$LOG" ]]; then ok "$label"; else fail "$label: $(state)"; fi

# 11b. The convention home is the one the pointer region binds (ADR 0075 fix 3).
#      The expected paths follow from the region grammar in
#      lib/resolve-convention-home.sh: the first backticked token inside the
#      region is the home, and a declined or absent region leaves docs/conventions.
region_for() {
  printf '%s\n' '# Team' '' '<!-- BEGIN GENERATED: convention-home -->' \
    "Team conventions live in \`$1\` — read the topic doc there" '<!-- END GENERATED: convention-home -->'
}
label="a repository bound to Documentation has its Documentation/<concern>.yaml validated"
new_repo && put plugins/alpha/schemas/alpha.schema.json '{}' && put Documentation/alpha.yaml 'mode: on' &&
  put AGENTS.md "$(region_for Documentation)"
run_sut
if [[ $RC -eq 0 && "$LOG" == "--schemafile plugins/alpha/schemas/alpha.schema.json -- Documentation/alpha.yaml" &&
  "$OUT" == *"1 Documentation YAML file(s)"* ]]; then
  ok "$label"
else
  fail "$label: $(state)"
fi
label="a repository bound to Documentation does not read docs/conventions YAML"
new_repo && put plugins/alpha/schemas/alpha.schema.json '{}' && put Documentation/keep.md '# prose' &&
  put docs/conventions/alpha.yaml 'reject: true' && put AGENTS.md "$(region_for Documentation)"
run_sut
if [[ $RC -eq 0 && -z "$LOG" ]]; then ok "$label"; else fail "$label: $(state)"; fi
label="a cross-plugin schema is found under the bound home"
new_repo && put Documentation/beta.yaml 'mode: on' && put Documentation/beta/beta.schema.json '{}' &&
  put AGENTS.md "$(region_for Documentation)"
run_sut
if [[ $RC -eq 0 && "$LOG" == "--schemafile Documentation/beta/beta.schema.json -- Documentation/beta.yaml" ]]; then
  ok "$label"
else
  fail "$label: $(state)"
fi
label="a declined home leaves docs/conventions"
new_repo && put plugins/alpha/schemas/alpha.schema.json '{}' && put docs/conventions/alpha.yaml 'mode: on' &&
  put AGENTS.md $'<!-- BEGIN GENERATED: convention-home -->\ndeclined\n<!-- END GENERATED: convention-home -->'
run_sut
if [[ $RC -eq 0 && "$LOG" == "--schemafile plugins/alpha/schemas/alpha.schema.json -- docs/conventions/alpha.yaml" ]]; then
  ok "$label"
else
  fail "$label: $(state)"
fi
label="a pointer to a missing directory exits 1 naming the region"
new_repo && put AGENTS.md "$(region_for Documentation)"
run_sut
if [[ $RC -eq 1 && "$ERR" == *"pointer target directory missing: Documentation"* && -z "$LOG" ]]; then
  ok "$label"
else
  fail "$label: $(state)"
fi
# 11c. The home is read from the merge base with the base branch, not from the
#      head: a head commit that moves the pointer away from a rejected file
#      still has that file checked, on a pull request (GITHUB_BASE_REF) and
#      locally (origin's default branch).
for base_env in GITHUB_BASE_REF=main GITHUB_BASE_REF=; do
  label="a head-only pointer change does not move the checked home ($base_env)"
  new_repo && put plugins/alpha/schemas/alpha.schema.json '{}' && put docs/conventions/alpha.yaml 'reject: true'
  git_test_config "$repo" update-ref refs/remotes/origin/main HEAD
  put Documentation/keep.md '# prose' && put AGENTS.md "$(region_for Documentation)"
  run_sut "$base_env"
  if [[ $RC -eq 1 && "$ERR" == *"docs/conventions/alpha.yaml: does not validate"* &&
    "$LOG" == "--schemafile plugins/alpha/schemas/alpha.schema.json -- docs/conventions/alpha.yaml" ]]; then
    ok "$label"
  else
    fail "$label: $(state)"
  fi
done
# 11d. The home the working tree binds is checked beside the merge base's.
#      Each case commits a base, points origin/main at it, then commits the head.
base_here() { git_test_config "$repo" update-ref refs/remotes/origin/main HEAD; }
label="B3: a head that adds a region has its new home checked"
new_repo && put plugins/alpha/schemas/alpha.schema.json '{}' && base_here &&
  put NewHome/alpha.yaml 'reject: true' && put AGENTS.md "$(region_for NewHome)"
run_sut GITHUB_BASE_REF=main
if [[ $RC -eq 1 && "$ERR" == *"NewHome/alpha.yaml: does not validate"* ]]; then ok "$label"; else fail "$label: $(state)"; fi
label="B: a head that moves the pointer to an invalid home exits 1"
new_repo && put plugins/alpha/schemas/alpha.schema.json '{}' && put Documentation/alpha.yaml 'mode: on' &&
  put AGENTS.md "$(region_for Documentation)" && base_here
git_test_config "$repo" mv Documentation 'Bad Home' >/dev/null
put AGENTS.md "$(region_for 'Bad Home')"
run_sut GITHUB_BASE_REF=main
if [[ $RC -eq 1 && "$ERR" == *"working tree"* ]]; then ok "$label"; else fail "$label: $(state)"; fi
label="B2: a head that deletes the bound home exits 1"
new_repo && put plugins/alpha/schemas/alpha.schema.json '{}' && put Documentation/alpha.yaml 'mode: on' &&
  put AGENTS.md "$(region_for Documentation)" && base_here
git_test_config "$repo" rm -rq Documentation && git_test_config "$repo" commit -qm 'drop home' >/dev/null
run_sut GITHUB_BASE_REF=main
if [[ $RC -eq 1 && "$ERR" == *"working tree"*"pointer target directory missing: Documentation"* ]]; then
  ok "$label"
else
  fail "$label: $(state)"
fi
label="W1: a broken pointer at the base warns, and the head that restores the home passes"
new_repo && put plugins/alpha/schemas/alpha.schema.json '{}' && put AGENTS.md "$(region_for Documentation)" && base_here &&
  put Documentation/alpha.yaml 'mode: on'
run_sut GITHUB_BASE_REF=main
if [[ $RC -eq 0 && "$ERR" == *"merge base"*"pointer target directory missing"* &&
  "$LOG" == "--schemafile plugins/alpha/schemas/alpha.schema.json -- Documentation/alpha.yaml" ]]; then
  ok "$label"
else
  fail "$label: $(state)"
fi
label="P4: no merge base under GITHUB_ACTIONS exits 2"
new_repo && put plugins/alpha/schemas/alpha.schema.json '{}' && put docs/conventions/alpha.yaml 'mode: on'
run_sut GITHUB_ACTIONS=true
if [[ $RC -eq 2 && "$ERR" == *"no merge base"* && -z "$LOG" ]]; then ok "$label"; else fail "$label: $(state)"; fi
label="P4: no merge base with a GITHUB_BASE_REF exits 2"
run_sut GITHUB_BASE_REF=main
if [[ $RC -eq 2 && "$ERR" == *"no merge base"* && -z "$LOG" ]]; then ok "$label"; else fail "$label: $(state)"; fi
label="a missing lib/resolve-convention-home.sh exits 2"
new_repo && put docs/conventions/alpha.yaml 'mode: on' && put plugins/alpha/schemas/alpha.schema.json '{}'
rm "$repo/lib/resolve-convention-home.sh"
run_sut
if [[ $RC -eq 2 && "$ERR" == *resolve-convention-home.sh* && -z "$LOG" ]]; then ok "$label"; else fail "$label: $(state)"; fi

# 12. An unknown argument is a usage error.
label="unknown argument exits 2"
new_repo
OUT="$(bash "$repo/scripts/check-convention-yaml.sh" --fix 2>/dev/null)"
RC=$?
if [[ $RC -eq 2 && -z "$OUT" ]]; then ok "$label"; else fail "$label: rc=$RC stdout=$OUT"; fi

test_harness::report
