#!/usr/bin/env bash
# Regression tests for lane-launcher.sh.
#
# Coverage:
#   - config resolution + validation (missing / malformed / empty-lanes)
#   - status renders per-lane running/stopped state from an --agents-json fixture
#   - start (dry-run): launches only lanes not already running; mirrors
#     model/effort onto the command; keeps the prompt body out of the echo
#   - start refresh step: pull + marketplace update lines; --no-pull / --no-update
#   - restart (dry-run): stop-then-start for a running lane
#   - stop (real dispatch, PATH-stub claude): stops only running configured lanes
#   - stop / restart of an unknown lane name is rejected (exit 3)
#   - missing / empty prompt file and invalid effort are skipped, not launched
#   - a lane with no effort is refused while its siblings launch
#   - CLAUDE_CODE_EFFORT_LEVEL in the environment warns once per run
#   - run-once: one `claude -p` pass in auto mode, the version-gated
#     --permission-prompts, the effort refusal, the per-lane mkdir lock, the
#     running-lane skip and the execution-target host
#   - print-schedule: entries only for scheduled lanes, the generated script,
#     the schedule range check and the 262-character Windows /TR limit
#
# Uses a per-suite fixture repo (config + prompt files) and PATH-stub `claude`
# and `git` so no real CLI or network is touched.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$SCRIPT_DIR/lane-launcher.sh"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
# A case that passes no --data-dir writes its launch-commit marker to the inherited
# data dir. Pin that to the sandbox, named for the plugin so the launcher accepts it,
# so no case writes into the caller's real plugin data.
export CLAUDE_PLUGIN_DATA="$TMP/harness-ops-test-data"

FAILED=0
CASE_NUM=0
pass() {
  CASE_NUM=$((CASE_NUM + 1))
  printf 'PASS: [%d] %s\n' "$CASE_NUM" "$1"
}
fail() {
  CASE_NUM=$((CASE_NUM + 1))
  printf 'FAIL: [%d] %s\n      expected: %q\n      got:      %q\n' "$CASE_NUM" "$1" "$2" "$3" >&2
  FAILED=$((FAILED + 1))
}
assert_eq() { if [[ "$3" == "$2" ]]; then pass "$1"; else fail "$1" "$2" "$3"; fi; }
assert_not_eq() { if [[ "$3" != "$2" ]]; then pass "$1"; else fail "$1" "anything but: $2" "$3"; fi; }
assert_contains() { if [[ "$2" == *"$3"* ]]; then pass "$1"; else fail "$1" "contains: $3" "$2"; fi; }
assert_not_contains() { if [[ "$2" != *"$3"* ]]; then pass "$1"; else fail "$1" "absent: $3" "$2"; fi; }

# --- Fixture repo -------------------------------------------------------------
REPO="$TMP/repo"
mkdir -p "$REPO/.work/lanes"
cat >"$REPO/.work/lanes/lanes.json" <<'JSON'
{
  "prompt_dir": ".work/lanes",
  "lanes": [
    { "name": "work",    "prompt": "work.md",    "model": "opus",   "effort": "high" },
    { "name": "babysit", "prompt": "babysit.md", "model": "opus",   "effort": "medium",
      "settings": { "pluginConfigs": { "autonomy@test-marketplace": { "options": { "lane_stop_gate_enabled": true } } } } },
    { "name": "decide",  "prompt": "decide.md",                    "effort": "high" }
  ]
}
JSON
printf 'You are the work lane.\n' >"$REPO/.work/lanes/work.md"
printf 'You are the babysit lane.\n' >"$REPO/.work/lanes/babysit.md"
printf 'You are the decide lane.\n' >"$REPO/.work/lanes/decide.md"

CONFIG="$REPO/.work/lanes/lanes.json"

# agents --json fixture: "work" running as a background session, others absent.
AGENTS_RUNNING="$TMP/agents-running.json"
cat >"$AGENTS_RUNNING" <<'JSON'
[
  { "pid": 111, "cwd": "/repo", "kind": "background", "startedAt": 100,
    "sessionId": "sid-work-1", "name": "work", "status": "idle" },
  { "pid": 222, "cwd": "/repo", "kind": "interactive", "startedAt": 90,
    "sessionId": "sid-other", "name": "PR Babysit", "status": "busy" }
]
JSON
AGENTS_EMPTY="$TMP/agents-empty.json"
echo '[]' >"$AGENTS_EMPTY"

# An INTERACTIVE session that happens to share a lane name ("work") must never be
# treated as the lane — it is not a `--bg` lane session.
AGENTS_INTERACTIVE_WORK="$TMP/agents-interactive-work.json"
cat >"$AGENTS_INTERACTIVE_WORK" <<'JSON'
[
  { "pid": 333, "cwd": "/repo", "kind": "interactive", "startedAt": 100,
    "sessionId": "sid-int-work", "name": "work", "status": "busy" }
]
JSON

# --- PATH-stub claude + git (log every invocation) ----------------------------
STUB_BIN="$TMP/bin"
mkdir -p "$STUB_BIN"
CLAUDE_LOG="$TMP/claude.log"
cat >"$STUB_BIN/claude" <<STUB
#!/usr/bin/env bash
printf '%s\n' "\$*" >>"$CLAUDE_LOG"
# A test can drive the live \`claude agents --json\` path (no --agents-json):
# STUB_CLAUDE_AGENTS_RC forces a non-zero exit (transient-failure simulation);
# STUB_CLAUDE_AGENTS_JSON supplies the emitted array (default []).
if [[ "\$1" == "agents" ]]; then
  [[ "\${STUB_CLAUDE_AGENTS_RC:-0}" != 0 ]] && exit "\$STUB_CLAUDE_AGENTS_RC"
  printf '%s\n' "\${STUB_CLAUDE_AGENTS_JSON:-[]}"
  exit 0
fi
# A test can force a failed \`claude stop\` via STUB_CLAUDE_STOP_RC to exercise
# the stop-failure paths (no relaunch, non-zero exit).
if [[ "\$1" == "stop" ]]; then exit "\${STUB_CLAUDE_STOP_RC:-0}"; fi
# A test can force a failed \`claude plugin marketplace update\` via
# STUB_CLAUDE_UPDATE_RC to exercise the refresh-failure abort path.
if [[ "\$1" == "plugin" ]]; then exit "\${STUB_CLAUDE_UPDATE_RC:-0}"; fi
# STUB_CLAUDE_VERSION drives the ultracode version gate; the default clears it.
if [[ "\$1" == "--version" ]]; then
  printf '%s (Claude Code)\n' "\${STUB_CLAUDE_VERSION:-2.1.220}"
  exit 0
fi
STUB
REAL_GIT="$(command -v git)"
cat >"$STUB_BIN/git" <<STUB
#!/usr/bin/env bash
printf 'git %s\n' "\$*" >>"$CLAUDE_LOG"
# A test can force a failed \`git pull\` via STUB_GIT_PULL_RC to exercise the
# refresh-failure abort path. git is invoked for pull, rev-parse, and
# hash-object here (repos are passed via --repo), so matching on those
# subcommands is sufficient.
#
# hash-object delegates to the real git: the marker's repo key is a genuine
# digest, and stubbing it would let a broken keying scheme pass. --show-toplevel
# stands in for a real checkout (the fixture repos are plain directories, not
# git repos) by echoing the -C directory; STUB_GIT_TOPLEVEL overrides it with a
# different path, standing in for the canonicalization real git performs when
# --repo names a symlink. STUB_GIT_REVPARSE_RC deliberately does NOT apply here:
# an unresolvable HEAD says nothing about the working tree's location.
case "\$*" in
*pull*) exit "\${STUB_GIT_PULL_RC:-0}" ;;
*hash-object*) exec "$REAL_GIT" "\$@" ;;
*--show-toplevel*)
  if [[ -n "\${STUB_GIT_TOPLEVEL:-}" ]]; then printf '%s\n' "\$STUB_GIT_TOPLEVEL"; exit 0; fi
  [[ "\$1" == "-C" ]] || exit 1
  printf '%s\n' "\$2"
  exit 0
  ;;
*rev-parse*)
  [[ "\${STUB_GIT_REVPARSE_RC:-0}" != 0 ]] && exit "\${STUB_GIT_REVPARSE_RC}"
  printf '%s\n' "\${STUB_GIT_REVPARSE_SHA:-deadbeefcafefeedfacefeeddeadbeefcafefeed}"
  exit 0
  ;;
esac
STUB
chmod +x "$STUB_BIN/claude" "$STUB_BIN/git"

# --- Gate-arm stub (#1784) ----------------------------------------------------
# Stands in for the autonomy plugin's hooks/lane-stop-gate-arm.sh: logs its argv
# and succeeds (or fails via STUB_ARM_RC) so the suite can pin the launcher's
# fail-closed arming without a staged autonomy install. run_launcher passes it
# via --gate-arm-script; a case that wants the no-helper path calls the script
# directly.
ARM_LOG="$TMP/arm.log"
ARM_STUB="$TMP/arm-stub.sh"
cat >"$ARM_STUB" <<STUB
#!/usr/bin/env bash
printf '%s\n' "\$*" >>"$ARM_LOG"
exit "\${STUB_ARM_RC:-0}"
STUB
chmod +x "$ARM_STUB"

# Hermetic: the suite must not depend on an ambient `claude` (CI runners have
# none). Every case resolves `claude`/`git` to the logging stubs; cases that
# inspect the log reset it first. Real git is never needed — repos are passed
# via --repo, so resolve_repo never shells out.
SUITE_BASE_PATH="$PATH"
export PATH="$STUB_BIN:$PATH"
# An ambient value would add the override warning to every start/restart below.
unset CLAUDE_CODE_EFFORT_LEVEL

# Launch-commit markers are namespaced by repo (#792): the data dir is
# plugin-wide, but `work` is a conventional lane name in every repo. Mirrors the
# launcher's own repo_marker_key — a digest of the canonical repo path, not a
# character fold, so two paths differing only in a folded character keep
# distinct keys.
# Mirrors the launcher's `-C` scoping too: `git hash-object` keys on the object
# format of the repository it resolves, so the digest must be taken in the
# TARGET repo rather than wherever the suite happens to run. $2 is that anchor
# (default: the fixture repo) and $1 is the path being hashed — the two differ
# whenever git canonicalizes a symlinked --repo.
marker_repo_key() { printf '%s' "$1" | git -C "${2:-$REPO}" hash-object --stdin; }
REPO_KEY="$(marker_repo_key "$REPO")"

run_launcher() { bash "$SCRIPT" --gate-arm-script "$ARM_STUB" "$@"; }

# ============================================================================
# Config resolution + validation
# ============================================================================
out="$(run_launcher status --repo "$REPO" --config "$TMP/nope.json" --agents-json "$AGENTS_EMPTY" 2>&1)"
rc=$?
assert_eq "missing config exits 4" 4 "$rc"
assert_contains "missing config message" "$out" "lane config not found"

echo '{ not json' >"$TMP/bad.json"
out="$(run_launcher status --repo "$REPO" --config "$TMP/bad.json" --agents-json "$AGENTS_EMPTY" 2>&1)"
rc=$?
assert_eq "malformed config exits 3" 3 "$rc"

echo '{ "lanes": [] }' >"$TMP/empty.json"
out="$(run_launcher status --repo "$REPO" --config "$TMP/empty.json" --agents-json "$AGENTS_EMPTY" 2>&1)"
rc=$?
assert_eq "empty-lanes config exits 3" 3 "$rc"

cat >"$TMP/dupe.json" <<'JSON'
{ "lanes": [
  { "name": "work", "prompt": "work.md" },
  { "name": "work", "prompt": "babysit.md" }
] }
JSON
out="$(run_launcher start --repo "$REPO" --config "$TMP/dupe.json" --agents-json "$AGENTS_EMPTY" --dry-run 2>&1)"
rc=$?
assert_eq "duplicate lane names exit 3" 3 "$rc"
assert_contains "duplicate lane names named in message" "$out" "duplicate lane names: work"

# The lane name is also the launch-commit marker's filename (#792), so a name
# that is not a single path component would let two distinct lanes share one
# marker (`work` vs `group/../work`) or escape the data dir entirely.
# portability-ok: 'back\slash' is a literal single-quoted test input naming a
# Windows path separator, not a GNU `\s` regex class
for bad_name in 'group/../work' 'back\slash' '.' '..'; do
  jq -n --arg n "$bad_name" \
    '{lanes: [{name: $n, prompt: "work.md"}, {name: "other", prompt: "babysit.md"}]}' \
    >"$TMP/traversal.json"
  out="$(run_launcher start --repo "$REPO" --config "$TMP/traversal.json" --agents-json "$AGENTS_EMPTY" --dry-run 2>&1)"
  rc=$?
  assert_eq "lane name '$bad_name' is rejected with exit 3" 3 "$rc"
  assert_contains "lane name '$bad_name' is named in the message" "$out" "$bad_name"
done

# …but a name with any other punctuation stays free-form and is accepted.
cat >"$TMP/ok-name.json" <<'JSON'
{ "lanes": [ { "name": "work.2 (alt)", "prompt": "work.md", "effort": "high" } ] }
JSON
out="$(run_launcher start --repo "$REPO" --config "$TMP/ok-name.json" --agents-json "$AGENTS_EMPTY" --dry-run 2>&1)"
rc=$?
assert_eq "a free-form lane name without path separators is accepted" 0 "$rc"

# A non-string scalar is a config error, not an absent field. `lane_field` reads
# these with jq's `//` alternative, which fires on every FALSY value, so a
# mistyped `"effort": false` collapsed to the same "" an unset field produces
# and the lane launched with no effort at all — silently (#1784).
for mistyped_field in name model effort prompt; do
  jq -n --arg k "$mistyped_field" \
    '{lanes: [({name: "work", prompt: "work.md"} | .[$k] = false)]}' >"$TMP/mistyped.json"
  out="$(run_launcher start --repo "$REPO" --config "$TMP/mistyped.json" --agents-json "$AGENTS_EMPTY" --dry-run 2>&1)"
  rc=$?
  assert_eq "a boolean .$mistyped_field is rejected with exit 3" 3 "$rc"
  assert_contains "a boolean .$mistyped_field is named in the message" "$out" ".$mistyped_field is boolean"
done

# Defense-in-depth: a failed validation jq query must reject the config, not
# pass vacuously on empty output when jq errors (#2088). Each resolve_config
# validation query gets its own stub match so copy-pasted guards cannot regress
# independently.
REAL_JQ="$(command -v jq)"
mkdir -p "$TMP/jqbin"
cat >"$TMP/valid-for-jq-fail.json" <<'JSON'
{ "lanes": [ { "name": "work", "prompt": "work.md" } ] }
JSON
install_jq_fail_stub() {
  local needle="$1"
  cat >"$TMP/jqbin/jq" <<EOF
#!/usr/bin/env bash
if [[ "\$*" == *$(printf '%q' "$needle")* ]]; then
  echo 'jq: error: simulated validation query failure' >&2
  exit 1
fi
exec $(printf '%q' "$REAL_JQ") "\$@"
EOF
  chmod +x "$TMP/jqbin/jq"
}

install_jq_fail_stub 'group_by'
out="$(PATH="$TMP/jqbin:$PATH" run_launcher status --repo "$REPO" --config "$TMP/valid-for-jq-fail.json" --agents-json "$AGENTS_EMPTY" 2>&1)"
rc=$?
assert_eq "a failed duplicate-names validation query exits 3" 3 "$rc"
assert_contains "a failed duplicate-names validation query is named in the message" "$out" "validation query failed (duplicate lane names)"

