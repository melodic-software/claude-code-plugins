#!/usr/bin/env bash

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$SCRIPT_DIR/probe-lane-config.sh"
START_DIR="$PWD"
TMP="$(mktemp -d)"
trap 'cd "$START_DIR" 2>/dev/null; rm -rf "$TMP"' EXIT

# shellcheck source=../../../lib/test-helpers.sh
source "$SCRIPT_DIR/../../../lib/test-helpers.sh"
fail() {
  CASE_NUM=$((CASE_NUM + 1))
  printf 'FAIL: [%d] %s\n      expected: %q\n      got:      %q\n' "$CASE_NUM" "$1" "$2" "$3" >&2
  FAILED=$((FAILED + 1))
}

ORIGINAL="$TMP/original.sh"
cat >"$ORIGINAL" <<'ORIG'
r="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"; c="${HARNESS_OPS_LANES_CONFIG:-}"; if [[ -z "$c" ]]; then c="$r/.work/lanes/lanes.json"; [[ ! -f "$c" && -f "$r/.work/lanes.json" ]] && c="$r/.work/lanes.json"; fi; [[ -f "$c" ]] && echo "$c ($(jq -r '(.lanes//[])|length' "$c" 2>/dev/null) lanes)" || echo "absent ($c) — author one (see context/config.md)"
ORIG

STUB="$TMP/stub"
mkdir -p "$STUB"
cat >"$STUB/git" <<'SH'
#!/usr/bin/env bash
if [[ "${1:-}" == "rev-parse" && "${2:-}" == "--show-toplevel" ]]; then
  if [[ -n "${STUB_GIT_TOPLEVEL:-}" ]]; then
    if [[ -n "${STUB_GIT_CRLF:-}" ]]; then
      printf '%s\r\n' "$STUB_GIT_TOPLEVEL"
    else
      printf '%s\n' "$STUB_GIT_TOPLEVEL"
    fi
    exit 0
  fi
  printf 'fatal: not a git repository\n' >&2
  exit 128
fi
exit 0
SH
chmod +x "$STUB/git"

NOJQ="$TMP/nojq"
mkdir -p "$NOJQ"
cat >"$NOJQ/jq" <<'SH'
#!/usr/bin/env bash
printf 'bash: jq: command not found\n' >&2
exit 127
SH
chmod +x "$NOJQ/jq"

BASE_PATH="$STUB:$PATH"
export PATH="$BASE_PATH"

ROOT="$TMP/repo"
mkdir -p "$ROOT/.work/lanes"
cat >"$ROOT/.work/lanes/lanes.json" <<'JSON'
{ "lanes": [ { "name": "a" }, { "name": "b" }, { "name": "c" } ] }
JSON

LEGACY_ROOT="$TMP/legacy-repo"
mkdir -p "$LEGACY_ROOT/.work"
cat >"$LEGACY_ROOT/.work/lanes.json" <<'JSON'
{ "lanes": [ { "name": "a" }, { "name": "b" } ] }
JSON

BOTH_ROOT="$TMP/both-repo"
mkdir -p "$BOTH_ROOT/.work/lanes"
cat >"$BOTH_ROOT/.work/lanes.json" <<'JSON'
{ "lanes": [ { "name": "old" } ] }
JSON
cat >"$BOTH_ROOT/.work/lanes/lanes.json" <<'JSON'
{ "lanes": [ { "name": "a" }, { "name": "b" }, { "name": "c" }, { "name": "d" } ] }
JSON

NO_LANES_KEY="$TMP/no-lanes-key.json"
cat >"$NO_LANES_KEY" <<'JSON'
{ "other": true }
JSON

