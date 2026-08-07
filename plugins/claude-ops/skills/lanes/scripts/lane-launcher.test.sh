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
#
# Uses a per-suite fixture repo (config + prompt files) and PATH-stub `claude`
# and `git` so no real CLI or network is touched.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$SCRIPT_DIR/lane-launcher.sh"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

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
mkdir -p "$REPO/.work"
cat >"$REPO/.work/lanes.json" <<'JSON'
{
  "prompt_dir": ".work",
  "lanes": [
    { "name": "work",    "prompt": "work.md",    "model": "opus",   "effort": "high" },
    { "name": "babysit", "prompt": "babysit.md", "model": "sonnet", "effort": "medium",
      "settings": { "pluginConfigs": { "autonomy@test-marketplace": { "options": { "lane_stop_gate_enabled": true } } } } },
    { "name": "decide",  "prompt": "decide.md" }
  ]
}
JSON
printf 'You are the work lane.\n' >"$REPO/.work/work.md"
printf 'You are the babysit lane.\n' >"$REPO/.work/babysit.md"
printf 'You are the decide lane.\n' >"$REPO/.work/decide.md"

CONFIG="$REPO/.work/lanes.json"

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
export PATH="$STUB_BIN:$PATH"

# Launch-commit markers are namespaced by repo (#792 review): the data dir is
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
{ "lanes": [ { "name": "work.2 (alt)", "prompt": "work.md" } ] }
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

# The containment check reads names with jq's `test()`, which RAISES on a
# non-string subject — and a raised query prints nothing, which the caller read
# as "no violations". A non-string name on an EARLIER lane therefore skipped
# containment for every name after it. The type check now runs first, so the
# later queries never see a non-string subject and no raw jq error reaches the
# operator.
jq -n '{lanes: [{name: 123, prompt: "a.md"}, {name: "../escape", prompt: "b.md"}]}' \
  >"$TMP/nonstring-then-escape.json"
out="$(run_launcher start --repo "$REPO" --config "$TMP/nonstring-then-escape.json" --agents-json "$AGENTS_EMPTY" --dry-run 2>&1)"
rc=$?
assert_eq "a non-string name ahead of an escaping name exits 3" 3 "$rc"
assert_contains "the non-string name is the reported reason" "$out" ".name is number"
assert_not_contains "no raw jq type error reaches the operator" "$out" "cannot be matched"
assert_not_contains "no lane is launched past the rejected config" "$out" "claude --bg"

# `null` remains the JSON spelling of "no value" and stays equivalent to absent.
jq -n '{lanes: [{name: "work", prompt: "work.md", model: null}]}' >"$TMP/nullmodel.json"
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
assert_contains "start mirrors babysit model" "$out" "--model sonnet"
assert_contains "start mirrors babysit effort" "$out" "--effort medium"
assert_contains "start seeds prompt as placeholder" "$out" "<prompt:"
assert_not_contains "start hides prompt body" "$out" "You are the babysit lane"
assert_contains "start launches decide (no model/effort)" "$out" "claude --bg -n decide"
assert_not_contains "decide has no model flag" "$out" "-n decide --model"
assert_contains "start passes babysit settings inline" "$out" "--settings"
assert_contains "start settings carry the lane config object" "$out" "lane_stop_gate_enabled"
assert_not_contains "work has no settings flag" "$out" "-n work --settings"