install_jq_fail_stub 'test("[/'
out="$(PATH="$TMP/jqbin:$PATH" run_launcher status --repo "$REPO" --config "$TMP/valid-for-jq-fail.json" --agents-json "$AGENTS_EMPTY" 2>&1)"
rc=$?
assert_eq "a failed lane-name path-safety validation query exits 3" 3 "$rc"
assert_contains "a failed lane-name path-safety validation query is named in the message" "$out" "validation query failed (lane name path safety)"

install_jq_fail_stub '.key == "effort"'
out="$(PATH="$TMP/jqbin:$PATH" run_launcher status --repo "$REPO" --config "$TMP/valid-for-jq-fail.json" --agents-json "$AGENTS_EMPTY" 2>&1)"
rc=$?
assert_eq "a failed lane field typing validation query exits 3" 3 "$rc"
assert_contains "a failed lane field typing validation query is named in the message" "$out" "validation query failed (lane field typing)"

# `null` remains the JSON spelling of "no value" and stays equivalent to absent.
jq -n '{lanes: [{name: "work", prompt: "work.md", model: null, effort: "high"}]}' >"$TMP/nullmodel.json"
out="$(run_launcher start --repo "$REPO" --config "$TMP/nullmodel.json" --agents-json "$AGENTS_EMPTY" --dry-run 2>&1)"
rc=$?
assert_eq "a null scalar field is treated as absent" 0 "$rc"
assert_not_contains "a null model passes no --model flag" "$out" "--model"

# ============================================================================
# status
# ============================================================================
out="$(run_launcher status --repo "$REPO" --config "$CONFIG" --agents-json "$AGENTS_RUNNING" 2>&1)"
assert_contains "status: work is running" "$out" "work"
assert_contains "status: work shows sessionId" "$out" "sid-work-1"
assert_contains "status: work state running" "$out" "running"
assert_contains "status: decide present" "$out" "decide"
assert_contains "status: decide stopped" "$out" "stopped"
assert_not_contains "status ignores non-lane sessions" "$out" "sid-other"

# ============================================================================
# start (dry-run) — launch only lanes not already running
# ============================================================================
out="$(run_launcher start --repo "$REPO" --config "$CONFIG" --agents-json "$AGENTS_RUNNING" --dry-run 2>&1)"
assert_contains "start skips running lane" "$out" "skip work — already running"
assert_contains "start launches babysit" "$out" "claude --bg -n babysit"
assert_contains "start launches babysit in auto mode" "$out" "claude --bg -n babysit --permission-mode auto"
assert_contains "start mirrors babysit model" "$out" "-n babysit --permission-mode auto --model opus"
assert_contains "start mirrors babysit effort" "$out" "--effort medium"
assert_contains "start seeds prompt as placeholder" "$out" "<prompt:"
assert_not_contains "start hides prompt body" "$out" "You are the babysit lane"
assert_contains "start launches decide (no model)" "$out" "claude --bg -n decide"
assert_not_contains "decide has no model flag" "$out" "-n decide --model"
assert_contains "start passes babysit settings inline" "$out" "--settings"
assert_contains "start settings carry the lane config object" "$out" "lane_stop_gate_enabled"
assert_not_contains "work has no settings flag" "$out" "-n work --settings"

# per-lane settings must be a JSON object — a non-object skips that lane only
cat >"$TMP/badsettings.json" <<'JSON'
{
  "prompt_dir": ".work/lanes",
  "lanes": [
    { "name": "work",   "prompt": "work.md", "effort": "high", "settings": "not-an-object" },
    { "name": "decide", "prompt": "decide.md", "effort": "high" }
  ]
}
JSON
outbad="$(run_launcher start --repo "$REPO" --config "$TMP/badsettings.json" --agents-json "$AGENTS_EMPTY" --dry-run --no-pull --no-update 2>&1)"
rcbad=$?
assert_contains "non-object settings skips the lane with an error" "$outbad" "settings must be a JSON object"
assert_not_contains "non-object settings lane not launched" "$outbad" "claude --bg -n work"
assert_contains "other lanes still launch past a bad-settings lane" "$outbad" "claude --bg -n decide"
assert_eq "bad settings surfaces a non-zero exit" 1 "$rcbad"

# …and a JSON `false` is a VALUE, not an absent field. `//` is jq's alternative
# operator, so `false` yielded `empty` and reached bash as "" — the type check
# above is guarded on a non-empty value, so it never ran and the lane launched
# with `--settings` silently omitted (#1784).
cat >"$TMP/falsesettings.json" <<'JSON'
{
  "prompt_dir": ".work/lanes",
  "lanes": [
    { "name": "work",   "prompt": "work.md", "effort": "high", "settings": false },
    { "name": "decide", "prompt": "decide.md", "effort": "high" }
  ]
}
JSON
outfalse="$(run_launcher start --repo "$REPO" --config "$TMP/falsesettings.json" --agents-json "$AGENTS_EMPTY" --dry-run --no-pull --no-update 2>&1)"
rcfalse=$?
assert_contains "settings:false reaches the type check" "$outfalse" "settings must be a JSON object"
assert_not_contains "settings:false lane not launched" "$outfalse" "claude --bg -n work"
assert_contains "other lanes still launch past a false-settings lane" "$outfalse" "claude --bg -n decide"
assert_eq "settings:false surfaces a non-zero exit" 1 "$rcfalse"

# `null` stays the JSON spelling of "no value": the lane launches, without
# --settings, rather than being skipped as mistyped.
cat >"$TMP/nullsettings.json" <<'JSON'
{ "prompt_dir": ".work/lanes", "lanes": [ { "name": "work", "prompt": "work.md", "effort": "high", "settings": null } ] }
JSON
outnull="$(run_launcher start --repo "$REPO" --config "$TMP/nullsettings.json" --agents-json "$AGENTS_EMPTY" --dry-run --no-pull --no-update 2>&1)"
rcnull=$?
assert_eq "settings:null launches the lane" 0 "$rcnull"
assert_contains "settings:null still launches work" "$outnull" "claude --bg -n work"
assert_not_contains "settings:null passes no --settings flag" "$outnull" "--settings"

assert_contains "start pulls by default" "$out" "git -C $REPO pull --ff-only"
assert_contains "start updates marketplace" "$out" "plugin marketplace update"
out2="$(run_launcher start --repo "$REPO" --config "$CONFIG" --agents-json "$AGENTS_EMPTY" --dry-run --no-pull --no-update 2>&1)"
assert_contains "--no-pull skips pull" "$out2" "skip git pull"
assert_contains "--no-update skips update" "$out2" "skip plugin marketplace update"
assert_contains "empty agents → all lanes start" "$out2" "claude --bg -n work"

# ============================================================================
# restart (dry-run) — stop then start a running lane
# ============================================================================
out="$(run_launcher restart work --repo "$REPO" --config "$CONFIG" --agents-json "$AGENTS_RUNNING" --dry-run 2>&1)"
assert_contains "restart stops running work" "$out" "stop work (sid-work-1)"
assert_contains "restart relaunches work" "$out" "claude --bg -n work"
assert_not_contains "restart scoped to work" "$out" "claude --bg -n babysit"

# ============================================================================
# stop (real dispatch via PATH-stub claude)
# ============================================================================
: >"$CLAUDE_LOG"
out="$(run_launcher stop --repo "$REPO" --config "$CONFIG" --agents-json "$AGENTS_RUNNING" 2>&1)"
log="$(cat "$CLAUDE_LOG")"
assert_contains "stop dispatches claude stop for running lane" "$log" "stop sid-work-1"
assert_contains "stop reports non-running lanes" "$out" "babysit — not running"
assert_not_contains "stop never targets a non-lane session" "$log" "sid-other"

# ============================================================================
# start (REAL dispatch via PATH-stub claude + git) — proves the launch path
# actually shells out: pull, marketplace update, and `claude --bg` seeded with
# the prompt-file BODY as a single trailing argument (not --dry-run).
# ============================================================================
: >"$CLAUDE_LOG"
out="$(run_launcher start --repo "$REPO" --config "$CONFIG" --agents-json "$AGENTS_EMPTY" 2>&1)"
log="$(cat "$CLAUDE_LOG")"
assert_contains "start really pulls the repo" "$log" "git -C $REPO pull --ff-only"
assert_contains "start really updates the marketplace" "$log" "plugin marketplace update"
assert_contains "start really launches work with model+effort" "$log" "--bg -n work --permission-mode auto --model opus --effort high"
assert_contains "start seeds the prompt-file body as the trailing arg" "$log" "--effort high You are the work lane."
assert_contains "start really launches babysit" "$log" "--bg -n babysit --permission-mode auto --model opus --effort medium"

# ============================================================================
# unknown lane rejected
# ============================================================================
out="$(run_launcher stop bogus --repo "$REPO" --config "$CONFIG" --agents-json "$AGENTS_EMPTY" 2>&1)"
rc=$?
assert_eq "stop unknown lane exits 3" 3 "$rc"
assert_contains "stop unknown lane message" "$out" "unknown lane 'bogus'"

# ============================================================================
# missing / empty prompt + invalid effort are skipped, not launched
# ============================================================================
cat >"$TMP/badprompt.json" <<'JSON'
{ "prompt_dir": ".work/lanes",
  "lanes": [
    { "name": "gone",  "prompt": "missing.md" },
    { "name": "blank", "prompt": "blank.md" },
    { "name": "baddy", "prompt": "work.md", "effort": "turbo" },
    { "name": "ultra", "prompt": "work.md", "effort": "ultracode" }
  ] }
JSON
: >"$REPO/.work/lanes/blank.md"
out="$(run_launcher start --repo "$REPO" --config "$TMP/badprompt.json" --agents-json "$AGENTS_EMPTY" --dry-run 2>&1)"
assert_contains "missing prompt file skipped" "$out" "prompt file not found"
assert_contains "empty prompt file skipped" "$out" "prompt file is empty"
assert_contains "invalid effort skipped" "$out" "invalid effort 'turbo'"
assert_not_contains "no launch for bad lanes" "$out" "claude --bg -n baddy"
assert_contains "ultracode effort accepted" "$out" "claude --bg -n ultra"
assert_contains "ultracode passed through as --effort" "$out" "claude --bg -n ultra --permission-mode auto --effort ultracode"

# ============================================================================
# a lane with no effort is refused, never launched at the default; its siblings
# still launch, and restart refuses it before stopping the running session
# ============================================================================
cat >"$TMP/noeffort.json" <<'JSON'
{ "prompt_dir": ".work/lanes",
  "lanes": [
    { "name": "work",   "prompt": "work.md" },
    { "name": "decide", "prompt": "decide.md", "effort": "high" }
  ] }
JSON
: >"$CLAUDE_LOG"
out="$(run_launcher start --repo "$REPO" --config "$TMP/noeffort.json" --agents-json "$AGENTS_EMPTY" --no-pull --no-update 2>&1)"
rc=$?
log="$(cat "$CLAUDE_LOG")"
assert_eq "no-effort lane: the sweep exits non-zero" 1 "$rc"
assert_contains "no-effort lane: the refusal names the lane" "$out" "lane 'work': no effort set"
assert_contains "no-effort lane: the refusal names the config key" "$out" "lanes[].effort"
assert_contains "no-effort lane: the refusal names the effort table" "$out" '"Choose an effort level" table'
assert_not_contains "no-effort lane: no claude launch is recorded for it" "$log" "--bg -n work"
assert_contains "no-effort lane: a sibling with effort still launches" "$log" "--bg -n decide --permission-mode auto --effort high"

jq -n '{lanes: [{name: "work", prompt: "work.md", effort: null}]}' >"$TMP/nulleffort.json"
out="$(run_launcher start --repo "$REPO" --config "$TMP/nulleffort.json" --agents-json "$AGENTS_EMPTY" --dry-run --no-pull --no-update 2>&1)"
assert_contains "no-effort lane: an explicit null effort is refused too" "$out" "lane 'work': no effort set"
assert_not_contains "no-effort lane: a null-effort lane is not previewed" "$out" "claude --bg -n work"

: >"$CLAUDE_LOG"
out="$(run_launcher restart work --repo "$REPO" --config "$TMP/noeffort.json" --agents-json "$AGENTS_RUNNING" --no-pull --no-update 2>&1)"
assert_contains "no-effort lane: restart refuses it" "$out" "lane 'work': no effort set"
assert_not_contains "no-effort lane: restart leaves the running session up" "$(cat "$CLAUDE_LOG")" "stop sid-work-1"

# ============================================================================
# CLAUDE_CODE_EFFORT_LEVEL may override every lane's --effort: one warning per run
# ============================================================================
out="$(CLAUDE_CODE_EFFORT_LEVEL=low run_launcher start --repo "$REPO" --config "$CONFIG" --agents-json "$AGENTS_EMPTY" --dry-run --no-pull --no-update 2>&1)"
assert_eq "CLAUDE_CODE_EFFORT_LEVEL: start warns once across three lanes" 1 "$(grep -c 'CLAUDE_CODE_EFFORT_LEVEL=low is set' <<<"$out")"
assert_contains "CLAUDE_CODE_EFFORT_LEVEL: the warning says lane levels and agent pins may not hold" "$out" "may override lane --effort values and agent effort pins"
assert_contains "CLAUDE_CODE_EFFORT_LEVEL: the lanes still launch" "$out" "claude --bg -n decide --permission-mode auto --effort high"
out="$(CLAUDE_CODE_EFFORT_LEVEL=low run_launcher restart --repo "$REPO" --config "$CONFIG" --agents-json "$AGENTS_RUNNING" --dry-run --no-pull --no-update 2>&1)"
assert_eq "CLAUDE_CODE_EFFORT_LEVEL: restart warns once" 1 "$(grep -c 'CLAUDE_CODE_EFFORT_LEVEL=low is set' <<<"$out")"
out="$(run_launcher start --repo "$REPO" --config "$CONFIG" --agents-json "$AGENTS_EMPTY" --dry-run --no-pull --no-update 2>&1)"
assert_not_contains "CLAUDE_CODE_EFFORT_LEVEL: no warning when the variable is unset" "$out" "CLAUDE_CODE_EFFORT_LEVEL"

# ============================================================================
# ultracode version gate — below the floor the lane is skipped, and a restart
# preflights it BEFORE stopping so a healthy running lane stays up
# ============================================================================
cat >"$TMP/ultra.json" <<'JSON'
{ "prompt_dir": ".work/lanes",
  "lanes": [ { "name": "work", "prompt": "work.md", "effort": "ultracode" } ] }
JSON
out="$(STUB_CLAUDE_VERSION=2.1.202 run_launcher start --repo "$REPO" --config "$TMP/ultra.json" --agents-json "$AGENTS_EMPTY" --dry-run 2>&1)"
assert_contains "ultracode below floor skipped" "$out" "needs Claude Code >= 2.1.203"
assert_contains "skip message reports installed version" "$out" "(installed: 2.1.202)"
assert_not_contains "no launch below the floor" "$out" "claude --bg -n work"

out="$(STUB_CLAUDE_VERSION=2.1.203 run_launcher start --repo "$REPO" --config "$TMP/ultra.json" --agents-json "$AGENTS_EMPTY" --dry-run 2>&1)"
assert_contains "ultracode at the floor launches" "$out" "claude --bg -n work"

# The running lane must survive a restart the version gate refuses. NOT --dry-run:
# `run` short-circuits under it, so the stop could never reach the stub and the
# assertion below would hold no matter when the launcher stopped the lane.
: >"$CLAUDE_LOG"
out="$(STUB_CLAUDE_VERSION=2.1.202 run_launcher restart --repo "$REPO" --config "$TMP/ultra.json" --agents-json "$AGENTS_RUNNING" 2>&1)"
assert_contains "restart refused below the floor" "$out" "needs Claude Code >= 2.1.203"
assert_not_contains "healthy lane not stopped by a refused restart" "$(cat "$CLAUDE_LOG")" "stop sid-work-1"

