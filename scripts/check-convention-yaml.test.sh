#!/usr/bin/env bash
# Black-box test for check-convention-yaml.sh.
#
# Each case builds a throwaway git repository holding a copy of the script,
# commits the YAML and schema files it needs, and runs the script against it.
# The validator is a stub named through CHECK_JSONSCHEMA_BIN: it records the
# arguments it was given and rejects any file holding a `reject: true` line, so
# the cases assert what the script owns (which schema it picks, which files it
# reads, how a rejection or a missing schema is reported) and not what
# check-jsonschema owns. The expected schema paths come from ADR 0060 Decision 6.
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
  mkdir -p "$repo/.stub" "$repo/docs/conventions"
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
  OUT="$(env CHECK_JSONSCHEMA_BIN="$repo/.stub/check-jsonschema" STUB_LOG="$repo/.stub/log" "$@" \
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

# 10. An unknown argument is a usage error.
label="unknown argument exits 2"
new_repo
OUT="$(bash "$repo/scripts/check-convention-yaml.sh" --fix 2>/dev/null)"
RC=$?
if [[ $RC -eq 2 && -z "$OUT" ]]; then ok "$label"; else fail "$label: rc=$RC stdout=$OUT"; fi

test_harness::report
