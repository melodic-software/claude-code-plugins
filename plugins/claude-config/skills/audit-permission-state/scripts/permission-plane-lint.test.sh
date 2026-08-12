#!/usr/bin/env bash
# Regression tests for permission-plane-lint.sh (self-contained — ships with the plugin).
#
# Every case feeds hand-written reader records on stdin, so no test reads or
# writes the operator's real ~/.claude. The one end-to-end case drives the real
# reader over a fully fixtured tree with HOME redirected and CLAUDE_CONFIG_DIR
# unset.
#
# portability-scope: one fixture spells a Windows UNC network path in a heredoc
# body. The backslash run the gate reads as a regex escape is that path, and the
# doubled prefix is what MAKES it a UNC path -- rewriting it would delete the
# case rather than fix anything.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$SCRIPT_DIR/permission-plane-lint.sh"
STATE_SCRIPT="$SCRIPT_DIR/permission-state.sh"

TEST_TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TEST_TMPDIR"' EXIT

FAILED=0
CASE_NUM=0
pass() {
  CASE_NUM=$((CASE_NUM + 1))
  printf 'PASS: %s\n' "$1"
}
fail() {
  CASE_NUM=$((CASE_NUM + 1))
  FAILED=$((FAILED + 1))
  printf 'FAIL: %s\n  detail: %s\n' "$1" "$2" >&2
}
assert_eq() {
  if [[ "$2" == "$3" ]]; then pass "$1"; else fail "$1" "expected: $2, actual: $3"; fi
}
assert_exit() {
  if [[ "$2" == "$3" ]]; then pass "$1"; else fail "$1" "expected exit $2, got $3"; fi
}
assert_contains() {
  case "$2" in
  *"$3"*) pass "$1" ;;
  *) fail "$1" "expected to contain: $3" ;;
  esac
}
assert_not_contains() {
  case "$2" in
  *"$3"*) fail "$1" "unexpected substring: $3" ;;
  *) pass "$1" ;;
  esac
}
count_matching() { printf '%s\n' "$1" | grep -cE "$2"; }

lint() { printf '%s\n' "$1" | bash "$SCRIPT"; }

SURFACES='managed file present /policy/managed-settings.json
user settings present /fx/home/.claude/settings.json
project settings present /proj/.claude/settings.json
local settings present /proj/.claude/settings.local.json
startdir-local settings present /start/.claude/settings.local.json'

# --- C2: three dead-config gates, reported SEPARATELY -------------------------
# The plan requires these never merge into one finding: they have different
# scope sets and different version histories, so an operator who fixed one
# would believe they had fixed all three.
C2=$(
  printf '%s\n' "$SURFACES"
  cat <<'EOF'
conf project settings autoModePresent true
conf project settings defaultMode "auto"
conf project settings useAutoModeDuringPlan false
EOF
)
OUT=$(lint "$C2")
assert_eq "the autoMode gate fires exactly once" 1 "$(count_matching "$OUT" '\[C2-autoMode\]')"
assert_eq "the defaultMode gate fires exactly once" 1 "$(count_matching "$OUT" '\[C2-defaultMode\]')"
assert_eq "the plan-mode gate fires exactly once" 1 "$(count_matching "$OUT" '\[C2-planMode\]')"
assert_contains "the defaultMode finding cites its version gate" "$OUT" "v2.1.142"
assert_contains "the plan-mode finding names the scope restriction" "$OUT" "not read from shared project settings"

# autoMode in LOCAL settings says it was live before v2.1.207 rather than
# implying it never worked.
C2_LOCAL=$(
  printf '%s\n' "$SURFACES"
  printf 'conf local settings autoModePresent true\n'
)
OUT=$(lint "$C2_LOCAL")
assert_contains "a local autoMode section fires" "$OUT" "[C2-autoMode] local"
assert_contains "and carries its version history" "$OUT" "v2.1.207"