# Every lane in a run shares ONE `claude --version` probe. Callers read the cache
# global directly; a `$(cli_version)` substitution would fill it in a subshell and
# re-probe once per lane, so this counts the probes rather than trusting the shape.
cat >"$TMP/ultra3.json" <<'JSON'
{ "prompt_dir": ".work/lanes",
  "lanes": [ { "name": "u1", "prompt": "work.md", "effort": "ultracode" },
             { "name": "u2", "prompt": "work.md", "effort": "ultracode" },
             { "name": "u3", "prompt": "work.md", "effort": "ultracode" } ] }
JSON
: >"$CLAUDE_LOG"
out="$(run_launcher start --repo "$REPO" --config "$TMP/ultra3.json" --agents-json "$AGENTS_EMPTY" --dry-run 2>&1)"
assert_contains "every ultracode lane launches" "$out" "claude --bg -n u3 --permission-mode auto --effort ultracode"
assert_eq "version probe memoized across lanes" 1 "$(grep -c -- '--version' "$CLAUDE_LOG")"

# --permission-prompts none keeps auto mode and denies only what would have
# prompted. The default stub is 2.1.220, below the 2.1.259 floor, so existing
# launch lines stay without the flag. These two cases pin both sides.
out="$(STUB_CLAUDE_VERSION=2.1.258 run_launcher start --repo "$REPO" --config "$CONFIG" --agents-json "$AGENTS_EMPTY" --dry-run --no-pull --no-update 2>&1)"
assert_contains "below 2.1.259 the launch stays auto" "$out" "claude --bg -n work --permission-mode auto --model opus"
assert_not_contains "below 2.1.259 the flag is omitted" "$out" "--permission-prompts none"
out="$(STUB_CLAUDE_VERSION=2.1.259 run_launcher start --repo "$REPO" --config "$CONFIG" --agents-json "$AGENTS_EMPTY" --dry-run --no-pull --no-update 2>&1)"
assert_contains "at 2.1.259 the flag follows auto" "$out" "claude --bg -n work --permission-mode auto --permission-prompts none --model opus"

# A dry run must preview with no `claude` installed — the exemption require_claude
# documents. The ultracode gate has no binary to probe there, so it reports the gate
# unevaluated and still previews the lane instead of refusing it.
NOCLAUDE_BIN="$TMP/bin-noclaude"
mkdir -p "$NOCLAUDE_BIN"
cp "$STUB_BIN/git" "$NOCLAUDE_BIN/git"
NOCLAUDE_PATH="$NOCLAUDE_BIN:$(dirname "$(command -v jq)"):/usr/bin:/bin"
assert_eq "no-claude PATH really carries no claude" "" "$(PATH="$NOCLAUDE_PATH" bash -c 'command -v claude' || true)"
out="$(
  export PATH="$NOCLAUDE_PATH"
  run_launcher start --repo "$REPO" --config "$TMP/ultra.json" --agents-json "$AGENTS_EMPTY" --dry-run 2>&1
)"
assert_contains "no-CLI dry run reports the gate unevaluated" "$out" "version gate not evaluated"
assert_contains "no-CLI dry run still previews the lane" "$out" "claude --bg -n work --permission-mode auto --effort ultracode"

# ============================================================================
# Medium 1 — an option must not swallow the next flag as its value
# ============================================================================
out="$(run_launcher status --config --dry-run --repo "$REPO" 2>&1)"
rc=$?
assert_eq "--config --dry-run rejected (exit 3)" 3 "$rc"
assert_contains "flag-squash message names the option" "$out" "option '--config' requires a non-option argument"
out="$(run_launcher status --repo --agents-json "$AGENTS_EMPTY" 2>&1)"
rc=$?
assert_eq "--repo followed by a flag rejected (exit 3)" 3 "$rc"
out="$(run_launcher status --agents-json --config "$CONFIG" --repo "$REPO" 2>&1)"
rc=$?
assert_eq "--agents-json followed by a flag rejected (exit 3)" 3 "$rc"

# ============================================================================
# Medium 3 — partial failure surfaces in the exit status (sweep still completes)
# ============================================================================
out="$(run_launcher start --repo "$REPO" --config "$TMP/badprompt.json" --agents-json "$AGENTS_EMPTY" 2>&1)"
rc=$?
assert_eq "partial launch failure exits non-zero" 1 "$rc"
out="$(run_launcher start --repo "$REPO" --config "$CONFIG" --agents-json "$AGENTS_EMPTY" 2>&1)"
rc=$?
assert_eq "all-lanes-ok start exits 0" 0 "$rc"

# ============================================================================
# Medium 3 / stop exit code — a failed `claude stop` must not relaunch, exits non-zero
# ============================================================================
: >"$CLAUDE_LOG"
out="$(STUB_CLAUDE_STOP_RC=1 run_launcher restart work --repo "$REPO" --config "$CONFIG" --agents-json "$AGENTS_RUNNING" 2>&1)"
rc=$?
log="$(cat "$CLAUDE_LOG")"
assert_eq "restart with failed stop exits non-zero" 1 "$rc"
assert_contains "restart with failed stop refuses relaunch" "$out" "not relaunching"
assert_not_contains "no relaunch after failed stop" "$log" "--bg -n work"
out="$(STUB_CLAUDE_STOP_RC=1 run_launcher stop work --repo "$REPO" --config "$CONFIG" --agents-json "$AGENTS_RUNNING" 2>&1)"
rc=$?
assert_eq "stop with failed claude stop exits non-zero" 1 "$rc"
assert_contains "stop failure reported" "$out" "work — stop failed"

# ============================================================================
# Codex P1 — restart must preflight launch inputs BEFORE stopping a running
# lane: a recoverable prompt/effort error must not take the healthy session
# down. `work` is running (sid-work-1) but its prompt file is missing, so the
# stop must never fire and the session must stay up.
# ============================================================================
cat >"$TMP/restart-badprompt.json" <<'JSON'
{ "prompt_dir": ".work/lanes",
  "lanes": [ { "name": "work", "prompt": "missing.md" } ] }
JSON
: >"$CLAUDE_LOG"
out="$(run_launcher restart work --repo "$REPO" --config "$TMP/restart-badprompt.json" --agents-json "$AGENTS_RUNNING" 2>&1)"
rc=$?
log="$(cat "$CLAUDE_LOG")"
assert_eq "restart with a bad prompt exits non-zero" 1 "$rc"
assert_contains "restart bad-prompt error surfaced" "$out" "prompt file not found"
assert_not_contains "restart does not stop the healthy running lane" "$log" "stop sid-work-1"

# ============================================================================
# Low-priority carry-forwards — uncovered flag paths
# ============================================================================
out="$(run_launcher status --repo "$REPO" --config "$CONFIG" --agents-json "$TMP/no-such-agents.json" 2>&1)"
rc=$?
assert_eq "--agents-json missing file exits 4" 4 "$rc"
assert_contains "--agents-json missing file message" "$out" "agents-json file not found"
# `--` ends option parsing: tokens after it are lane names (options must precede it).
out="$(run_launcher stop --repo "$REPO" --config "$CONFIG" --agents-json "$AGENTS_EMPTY" -- babysit 2>&1)"
rc=$?
assert_eq "-- passthrough: known lane after -- is accepted (exit 0)" 0 "$rc"
assert_contains "-- passthrough targets the named lane" "$out" "babysit — not running"

# ============================================================================
# Codex P1 — an interactive session sharing a lane name is not the lane
# (kind must be background). `start` launches the lane, `status` shows stopped,
# `stop` never targets the interactive session.
# ============================================================================
out="$(run_launcher status --repo "$REPO" --config "$CONFIG" --agents-json "$AGENTS_INTERACTIVE_WORK" 2>&1)"
assert_contains "interactive same-name is not a running lane" "$out" "stopped"
assert_not_contains "interactive same-name sessionId not shown" "$out" "sid-int-work"
out="$(run_launcher start --repo "$REPO" --config "$CONFIG" --agents-json "$AGENTS_INTERACTIVE_WORK" --dry-run 2>&1)"
assert_contains "start launches lane despite interactive namesake" "$out" "claude --bg -n work"
assert_not_contains "start does not skip work for interactive namesake" "$out" "skip work"
: >"$CLAUDE_LOG"
out="$(run_launcher stop work --repo "$REPO" --config "$CONFIG" --agents-json "$AGENTS_INTERACTIVE_WORK" 2>&1)"
log="$(cat "$CLAUDE_LOG")"
assert_contains "stop treats interactive namesake as not running" "$out" "work — not running"
assert_not_contains "stop never targets the interactive namesake" "$log" "sid-int-work"

# ============================================================================
# Codex P1 — a failed live `claude agents --json` must abort a mutating action,
# never fabricate an empty list (which would relaunch still-live lanes). These
# omit --agents-json so the live listing path is exercised via the stub.
# ============================================================================
: >"$CLAUDE_LOG"
out="$(STUB_CLAUDE_AGENTS_RC=1 run_launcher start --repo "$REPO" --config "$CONFIG" 2>&1)"
rc=$?
log="$(cat "$CLAUDE_LOG")"
assert_eq "failed live session list aborts start (exit 4)" 4 "$rc"
assert_contains "failed session list is reported" "$out" "could not list sessions"
assert_not_contains "no lane is launched when the session list failed" "$log" "--bg -n"

# A successful live list drives the same decisions as a fixture: empty → launch.
out="$(STUB_CLAUDE_AGENTS_JSON='[]' run_launcher start --repo "$REPO" --config "$CONFIG" --dry-run 2>&1)"
assert_contains "live empty session list → lanes launch" "$out" "claude --bg -n work"

# --dry-run mutates nothing, so a failed live list is tolerated (preview, exit 0)
# — preserving the documented offline-dry-run behavior.
out="$(STUB_CLAUDE_AGENTS_RC=1 run_launcher start --repo "$REPO" --config "$CONFIG" --dry-run 2>&1)"
rc=$?
assert_eq "dry-run tolerates a failed live list (exit 0)" 0 "$rc"

# ============================================================================
# A failed pre-launch refresh ABORTS the launch: no lane is started/stopped and
# the action exits non-zero with an actionable message. The refresh is a
# documented launch prerequisite, so stale repo/plugin state must never seed
# background lanes.
# ============================================================================
: >"$CLAUDE_LOG"
out="$(STUB_GIT_PULL_RC=1 run_launcher start --repo "$REPO" --config "$CONFIG" --agents-json "$AGENTS_EMPTY" 2>&1)"
rc=$?
log="$(cat "$CLAUDE_LOG")"
assert_eq "start aborts when git pull fails (exit 1)" 1 "$rc"
assert_contains "start refresh-failure message is actionable" "$out" "refresh failed"
assert_not_contains "no lane launched after a failed pull" "$log" "--bg -n"

: >"$CLAUDE_LOG"
out="$(STUB_CLAUDE_UPDATE_RC=1 run_launcher start --repo "$REPO" --config "$CONFIG" --agents-json "$AGENTS_EMPTY" 2>&1)"
rc=$?
log="$(cat "$CLAUDE_LOG")"
assert_eq "start aborts when marketplace update fails (exit 1)" 1 "$rc"
assert_contains "start marketplace-update refresh-failure message is actionable" "$out" "refresh failed"
assert_not_contains "no lane launched after a failed update" "$log" "--bg -n"

: >"$CLAUDE_LOG"
out="$(STUB_GIT_PULL_RC=1 run_launcher restart work --repo "$REPO" --config "$CONFIG" --agents-json "$AGENTS_RUNNING" 2>&1)"
rc=$?
log="$(cat "$CLAUDE_LOG")"
assert_eq "restart aborts when git pull fails (exit 1)" 1 "$rc"
assert_not_contains "restart does not stop a lane after a failed pull" "$log" "stop sid-work-1"
assert_not_contains "restart does not relaunch after a failed pull" "$log" "--bg -n"

# The intentional-bypass path (--no-pull/--no-update) is NOT a refresh failure:
# the skipped-step status stays 0, so lanes still launch even with the failure
# env set (proves the abort keys on real failure, not on skipping).
out="$(STUB_GIT_PULL_RC=1 STUB_CLAUDE_UPDATE_RC=1 run_launcher start --repo "$REPO" --config "$CONFIG" --agents-json "$AGENTS_EMPTY" --no-pull --no-update --dry-run 2>&1)"
rc=$?
assert_eq "refresh bypass still launches despite failure env (exit 0)" 0 "$rc"
assert_contains "refresh bypass launches lanes" "$out" "claude --bg -n work"

# The same intentional-bypass invariant holds for restart, which refreshes via a
# different callback path (_restart_one): --no-pull/--no-update keeps the refresh
# status 0, so a targeted dry-run restart still previews the relaunch despite the
# failure env being set.
out="$(STUB_GIT_PULL_RC=1 STUB_CLAUDE_UPDATE_RC=1 run_launcher restart work --repo "$REPO" --config "$CONFIG" --agents-json "$AGENTS_RUNNING" --no-pull --no-update --dry-run 2>&1)"
rc=$?
assert_eq "restart refresh bypass still relaunches despite failure env (exit 0)" 0 "$rc"
assert_contains "restart refresh bypass previews the lane relaunch" "$out" "claude --bg -n work"

# ============================================================================
# An unknown restart target is rejected BEFORE the refresh mutates anything
# (matches stop's fail-first behavior): the log shows no git pull and no
# marketplace update. Regression guard against the old order that pulled +
# updated only to reject the misspelled target afterward.
# ============================================================================
: >"$CLAUDE_LOG"
out="$(run_launcher restart does-not-exist --repo "$REPO" --config "$CONFIG" --agents-json "$AGENTS_RUNNING" 2>&1)"
rc=$?
log="$(cat "$CLAUDE_LOG")"
assert_eq "restart unknown lane exits 3" 3 "$rc"
assert_contains "restart unknown lane message" "$out" "unknown lane 'does-not-exist'"
assert_not_contains "restart unknown lane does not pull" "$log" "pull --ff-only"
assert_not_contains "restart unknown lane does not update the marketplace" "$log" "plugin marketplace update"

# ============================================================================
# #792 — launch-commit marker: start (real dispatch) writes
# <data-dir>/lanes/<repo-key>/<name>-launch-commit for every lane it actually launches,
# holding the captured `git rev-parse HEAD` SHA.
# ============================================================================
DATA_DIR="$TMP/data"
: >"$CLAUDE_LOG"
out="$(run_launcher start --repo "$REPO" --config "$CONFIG" --agents-json "$AGENTS_EMPTY" --data-dir "$DATA_DIR" 2>&1)"
rc=$?
assert_eq "marker: start with all lanes launching exits 0" 0 "$rc"
marker="$(cat "$DATA_DIR/lanes/$REPO_KEY/work-launch-commit" 2>/dev/null)"
assert_eq "marker: work marker holds the stubbed HEAD sha" "deadbeefcafefeedfacefeeddeadbeefcafefeed" "$marker"
marker="$(cat "$DATA_DIR/lanes/$REPO_KEY/babysit-launch-commit" 2>/dev/null)"
assert_eq "marker: babysit marker holds the stubbed HEAD sha" "deadbeefcafefeedfacefeeddeadbeefcafefeed" "$marker"