# per-lane settings must be a JSON object — a non-object skips that lane only
cat >"$TMP/badsettings.json" <<'JSON'
{
  "prompt_dir": ".work",
  "lanes": [
    { "name": "work",   "prompt": "work.md", "settings": "not-an-object" },
    { "name": "decide", "prompt": "decide.md" }
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
  "prompt_dir": ".work",
  "lanes": [
    { "name": "work",   "prompt": "work.md", "settings": false },
    { "name": "decide", "prompt": "decide.md" }
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
{ "prompt_dir": ".work", "lanes": [ { "name": "work", "prompt": "work.md", "settings": null } ] }
JSON
outnull="$(run_launcher start --repo "$REPO" --config "$TMP/nullsettings.json" --agents-json "$AGENTS_EMPTY" --dry-run --no-pull --no-update 2>&1)"
rcnull=$?
assert_eq "settings:null launches the lane" 0 "$rcnull"
assert_contains "settings:null still launches work" "$outnull" "claude --bg -n work"
assert_not_contains "settings:null passes no --settings flag" "$outnull" "--settings"

# refresh step present by default; suppressible
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
assert_contains "start really launches work with model+effort" "$log" "--bg -n work --model opus --effort high"
assert_contains "start seeds the prompt-file body as the trailing arg" "$log" "--effort high You are the work lane."
assert_contains "start really launches babysit" "$log" "--bg -n babysit --model sonnet --effort medium"

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
{ "prompt_dir": ".work",
  "lanes": [
    { "name": "gone",  "prompt": "missing.md" },
    { "name": "blank", "prompt": "blank.md" },
    { "name": "baddy", "prompt": "work.md", "effort": "turbo" },
    { "name": "ultra", "prompt": "work.md", "effort": "ultracode" }
  ] }
JSON
: >"$REPO/.work/blank.md"
out="$(run_launcher start --repo "$REPO" --config "$TMP/badprompt.json" --agents-json "$AGENTS_EMPTY" --dry-run 2>&1)"
assert_contains "missing prompt file skipped" "$out" "prompt file not found"
assert_contains "empty prompt file skipped" "$out" "prompt file is empty"
assert_contains "invalid effort skipped" "$out" "invalid effort 'turbo'"
assert_not_contains "no launch for bad lanes" "$out" "claude --bg -n baddy"
assert_contains "ultracode effort accepted" "$out" "claude --bg -n ultra"
assert_contains "ultracode passed through as --effort" "$out" "claude --bg -n ultra --effort ultracode"

# ============================================================================
# ultracode version gate — below the floor the lane is skipped, and a restart
# preflights it BEFORE stopping so a healthy running lane stays up
# ============================================================================
cat >"$TMP/ultra.json" <<'JSON'
{ "prompt_dir": ".work",
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
{ "prompt_dir": ".work",
  "lanes": [ { "name": "u1", "prompt": "work.md", "effort": "ultracode" },
             { "name": "u2", "prompt": "work.md", "effort": "ultracode" },
             { "name": "u3", "prompt": "work.md", "effort": "ultracode" } ] }
JSON
: >"$CLAUDE_LOG"
out="$(run_launcher start --repo "$REPO" --config "$TMP/ultra3.json" --agents-json "$AGENTS_EMPTY" --dry-run 2>&1)"
assert_contains "every ultracode lane launches" "$out" "claude --bg -n u3 --effort ultracode"
assert_eq "version probe memoized across lanes" 1 "$(grep -c -- '--version' "$CLAUDE_LOG")"

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
assert_contains "no-CLI dry run still previews the lane" "$out" "claude --bg -n work --effort ultracode"

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
{ "prompt_dir": ".work",
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
# — preserving the documented offline-dry-run behaviour.
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
# (matches stop's fail-first behaviour): the log shows no git pull and no
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

# restart re-records the marker for the restarted lane.
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

# CLAUDE_PLUGIN_DATA env var is honored when --data-dir is not passed.
DATA_DIR6="$TMP/data6"
out="$(CLAUDE_PLUGIN_DATA="$DATA_DIR6" run_launcher start --repo "$REPO" --config "$CONFIG" --agents-json "$AGENTS_EMPTY" 2>&1)"
marker="$(cat "$DATA_DIR6/lanes/$REPO_KEY/work-launch-commit" 2>/dev/null)"
assert_eq "marker: falls back to \$CLAUDE_PLUGIN_DATA when --data-dir is unset" "deadbeefcafefeedfacefeeddeadbeefcafefeed" "$marker"

# The data dir is plugin-wide, so a second repo running the same conventional
# lane name must not overwrite the first repo's marker.
REPO_B="$TMP/repo-b"
mkdir -p "$REPO_B/.work"
cp "$REPO/.work/lanes.json" "$REPO_B/.work/lanes.json"
cp "$REPO/.work/work.md" "$REPO/.work/babysit.md" "$REPO/.work/decide.md" "$REPO_B/.work/"
REPO_B_KEY="$(marker_repo_key "$REPO_B")"
DATA_DIR7="$TMP/data7"
mkdir -p "$DATA_DIR7/lanes/$REPO_KEY"
printf 'repo-a-sha\n' >"$DATA_DIR7/lanes/$REPO_KEY/work-launch-commit"
out="$(run_launcher start --repo "$REPO_B" --config "$REPO_B/.work/lanes.json" --agents-json "$AGENTS_EMPTY" --data-dir "$DATA_DIR7" 2>&1)"
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
SHA256_REPO="$TMP/sha256-repo"
if git init --object-format=sha256 -q "$SHA256_REPO" 2>/dev/null; then
  mkdir -p "$SHA256_REPO/.work"
  cp "$REPO/.work/work.md" "$SHA256_REPO/.work/"
  cat >"$SHA256_REPO/.work/lanes.json" <<'JSON'
{ "prompt_dir": ".work", "lanes": [ { "name": "work", "prompt": "work.md" } ] }
JSON
  DATA_DIR9="$TMP/data9"
  out="$(run_launcher start --repo "$SHA256_REPO" --config "$SHA256_REPO/.work/lanes.json" \
    --agents-json "$AGENTS_EMPTY" --data-dir "$DATA_DIR9" --no-pull --no-update 2>&1)"
  # The key the target repo's own object format yields — 64 hex for SHA-256.
  sha256_key="$(marker_repo_key "$SHA256_REPO" "$SHA256_REPO")"
  assert_eq "marker: a SHA-256 repo yields a 64-character key" 64 "${#sha256_key}"
  marker="$(cat "$DATA_DIR9/lanes/$sha256_key/work-launch-commit" 2>/dev/null)"
  assert_eq "marker: written under the TARGET repo's object-format key" "deadbeefcafefeedfacefeeddeadbeefcafefeed" "$marker"
  # The SHA-1 key the unscoped digest used to produce must hold nothing.
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
{ "prompt_dir": ".work",
  "lanes": [ { "name": "work", "prompt": "work.md",
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
cat >"$TMP/gate-empty-marker.json" <<'JSON'
{ "prompt_dir": ".work",
  "lanes": [ { "name": "work", "prompt": "work.md",
    "settings": { "pluginConfigs": { "autonomy@test-marketplace": { "options": {
      "lane_stop_gate_enabled": true,
      "lane_stop_gate_sentinel": "",
      "lane_stop_gate_marker": "" } } } } } ] }
JSON
: >"$ARM_LOG"
out="$(run_launcher start --repo "$REPO" --config "$TMP/gate-empty-marker.json" --agents-json "$AGENTS_EMPTY" --no-pull --no-update 2>&1)"
armlog="$(cat "$ARM_LOG")"
assert_contains "arm: an explicitly empty marker still reaches the helper" "$armlog" "--marker"
assert_contains "arm: an explicitly empty sentinel still reaches the helper" "$armlog" "--sentinel"

# …while an option the lane never set stays absent from the arm call, so the
# gate's own resolution order (managed ▷ arm record ▷ user settings) still
# reaches user settings for it.
cat >"$TMP/gate-no-opts.json" <<'JSON'
{ "prompt_dir": ".work",
  "lanes": [ { "name": "work", "prompt": "work.md",
    "settings": { "pluginConfigs": { "autonomy@test-marketplace": { "options": {
      "lane_stop_gate_enabled": true } } } } } ] }
JSON
: >"$ARM_LOG"
out="$(run_launcher start --repo "$REPO" --config "$TMP/gate-no-opts.json" --agents-json "$AGENTS_EMPTY" --no-pull --no-update 2>&1)"
armlog="$(cat "$ARM_LOG")"
assert_not_contains "arm: an unset marker passes no --marker" "$armlog" "--marker"
assert_not_contains "arm: an unset sentinel passes no --sentinel" "$armlog" "--sentinel"

# Settings may name several autonomy installs. The arm id must reach ONLY the
# entries that asked: an `autonomy@a` carrying an explicit false would otherwise
# find a valid arm record and honor it as enablement ahead of the operator's
# false, gating an installation deliberately opted out. Options likewise come
# only from the requesting entry — the disabled sibling's marker must not leak
# into the arm call.
cat >"$TMP/gate-multi.json" <<'JSON'
{ "prompt_dir": ".work",
  "lanes": [ { "name": "work", "prompt": "work.md",
    "settings": { "pluginConfigs": {
      "autonomy@a": { "options": {
        "lane_stop_gate_enabled": false,
        "lane_stop_gate_marker": "DISABLED-SIBLING-MARKER" } },
      "autonomy@b": { "options": {
        "lane_stop_gate_enabled": true,
        "lane_stop_gate_marker": "REQUESTING-MARKER" } } } } } ] }
JSON
: >"$CLAUDE_LOG"
: >"$ARM_LOG"
out="$(run_launcher start --repo "$REPO" --config "$TMP/gate-multi.json" --agents-json "$AGENTS_EMPTY" --no-pull --no-update 2>&1)"
log="$(cat "$CLAUDE_LOG")"
armlog="$(cat "$ARM_LOG")"
assert_contains "arm: options come from the requesting entry" "$armlog" "--marker REQUESTING-MARKER"
assert_not_contains "arm: a disabled sibling's marker never reaches the helper" "$armlog" "DISABLED-SIBLING-MARKER"
# The launched --settings must carry the arm id under autonomy@b only. Isolate
# each entry's object from the echoed command rather than matching the whole
# line, which contains both.
entry_a="$(printf '%s\n' "$log" | grep -o '"autonomy@a":{[^}]*}[^}]*}' | head -n 1)"
entry_b="$(printf '%s\n' "$log" | grep -o '"autonomy@b":{[^}]*}[^}]*}' | head -n 1)"
assert_contains "arm: the requesting entry receives the arm id" "$entry_b" "lane_stop_gate_arm_id"
assert_not_contains "arm: the explicitly-disabled entry receives no arm id" "$entry_a" "lane_stop_gate_arm_id"

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
{ "prompt_dir": ".work",
  "lanes": [ { "name": "work", "prompt": "work.md",
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
LAUNCHER_STAGED="$STAGE/plugins/cache/mkt-a/claude-ops/1.0.0/skills/lanes/scripts/lane-launcher.sh"
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

# ============================================================================
echo
if ((FAILED)); then
  printf 'lane-launcher.test: FAIL — %d case(s) failed\n' "$FAILED" >&2
  exit 1
fi
printf 'lane-launcher.test: PASS — %d cases\n' "$CASE_NUM"
