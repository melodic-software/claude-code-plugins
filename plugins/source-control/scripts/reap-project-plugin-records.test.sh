#!/usr/bin/env bash
# Regression tests for reap-project-plugin-records.sh. Black-box: a stubbed
# `claude` on PATH reproduces the measured CLI contract — `plugin list --json`
# reports every project-scope record regardless of cwd, while
# `plugin uninstall <id> -s project` acts ONLY on a record whose projectPath is
# the current directory and otherwise fails with the text that suggests
# `--scope user`. Every case here pins a safety property the reap rests on:
# the cwd-equality refusal, the never-`-s user` / never-`--prune` rule, the
# other-path records left untouched, and the visible degrade.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REAP="$SCRIPT_DIR/reap-project-plugin-records.sh"

FAILED=0
CASE_NUM=0
# shellcheck source=test-helpers.sh
source "$SCRIPT_DIR/test-helpers.sh"

command -v jq >/dev/null 2>&1 || skip_suite "jq not available"

TEST_TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TEST_TMPDIR"' EXIT

STUB_DIR="$TEST_TMPDIR/stub"
mkdir -p "$STUB_DIR"

STATE="$TEST_TMPDIR/state.json"
LOG="$TEST_TMPDIR/calls.log"

# The stub reproduces the measured contract, not a convenience fiction.
cat >"$STUB_DIR/claude" <<'STUB'
#!/usr/bin/env bash
set -uo pipefail
printf '%s\n' "$*" >>"$STUB_CALL_LOG"