# A lane `start` SKIPS (already running) must not get a fresh/overwritten
# marker — only lanes actually (re)launched this run are recorded.
DATA_DIR2="$TMP/data2"
mkdir -p "$DATA_DIR2/lanes/$REPO_KEY"
printf 'pre-existing-sha\n' >"$DATA_DIR2/lanes/$REPO_KEY/work-launch-commit"
out="$(run_launcher start --repo "$REPO" --config "$CONFIG" --agents-json "$AGENTS_RUNNING" --data-dir "$DATA_DIR2" 2>&1)"
marker="$(cat "$DATA_DIR2/lanes/$REPO_KEY/work-launch-commit" 2>/dev/null)"
assert_eq "marker: skipped (already-running) lane keeps its existing marker" "pre-existing-sha" "$marker"
marker="$(cat "$DATA_DIR2/lanes/$REPO_KEY/babysit-launch-commit" 2>/dev/null)"
assert_eq "marker: a lane that DID launch this run still gets one" "deadbeefcafefeedfacefeeddeadbeefcafefeed" "$marker"

DATA_DIR3="$TMP/data3"
out="$(run_launcher restart work --repo "$REPO" --config "$CONFIG" --agents-json "$AGENTS_RUNNING" --data-dir "$DATA_DIR3" 2>&1)"
marker="$(cat "$DATA_DIR3/lanes/$REPO_KEY/work-launch-commit" 2>/dev/null)"
assert_eq "marker: restart records the marker for the relaunched lane" "deadbeefcafefeedfacefeeddeadbeefcafefeed" "$marker"

# --dry-run mutates nothing: no marker file is written, but the preview names
# the would-be marker path and the resolved HEAD.
DATA_DIR4="$TMP/data4"
out="$(run_launcher start --repo "$REPO" --config "$CONFIG" --agents-json "$AGENTS_EMPTY" --data-dir "$DATA_DIR4" --dry-run 2>&1)"
assert_contains "marker: dry-run previews the marker write" "$out" "DRY-RUN: write launch-commit marker $DATA_DIR4/lanes/$REPO_KEY/work-launch-commit <- deadbeefcafefeedfacefeeddeadbeefcafefeed"
if [[ -e "$DATA_DIR4/lanes/$REPO_KEY/work-launch-commit" ]]; then notwritten=1; else notwritten=0; fi
assert_eq "marker: dry-run writes no file" 0 "$notwritten"

# An unresolvable HEAD (git rev-parse fails) skips the write with a warning on
# stderr but must NOT fail the lane launch itself (best-effort).
DATA_DIR5="$TMP/data5"
out="$(STUB_GIT_REVPARSE_RC=1 run_launcher start --repo "$REPO" --config "$CONFIG" --agents-json "$AGENTS_EMPTY" --data-dir "$DATA_DIR5" 2>&1)"
rc=$?
assert_eq "marker: unresolvable HEAD still exits 0 (best-effort)" 0 "$rc"
assert_contains "marker: unresolvable HEAD warns on skip" "$out" "launch-commit marker skipped"
if [[ -e "$DATA_DIR5/lanes/$REPO_KEY/work-launch-commit" ]]; then notwritten=1; else notwritten=0; fi
assert_eq "marker: unresolvable HEAD writes no file" 0 "$notwritten"

# …and when a PREVIOUS launch left a marker, an unrecordable relaunch must
# remove it rather than let the probe read that older commit as this session's
# launch point.
DATA_DIR5B="$TMP/data5b"
mkdir -p "$DATA_DIR5B/lanes/$REPO_KEY"
printf 'previouslaunchsha\n' >"$DATA_DIR5B/lanes/$REPO_KEY/work-launch-commit"
out="$(STUB_GIT_REVPARSE_RC=1 run_launcher restart work --repo "$REPO" --config "$CONFIG" --agents-json "$AGENTS_RUNNING" --data-dir "$DATA_DIR5B" 2>&1)"
rc=$?
assert_eq "marker: unrecordable relaunch still exits 0 (best-effort)" 0 "$rc"
if [[ -e "$DATA_DIR5B/lanes/$REPO_KEY/work-launch-commit" ]]; then stale=1; else stale=0; fi
assert_eq "marker: unrecordable relaunch invalidates the previous launch's marker" 0 "$stale"
assert_contains "marker: invalidation is announced on stderr" "$out" "removed the previous launch's marker"

# A write failure (marker path occupied by a directory) is the other
# unrecordable path: same invalidation, same best-effort exit.
DATA_DIR5C="$TMP/data5c"
mkdir -p "$DATA_DIR5C/lanes/$REPO_KEY/work-launch-commit"
out="$(run_launcher restart work --repo "$REPO" --config "$CONFIG" --agents-json "$AGENTS_RUNNING" --data-dir "$DATA_DIR5C" 2>&1)"
rc=$?
assert_eq "marker: failed write still exits 0 (best-effort)" 0 "$rc"
assert_contains "marker: failed write warns" "$out" "launch-commit marker write failed"

# --dry-run must never touch an existing marker, even when HEAD is unresolvable:
# it returns before the marker write/invalidate path entirely.
DATA_DIR5D="$TMP/data5d"
mkdir -p "$DATA_DIR5D/lanes/$REPO_KEY"
printf 'previouslaunchsha\n' >"$DATA_DIR5D/lanes/$REPO_KEY/work-launch-commit"
out="$(STUB_GIT_REVPARSE_RC=1 run_launcher restart work --repo "$REPO" --config "$CONFIG" --agents-json "$AGENTS_RUNNING" --data-dir "$DATA_DIR5D" --dry-run 2>&1)"
marker="$(cat "$DATA_DIR5D/lanes/$REPO_KEY/work-launch-commit" 2>/dev/null)"
assert_eq "marker: dry-run leaves an existing marker untouched" "previouslaunchsha" "$marker"

DATA_DIR6="$TMP/harness-ops-data6"
out="$(CLAUDE_PLUGIN_DATA="$DATA_DIR6" run_launcher start --repo "$REPO" --config "$CONFIG" --agents-json "$AGENTS_EMPTY" 2>&1)"
marker="$(cat "$DATA_DIR6/lanes/$REPO_KEY/work-launch-commit" 2>/dev/null)"
assert_eq "marker: falls back to \$CLAUDE_PLUGIN_DATA when --data-dir is unset" "deadbeefcafefeedfacefeeddeadbeefcafefeed" "$marker"

# Another plugin's SessionStart hook can export its own data dir into every Bash
# call as CLAUDE_PLUGIN_DATA; the marker must never land there.
FOREIGN7="$TMP/codex-openai-codex"
out="$(HOME="$TMP/home7" CLAUDE_PLUGIN_DATA="$FOREIGN7" run_launcher start --repo "$REPO" --config "$CONFIG" --agents-json "$AGENTS_EMPTY" 2>&1)"
assert_eq "marker: a foreign CLAUDE_PLUGIN_DATA gets no marker" "absent" "$([[ -e "$FOREIGN7" ]] && echo present || echo absent)"
marker="$(cat "$TMP/home7/.claude/plugins/data/harness-ops/lanes/$REPO_KEY/work-launch-commit" 2>/dev/null)"
assert_eq "marker: a foreign CLAUDE_PLUGIN_DATA falls back to the home data dir" "deadbeefcafefeedfacefeeddeadbeefcafefeed" "$marker"

# The data dir is plugin-wide, so a second repo running the same conventional
# lane name must not overwrite the first repo's marker.
REPO_B="$TMP/repo-b"
mkdir -p "$REPO_B/.work/lanes"
cp "$REPO/.work/lanes/lanes.json" "$REPO_B/.work/lanes/lanes.json"
cp "$REPO/.work/lanes/work.md" "$REPO/.work/lanes/babysit.md" "$REPO/.work/lanes/decide.md" "$REPO_B/.work/lanes/"
REPO_B_KEY="$(marker_repo_key "$REPO_B")"
DATA_DIR7="$TMP/data7"
mkdir -p "$DATA_DIR7/lanes/$REPO_KEY"
printf 'repo-a-sha\n' >"$DATA_DIR7/lanes/$REPO_KEY/work-launch-commit"
out="$(run_launcher start --repo "$REPO_B" --config "$REPO_B/.work/lanes/lanes.json" --agents-json "$AGENTS_EMPTY" --data-dir "$DATA_DIR7" 2>&1)"
marker="$(cat "$DATA_DIR7/lanes/$REPO_KEY/work-launch-commit" 2>/dev/null)"
assert_eq "marker: launching 'work' in another repo leaves repo A's marker intact" "repo-a-sha" "$marker"
marker="$(cat "$DATA_DIR7/lanes/$REPO_B_KEY/work-launch-commit" 2>/dev/null)"
assert_eq "marker: the other repo gets its own namespaced marker" "deadbeefcafefeedfacefeeddeadbeefcafefeed" "$marker"

# The repo key must be injective. A character fold (`tr -c 'A-Za-z0-9_-' '-'`)
# collapses these two real, distinct checkout paths onto one key — the exact
# collision the repo namespace exists to prevent.
fold_key_a="$(printf '%s' "$TMP/repos/foo-bar" | git hash-object --stdin)"
fold_key_b="$(printf '%s' "$TMP/repos/foo/bar" | git hash-object --stdin)"
assert_not_eq "marker: repo key does not collide across fold-equivalent paths" \
  "$fold_key_a" "$fold_key_b"

# The key must come from git's canonical toplevel, not the --repo argument
# verbatim: when --repo names a symlink, git resolves it and the documented
# probe (which asks git directly) would otherwise look under a different key.
# STUB_GIT_TOPLEVEL stands in for that resolution.
DATA_DIR8="$TMP/data8"
CANONICAL="$TMP/canonical-repo"
out="$(STUB_GIT_TOPLEVEL="$CANONICAL" run_launcher start --repo "$REPO" --config "$CONFIG" --agents-json "$AGENTS_EMPTY" --data-dir "$DATA_DIR8" 2>&1)"
marker="$(cat "$DATA_DIR8/lanes/$(marker_repo_key "$CANONICAL")/work-launch-commit" 2>/dev/null)"
assert_eq "marker: keys on git's canonical toplevel, not the --repo argument" "deadbeefcafefeedfacefeeddeadbeefcafefeed" "$marker"
if [[ -e "$DATA_DIR8/lanes/$REPO_KEY/work-launch-commit" ]]; then usedarg=1; else usedarg=0; fi
assert_eq "marker: nothing is written under the un-canonicalized --repo key" 0 "$usedarg"

# `git hash-object` digests with the object format of the repository it
# RESOLVES. Unscoped, it resolved the caller's — so a launcher run from a SHA-1
# cwd against a SHA-256 --repo wrote a 40-hex key, while context/refresh.md's
# probe, which runs inside that checkout, computed the 64-hex one and read a
# directory the launcher never wrote: staleness detection silently off. The
# digest must be taken IN the target repo. Skipped where git cannot create a
# SHA-256 repository (the format is not universally compiled in).
# $REAL_GIT, not the PATH stub: the stub answers only pull / rev-parse /
# hash-object and exits 0 for anything else, so a stubbed `git init` would
# report success while creating no repository at all — and the fixture would
# then compare two SHA-1 keys and discriminate nothing.
SHA256_REPO="$TMP/sha256-repo"
if "$REAL_GIT" init --object-format=sha256 -q "$SHA256_REPO" 2>/dev/null; then
  mkdir -p "$SHA256_REPO/.work/lanes"
  cp "$REPO/.work/lanes/work.md" "$SHA256_REPO/.work/lanes/"
  cat >"$SHA256_REPO/.work/lanes/lanes.json" <<'JSON'
{ "prompt_dir": ".work/lanes", "lanes": [ { "name": "work", "prompt": "work.md", "effort": "high" } ] }
JSON
  DATA_DIR9="$TMP/data9"
  out="$(run_launcher start --repo "$SHA256_REPO" --config "$SHA256_REPO/.work/lanes/lanes.json" \
    --agents-json "$AGENTS_EMPTY" --data-dir "$DATA_DIR9" --no-pull --no-update 2>&1)"
  # The key the target repo's own object format yields — 64 hex for SHA-256.
  sha256_key="$(marker_repo_key "$SHA256_REPO" "$SHA256_REPO")"
  assert_eq "marker: a SHA-256 repo yields a 64-character key" 64 "${#sha256_key}"
  marker="$(cat "$DATA_DIR9/lanes/$sha256_key/work-launch-commit" 2>/dev/null)"
  assert_eq "marker: written under the TARGET repo's object-format key" "deadbeefcafefeedfacefeeddeadbeefcafefeed" "$marker"
  # A key derived from the CALLER's object format (SHA-1 here) must hold
  # nothing — only the target repo's object-format key is valid.
  sha1_key="$(printf '%s' "$SHA256_REPO" | git -C "$REPO" hash-object --stdin)"
  if [[ -e "$DATA_DIR9/lanes/$sha1_key/work-launch-commit" ]]; then wrongfmt=1; else wrongfmt=0; fi
  assert_eq "marker: nothing is written under the caller-format key" 0 "$wrongfmt"
else
  printf 'SKIP: git cannot create a SHA-256 repository here — object-format keying unverified\n' >&2
fi

# ============================================================================
# #1784 — lane-stop gate arming: a lane whose settings request the gate is
# armed at launch (arm id injected into --settings), and one that cannot be
# armed is skipped — fail closed, never silently ungated.
# ============================================================================
# Real dispatch: the babysit lane requests the gate → the arm stub runs with
# --id/--cwd, and the launched --settings carry the SAME id under
# lane_stop_gate_arm_id.
: >"$CLAUDE_LOG"
: >"$ARM_LOG"
out="$(run_launcher start --repo "$REPO" --config "$CONFIG" --agents-json "$AGENTS_EMPTY" 2>&1)"
rc=$?
log="$(cat "$CLAUDE_LOG")"
armlog="$(cat "$ARM_LOG")"
assert_eq "arm: gate-requesting start exits 0" 0 "$rc"
assert_contains "arm: helper invoked with an arm id" "$armlog" "--id "
assert_contains "arm: helper receives the lane cwd" "$armlog" "--cwd $REPO"
assert_contains "arm: launched settings carry lane_stop_gate_arm_id" "$log" "lane_stop_gate_arm_id"
armed_id="$(printf '%s' "$armlog" | sed -n 's/.*--id \([A-Za-z0-9_-]*\).*/\1/p' | head -n 1)"
settings_id="$(printf '%s\n' "$log" | grep -o 'lane_stop_gate_arm_id[^,}]*' | sed 's/.*://; s/"//g' | head -n 1)"
assert_eq "arm: the id the helper armed is the id the session receives" "$armed_id" "$settings_id"
assert_not_eq "arm: the id is non-empty" "" "$armed_id"

# The non-gate lanes (work, decide: no gate request in settings) never arm.
gate_calls="$(grep -c -- '--id' "$ARM_LOG" 2>/dev/null || true)"
assert_eq "arm: only the gate-requesting lane arms (one helper call)" 1 "$gate_calls"

# The lane's sentinel/marker settings ride into the arm call.
cat >"$TMP/gateopts.json" <<'JSON'
{ "prompt_dir": ".work/lanes",
  "lanes": [ { "name": "work", "prompt": "work.md", "effort": "high",
    "settings": { "pluginConfigs": { "autonomy@test-marketplace": { "options": {
      "lane_stop_gate_enabled": true,
      "lane_stop_gate_sentinel": "DONE-X",
      "lane_stop_gate_marker": ".lane-complete" } } } } } ] }
JSON
: >"$ARM_LOG"
out="$(run_launcher start --repo "$REPO" --config "$TMP/gateopts.json" --agents-json "$AGENTS_EMPTY" --no-pull --no-update 2>&1)"
armlog="$(cat "$ARM_LOG")"
assert_contains "arm: the lane's sentinel reaches the helper" "$armlog" "--sentinel DONE-X"
assert_contains "arm: the lane's marker reaches the helper" "$armlog" "--marker .lane-complete"