# The scopes the classifier DOES read are silent.
C2_LIVE=$(
  printf '%s\n' "$SURFACES"
  cat <<'EOF'
conf user settings autoModePresent true
conf managed file autoModePresent true
conf user settings defaultMode "auto"
conf user settings useAutoModeDuringPlan false
EOF
)
OUT=$(lint "$C2_LIVE")
assert_eq "no C2 finding on a scope the classifier reads" 0 "$(count_matching "$OUT" '\[C2-')"

# Only the value `auto` is dead in project scope; other modes are read there.
C2_OTHER=$(
  printf '%s\n' "$SURFACES"
  printf 'conf project settings defaultMode "acceptEdits"\n'
)
OUT=$(lint "$C2_OTHER")
assert_eq "a non-auto defaultMode in project scope is legitimate" 0 "$(count_matching "$OUT" '\[C2-defaultMode\]')"

# The page restricts useAutoModeDuringPlan to SHARED PROJECT settings by name.
# Claiming a local occurrence is dead would assert a restriction no page states.
C2_PLAN_LOCAL=$(
  printf '%s\n' "$SURFACES"
  printf 'conf local settings useAutoModeDuringPlan false\n'
)
OUT=$(lint "$C2_PLAN_LOCAL")
assert_eq "a local useAutoModeDuringPlan is not claimed dead" 0 "$(count_matching "$OUT" '\[C2-planMode\]')"

# --- C5: disableAutoMode must be the STRING "disable" -------------------------
# The worst failure mode in this file: an operator believes auto mode is locked
# out and it is not.
C5=$(
  printf '%s\n' "$SURFACES"
  cat <<'EOF'
conf user settings disableAutoMode true
conf project settings permissions.disableAutoMode false
conf managed file disableAutoMode "disable"
conf local settings permissions.disableAutoMode "disable"
EOF
)
OUT=$(lint "$C5")
assert_eq "both wrongly-typed entries fire, and only those" 2 "$(count_matching "$OUT" '\[C5-disableType\]')"
assert_contains "the boolean at the top-level key fires" "$OUT" "[C5-disableType] user disableAutoMode is true"
assert_contains "the boolean under permissions fires too" "$OUT" "[C5-disableType] project permissions.disableAutoMode is false"
assert_contains "the finding states the consequence, not just the type" "$OUT" "auto mode is NOT disabled here"

# It is not managed-only: every scope is checked.
C5_MANAGED=$(
  printf '%s\n' "$SURFACES"
  printf 'conf managed file permissions.disableAutoMode true\n'
)
OUT=$(lint "$C5_MANAGED")
assert_contains "managed scope is checked like any other" "$OUT" "[C5-disableType] managed"