stub_native_pwd() {
  local p
  p="$(pwd -W 2>/dev/null)" || p=""
  [[ -n "$p" ]] || p="$(pwd -P 2>/dev/null)" || p="$PWD"
  printf '%s' "$p"
}
stub_key() {
  local p="${1//\\//}"
  while [[ "$p" == */ && ${#p} -gt 1 ]]; do p="${p%/}"; done
  printf '%s' "$p" | tr '[:upper:]' '[:lower:]'
}

if [[ "${1:-}" == "plugin" && "${2:-}" == "list" ]]; then
  [[ "${STUB_LIST_FAIL:-0}" == 1 ]] && exit 1
  if [[ "${STUB_LIST_SHAPE:-object}" == "array" ]]; then
    jq -c '.' "$STUB_STATE"
  else
    jq -c '{installed: .}' "$STUB_STATE"
  fi
  exit 0
fi

if [[ "${1:-}" == "plugin" && "${2:-}" == "uninstall" ]]; then
  id="${3:-}"
  scope=""
  shift 3
  while [[ $# -gt 0 ]]; do
    case "$1" in
    -s | --scope)
      scope="${2:-}"
      shift 2
      ;;
    *) shift ;;
    esac
  done
  here="$(stub_key "$(stub_native_pwd)")"
  hit="$(jq -r --arg id "$id" --arg here "$here" '
    map(select(.id == $id and .scope == "project"
      and ((.projectPath // "") | gsub("\\\\"; "/") | ascii_downcase | sub("/$"; "")) == $here))
    | length' "$STUB_STATE")"
  if [[ "$scope" == "project" && "$hit" -gt 0 ]]; then
    tmp="$(mktemp)"
    jq --arg id "$id" --arg here "$here" '
      map(select((.id == $id and .scope == "project"
        and ((.projectPath // "") | gsub("\\\\"; "/") | ascii_downcase | sub("/$"; "")) == $here) | not))
    ' "$STUB_STATE" >"$tmp" && mv "$tmp" "$STUB_STATE"
    printf 'Successfully uninstalled plugin: %s (scope: project)\n' "$id"
    exit 0
  fi
  printf 'Failed to uninstall plugin "%s": Plugin "%s" is installed in user scope, not project. Use --scope user to uninstall.\n' "$id" "$id" >&2
  exit 1
fi

printf 'stub: unhandled: %s\n' "$*" >&2
exit 64
STUB
chmod +x "$STUB_DIR/claude"

native_of() { (cd "$1" && { pwd -W 2>/dev/null || pwd -P; }); }

# run <cwd> [args...] — one reap invocation with the stub on PATH.
RC=0
OUT=""
run() {
  local cwd="$1"
  shift
  OUT="$(cd "$cwd" && PATH="$STUB_DIR:$PATH" STUB_STATE="$STATE" STUB_CALL_LOG="$LOG" \
    bash "$REAP" "$@" 2>&1)"
  RC=$?
}

seed_state() { printf '%s\n' "$1" >"$STATE"; }
reset_log() { : >"$LOG"; }

WT="$TEST_TMPDIR/wt"
OTHER="$TEST_TMPDIR/other"
mkdir -p "$WT" "$OTHER"
WT_NATIVE="$(native_of "$WT")"
OTHER_NATIVE="$(native_of "$OTHER")"

# --- CLI contract ---------------------------------------------------------------

help_out="$(bash "$REAP" --help 2>&1)"
help_rc=$?
assert_exit "--help exits 0" 0 "$help_rc"
assert_contains "--help documents the usage line" "$help_out" "--worktree-path"

run "$WT"
assert_exit "missing --worktree-path is a usage error" 2 "$RC"

run "$WT" --bogus
assert_exit "unknown argument is a usage error" 2 "$RC"

run "$WT" --worktree-path "$TEST_TMPDIR/does-not-exist"
assert_exit "unresolvable --worktree-path is a usage error" 2 "$RC"

# --- the cwd-equality boundary --------------------------------------------------

seed_state "$(jq -n --arg wt "$WT_NATIVE" '[{id:"a@m",scope:"project",projectPath:$wt}]')"
reset_log
run "$OTHER" --worktree-path "$WT"
assert_exit "refuses when --worktree-path is not the current directory" 2 "$RC"
assert_contains "the refusal names both paths" "$OUT" "current directory is"
remaining="$(jq 'length' "$STATE")"
assert_eq "a refused run removes nothing" "1" "$remaining"
assert_not_contains "a refused run never calls the CLI" "$(cat "$LOG")" "plugin"

# --- nothing to reap ------------------------------------------------------------

seed_state "$(jq -n --arg o "$OTHER_NATIVE" '[{id:"a@m",scope:"project",projectPath:$o}]')"
reset_log
run "$WT" --worktree-path "$WT"
assert_exit "no records for this directory exits 0" 0 "$RC"
assert_contains "the zero case is reported, not silent" "$OUT" "nothing to reap"
assert_not_contains "no uninstall is attempted" "$(cat "$LOG")" "uninstall"

# --- the reap itself ------------------------------------------------------------

seed_state "$(jq -n --arg wt "$WT_NATIVE" --arg o "$OTHER_NATIVE" '[
  {id:"a@m",scope:"project",projectPath:$wt},
  {id:"b@m",scope:"project",projectPath:$wt},
  {id:"c@m",scope:"project",projectPath:$o},
  {id:"d@m",scope:"user"}
]')"
reset_log
run "$WT" --worktree-path "$WT"
assert_exit "a clean reap exits 0" 0 "$RC"
assert_contains "each reaped id is named" "$OUT" "reaped a@m"
assert_contains "each reaped id is named (2)" "$OUT" "reaped b@m"
left="$(jq -r 'map(.id) | sort | join(",")' "$STATE")"
assert_eq "only this directory's project records are removed" "c@m,d@m" "$left"
assert_not_contains "never escalates to user scope" "$(cat "$LOG")" "-s user"
assert_not_contains "never passes --prune" "$(cat "$LOG")" "--prune"

# --- path normalization ---------------------------------------------------------
# The record is written by Claude Code in native form; a case- or
# separator-variant of the same directory must still match. An early probe of
# this behaviour read as a null purely because two spellings of one path were
# compared raw.
if [[ "$(uname -s 2>/dev/null)" == MINGW* || "$(uname -s 2>/dev/null)" == MSYS* || "$(uname -s 2>/dev/null)" == CYGWIN* ]]; then
  variant="$(printf '%s' "$WT_NATIVE" | tr '/' "\134" | tr '[:lower:]' '[:upper:]')"
  seed_state "$(jq -n --arg v "$variant" '[{id:"a@m",scope:"project",projectPath:$v}]')"
  reset_log
  run "$WT" --worktree-path "$WT"
  assert_exit "a case/separator variant of the same path still reaps" 0 "$RC"
  # Asserting the exit code alone would pass on the "nothing to reap" path too,
  # which is exactly how a backslash-blind matcher hides.
  assert_contains "the backslash-spelled record was matched, not skipped" "$OUT" "reaped a@m"
  assert_eq "the variant record is gone" "0" "$(jq 'length' "$STATE")"
else
  variant="${WT_NATIVE}/"
  seed_state "$(jq -n --arg v "$variant" '[{id:"a@m",scope:"project",projectPath:$v}]')"
  reset_log
  run "$WT" --worktree-path "$WT"
  assert_exit "a trailing-slash variant of the same path still reaps" 0 "$RC"
  assert_eq "the variant record is gone" "0" "$(jq 'length' "$STATE")"
fi

# --- dry run --------------------------------------------------------------------

seed_state "$(jq -n --arg wt "$WT_NATIVE" '[{id:"a@m",scope:"project",projectPath:$wt}]')"
reset_log
run "$WT" --worktree-path "$WT" --dry-run
assert_exit "--dry-run exits 0" 0 "$RC"
assert_contains "--dry-run names what it would remove" "$OUT" "would reap a@m"
assert_eq "--dry-run removes nothing" "1" "$(jq 'length' "$STATE")"
assert_not_contains "--dry-run issues no uninstall" "$(cat "$LOG")" "uninstall"

# --- a CLI no-op is reported, never escalated -----------------------------------
# `enumerated but not removable` is the shape a stale enumeration produces. The
# script must report it and must not follow the CLI's own `--scope user` hint.

seed_state '[]'
reset_log
# Enumeration is stubbed to report a record the uninstall path will not honour.
cat >"$STUB_DIR/claude" <<'STUB2'
#!/usr/bin/env bash
set -uo pipefail
printf '%s\n' "$*" >>"$STUB_CALL_LOG"
if [[ "${1:-}" == "plugin" && "${2:-}" == "list" ]]; then
  p="$(pwd -W 2>/dev/null || pwd -P)"
  jq -n --arg p "$p" '{installed: [{id:"z@m",scope:"project",projectPath:$p}]}'
  exit 0
fi
printf 'Failed to uninstall plugin "z@m": Plugin "z@m" is installed in user scope, not project. Use --scope user to uninstall.\n' >&2
exit 1
STUB2
chmod +x "$STUB_DIR/claude"
run "$WT" --worktree-path "$WT"
assert_exit "a record that survives the pass exits 1" 1 "$RC"
assert_contains "the no-op is reported" "$OUT" "no-op for z@m"
assert_contains "the report forbids the user-scope escalation" "$OUT" "do NOT retry it with"
assert_contains "survivors are surfaced" "$OUT" "survived the pass"
assert_not_contains "never escalates to user scope" "$(cat "$LOG")" "-s user"

# --- visible degrade ------------------------------------------------------------

cat >"$STUB_DIR/claude" <<'STUB3'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"$STUB_CALL_LOG"
exit 1
STUB3
chmod +x "$STUB_DIR/claude"
seed_state '[]'
reset_log
run "$WT" --worktree-path "$WT"
assert_exit "an enumeration failure degrades with exit 3" 3 "$RC"
assert_contains "the degrade is visible, not silent" "$OUT" "warn:"

[[ $FAILED -eq 0 ]] || exit 1
printf '\nAll %d cases passed.\n' "$CASE_NUM"