# An EXPLICIT empty marker disables the marker channel for this session, which
# is a different verdict from leaving the option unset: an arm record with no
# marker key at all lets the gate fall through to the user-level marker, where a
# leftover global marker file can authorize a stop the lane never signaled. The
# empty value must therefore reach the helper, not be read as absence.
#
# The sentinel is deliberately NOT symmetric, and this fixture sets both to pin
# the asymmetry: lane-stop-gate.sh substitutes the default token for an empty
# sentinel, so emptiness is not a configured value there. Recording one would
# buy no behavior while suppressing the record's fall-through to the user-level
# sentinel — so an empty sentinel is still treated as absent.
cat >"$TMP/gate-empty-marker.json" <<'JSON'
{ "prompt_dir": ".work/lanes",
  "lanes": [ { "name": "work", "prompt": "work.md", "effort": "high",
    "settings": { "pluginConfigs": { "autonomy@test-marketplace": { "options": {
      "lane_stop_gate_enabled": true,
      "lane_stop_gate_sentinel": "",
      "lane_stop_gate_marker": "" } } } } } ] }
JSON
: >"$ARM_LOG"
out="$(run_launcher start --repo "$REPO" --config "$TMP/gate-empty-marker.json" --agents-json "$AGENTS_EMPTY" --no-pull --no-update 2>&1)"
armlog="$(cat "$ARM_LOG")"
assert_contains "arm: an explicitly empty marker still reaches the helper" "$armlog" "--marker"
assert_not_contains "arm: an explicitly empty sentinel is still treated as absent" "$armlog" "--sentinel"

# …while an option the lane never set stays absent from the arm call, so the
# gate's own resolution order (managed ▷ arm record ▷ user settings) still
# reaches user settings for it.
cat >"$TMP/gate-no-opts.json" <<'JSON'
{ "prompt_dir": ".work/lanes",
  "lanes": [ { "name": "work", "prompt": "work.md", "effort": "high",
    "settings": { "pluginConfigs": { "autonomy@test-marketplace": { "options": {
      "lane_stop_gate_enabled": true } } } } } ] }
JSON
: >"$ARM_LOG"
out="$(run_launcher start --repo "$REPO" --config "$TMP/gate-no-opts.json" --agents-json "$AGENTS_EMPTY" --no-pull --no-update 2>&1)"
armlog="$(cat "$ARM_LOG")"
assert_not_contains "arm: an unset marker passes no --marker" "$armlog" "--marker"
assert_not_contains "arm: an unset sentinel passes no --sentinel" "$armlog" "--sentinel"

# Settings may name several autonomy installs. The arm id must reach ONLY the
# entries that asked. The gate does not read this channel as a trusted verdict
# either way, so an arm id on `autonomy@a` is not overriding its `false`; what
# it does do is mark an install the lane never asked to arm, so the settings
# handed to `claude` misdescribe the request. Options likewise come only from
# the requesting entry — the non-requesting sibling's marker must not leak into
# the arm call, which is the one place the any-quantifier could change behavior.
#
# The non-requesting entry is deliberately LAST: option extraction takes the
# last match, so a fixture that puts it first would read the requesting entry's
# marker whether or not the filter scopes to requesting entries, and would pin
# nothing.
cat >"$TMP/gate-multi.json" <<'JSON'
{ "prompt_dir": ".work/lanes",
  "lanes": [ { "name": "work", "prompt": "work.md", "effort": "high",
    "settings": { "pluginConfigs": {
      "autonomy@a": { "options": {
        "lane_stop_gate_enabled": true,
        "lane_stop_gate_marker": "REQUESTING-MARKER" } },
      "autonomy@b": { "options": {
        "lane_stop_gate_enabled": false,
        "lane_stop_gate_marker": "DISABLED-SIBLING-MARKER" } } } } } ] }
JSON
: >"$CLAUDE_LOG"
: >"$ARM_LOG"
out="$(run_launcher start --repo "$REPO" --config "$TMP/gate-multi.json" --agents-json "$AGENTS_EMPTY" --no-pull --no-update 2>&1)"
log="$(cat "$CLAUDE_LOG")"
armlog="$(cat "$ARM_LOG")"
assert_contains "arm: options come from the requesting entry" "$armlog" "--marker REQUESTING-MARKER"
assert_not_contains "arm: a disabled sibling's marker never reaches the helper" "$armlog" "DISABLED-SIBLING-MARKER"
# The launched --settings must carry the arm id under autonomy@a only. Isolate
# each entry's object from the echoed command rather than matching the whole
# line, which contains both.
entry_a="$(printf '%s\n' "$log" | grep -o '"autonomy@a":{[^}]*}[^}]*}' | head -n 1)"
entry_b="$(printf '%s\n' "$log" | grep -o '"autonomy@b":{[^}]*}[^}]*}' | head -n 1)"
assert_contains "arm: the requesting entry receives the arm id" "$entry_a" "lane_stop_gate_arm_id"
assert_not_contains "arm: the explicitly-disabled entry receives no arm id" "$entry_b" "lane_stop_gate_arm_id"

# Arming failure → that lane is skipped with an error (fail closed), the other
# lanes still launch, and the sweep exits non-zero.
: >"$CLAUDE_LOG"
out="$(STUB_ARM_RC=1 run_launcher start --repo "$REPO" --config "$CONFIG" --agents-json "$AGENTS_EMPTY" 2>&1)"
rc=$?
log="$(cat "$CLAUDE_LOG")"
assert_eq "arm: arming failure surfaces a non-zero exit" 1 "$rc"
assert_contains "arm: arming failure names the lane and skips it" "$out" "lane-stop gate arming failed"
assert_not_contains "arm: a lane that could not be armed is NOT launched" "$log" "--bg -n babysit"
assert_contains "arm: other lanes still launch past an arm failure" "$log" "--bg -n work"

# No helper found (no override, unanchored checkout) → same fail-closed skip
# with an actionable message. Invoked directly, without run_launcher's
# --gate-arm-script.
: >"$CLAUDE_LOG"
out="$(bash "$SCRIPT" start --repo "$REPO" --config "$CONFIG" --agents-json "$AGENTS_EMPTY" 2>&1)"
rc=$?
log="$(cat "$CLAUDE_LOG")"
assert_eq "arm: missing helper surfaces a non-zero exit" 1 "$rc"
assert_contains "arm: missing helper message is actionable" "$out" "no autonomy gate-arm helper was found"
assert_not_contains "arm: no launch without a helper for a gate-requesting lane" "$log" "--bg -n babysit"

# --dry-run mutates nothing: the arming is previewed, the helper is not run.
: >"$ARM_LOG"
out="$(run_launcher start --repo "$REPO" --config "$CONFIG" --agents-json "$AGENTS_EMPTY" --dry-run 2>&1)"
assert_contains "arm: dry-run previews the arming" "$out" "DRY-RUN: arm lane-stop gate for babysit"
if [[ -s "$ARM_LOG" ]]; then armran=1; else armran=0; fi
assert_eq "arm: dry-run does not run the helper" 0 "$armran"

# A missing helper is caught in validate_launch_inputs, so restart preflights it
# BEFORE stopping a healthy running lane (same doctrine as the prompt/effort
# checks). `work` is running; a gate-requesting config with no helper must not
# take the session down. No --gate-arm-script → no helper discoverable.
cat >"$TMP/gate-work.json" <<'JSON'
{ "prompt_dir": ".work/lanes",
  "lanes": [ { "name": "work", "prompt": "work.md", "effort": "high",
    "settings": { "pluginConfigs": { "autonomy@test-marketplace": { "options": {
      "lane_stop_gate_enabled": true } } } } } ] }
JSON
: >"$CLAUDE_LOG"
out="$(bash "$SCRIPT" restart work --repo "$REPO" --config "$TMP/gate-work.json" --agents-json "$AGENTS_RUNNING" 2>&1)"
rc=$?
log="$(cat "$CLAUDE_LOG")"
assert_eq "arm: restart with an unarmable gate lane exits non-zero" 1 "$rc"
assert_contains "arm: restart preflights the missing helper" "$out" "no autonomy gate-arm helper was found"
assert_not_contains "arm: restart does not stop the healthy lane over a missing helper" "$log" "stop sid-work-1"

# EVERY discovered helper must arm. Each autonomy install writes into its own
# install-derived store and the launcher cannot tell which one the session will
# load, so accepting a partial arm would launch a lane carrying an id its own
# gate resolves to nothing — ungated, with only a stale-arm notice. Exercised
# through REAL discovery (no --gate-arm-script): the launcher is staged inside a
# synthetic plugins/cache tree carrying two marketplaces' autonomy installs.
STAGE="$TMP/stage"
LAUNCHER_STAGED="$STAGE/plugins/cache/mkt-a/harness-ops/1.0.0/skills/lanes/scripts/lane-launcher.sh"
mkdir -p "$(dirname "$LAUNCHER_STAGED")"
cp "$SCRIPT" "$LAUNCHER_STAGED"
MULTI_ARM_LOG="$TMP/arm-multi.log"
for mkt in mkt-a mkt-b; do
  helper="$STAGE/plugins/cache/$mkt/autonomy/1.0.0/hooks/lane-stop-gate-arm.sh"
  mkdir -p "$(dirname "$helper")"
  # mkt-b's helper fails; mkt-a's succeeds. Under the old any-success rule the
  # lane would launch.
  cat >"$helper" <<STUB
#!/usr/bin/env bash
printf '%s\n' "$mkt" >>"$MULTI_ARM_LOG"
[[ "$mkt" == mkt-b ]] && exit 4
exit 0
STUB
  chmod +x "$helper"
done
: >"$MULTI_ARM_LOG"
: >"$CLAUDE_LOG"
out="$(bash "$LAUNCHER_STAGED" start --repo "$REPO" --config "$TMP/gate-work.json" --agents-json "$AGENTS_EMPTY" --no-pull --no-update 2>&1)"
rc=$?
log="$(cat "$CLAUDE_LOG")"
armed_count="$(grep -c . "$MULTI_ARM_LOG" 2>/dev/null || true)"
assert_eq "arm: discovery finds every installed marketplace's helper" 2 "$armed_count"
assert_eq "arm: one helper failing fails the whole arming" 1 "$rc"
assert_contains "arm: a partial arm names the lane and skips it" "$out" "lane-stop gate arming failed"
assert_not_contains "arm: a partially-armed lane is NOT launched" "$log" "--bg -n work"

# --- Default config home + pre-move compatibility -----------------------------
# Every case above passes --config explicitly, so nothing there exercises the
# DEFAULT resolution — which is exactly what moved. These drive it with no
# --config at all.
#
# The `lanes/` concern home: config and prompts both inside it, and no
# `prompt_dir` in the config, so the default has to be the one doing the work.
HOME_REPO="$TMP/home-repo"
mkdir -p "$HOME_REPO/.work/lanes"
cat >"$HOME_REPO/.work/lanes/lanes.json" <<'JSON'
{ "lanes": [ { "name": "work", "prompt": "work.md", "model": "opus", "effort": "high" } ] }
JSON
printf 'You are the work lane.\n' >"$HOME_REPO/.work/lanes/work.md"
: >"$CLAUDE_LOG"
out="$(run_launcher start --repo "$HOME_REPO" --agents-json "$AGENTS_EMPTY" --data-dir "$TMP/data-home" --dry-run 2>&1)"
assert_contains "default config resolves to .work/lanes/lanes.json" "$out" "DRY-RUN: claude --bg -n work"
assert_contains "default prompt_dir resolves to .work/lanes" "$out" "$HOME_REPO/.work/lanes/work.md"
assert_not_contains "the lanes/ home emits no deprecation warning" "$out" "pre-move lane config"

# A checkout that predates the move: config and prompts still at the memory
# root, and the config never named a prompt_dir. Both must keep resolving, with
# the migration said out loud.
OLD_REPO="$TMP/old-repo"
mkdir -p "$OLD_REPO/.work"
cat >"$OLD_REPO/.work/lanes.json" <<'JSON'
{ "lanes": [ { "name": "work", "prompt": "work.md", "model": "opus", "effort": "high" } ] }
JSON
printf 'You are the work lane.\n' >"$OLD_REPO/.work/work.md"
out="$(run_launcher start --repo "$OLD_REPO" --agents-json "$AGENTS_EMPTY" --data-dir "$TMP/data-old" --dry-run 2>&1)"
assert_contains "pre-move config is read rather than failing the run" "$out" "DRY-RUN: claude --bg -n work"
assert_contains "pre-move config warns about the move" "$out" "reading the pre-move lane config"
assert_contains "the warning names the destination" "$out" "$OLD_REPO/.work/lanes/"
assert_contains "a pre-move config keeps the pre-move prompt_dir default" "$out" "$OLD_REPO/.work/work.md"

# Both present: the `lanes/` home wins outright and nothing warns.
BOTH_REPO="$TMP/both-repo"
mkdir -p "$BOTH_REPO/.work/lanes"
cat >"$BOTH_REPO/.work/lanes.json" <<'JSON'
{ "lanes": [ { "name": "stale", "prompt": "stale.md" } ] }
JSON
cat >"$BOTH_REPO/.work/lanes/lanes.json" <<'JSON'
{ "lanes": [ { "name": "work", "prompt": "work.md", "effort": "high" } ] }
JSON
printf 'You are the work lane.\n' >"$BOTH_REPO/.work/lanes/work.md"
printf 'stale\n' >"$BOTH_REPO/.work/stale.md"
out="$(run_launcher start --repo "$BOTH_REPO" --agents-json "$AGENTS_EMPTY" --data-dir "$TMP/data-both" --dry-run 2>&1)"
assert_contains "with both present the lanes/ home wins" "$out" "DRY-RUN: claude --bg -n work"
assert_not_contains "the leftover pre-move config is not read" "$out" "-n stale"
assert_not_contains "no warning when the lanes/ home exists" "$out" "pre-move lane config"

# $HARNESS_OPS_LANES_CONFIG stays the escape hatch: used verbatim, never
# suffixed and never fallen back from, so a config kept outside the memory root
# fails loudly rather than silently resolving to a pre-move file.
out="$(HARNESS_OPS_LANES_CONFIG="$TMP/nowhere.json" run_launcher status --repo "$OLD_REPO" --agents-json "$AGENTS_EMPTY" 2>&1)"
rc=$?
assert_eq "the env override is not fallen back from" 4 "$rc"
assert_contains "the env override is used verbatim" "$out" "lane config not found: $TMP/nowhere.json"

# An explicit --config at the pre-move path is honored verbatim (no warning),
# and still gets the pre-move prompt_dir default — the default is keyed on
# WHERE the config resolved, not on how.
out="$(run_launcher start --repo "$OLD_REPO" --config "$OLD_REPO/.work/lanes.json" --agents-json "$AGENTS_EMPTY" --data-dir "$TMP/data-explicit" --dry-run 2>&1)"
assert_not_contains "an explicit pre-move --config does not warn" "$out" "reading the pre-move lane config"
assert_contains "an explicit pre-move --config keeps the pre-move prompt_dir" "$out" "$OLD_REPO/.work/work.md"