MALFORMED="$TMP/malformed.json"
cat >"$MALFORMED" <<'JSON'
{ "lanes": [ this is not json
JSON

ELSEWHERE="$TMP/elsewhere"
mkdir -p "$ELSEWHERE/.work"

HAVE_JQ=0
command -v jq >/dev/null 2>&1 && HAVE_JQ=1

run_both() {
  local label="$1" expected="$2" got orig
  got="$(bash "$SCRIPT" 2>/dev/null)"
  orig="$(bash "$ORIGINAL" 2>/dev/null | tr -d '\r')"
  [[ "$expected" == "SKIP" ]] || assert_eq "$label" "$expected" "$got"
  assert_eq "$label (matches the original inline line, modulo the CR-strip)" "$orig" "$got"
}

export STUB_GIT_TOPLEVEL="$ROOT"
export HARNESS_OPS_LANES_CONFIG="$ROOT/.work/lanes/lanes.json"
if ((HAVE_JQ)); then
  run_both "override → present config with a lane count" "$ROOT/.work/lanes/lanes.json (3 lanes)"
else
  run_both "override → present config (jq absent; equivalence only)" "SKIP"
fi

export HARNESS_OPS_LANES_CONFIG="$TMP/nowhere.json"
run_both "override is used verbatim when the file is absent" \
  "absent ($TMP/nowhere.json) — author one (see context/config.md)"

export HARNESS_OPS_LANES_CONFIG=""
if ((HAVE_JQ)); then
  run_both "empty override falls through to <toplevel>/.work/lanes/lanes.json" \
    "$ROOT/.work/lanes/lanes.json (3 lanes)"
else
  run_both "empty override falls through (jq absent; equivalence only)" "SKIP"
fi
unset HARNESS_OPS_LANES_CONFIG

export STUB_GIT_TOPLEVEL="$ELSEWHERE"
run_both "default resolves under the git toplevel" \
  "absent ($ELSEWHERE/.work/lanes/lanes.json) — author one (see context/config.md)"

export STUB_GIT_CRLF=1
assert_eq "CRLF toplevel is stripped" \
  "absent ($ELSEWHERE/.work/lanes/lanes.json) — author one (see context/config.md)" \
  "$(bash "$SCRIPT" 2>/dev/null)"
unset STUB_GIT_CRLF

unset STUB_GIT_TOPLEVEL
cd "$ELSEWHERE" || exit 1
run_both "not in a repo → default resolves under the working directory" \
  "absent ($ELSEWHERE/.work/lanes/lanes.json) — author one (see context/config.md)"
cd "$START_DIR" || exit 1

export STUB_GIT_TOPLEVEL="$LEGACY_ROOT"
if ((HAVE_JQ)); then
  run_both "pre-move <root>/.work/lanes.json is reported when the lanes/ home is empty" \
    "$LEGACY_ROOT/.work/lanes.json (2 lanes)"
else
  run_both "pre-move config is reported (jq absent; equivalence only)" "SKIP"
fi

export STUB_GIT_TOPLEVEL="$BOTH_ROOT"
if ((HAVE_JQ)); then
  run_both "the lanes/ home wins over a leftover pre-move config" \
    "$BOTH_ROOT/.work/lanes/lanes.json (4 lanes)"
else
  run_both "the lanes/ home wins over a leftover pre-move config (jq absent)" "SKIP"
fi

export STUB_GIT_TOPLEVEL="$ROOT"
if ((HAVE_JQ)); then
  export HARNESS_OPS_LANES_CONFIG="$NO_LANES_KEY"
  run_both "config without a .lanes key counts 0" "$NO_LANES_KEY (0 lanes)"
  export HARNESS_OPS_LANES_CONFIG="$MALFORMED"
  run_both "malformed config degrades the count to empty" "$MALFORMED ( lanes)"
  unset HARNESS_OPS_LANES_CONFIG
else
  printf 'SKIP: jq absent — real-count cases not exercised\n'
fi

export PATH="$NOJQ:$BASE_PATH"
export HARNESS_OPS_LANES_CONFIG="$ROOT/.work/lanes/lanes.json"
run_both "jq missing degrades the count to empty" "$ROOT/.work/lanes/lanes.json ( lanes)"
unset HARNESS_OPS_LANES_CONFIG
export PATH="$BASE_PATH"

out="$(bash "$SCRIPT" --bogus 2>&1)"
rc=$?
assert_eq "unknown argument exits 3" "3" "$rc"
case "$out" in
*"unknown argument: --bogus"*) pass "unknown argument is named on stderr" ;;
*) fail "unknown argument is named on stderr" "unknown argument: --bogus" "$out" ;;
esac

bash "$SCRIPT" --help >/dev/null 2>&1
assert_eq "--help exits 0" "0" "$?"

if [[ $FAILED -eq 0 ]]; then
  printf '\nAll %d cases passed.\n' "$CASE_NUM"
  exit 0
fi
printf '\n%d of %d cases FAILED.\n' "$FAILED" "$CASE_NUM" >&2
exit 1