# --- C6: rules that cannot match ---------------------------------------------
C6=$(
  printf '%s\n' "$SURFACES"
  cat <<'EOF'
rule user settings allow Read(C:\\Users\\x\\.env)
rule user settings allow Bash(git:* push)
rule project settings allow Bash(command:rm *)
rule project settings allow Write(file_path:/etc/**)
rule project settings allow Write(docs/**)
EOF
)
OUT=$(lint "$C6")
assert_eq "the doubled-backslash path fires once" 1 "$(count_matching "$OUT" '\[C6-winPath\]')"
assert_eq "the mid-pattern :* fires once" 1 "$(count_matching "$OUT" '\[C6-colonStar\]')"
assert_eq "both content-field rules fire" 2 "$(count_matching "$OUT" '\[C6-contentField\]')"
assert_eq "the uncovered path rule fires once" 1 "$(count_matching "$OUT" '\[C6-uncoveredPath\]')"
assert_contains "the winPath finding gives the working form" "$OUT" "//c/**"

# Legitimate rule shapes that MUST NOT fire. Each of these is a false positive
# the checks were specifically written to avoid.
C6_CLEAN=$(
  printf '%s\n' "$SURFACES"
  cat <<'EOF'
rule user settings allow Bash(npm test)
rule user settings allow Bash(git:*)
rule user settings allow Read(//c/**/.env)
rule user settings allow Read(/c/Users/x/.env)
rule user settings deny Write
rule user settings deny Glob
rule user settings allow Edit(src/**)
rule user settings allow Read(docs/**)
rule user settings allow Bash(timeout:30)
EOF
)
OUT=$(lint "$C6_CLEAN")
assert_eq "no finding on any legitimate rule shape" 0 "$(count_matching "$OUT" '^finding ')"

# A bare tool-name rule is legitimate AT THE TOOL LEVEL and is the single most
# common rule shape there is; flagging it would drown every real finding.
C6_BARE=$(
  printf '%s\n' "$SURFACES"
  printf 'rule user settings deny Write\nrule user settings deny NotebookEdit\nrule user settings deny MultiEdit\n'
)
OUT=$(lint "$C6_BARE")
assert_eq "bare tool-name rules never fire the uncovered-path check" 0 "$(count_matching "$OUT" '\[C6-uncoveredPath\]')"

# `:*` AT the end is the documented working form; only mid-pattern is dead.
C6_COLON=$(
  printf '%s\n' "$SURFACES"
  printf 'rule user settings allow Bash(npm:*)\nrule user settings allow Bash(git:* push)\n'
)
OUT=$(lint "$C6_COLON")
assert_eq "only the mid-pattern colon-star fires" 1 "$(count_matching "$OUT" '\[C6-colonStar\]')"
assert_contains "and it is the mid-pattern one" "$OUT" "Bash(git:* push)"

# A parameter rule on a NON-content field is the documented working form.
C6_PARAM=$(
  printf '%s\n' "$SURFACES"
  printf 'rule user settings allow WebFetch(domain:example.com)\nrule user settings allow WebFetch(url:https://x)\n'
)
OUT=$(lint "$C6_PARAM")
assert_eq "only the content-field parameter rule fires" 1 "$(count_matching "$OUT" '\[C6-contentField\]')"
assert_contains "and it is the url one" "$OUT" "WebFetch(url:https://x)"

# --- Reporting shape ----------------------------------------------------------
OUT=$(lint "$C6")
assert_contains "every finding carries a severity" "$OUT" "finding error ["
assert_eq "every finding line has a bracketed check id" \
  "$(count_matching "$OUT" '^finding ')" "$(count_matching "$OUT" '^finding [a-z]+ \[C[0-9]')"
assert_contains "the summary states how many checks ran" "$OUT" "checks_run=9"

# A clean plane is reported as clean, with the check count, not as silence.
OUT=$(lint "$SURFACES")
assert_contains "a clean run still reports its summary" "$OUT" "lint summary findings=0"

# --- C6-winPath fires on SHAPE, not on the backslash character ---------------
# This check has been wrong in both directions: first testing the doubled JSON
# source spelling (dead in the real pipeline), then a bare backslash (worse than
# dead -- backslashes are ordinary in shell rules, so every escape became a
# severity-error finding and the one true finding drowned).
WINSHAPE=$(
  printf '%s
' "$SURFACES"
  cat <<'EOF'
rule user settings allow Bash(echo \n *)
rule user settings allow Bash(sed 's/\./_/g' *)
rule user settings allow Bash(grep 'a	b' *)
rule user settings allow Read(//c/Users/alice/**)
EOF
)
OUT=$(lint "$WINSHAPE")
assert_eq "a backslash escape in a shell rule is not a Windows path" 0 "$(count_matching "$OUT" '\[C6-winPath\]')"

WINREAL=$(
  printf '%s
' "$SURFACES"
  printf 'rule user settings allow Read(C:\Users\alice\**)
'
)
OUT=$(lint "$WINREAL")
assert_eq "a drive-letter path still fires" 1 "$(count_matching "$OUT" '\[C6-winPath\]')"
assert_contains "with the POSIX remedy" "$OUT" "//c/** form instead"

# A UNC path is a real finding, but //c/** is the wrong advice for it.
#
# A quoted heredoc, not printf: printf interprets backslash escapes, so the
# doubled prefix that MAKES this a UNC path collapses before the lint sees it.
UNCREAL=$(
  printf '%s\n' "$SURFACES"
  cat <<'EOF'
rule user settings allow Read(\\server\share\**)
EOF
)
OUT=$(lint "$UNCREAL")
assert_eq "a UNC path fires" 1 "$(count_matching "$OUT" '\[C6-winPath\]')"
assert_contains "and is named as UNC rather than given drive-letter advice" "$OUT" "a UNC path in a rule cannot match"

# --- C6-colonStar is about COMMAND PREFIX patterns ---------------------------
# "WebFetch rules use a `domain:` prefix… supports `*` wildcards", so a wildcard
# mid-value there is documented and working. Firing on it called a working rule
# broken. The documented mechanic names Bash prefix patterns specifically.
COLON_PARAM=$(
  printf '%s
' "$SURFACES"
  cat <<'EOF'
rule user settings allow WebFetch(domain:*.example.com)
rule user settings allow Bash(git:* push)
EOF
)
OUT=$(lint "$COLON_PARAM")
assert_eq "only the command-prefix rule fires" 1 "$(count_matching "$OUT" '\[C6-colonStar\]')"
assert_contains "and it is the Bash one" "$OUT" "Bash(git:* push)"
assert_not_contains "a documented domain wildcard is not called broken" "$OUT" "WebFetch(domain:*.example.com)"

# --- A dead command prefix fires in EVERY kind, not just allow ---------------
# The gap that let a fail-open defect through: no case here covered a
# mid-pattern `:*` in a DENY rule, so exempting the parameter form by grammar
# silenced `deny Bash(git:* push)` -- the dead-rule example the page itself
# gives -- and the suite stayed 58/58.
#
# The direction matters. A dead ALLOW fails closed: the operator is denied
# something they thought they had, and finds out. A dead DENY fails OPEN: they
# believe they blocked `git push` and did not, and nothing says so.
#
# The discriminator is the SPACE. "Each rule names one parameter" and its value
# is one scalar, so a parameter value never carries space-separated trailing
# words; a dead command prefix is precisely a prefix followed by more words.
DEAD_PREFIX=$(
  printf '%s
' "$SURFACES"
  cat <<'EOF'
rule user settings deny Bash(git:* push)
rule user settings deny Bash(npm:* run build)
rule user settings deny Bash(docker:* rm -f)
rule user settings ask PowerShell(Get:* -Force)
rule user settings allow Bash(git:* push)
EOF
)
OUT=$(lint "$DEAD_PREFIX")
assert_eq "every dead command prefix fires, whatever its kind" 5 "$(count_matching "$OUT" '\[C6-colonStar\]')"
assert_contains "including the deny form of the page's own example" "$OUT" "[C6-colonStar] user Bash(git:* push)"
assert_contains "and an ask on PowerShell" "$OUT" "PowerShell(Get:* -Force)"

# The parameter forms stay exempt in the same kinds -- the space predicate must
# not undo the grammar exemption it refines.
PARAM_KINDS=$(
  printf '%s
' "$SURFACES"
  cat <<'EOF'
rule user settings deny Agent(model:*-haiku)
rule user settings ask Agent(isolation:*)
rule user settings deny Bash(run_in_background:*)
rule user settings deny Agent(model:opus*)
rule user settings allow WebFetch(domain:*.example.com)
EOF
)
OUT=$(lint "$PARAM_KINDS")
assert_eq "no parameter form fires, in any kind" 0 "$(count_matching "$OUT" '\[C6-colonStar\]')"

# --- One rule, one explanation -----------------------------------------------
# `allow Agent(model:*-haiku)` drew BOTH colonStar and allowParam, with two
# different mechanics -- and colonStar explains it as a dead Bash COMMAND
# PREFIX, which Agent does not take. The rule is dead either way; only one of
# the two findings says why.
DOUBLE=$(
  printf '%s
' "$SURFACES"
  printf 'rule user settings allow Agent(model:*-haiku)
'
)
OUT=$(lint "$DOUBLE")
assert_eq "the parameter-form allow draws exactly one finding" 1 "$(count_matching "$OUT" '^finding ')"
assert_contains "and it is the one that explains it correctly" "$OUT" "[C6-allowParam]"
assert_not_contains "not a command-prefix explanation for a tool with no command prefixes" "$OUT" "[C6-colonStar]"

# Suppression is scoped to the parameter shape: a real dead command prefix in an
# allow rule still fires colonStar.
NOT_SUPPRESSED=$(
  printf '%s
' "$SURFACES"
  printf 'rule user settings allow Bash(git:* push)
'
)
OUT=$(lint "$NOT_SUPPRESSED")
assert_contains "an allow-rule command prefix still fires colonStar" "$OUT" "[C6-colonStar]"

# --- Parameter matching is deny/ask only -------------------------------------
# "Deny and ask rules can match a top-level input parameter... An allow rule for
# one parameter value would not establish that the call is safe overall, so
# allow rules continue to use each tool own specifier syntax." An operator who
# writes one believes they narrowed a grant and did not.
ALLOW_PARAM=$(
  printf '%s
' "$SURFACES"
  cat <<'EOF'
rule user settings allow Agent(model:opus)
rule user settings allow Bash(run_in_background:true)
rule user settings deny Agent(model:opus)
rule user settings ask Agent(isolation:worktree)
EOF
)
OUT=$(lint "$ALLOW_PARAM")
assert_eq "only the two allow rules fire" 2 "$(count_matching "$OUT" '\[C6-allowParam\]')"
assert_contains "the Agent allow fires" "$OUT" "[C6-allowParam] user Agent(model:opus)"
assert_contains "the Bash parameter allow fires too" "$OUT" "[C6-allowParam] user Bash(run_in_background:true)"
assert_contains "the finding cites the deny/ask restriction" "$OUT" "documented for deny and ask rules only"

# Shapes that are a tool own syntax, not the parameter form, must stay silent --
# `WebFetch(domain:host)` is documented as the WebFetch form and `Bash(npm:*)`
# is a command prefix, so neither is distinguishable from a parameter by shape.
PARAM_CLEAN=$(
  printf '%s
' "$SURFACES"
  cat <<'EOF'
rule user settings allow WebFetch(domain:example.com)
rule user settings allow Bash(npm:*)
rule user settings allow Bash(git:*)
EOF
)
OUT=$(lint "$PARAM_CLEAN")
assert_eq "a tool own specifier syntax never fires allowParam" 0 "$(count_matching "$OUT" '\[C6-allowParam\]')"

# --- C6-winPath must fire on what the READER actually emits ------------------
# It did not. The check tested for a doubled backslash -- the JSON SOURCE
# spelling -- but `jq -r` decodes the escape, so the reader emits a single
# backslash and the check was dead in the real pipeline. It passed its own suite
# only because every other case here feeds a hand-written record that bypasses
# the reader. This one drives the reader.
if command -v jq >/dev/null 2>&1; then
  WPFX="$TEST_TMPDIR/wpfx"
  mkdir -p "$WPFX/proj/.claude" "$WPFX/home/.claude" "$WPFX/pol" "$WPFX/sd/.claude"
  jq -n '{}' >"$WPFX/proj/.claude/settings.json"
  jq -n '{}' >"$WPFX/pol/managed-settings.json"
  # Doubled in the jq SOURCE so the file carries single backslashes -- which is
  # exactly the point: the reader decodes them, and the check has to match what
  # the reader emits rather than the source spelling.
  jq -n '{permissions:{allow:["Read(C:\\Users\\alice\\**)","Read(//c/**/.env)"]}}' >"$WPFX/home/.claude/settings.json"
  E2E_WP=$(env -u CLAUDE_CONFIG_DIR HOME="$WPFX/home"     PERMISSION_STATE_FIXTURE_DIR="$WPFX/proj"     PERMISSION_STATE_STARTDIR="$WPFX/sd"     PERMISSION_STATE_MANAGED_PATH="$WPFX/pol/managed-settings.json"     PERMISSION_STATE_REGISTRY_KEYS=""     PERMISSION_STATE_PLIST_DOMAIN=""     bash "$STATE_SCRIPT" | bash "$SCRIPT")
  assert_eq "the Windows path is caught through the real reader" 1 "$(count_matching "$E2E_WP" '\[C6-winPath\]')"
  assert_contains "and it is the backslash rule, not the POSIX one" "$E2E_WP" "Read(C:\Users\alice"
else
  pass "winPath end-to-end (skipped -- jq not installed)"
fi

# --- Fail-loud: no input is never a clean bill --------------------------------
rc=0
err=$(printf '' | bash "$SCRIPT" 2>&1) || rc=$?
assert_exit "exit 2 on empty input" 2 "$rc"
assert_contains "the error says it will not claim a clean plane" "$err" "will not report a clean plane"

rc=0
printf 'NOTE: only a note\n' | bash "$SCRIPT" >/dev/null 2>&1 || rc=$?
assert_exit "notes alone are not scope records" 2 "$rc"

rc=0
err=$(bash "$SCRIPT" --bogus </dev/null 2>&1) || rc=$?
assert_exit "exit 2 on an unknown argument" 2 "$rc"
assert_contains "the unknown argument is named" "$err" "unknown argument"

rc=0
help=$(bash "$SCRIPT" --help </dev/null 2>&1) || rc=$?
assert_exit "--help exits 0" 0 "$rc"
assert_contains "--help states the advisory contract" "$help" "never \"nothing found\""

# --- End to end: real reader into the lint ------------------------------------
if command -v jq >/dev/null 2>&1; then
  FX="$TEST_TMPDIR/fx"
  mkdir -p "$FX/proj/.claude" "$FX/home/.claude" "$FX/policy" "$FX/startdir/.claude"
  jq -n '{
    autoMode: {classifyAllShell: true},
    permissions: {defaultMode: "auto", allow: ["Write(docs/**)"]},
    useAutoModeDuringPlan: false
  }' >"$FX/proj/.claude/settings.json"
  jq -n '{permissions: {disableAutoMode: true, allow: ["Bash(npm test)"]}}' >"$FX/home/.claude/settings.json"
  jq -n '{}' >"$FX/policy/managed-settings.json"

  E2E=$(env -u CLAUDE_CONFIG_DIR \
    HOME="$FX/home" \
    PERMISSION_STATE_FIXTURE_DIR="$FX/proj" \
    PERMISSION_STATE_STARTDIR="$FX/startdir" \
    PERMISSION_STATE_MANAGED_PATH="$FX/policy/managed-settings.json" \
    PERMISSION_STATE_REGISTRY_KEYS="" \
    PERMISSION_STATE_PLIST_DOMAIN="" \
    bash "$STATE_SCRIPT" | bash "$SCRIPT")

  assert_contains "end to end: the dead autoMode section is found" "$E2E" "[C2-autoMode] project"
  assert_contains "end to end: the dead defaultMode is found" "$E2E" "[C2-defaultMode] project"
  assert_contains "end to end: the dead plan-mode key is found" "$E2E" "[C2-planMode] project"
  assert_contains "end to end: the mistyped lock-out switch is found" "$E2E" "[C5-disableType] user"
  assert_contains "end to end: the never-consulted path rule is found" "$E2E" "[C6-uncoveredPath] project"
  assert_not_contains "end to end: the narrow allow rule is not flagged" "$E2E" "Bash(npm test)"
else
  pass "end-to-end reader lint (skipped — jq not installed)"
fi

if [[ "$FAILED" -eq 0 ]]; then
  printf '\nAll %d checks passed.\n' "$CASE_NUM"
  exit 0
fi
printf '\n%d/%d checks failed.\n' "$FAILED" "$CASE_NUM" >&2
exit 1