# ============================================================================
# Execution target: host per lane from docs/conventions/execution-target.yaml
# ============================================================================
# These cases need real git (a bare origin and a clone), so they run with the
# logging `claude` stub and a `gh` stub but WITHOUT the git stub. The fixture
# path holds a literal `$(...)`, and every case runs under BASH_COMPAT=51, where
# bash expands some array subscripts twice: a launcher that evaluated a path,
# a value from the file or a telemetry body would create the PWNED file.
unset GIT_DIR GIT_WORK_TREE GIT_CONFIG
ET_BIN="$TMP/et-bin"
mkdir -p "$ET_BIN"
ln -s "$STUB_BIN/claude" "$ET_BIN/claude"
GH_LOG="$TMP/gh.log"
cat >"$ET_BIN/gh" <<STUB
#!/usr/bin/env bash
printf 'gh %s\n' "\$*" >>"$GH_LOG"
jqf="" prev=""
for a in "\$@"; do [[ "\$prev" == "--jq" || "\$prev" == "-q" ]] && jqf="\$a"; prev="\$a"; done
case "\$*" in
"repo view"*) printf '%s\n' "\${STUB_GH_SLUG:-acme/widgets}" ;;
"api user --jq"*) printf '%s\n' "\${STUB_GH_LOGIN:-operator}" ;;
*"user/installations/"*"/repositories"*)
  data="\${STUB_GH_REPOS:-}"
  [[ -n "\$data" ]] || data='{"repositories":[]}'
  jq -r "\$jqf" <<<"\$data"
  ;;
*"user/installations"*)
  [[ "\${STUB_GH_INSTALL_RC:-0}" != 0 ]] && exit "\$STUB_GH_INSTALL_RC"
  data="\${STUB_GH_INSTALLATIONS:-}"
  [[ -n "\$data" ]] || data='{"installations":[{"id":7,"app_slug":"claude","repository_selection":"all","account":{"login":"Acme"}}]}'
  jq -r "\$jqf" <<<"\$data"
  ;;
*) exit 1 ;;
esac
STUB
chmod +x "$ET_BIN/gh"
ET_PATH="$ET_BIN:$SUITE_BASE_PATH"
# The rest of the suite builds and reads real repositories.
PATH="$ET_PATH"
ET_SANDBOX="$TMP/et \$(touch PWNED) sandbox"
mkdir -p "$ET_SANDBOX"
ET_ORIGIN="$ET_SANDBOX/origin.git"
ET_REPO="$ET_SANDBOX/repo"
fx_git() { git -c user.name=fixture -c user.email=fixture@example.invalid -c commit.gpgsign=false "$@"; }
git init -q --bare -b main "$ET_ORIGIN"
git clone -q "$ET_ORIGIN" "$ET_REPO" 2>/dev/null
# origin is the local bare repository by path. For the cloud-launch cases it is
# configured as github.com/acme/widgets (the slug the launcher derives), with
# git reaching the bare repository through insteadOf; the shipped launcher
# refuses that rewrite, so only the trusted-stage copy below runs under it.
et_origin_github() {
  git -C "$ET_REPO" remote set-url origin https://github.com/acme/widgets.git
  git -C "$ET_REPO" config "url.$ET_ORIGIN.insteadOf" https://github.com/acme/widgets.git
}
et_origin_local() {
  git -C "$ET_REPO" config --unset-all "url.$ET_ORIGIN.insteadOf" 2>/dev/null
  git -C "$ET_REPO" remote set-url origin "$ET_ORIGIN"
}
mkdir -p "$ET_REPO/docs/conventions" "$ET_REPO/.work/lanes"
printf '.work/\n' >"$ET_REPO/.gitignore"
printf 'You are the work lane.\n' >"$ET_REPO/.work/lanes/work.md"
ET_TELEMETRY_NONE="$TMP/et-telemetry-none.json"
printf '{}\n' >"$ET_TELEMETRY_NONE"

# Every local-lane stage may read untrusted input, so the shipped launcher never
# reaches its cloud launch. The cloud-launch cases run a copy with two changes:
# its trusted-stage list names one fixture stage, and its origin-rewrite check
# is off so the fixture's insteadOf can stand in for github.com. Everything
# else in the copy is the shipped code.
TRUSTED_DIR="$TMP/trusted-launcher"
mkdir -p "$TRUSTED_DIR"
cp -R "$SCRIPT_DIR/lib" "$TRUSTED_DIR/lib"
sed -e 's/^ET_TRUSTED_STAGES=""$/ET_TRUSTED_STAGES="fixture:trusted"/' \
  -e 's/^origin_url_rewritten() {$/origin_url_rewritten() { return 1; }\
origin_url_rewritten_shipped() {/' \
  "$SCRIPT" >"$TRUSTED_DIR/lane-launcher.sh"
assert_contains "the trusted-stage copy names the fixture stage" "$(cat "$TRUSTED_DIR/lane-launcher.sh")" 'ET_TRUSTED_STAGES="fixture:trusted"'
assert_contains "the trusted-stage copy turns off the origin-rewrite check" "$(cat "$TRUSTED_DIR/lane-launcher.sh")" 'origin_url_rewritten() { return 1; }'
TRUSTED_SCRIPT="$TRUSTED_DIR/lane-launcher.sh"

# Commit <yaml> (or delete the file when <yaml> is empty) on origin's main.
et_publish() {
  if [[ -n "$1" ]]; then
    printf '%s\n' "$1" >"$ET_REPO/docs/conventions/execution-target.yaml"
  else
    rm -f "$ET_REPO/docs/conventions/execution-target.yaml"
  fi
  fx_git -C "$ET_REPO" add -A
  fx_git -C "$ET_REPO" commit -q --allow-empty -m fixture
  fx_git -C "$ET_REPO" push -q origin HEAD:main 2>/dev/null
  git -C "$ET_REPO" remote set-head origin main >/dev/null 2>&1
  ET_SHA_NOW="$(git -C "$ET_REPO" rev-parse HEAD)"
}
et_lanes() { # <stage or ""> [extra lane JSON members]
  jq -n --arg s "$1" --argjson x "${2:-{\}}" \
    '{lanes: [({name: "work", prompt: "work.md", effort: "high"} + (if $s == "" then {} else {stage: $s} end) + $x)]}' \
    >"$ET_REPO/.work/lanes/lanes.json"
}
ET_TELEMETRY_BINDING='{"telemetry":{"issue":5}}'
et_cloud_lane() { et_lanes fixture:trusted "$ET_TELEMETRY_BINDING"; }
et_run_with() { # <script> <action> [args...]
  PATH="$ET_PATH" BASH_COMPAT=51 bash "$1" --gate-arm-script "$ARM_STUB" "$2" --repo "$ET_REPO" \
    --agents-json "$AGENTS_EMPTY" --no-pull --no-update --telemetry-json "$ET_TELEMETRY_NONE" "${@:3}"
}
et_run() { et_run_with "$SCRIPT" "$@"; }
et_run_trusted() {
  local rc
  et_origin_github
  et_run_with "$TRUSTED_SCRIPT" "$@"
  rc=$?
  et_origin_local
  return "$rc"
}
et_origin_local
ET_DATA="$TMP/et-data"
ET_KEY="$(printf '%s' "$(git -C "$ET_REPO" rev-parse --show-toplevel)" | git -C "$ET_REPO" hash-object --stdin)"
ET_WT="$ET_DATA/lanes/$ET_KEY/worktrees/work"

# --- Policy read and key resolution ------------------------------------------
# The skill key, read as the dotted key skill.fixture.trusted, sends the lane
# to a cloud session: fetched first, SHA printed, launched from a linked
# worktree at that SHA with the probe preamble.
et_publish $'default: local-worktree\nskill:\n  fixture:\n    trusted: cloud-session'
et_cloud_lane
out="$(et_run_trusted start --data-dir "$ET_DATA" --dry-run 2>&1)"
rc=$?
assert_eq "cloud-session dry-run exits 0" 0 "$rc"
assert_contains "the default branch is fetched first" "$out" "DRY-RUN: git -C $(printf '%q' "$ET_REPO") fetch --quiet origin +refs/heads/main:refs/remotes/origin/main"
assert_contains "the commit the file was read at is printed" "$out" "read docs/conventions/execution-target.yaml at origin/main $ET_SHA_NOW"
assert_contains "skill.fixture.trusted supplies the value" "$out" "execution target cloud-session (skill.fixture.trusted)"
assert_contains "the cloud launch runs from a linked worktree at the fetched SHA" "$out" "worktree add --quiet --detach $(printf '%q' "$ET_WT") $ET_SHA_NOW"
assert_contains "a cloud-session lane prints a claude --cloud line" "$out" "DRY-RUN: claude --cloud"
assert_contains "the cloud prompt opens with the stage-start probe" "$out" 'stage-start\ probe\ preamble'
assert_not_contains "a cloud-session lane does not also launch locally" "$out" "claude --bg"

# The two-level skill map is read as skill.<plugin>.<skill>.
et_publish $'default: local-worktree\nskill:\n  work-items:\n    work-loop: local-background'
et_lanes work-items:work-loop
out="$(et_run start --data-dir "$ET_DATA" --dry-run 2>&1)"
assert_contains "skill.work-items.work-loop supplies the value" "$out" "execution target local-background (skill.work-items.work-loop)"

# local-background: claude --bg with auto mode from the lane's linked worktree.
et_publish 'default: local-background'
out="$(et_run start --data-dir "$ET_DATA" --dry-run 2>&1)"
assert_contains "default supplies local-background" "$out" "execution target local-background (default)"
assert_contains "local-background launches from the linked worktree" "$out" "DRY-RUN: cd $(printf '%q' "$ET_WT")"
assert_contains "local-background is claude --bg -n <name> --permission-mode auto" "$out" "DRY-RUN: claude --bg -n work --permission-mode auto"

# cloud-routine and cloud-project print setup steps and launch nothing, for a
# stage whose input is never untrusted (the trusted-stage copy).
et_cloud_lane
for v in cloud-routine cloud-project; do
  et_publish "default: $v"
  out="$(et_run_trusted start --data-dir "$ET_DATA" --dry-run 2>&1)"
  rc=$?
  assert_eq "$v exits 0" 0 "$rc"
  assert_contains "$v prints setup steps" "$out" "$v is set by default"
  assert_not_contains "$v launches no local session" "$out" "claude --bg"
  assert_not_contains "$v launches no cloud session" "$out" "claude --cloud"
done
# restart leaves a running lane up when its host is one the launcher does not start.
cat >"$TMP/et-agents-running.json" <<'JSON'
[ { "pid": 1, "cwd": "/r", "kind": "background", "startedAt": 1, "sessionId": "sid-et", "name": "work", "status": "idle" } ]
JSON
out="$(et_run_trusted restart --agents-json "$TMP/et-agents-running.json" --data-dir "$ET_DATA" --dry-run 2>&1)"
assert_contains "restart to cloud-project prints its setup steps" "$out" "cloud-project is set by default"
assert_not_contains "restart to cloud-project does not stop the running lane" "$out" "claude stop"

# --- [N1] routines and projects are cloud hosts: untrusted stages get none ----
et_publish $'default: cloud-project\nclass:\n  untrusted-provenance: cloud-routine'
for lane in work-items:triage ""; do
  et_lanes "$lane"
  out="$(et_run start --data-dir "$ET_DATA" --dry-run 2>&1)"
  rc=$?
  label="${lane:-a lane with no stage}"
  assert_eq "[N1] $label placed on a routine or project exits 1" 1 "$rc"
  assert_not_contains "[N1] $label gets no setup steps" "$out" "the launcher starts nothing for it"
  assert_contains "[N1] $label is skipped with the attend-queue message" "$out" "Nothing was filed; escalate it through /work-items:attend-queue"
done
et_lanes work-items:triage
out="$(et_run start --data-dir "$ET_DATA" --dry-run 2>&1)"
assert_contains "[N1] the triage lane resolved a routine first" "$out" "cloud-routine refused"
et_lanes ""
out="$(et_run start --data-dir "$ET_DATA" --dry-run 2>&1)"
assert_contains "[N1] a lane with no stage resolved a project first" "$out" "cloud-project refused"
out="$(et_run restart --agents-json "$TMP/et-agents-running.json" --data-dir "$ET_DATA" --dry-run 2>&1)"
assert_not_contains "[N1] restart of a skipped lane does not stop the running session" "$out" "claude stop"
# A cloud-session placement is refused before restart stops the running lane.
et_publish 'default: cloud-session'
et_lanes work-items:triage
out="$(et_run restart --agents-json "$TMP/et-agents-running.json" --data-dir "$ET_DATA" --dry-run 2>&1)"
assert_contains "[P4] restart of an untrusted cloud-session lane is skipped" "$out" "cloud-session refused"
assert_not_contains "[P4] restart of an untrusted cloud-session lane does not stop the running session" "$out" "claude stop"
et_lanes work-items:work-loop

# No file on the default branch, or an unknown value, keeps today's launch.
et_publish ""
out="$(et_run start --data-dir "$ET_DATA" --dry-run 2>&1)"
assert_contains "an absent file is reported with the SHA read" "$out" "docs/conventions/execution-target.yaml absent at origin/main $ET_SHA_NOW"
assert_contains "an absent file keeps today's launch" "$out" "DRY-RUN: claude --bg -n work --permission-mode auto"
# shellcheck disable=SC2016 # the literal $(...) is the fixture.
et_publish 'default: "$(touch PWNED_VALUE)"'
out="$(et_run start --data-dir "$ET_DATA" --dry-run 2>&1)"
assert_contains "an unknown value names the file and the SHA it was read at" "$out" "at default in docs/conventions/execution-target.yaml at origin/main $ET_SHA_NOW; local-worktree"
assert_contains "an unknown value keeps today's launch" "$out" "DRY-RUN: claude --bg -n work --permission-mode auto"
et_publish $'default: [unclosed'
out="$(et_run start --data-dir "$ET_DATA" --dry-run 2>&1)"
assert_contains "a file the parser rejects is reported" "$out" "does not parse"
assert_contains "a file the parser rejects keeps today's launch" "$out" "DRY-RUN: claude --bg -n work --permission-mode auto"

# Only the default branch counts: an uncommitted working-tree edit moves nothing.
et_publish 'default: local-worktree'
printf 'default: cloud-session\n' >"$ET_REPO/docs/conventions/execution-target.yaml"
out="$(et_run start --data-dir "$ET_DATA" --dry-run 2>&1)"
assert_contains "a working-tree edit is not read" "$out" "execution target local-worktree (default)"
git -C "$ET_REPO" checkout -q -- docs/conventions/execution-target.yaml

# class.untrusted-provenance applies to a stage whose input is always untrusted.
et_publish $'default: local-worktree\nclass:\n  untrusted-provenance: cloud-session'
et_lanes work-items:triage
out="$(et_run start --data-dir "$ET_DATA" --dry-run 2>&1)"
rc=$?
assert_contains "class.untrusted-provenance supplies the triage stage's host" "$out" "execution target cloud-session (class.untrusted-provenance)"
assert_eq "a triage lane placed in the cloud exits 1" 1 "$rc"
assert_contains "the skip names the escalation route and files nothing" "$out" "Nothing was filed; escalate it through /work-items:attend-queue"
assert_not_contains "a triage lane placed in the cloud does not launch locally" "$out" "claude --bg"
assert_not_contains "the skip message carries no em dash" "$out" $'\xe2\x80\x94'
# The skill key wins over the class key and the default.
et_publish $'default: local-background\nclass:\n  untrusted-provenance: cloud-routine\nskill:\n  work-items:\n    triage: local-worktree'
out="$(et_run start --data-dir "$ET_DATA" --dry-run 2>&1)"
assert_contains "the skill key wins over the class key" "$out" "execution target local-worktree (skill.work-items.triage)"
et_lanes work-items:work-loop
out="$(et_run start --data-dir "$ET_DATA" --dry-run 2>&1)"
assert_contains "the class key does not apply to a stage with trusted input" "$out" "execution target local-background (default)"

# --- [fix 1] the launcher enforces the untrusted-input guard -------------------
# work-loop, work, babysit-loop and babysit-prs read untrusted input on some
# runs; with no deterministic connector and egress check, none goes to the cloud.
et_publish 'default: cloud-session'
for st in work-items:work-loop work-items:work source-control:babysit-loop source-control:babysit-prs; do
  et_lanes "$st" "$ET_TELEMETRY_BINDING"
  out="$(et_run start --data-dir "$ET_DATA" --dry-run 2>&1)"
  rc=$?
  assert_eq "[fix 1] $st placed in the cloud exits 1" 1 "$rc"
  assert_contains "[fix 1] $st is skipped as a stage that may read untrusted input" "$out" "stage $st may read untrusted input"
  assert_not_contains "[fix 1] $st gets no claude --cloud line" "$out" "claude --cloud"
  assert_not_contains "[fix 1] $st does not fall back to a local launch" "$out" "claude --bg"
done

# --- [fix 2] a lane with no stage is untrusted; telemetry.repo is pinned ------
et_lanes "" "$ET_TELEMETRY_BINDING"
out="$(et_run start --data-dir "$ET_DATA" --dry-run 2>&1)"
rc=$?
assert_eq "[fix 2] a lane with no stage placed in the cloud exits 1" 1 "$rc"
assert_contains "[fix 2] a lane with no stage is skipped" "$out" "stage unset may read untrusted input"
assert_not_contains "[fix 2] a lane with no stage gets no claude --cloud line" "$out" "claude --cloud"
et_lanes fixture:trusted '{"telemetry":{"issue":5,"repo":"evil/elsewhere"}}'
out="$(et_run_trusted start --data-dir "$ET_DATA" --dry-run 2>&1)"
assert_contains "[fix 2] a telemetry.repo naming another repository is refused" "$out" "telemetry.repo names a repository other than origin"
assert_not_contains "[fix 2] the foreign telemetry.repo lane gets no claude --cloud line" "$out" "claude --cloud"

# --- [fix 3] fallback comments count only from authorized authors --------------
ET_TELEMETRY_FB="$TMP/et-telemetry-fallback.json"
ET_TELEMETRY_SPOOF="$TMP/et-telemetry-spoof.json"
# shellcheck disable=SC2016 # the literal $(...) is the fixture.
fb_body='<!-- harness-ops:lane-telemetry marker=fixture:trusted -->
```json
{"restart_request": null, "execution_target_fallback": {"reason": "$(touch PWNED_BODY)", "at": "2026-10-04T00:00:00Z"}}
```
'
jq -n --arg b "$fb_body" '{work: [{body: $b, user: {login: "operator"}}]}' >"$ET_TELEMETRY_FB"
jq -n --arg b "$fb_body" '{work: [{body: $b, user: {login: "intruder"}}]}' >"$ET_TELEMETRY_SPOOF"
et_cloud_lane
out="$(et_run_trusted start --data-dir "$ET_DATA" --dry-run --telemetry-json "$ET_TELEMETRY_SPOOF" 2>&1)"
assert_not_contains "[fix 3] a fallback from another author changes nothing" "$out" "telemetry carries an execution-target fallback"
assert_contains "[fix 3] the lane still goes to the cloud" "$out" "DRY-RUN: claude --cloud"
et_lanes fixture:trusted
out="$(et_run_trusted start --data-dir "$ET_DATA" --dry-run 2>&1)"
assert_contains "[fix 3] a cloud lane without telemetry.issue is refused" "$out" "the lane has no numeric telemetry.issue"
assert_not_contains "[fix 3] the lane without telemetry.issue gets no claude --cloud line" "$out" "claude --cloud"
et_cloud_lane

# --- [fix 4] the policy branch is origin's HEAD, not the local symref ---------
et_publish 'default: local-worktree'
# A branch `evil` on origin carrying a cloud policy; origin's HEAD stays main.
fx_git -C "$ET_REPO" checkout -q -b evil
printf 'default: cloud-session\n' >"$ET_REPO/docs/conventions/execution-target.yaml"
fx_git -C "$ET_REPO" commit -q -am evil
fx_git -C "$ET_REPO" push -q origin HEAD:evil 2>/dev/null
fx_git -C "$ET_REPO" checkout -q main
fx_git -C "$ET_REPO" branch -q -D evil
git -C "$ET_REPO" fetch -q origin
git -C "$ET_REPO" remote set-head origin evil >/dev/null 2>&1
et_lanes work-items:triage
out="$(et_run start --data-dir "$ET_DATA" --dry-run 2>&1)"
rc=$?
assert_contains "[fix 4] a local origin/HEAD that disagrees with origin's HEAD refuses the policy read" "$out" "disagrees with the local origin/HEAD"
assert_not_contains "[fix 4] the policy on the other branch is not read" "$out" "read docs/conventions/execution-target.yaml at origin/evil"
assert_eq "[fix 4] a triage lane is skipped when the policy read is refused" 1 "$rc"
assert_not_contains "[fix 4] the skipped triage lane launches nothing" "$out" "claude --"
et_lanes work-items:work-loop
out="$(et_run start --data-dir "$ET_DATA" --dry-run 2>&1)"
assert_contains "[fix 4] other lanes launch local-worktree when the policy read is refused" "$out" "DRY-RUN: claude --bg -n work --permission-mode auto"
git -C "$ET_REPO" remote set-head origin main >/dev/null 2>&1

# --- [fix 5] the App check uses origin's slug, not gh's default repository ----
et_publish 'default: cloud-session'
et_cloud_lane
out="$(STUB_GH_SLUG=upstream/widgets \
  STUB_GH_INSTALLATIONS='{"installations":[{"id":9,"app_slug":"claude","repository_selection":"selected","account":{"login":"upstream"}}]}' \
  STUB_GH_REPOS='{"repositories":[{"full_name":"upstream/widgets"}]}' et_run_trusted start --data-dir "$ET_DATA" --dry-run 2>&1)"
assert_contains "[fix 5] an App covering gh's default repository does not cover origin" "$out" "cloud-session refused (no Claude GitHub App"
assert_not_contains "[fix 5] that lane gets no claude --cloud line" "$out" "claude --cloud"

# --- [N2] a rewritten or ambiguous origin URL refuses the policy read --------
et_publish 'default: local-background'
et_lanes work-items:work-loop
et_origin_github
out="$(et_run start --data-dir "$ET_DATA" --dry-run 2>&1)"
assert_contains "[N2] an insteadOf rule rewriting origin refuses the policy read" "$out" "origin's URL is rewritten by a url.*.insteadOf rule"
assert_not_contains "[N2] the rewritten origin's policy is not read" "$out" "read docs/conventions/execution-target.yaml"
assert_contains "[N2] the lane launches local-worktree" "$out" "DRY-RUN: claude --bg -n work --permission-mode auto"
et_origin_local
git -C "$ET_REPO" config --add remote.origin.url https://github.com/acme/elsewhere.git
out="$(et_run start --data-dir "$ET_DATA" --dry-run 2>&1)"
assert_contains "[N2] two remote.origin.url values refuse the policy read" "$out" "remote.origin.url has more than one value"
git -C "$ET_REPO" config --unset-all remote.origin.url
git -C "$ET_REPO" config remote.origin.url "$ET_ORIGIN"
out="$(et_run start --data-dir "$ET_DATA" --dry-run 2>&1)"
assert_contains "[N2] a plain origin reads the policy again" "$out" "execution target local-background (default)"

# --- [N4] the shared github-actions[bot] is not a telemetry author -----------
et_publish 'default: cloud-session'
et_lanes fixture:trusted '{"telemetry":{"issue":5,"author":"github-actions[bot]"}}'
out="$(et_run_trusted start --data-dir "$ET_DATA" --dry-run 2>&1)"
assert_contains "[N4] github-actions[bot] as telemetry.author is refused" "$out" "telemetry.author github-actions[bot] is a bot account, which is not allowed"
assert_not_contains "[N4] that lane gets no claude --cloud line" "$out" "claude --cloud"
et_lanes fixture:trusted '{"telemetry":{"issue":5,"author":"dependabot[bot]"}}'
out="$(et_run_trusted start --data-dir "$ET_DATA" --dry-run 2>&1)"
assert_contains "[P4] any [bot] login as telemetry.author is refused" "$out" "telemetry.author dependabot[bot] is a bot account, which is not allowed"
assert_not_contains "[P4] that lane gets no claude --cloud line" "$out" "claude --cloud"

# --- [N5] a telemetry fixture read says so -----------------------------------
et_cloud_lane
out="$(et_run_trusted start --data-dir "$ET_DATA" --dry-run 2>&1)"
assert_contains "[N5] --telemetry-json warns that the read is a local file" "$out" "(--telemetry-json, a test aid), not from GitHub"

# --- Cloud launch rule, on the trusted-stage copy -----------------------------
out="$(STUB_GH_INSTALLATIONS='{"installations":[{"id":9,"app_slug":"other-app","repository_selection":"all","account":{"login":"acme"}}]}' \
  et_run_trusted start --data-dir "$ET_DATA" --dry-run 2>&1)"
assert_contains "no Claude GitHub App refuses the cloud launch" "$out" "cloud-session refused (no Claude GitHub App installation"
assert_contains "the refused trusted lane launches local-worktree" "$out" "DRY-RUN: claude --bg -n work --permission-mode auto"
assert_not_contains "the refused lane prints no claude --cloud line" "$out" "claude --cloud"
out="$(STUB_GH_INSTALLATIONS='{"installations":[{"id":9,"app_slug":"claude","repository_selection":"selected","account":{"login":"acme"}}]}' \
  STUB_GH_REPOS='{"repositories":[{"full_name":"acme/other"}]}' et_run_trusted start --data-dir "$ET_DATA" --dry-run 2>&1)"
assert_contains "an installation selecting other repositories does not cover this one" "$out" "cloud-session refused (no Claude GitHub App"
out="$(STUB_GH_INSTALLATIONS='{"installations":[{"id":9,"app_slug":"claude","repository_selection":"selected","account":{"login":"acme"}}]}' \
  STUB_GH_REPOS='{"repositories":[{"full_name":"Acme/Widgets"}]}' et_run_trusted start --data-dir "$ET_DATA" --dry-run 2>&1)"
assert_contains "an installation selecting this repository covers it" "$out" "DRY-RUN: claude --cloud"
out="$(STUB_GH_INSTALL_RC=1 et_run_trusted start --data-dir "$ET_DATA" --dry-run 2>&1)"
assert_contains "a failed installations read refuses the cloud launch" "$out" "cloud-session refused (no Claude GitHub App"

# A lane requesting the lane-stop gate cannot be armed in the cloud.
et_lanes fixture:trusted '{"telemetry":{"issue":5},"settings":{"pluginConfigs":{"autonomy@m":{"options":{"lane_stop_gate_enabled":true}}}}}'
out="$(et_run_trusted start --data-dir "$ET_DATA" --dry-run 2>&1)"
assert_contains "a gate-requesting lane is refused the cloud" "$out" "lane-stop gate, which cannot be armed in a cloud session"
et_cloud_lane

# A cloud launch needs a clean linked worktree.
mkdir -p "$(dirname "$ET_WT")"
git -C "$ET_REPO" worktree add -q --detach "$ET_WT" HEAD
printf 'scratch\n' >"$ET_WT/untracked.txt"
out="$(et_run_trusted start --data-dir "$ET_DATA" --dry-run 2>&1)"
assert_contains "a dirty linked worktree refuses the cloud launch" "$out" "cloud-session refused (no clean linked worktree"
assert_contains "the dirty-worktree refusal launches local-worktree" "$out" "DRY-RUN: claude --bg -n work"
rm -f "$ET_WT/untracked.txt"
out="$(et_run_trusted start --data-dir "$ET_DATA" --dry-run 2>&1)"
assert_contains "a clean existing linked worktree is moved to the fetched SHA" "$out" "checkout --quiet --detach $ET_SHA_NOW"

# A fallback marker from an authorized author moves exactly one launch local.
out="$(et_run_trusted start --data-dir "$ET_DATA" --dry-run --telemetry-json "$ET_TELEMETRY_FB" 2>&1)"
assert_contains "a telemetry fallback marker launches local-worktree" "$out" "telemetry carries an execution-target fallback; this launch runs local-worktree"
assert_contains "the fallback launch is today's local launch" "$out" "DRY-RUN: claude --bg -n work --permission-mode auto"
: >"$CLAUDE_LOG"
out="$(et_run_trusted start --data-dir "$ET_DATA" --telemetry-json "$ET_TELEMETRY_FB" 2>&1)"
assert_contains "a real fallback launch runs claude --bg" "$(cat "$CLAUDE_LOG")" "--bg -n work --permission-mode auto"
out="$(et_run_trusted start --data-dir "$ET_DATA" --dry-run --telemetry-json "$ET_TELEMETRY_FB" 2>&1)"
assert_contains "the next launch after an honored fallback probes the cloud again" "$out" "DRY-RUN: claude --cloud"
out="$(et_run_trusted start --data-dir "$ET_DATA" --dry-run --telemetry-json "$TMP/missing-telemetry.json" 2>&1)"
assert_contains "unreadable telemetry refuses the cloud launch" "$out" "lane telemetry could not be read"

# `claude agents --json` does not list cloud sessions: start does not send a
# second one while the launch record stands; restart does.
mkdir -p "$ET_DATA/lanes/$ET_KEY"
printf '2026-10-04T00:00:00Z at %s\n' "$ET_SHA_NOW" >"$ET_DATA/lanes/$ET_KEY/work-cloud-launch"
out="$(et_run_trusted start --data-dir "$ET_DATA" --dry-run 2>&1)"
assert_contains "start skips a lane already sent to the cloud" "$out" "skip work: already sent to the cloud"
printf '\033]0;x\007\033[31mred\n' >"$ET_DATA/lanes/$ET_KEY/work-cloud-launch"
out="$(et_run_trusted start --data-dir "$ET_DATA" --dry-run 2>&1)"
assert_not_contains "[P5] the launch record prints without control characters" "$out" $'\033'
assert_contains "[P5] the record's printable text still prints" "$out" "already sent to the cloud (]0;x[31mred)"
printf '2026-10-04T00:00:00Z at %s\n' "$ET_SHA_NOW" >"$ET_DATA/lanes/$ET_KEY/work-cloud-launch"
out="$(et_run_trusted restart --data-dir "$ET_DATA" --dry-run 2>&1)"
assert_contains "restart sends a new cloud session" "$out" "DRY-RUN: claude --cloud"
# A real cloud launch: the stub logs one line per argv, so the probe preamble
# and the lane prompt both reach the single prompt argument.
: >"$CLAUDE_LOG"
out="$(et_run_trusted restart --data-dir "$ET_DATA" 2>&1)"
rc=$?
assert_eq "a real cloud launch exits 0" 0 "$rc"
assert_contains "the cloud prompt carries the stage-start probe" "$(cat "$CLAUDE_LOG")" "--cloud Stage-start probe (execution target cloud-session; lane work; stage fixture:trusted"
assert_contains "the cloud prompt names the plugins the stage needs" "$(cat "$CLAUDE_LOG")" "loaded in this session, not only declared: fixture."
assert_contains "the cloud prompt ends with the lane prompt" "$(cat "$CLAUDE_LOG")" "You are the work lane."
assert_contains "the launch record names the SHA" "$(cat "$ET_DATA/lanes/$ET_KEY/work-cloud-launch")" "at $ET_SHA_NOW"

# A stage that is not <plugin>:<skill> is a config error before anything launches.
et_lanes 'Work Items'
out="$(et_run start --data-dir "$ET_DATA" --dry-run 2>&1)"
rc=$?
assert_eq "a malformed stage exits 3" 3 "$rc"
et_lanes work-items:work-loop

# ============================================================================
# run-once: one headless `claude -p` pass of a lane, for a scheduler
# ============================================================================
# Same fixture repository (its path holds a literal `$(...)`), real git, the
# logging claude stub. No policy file, so the lane runs local-worktree.
et_publish ''
RO_LOCK="$ET_DATA/lanes/$ET_KEY/work-run-once.lock"
claude_runs() { grep -c -- '^-p ' "$CLAUDE_LOG"; }

out="$(et_run run-once --data-dir "$ET_DATA" 2>&1)"
rc=$?
assert_eq "run-once with no lane exits 3" 3 "$rc"
assert_contains "run-once with no lane says it takes one" "$out" "run-once takes exactly one lane name"
out="$(et_run run-once work work --data-dir "$ET_DATA" 2>&1)"
assert_eq "run-once with two lanes exits 3" 3 "$?"

: >"$CLAUDE_LOG"
out="$(STUB_CLAUDE_VERSION=2.1.259 et_run run-once work --data-dir "$ET_DATA" 2>&1)"
rc=$?
assert_eq "run-once exits 0" 0 "$rc"
assert_contains "run-once runs one print-mode pass in auto mode with the lane's effort and prompt" "$(cat "$CLAUDE_LOG")" "-p --permission-mode auto --permission-prompts none --effort high You are the work lane."
assert_not_contains "run-once starts no background session" "$(cat "$CLAUDE_LOG")" "--bg"
assert_eq "run-once releases its lock" "absent" "$([[ -e "$RO_LOCK" ]] && echo present || echo absent)"

: >"$CLAUDE_LOG"
out="$(STUB_CLAUDE_VERSION=2.1.258 et_run run-once work --data-dir "$ET_DATA" 2>&1)"
assert_contains "below 2.1.259 run-once still runs in auto mode" "$(cat "$CLAUDE_LOG")" "-p --permission-mode auto --effort high"
assert_not_contains "below 2.1.259 run-once omits --permission-prompts" "$(cat "$CLAUDE_LOG")" "--permission-prompts"

# A model, when set, is passed the same way start passes it.
et_lanes work-items:work-loop '{"model":"opus"}'
: >"$CLAUDE_LOG"
out="$(et_run run-once work --data-dir "$ET_DATA" 2>&1)"
assert_contains "run-once passes the lane's model" "$(cat "$CLAUDE_LOG")" "--model opus --effort high"

# No effort: refused, nothing runs.
jq -n '{lanes: [{name: "work", prompt: "work.md", stage: "work-items:work-loop"}]}' >"$ET_REPO/.work/lanes/lanes.json"
: >"$CLAUDE_LOG"
out="$(et_run run-once work --data-dir "$ET_DATA" 2>&1)"
rc=$?
assert_eq "run-once of a lane with no effort exits 1" 1 "$rc"
assert_contains "the refusal names lanes[].effort" "$out" "add lanes[].effort"
assert_eq "a lane with no effort runs no pass" 0 "$(claude_runs)"
et_lanes work-items:work-loop

# A held lock: a second run exits 0 quietly, runs nothing and leaves the lock.
mkdir -p "$RO_LOCK"
printf '%s\n' "$$" >"$RO_LOCK/pid"
: >"$CLAUDE_LOG"
out="$(et_run run-once work --data-dir "$ET_DATA" 2>&1)"
rc=$?
assert_eq "run-once with the lock held exits 0" 0 "$rc"
assert_contains "run-once with the lock held says so" "$out" "another run-once holds"
assert_eq "run-once with the lock held runs no pass" 0 "$(claude_runs)"
assert_eq "the loser leaves the holder's lock in place" "$$" "$(cat "$RO_LOCK/pid" 2>/dev/null)"

# A lock whose recorded owner has exited is reclaimed.
bash -c 'exit 0' &
dead_pid=$!
wait "$dead_pid"
printf '%s\n' "$dead_pid" >"$RO_LOCK/pid"
: >"$CLAUDE_LOG"
out="$(et_run run-once work --data-dir "$ET_DATA" 2>&1)"
rc=$?
assert_eq "run-once reclaims a lock whose owner exited" 0 "$rc"
assert_eq "the reclaiming run runs its pass" 1 "$(claude_runs)"
assert_eq "the reclaiming run releases the lock" "absent" "$([[ -e "$RO_LOCK" ]] && echo present || echo absent)"

# A lane already running as a background session is not run a second time.
AGENTS_WORK_BG="$TMP/agents-work-bg.json"
printf '%s\n' '[{"pid":1,"cwd":"/r","kind":"background","startedAt":1,"sessionId":"sid-bg","name":"work","status":"idle"}]' >"$AGENTS_WORK_BG"
: >"$CLAUDE_LOG"
out="$(et_run run-once work --data-dir "$ET_DATA" --agents-json "$AGENTS_WORK_BG" 2>&1)"
rc=$?
assert_eq "run-once of a running lane exits 0" 0 "$rc"
assert_contains "run-once of a running lane names the session" "$out" "sid-bg"
assert_eq "run-once of a running lane runs no pass" 0 "$(claude_runs)"

# The execution target decides the host: local-background runs from the lane's
# linked worktree; a cloud host runs nothing here.
et_publish 'default: local-background'
out="$(et_run run-once work --data-dir "$ET_DATA" --dry-run 2>&1)"
assert_contains "run-once reads the execution target" "$out" "execution target local-background (default)"
assert_contains "run-once on local-background runs from the linked worktree" "$out" "DRY-RUN: cd $(printf '%q' "$ET_WT")"
assert_contains "the dry run previews the print-mode pass" "$out" "DRY-RUN: claude -p --permission-mode auto"
et_publish 'default: cloud-routine'
: >"$CLAUDE_LOG"
out="$(et_run run-once work --data-dir "$ET_DATA" 2>&1)"
assert_eq "run-once runs no local pass for a cloud host" 0 "$(claude_runs)"
et_publish ''

# ============================================================================
# print-schedule: OS scheduler entries that call a generated per-lane script
# ============================================================================
et_lanes work-items:work-loop '{"schedule":{"every_minutes":15}}'
SCHED_SCRIPT="$ET_REPO/.work/lanes/scheduled/work.sh"
: >"$CLAUDE_LOG"
out="$(et_run print-schedule --data-dir "$ET_DATA" 2>&1)"
rc=$?
assert_eq "print-schedule exits 0" 0 "$rc"
assert_contains "print-schedule emits a schtasks entry on the lane's interval" "$out" 'schtasks /Create /TN "HarnessOps Lane work" /SC MINUTE /MO 15 '
assert_contains "print-schedule emits the cron form" "$out" "*/15 * * * * "
assert_contains "print-schedule emits the removal" "$out" 'schtasks /Delete /TN "HarnessOps Lane work" /F'
assert_eq "print-schedule without --write-script writes no script" "absent" "$([[ -e "$SCHED_SCRIPT" ]] && echo present || echo absent)"
assert_eq "print-schedule calls no claude" "" "$(cat "$CLAUDE_LOG")"

out="$(et_run print-schedule --write-script --data-dir "$ET_DATA" 2>&1)"
rc=$?
assert_eq "print-schedule --write-script exits 0" 0 "$rc"
assert_eq "the generated script is executable" "yes" "$([[ -x "$SCHED_SCRIPT" ]] && echo yes || echo no)"
bash -n "$SCHED_SCRIPT" 2>/dev/null
assert_eq "the generated script parses" 0 "$?"
assert_contains "the generated script calls run-once for the lane" "$(cat "$SCHED_SCRIPT")" "run-once work"
# Running it does one pass, and the `$(...)` in the repository path stays text.
: >"$CLAUDE_LOG"
PATH="$ET_PATH" BASH_COMPAT=51 bash "$SCHED_SCRIPT" >/dev/null 2>&1
rc=$?
assert_eq "the generated script exits 0" 0 "$rc"
assert_eq "the generated script runs one pass" 1 "$(claude_runs)"

# Only lanes with a schedule object get entries.
et_lanes work-items:work-loop
out="$(et_run print-schedule --data-dir "$ET_DATA" 2>&1)"
assert_not_contains "a lane with no schedule gets no schtasks entry" "$out" "schtasks /Create"
assert_contains "a lane with no schedule is named as skipped" "$out" "work: no schedule"

# Cron cannot say every 7 minutes; every 120 is every second hour.
et_lanes work-items:work-loop '{"schedule":{"every_minutes":120}}'
out="$(et_run print-schedule --data-dir "$ET_DATA" 2>&1)"
assert_contains "120 minutes is the cron form every second hour" "$out" "0 */2 * * * "
et_lanes work-items:work-loop '{"schedule":{"every_minutes":7}}'
out="$(et_run print-schedule --data-dir "$ET_DATA" 2>&1)"
assert_not_contains "7 minutes has no cron line" "$out" "*/7 "
assert_contains "7 minutes points at a systemd timer instead" "$out" "OnUnitActiveSec=7min"

# every_minutes is a whole number from 1 to 999. Any other value is warned
# about (file, lane, key, value) and dropped: the lane runs unscheduled.
ET_CONFIG="$ET_REPO/.work/lanes/lanes.json"
for bad in '{"every_minutes":0}' '{"every_minutes":1000}' '{"every_minutes":"15"}' '{"every_minutes":1.5}' '{}' '5'; do
  et_lanes work-items:work-loop "{\"schedule\":$bad}"
  out="$(et_run print-schedule --data-dir "$ET_DATA" 2>&1)"
  assert_eq "schedule $bad exits 0" 0 "$?"
  assert_contains "schedule $bad is warned about with the file, lane, key and value" "$out" \
    "WARNING: $ET_CONFIG: lane 'work': schedule $bad is not"
  assert_not_contains "schedule $bad gets no schtasks entry" "$out" "schtasks /Create"
  assert_not_contains "schedule $bad gets no cron line" "$out" "* * * "
  assert_contains "schedule $bad leaves the lane unscheduled" "$out" "work: no schedule"
done
# A bad schedule on one lane leaves the other lanes' entries and other actions alone.
jq -n '{lanes: [{name: "work", prompt: "work.md", effort: "high", schedule: {every_minutes: 0}},
  {name: "other", prompt: "work.md", effort: "high", schedule: {every_minutes: 15}}]}' >"$ET_CONFIG"
out="$(et_run print-schedule --data-dir "$ET_DATA" 2>&1)"
assert_eq "a bad schedule beside a good one exits 0" 0 "$?"
assert_not_contains "the bad lane gets no schtasks entry" "$out" 'HarnessOps Lane work"'
assert_contains "the good lane keeps its schtasks entry" "$out" 'schtasks /Create /TN "HarnessOps Lane other" /SC MINUTE /MO 15 '
et_lanes work-items:work-loop '{"schedule":{"every_minutes":0}}'
out="$(et_run run-once work --data-dir "$ET_DATA" --dry-run 2>&1)"
assert_eq "run-once proceeds past a bad schedule" 0 "$?"
assert_contains "run-once previews its pass despite a bad schedule" "$out" "DRY-RUN: claude -p"

# An integral number written with a fraction (20.0) is the whole number 20.
et_lanes work-items:work-loop '{"schedule":{"every_minutes":20.0}}'
out="$(et_run print-schedule --data-dir "$ET_DATA" 2>&1)"
assert_eq "every_minutes 20.0 exits 0" 0 "$?"
assert_contains "every_minutes 20.0 registers every 20 minutes" "$out" 'schtasks /Create /TN "HarnessOps Lane work" /SC MINUTE /MO 20 '
assert_contains "every_minutes 20.0 gets the 20-minute cron form" "$out" "*/20 * * * * "

# A scheduled lane's name becomes a file name and a task name, so it is held
# to letters, digits, '.', '_' and '-'.
jq -n '{lanes: [{name: "w$(touch PWNED_SCHED)", prompt: "work.md", effort: "high", schedule: {every_minutes: 15}}]}' >"$ET_REPO/.work/lanes/lanes.json"
out="$(et_run print-schedule --write-script --data-dir "$ET_DATA" 2>&1)"
rc=$?
assert_eq "a scheduled lane with an unsafe name exits 1" 1 "$rc"
assert_contains "the refusal names the allowed characters" "$out" "letters, digits"
assert_eq "no script is written for an unsafe name" "" "$(find "$ET_REPO/.work/lanes/scheduled" -name 'w*PWNED*' -print 2>/dev/null)"
et_lanes work-items:work-loop

out="$(et_run start --write-script --data-dir "$ET_DATA" --dry-run 2>&1)"
assert_eq "--write-script outside print-schedule exits 3" 3 "$?"

# The Windows /TR payload stays within schtasks' 262-character limit with a
# 120-character repository path. A cygpath stub stands in for Git Bash's.
WIN_BIN="$TMP/win-bin"
mkdir -p "$WIN_BIN"
cat >"$WIN_BIN/cygpath" <<'STUB'
#!/usr/bin/env bash
p="$2"
case "$p" in
*/bash) printf '%s\n' 'C:\Program Files\Git\usr\bin\bash.exe' ;;
*) printf 'C:%s\n' "${p//\//\\}" ;;
esac
STUB
chmod +x "$WIN_BIN/cygpath"
tr_payload() { # the /TR value of the first schtasks /Create line, unescaped
  printf '%s\n' "$1" | grep -m1 '^schtasks /Create' | sed -e 's/.* \/TR "//' -e 's/"$//' -e 's/\\"/"/g'
}
long_repo() { # <length of the Windows form> -> a directory whose C:-prefixed path has that length
  local base="$TMP/lr" pad
  pad=$(($1 - 2 - ${#base} - 1))
  printf '%s/%s' "$base" "$(printf '%*s' "$pad" '' | tr ' ' 'r')"
}
LR="$(long_repo 120)"
mkdir -p "$LR/.work/lanes"
printf 'You are the work lane.\n' >"$LR/.work/lanes/work.md"
jq -n '{lanes: [{name: "work", prompt: "work.md", effort: "high", schedule: {every_minutes: 15}}]}' >"$LR/.work/lanes/lanes.json"
out="$(PATH="$WIN_BIN:$ET_PATH" bash "$SCRIPT" print-schedule --repo "$LR" --data-dir "$ET_DATA" 2>&1)"
rc=$?
assert_eq "print-schedule with a 120-character repository path exits 0" 0 "$rc"
payload="$(tr_payload "$out")"
assert_eq "the /TR payload calls bash on the generated script" "\"C:\\Program Files\\Git\\usr\\bin\\bash.exe\" \"C:${LR//\//\\}\\.work\\lanes\\scheduled\\work.sh\"" "$payload"
within_limit=no
((${#payload} <= 262)) && within_limit=yes
assert_eq "the /TR payload is at most 262 characters" "yes" "$within_limit"

LR2="$(long_repo 240)"
mkdir -p "$LR2/.work/lanes"
cp "$LR/.work/lanes/lanes.json" "$LR/.work/lanes/work.md" "$LR2/.work/lanes/"
out="$(PATH="$WIN_BIN:$ET_PATH" bash "$SCRIPT" print-schedule --repo "$LR2" --data-dir "$ET_DATA" 2>&1)"
rc=$?
assert_eq "a /TR payload over 262 characters exits 1" 1 "$rc"
assert_contains "the refusal names the limit" "$out" "262"
assert_not_contains "no schtasks entry is printed over the limit" "$out" "schtasks /Create"

pwned="$(find "$TMP" "$PWD" -maxdepth 3 -name 'PWNED*' -print 2>/dev/null | head -n 1)"
assert_eq "no fixture string was evaluated by the shell" "" "$pwned"

# ============================================================================
echo
if ((FAILED)); then
  printf 'lane-launcher.test: FAIL — %d case(s) failed\n' "$FAILED" >&2
  exit 1
fi
printf 'lane-launcher.test: PASS — %d cases\n' "$CASE_NUM"
