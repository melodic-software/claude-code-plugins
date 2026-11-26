#!/usr/bin/env bash
# portability-scope: one fixture spells a Windows UNC network path in a heredoc body, not a regex escape
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$SCRIPT_DIR/permission-plane-lint.sh"
STATE_SCRIPT="$SCRIPT_DIR/permission-state.sh"

TEST_TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TEST_TMPDIR"' EXIT

# shellcheck source=test-helpers.sh
source "$SCRIPT_DIR/test-helpers.sh"

export PERMISSION_STATE_OSTYPE=linux-gnu

lint() { printf '%s\n' "$1" | bash "$SCRIPT"; }

SURFACES='managed file present /policy/managed-settings.json
user settings present /fx/home/.claude/settings.json
project settings present /proj/.claude/settings.json
local settings present /proj/.claude/settings.local.json
startdir-local settings present /start/.claude/settings.local.json'

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
assert_contains "the auto finding says the built-in default replaces a user-scope defaultMode" "$OUT" "uses the built-in default instead of a defaultMode from ~/.claude/settings.json"
assert_contains "the auto finding says to remove the value from the file" "$OUT" "remove it here"
assert_contains "the plan-mode finding names the scope restriction" "$OUT" "not read from shared project settings"

C2_LOCAL=$(
  printf '%s\n' "$SURFACES"
  printf 'conf local settings autoModePresent true\n'
)
OUT=$(lint "$C2_LOCAL")
assert_contains "a local autoMode section fires" "$OUT" "[C2-autoMode] local"
assert_contains "and carries its version history" "$OUT" "v2.1.207"

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

for mode in acceptEdits plan dontAsk default manual; do
  C2_OTHER=$(
    printf '%s\n' "$SURFACES"
    printf 'conf project settings defaultMode "%s"\n' "$mode"
  )
  OUT=$(lint "$C2_OTHER")
  assert_eq "$mode in project scope still applies" 0 "$(count_matching "$OUT" '\[C2-defaultMode\]')"
done

C2_BYPASS=$(
  printf '%s\n' "$SURFACES"
  printf 'conf project settings defaultMode "bypassPermissions"\n'
)
OUT=$(lint "$C2_BYPASS")
assert_eq "project bypassPermissions fires the defaultMode gate" 1 "$(count_matching "$OUT" '\[C2-defaultMode\]')"
assert_contains "the finding names the 2.1.257 gate" "$OUT" "v2.1.257"
assert_contains "the finding says the session starts in Manual" "$OUT" "starts in Manual"
assert_contains "the finding says to remove the value from the file" "$OUT" "remove it here"
assert_contains "the Manual start is conditional on nothing higher-ranked setting a mode" "$OUT" "Unless a higher-ranked settings file or --permission-mode sets a mode"

for scope in local startdir-local; do
  C2_BYPASS_LOCAL=$(
    printf '%s\n' "$SURFACES"
    printf 'conf %s settings defaultMode "bypassPermissions"\n' "$scope"
  )
  OUT=$(lint "$C2_BYPASS_LOCAL")
  assert_contains "$scope bypassPermissions fires the defaultMode gate" "$OUT" "[C2-defaultMode] $scope"
done

C2_BYPASS_USER=$(
  printf '%s\n' "$SURFACES"
  printf 'conf user settings defaultMode "bypassPermissions"\n'
  printf 'conf managed file defaultMode "bypassPermissions"\n'
)
OUT=$(lint "$C2_BYPASS_USER")
assert_eq "user and managed bypassPermissions are not dead" 0 "$(count_matching "$OUT" '\[C2-defaultMode\]')"

C2_PLAN_LOCAL=$(
  printf '%s\n' "$SURFACES"
  printf 'conf local settings useAutoModeDuringPlan false\n'
)
OUT=$(lint "$C2_PLAN_LOCAL")
assert_eq "a local useAutoModeDuringPlan is not claimed dead" 0 "$(count_matching "$OUT" '\[C2-planMode\]')"

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

C5_MANAGED=$(
  printf '%s\n' "$SURFACES"
  printf 'conf managed file permissions.disableAutoMode true\n'
)
OUT=$(lint "$C5_MANAGED")
assert_contains "managed scope is checked like any other" "$OUT" "[C5-disableType] managed"

TWO_FILES=$(
  printf '%s\n' "$SURFACES"
  cat <<'EOF'
conf project settings disableAutoMode true
conf project toplevel disableAutoMode "disable"
conf project settings defaultMode "acceptEdits"
conf project toplevel defaultMode "auto"
conf project toplevel autoModePresent true
conf project toplevel useAutoModeDuringPlan false
EOF
)
OUT=$(lint "$TWO_FILES")
assert_contains "two project files: this directory's mistyped switch survives the root's" "$OUT" "[C5-disableType] project disableAutoMode is true"
assert_eq "two project files: the correctly typed switch does not fire" 1 "$(count_matching "$OUT" '\[C5-disableType\]')"
assert_contains "two project files: the root's ignored mode survives this directory's" "$OUT" "[C2-defaultMode] project:toplevel defaultMode:\"auto\""
assert_contains "two project files: the root's dead autoMode is named as the root's" "$OUT" "[C2-autoMode] project:toplevel an autoMode section here is never read"
assert_not_contains "two project files: it carries no local-settings history" "$(grep -F '[C2-autoMode]' <<<"$OUT")" "before v2.1.207"
assert_contains "two project files: the root's plan key is named as the root's" "$OUT" "[C2-planMode] project:toplevel"
ROOT_RULE=$(
  printf '%s\n' "$SURFACES"
  printf 'rule project toplevel allow Bash(git:* push)\n'
  printf 'rule project settings allow Bash(npm:* test)\n'
)
OUT=$(lint "$ROOT_RULE")
assert_contains "two project files: a root rule finding is named as the root's" "$OUT" "[C6-colonStar] project:toplevel"
assert_contains "two project files: this directory's rule finding stays project" "$OUT" "[C6-colonStar] project "
assert_eq "two project files: one finding each" 2 "$(count_matching "$OUT" '\[C6-colonStar\]')"
LAST_WINS=$(
  printf '%s\n' "$SURFACES"
  printf 'conf managed file disableAutoMode true\n'
  printf 'conf managed dropin-file:z.json disableAutoMode "disable"\n'
)
assert_not_contains "managed: a later drop-in's value is the one in force" "$(lint "$LAST_WINS")" "[C5-disableType]"

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

C6_BARE=$(
  printf '%s\n' "$SURFACES"
  printf 'rule user settings deny Write\nrule user settings deny NotebookEdit\nrule user settings deny MultiEdit\n'
)
OUT=$(lint "$C6_BARE")
assert_eq "bare tool-name rules never fire the uncovered-path check" 0 "$(count_matching "$OUT" '\[C6-uncoveredPath\]')"

C6_COLON=$(
  printf '%s\n' "$SURFACES"
  printf 'rule user settings allow Bash(npm:*)\nrule user settings allow Bash(git:* push)\n'
)
OUT=$(lint "$C6_COLON")
assert_eq "only the mid-pattern colon-star fires" 1 "$(count_matching "$OUT" '\[C6-colonStar\]')"
assert_contains "and it is the mid-pattern one" "$OUT" "Bash(git:* push)"

C6_PARAM=$(
  printf '%s\n' "$SURFACES"
  printf 'rule user settings allow WebFetch(domain:example.com)\nrule user settings allow WebFetch(url:https://x)\n'
)
OUT=$(lint "$C6_PARAM")
assert_eq "only the content-field parameter rule fires" 1 "$(count_matching "$OUT" '\[C6-contentField\]')"
assert_contains "and it is the url one" "$OUT" "WebFetch(url:https://x)"

OUT=$(lint "$C6")
assert_contains "every finding carries a severity" "$OUT" "finding error ["
assert_eq "every finding line has a bracketed check id" \
  "$(count_matching "$OUT" '^finding ')" "$(count_matching "$OUT" '^finding [a-z]+ \[C[0-9]')"
assert_contains "the summary states how many checks ran" "$OUT" "checks_run=12"

OUT=$(lint "$SURFACES")
assert_contains "a clean run still reports its summary" "$OUT" "lint summary findings=0"

WINSHAPE=$(
  printf '%s\n' "$SURFACES"
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
  printf '%s\n' "$SURFACES"
  cat <<'EOF'
rule user settings allow Read(C:\Temp\alice\**)
EOF
)
OUT=$(lint "$WINREAL")
assert_eq "a drive-letter path still fires" 1 "$(count_matching "$OUT" '\[C6-winPath\]')"
assert_contains "with the POSIX remedy" "$OUT" "//c/** form instead"

UNCREAL=$(
  printf '%s\n' "$SURFACES"
  cat <<'EOF'
rule user settings allow Read(\\server\share\**)
EOF
)
OUT=$(lint "$UNCREAL")
assert_eq "a UNC path fires" 1 "$(count_matching "$OUT" '\[C6-winPath\]')"
assert_contains "and is named as UNC rather than given drive-letter advice" "$OUT" "a UNC path in a rule cannot match"

COLON_PARAM=$(
  printf '%s\n' "$SURFACES"
  cat <<'EOF'
rule user settings allow WebFetch(domain:*.example.com)
rule user settings allow Bash(git:* push)
EOF
)
OUT=$(lint "$COLON_PARAM")
assert_eq "only the command-prefix rule fires" 1 "$(count_matching "$OUT" '\[C6-colonStar\]')"
assert_contains "and it is the Bash one" "$OUT" "Bash(git:* push)"
assert_not_contains "a documented domain wildcard is not called broken" "$OUT" "WebFetch(domain:*.example.com)"

DEAD_PREFIX=$(
  printf '%s\n' "$SURFACES"
  cat <<'EOF'
rule user settings deny Bash(git:* push)
rule user settings deny Bash(npm:* run build)
rule user settings deny Bash(docker:* rm -f)
rule user settings ask PowerShell(Get:* -Force)
rule user settings allow Bash(git:* push)
EOF
)
OUT=$(lint "$DEAD_PREFIX")
assert_eq "every literal-colon command wildcard fires, whatever its kind" 5 "$(count_matching "$OUT" '\[C6-colonStar\]')"
assert_contains "including the deny form of the page's own example" "$OUT" "[C6-colonStar] user Bash(git:* push)"
assert_contains "and an ask on PowerShell" "$OUT" "PowerShell(Get:* -Force)"

PARAM_KINDS=$(
  printf '%s\n' "$SURFACES"
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

NO_PREFIX=$(
  printf '%s\n' "$SURFACES"
  cat <<'EOF'
rule user settings deny PowerShell(*env:*lefthook*)
rule user settings deny Bash(git:* push)
rule user settings deny Bash(* git:* push)
rule user settings deny Bash(*foo:* rm -rf /)
EOF
)
OUT=$(lint "$NO_PREFIX")
assert_eq "only the command-prefix rules fire" 3 "$(count_matching "$OUT" '\[C6-colonStar\]')"
assert_contains "a leading wildcard before prefix-shaped words still fires" "$OUT" "[C6-colonStar] user Bash(* git:* push)"
assert_contains "a leading wildcard glued to a prefix still fires" "$OUT" "[C6-colonStar] user Bash(*foo:* rm -rf /)"
assert_not_contains "a leading-wildcard literal colon is not called broken" "$OUT" "PowerShell(*env:*lefthook*)"

DOUBLE=$(
  printf '%s\n' "$SURFACES"
  printf 'rule user settings allow Agent(model:*-haiku)\n'
)
OUT=$(lint "$DOUBLE")
assert_eq "the parameter-form allow draws exactly one finding" 1 "$(count_matching "$OUT" '^finding ')"
assert_contains "and it is the one that explains it correctly" "$OUT" "[C6-allowParam]"
assert_not_contains "not a command-prefix explanation for a tool with no command prefixes" "$OUT" "[C6-colonStar]"

NOT_SUPPRESSED=$(
  printf '%s\n' "$SURFACES"
  printf 'rule user settings allow Bash(git:* push)\n'
)
OUT=$(lint "$NOT_SUPPRESSED")
assert_contains "an allow-rule command prefix still fires colonStar" "$OUT" "[C6-colonStar]"

C6_AMBIG=$(
  printf '%s\n' "$SURFACES"
  cat <<'EOF'
rule user settings deny Bash(git:*push)
rule user settings deny Agent(model:*-haiku)
EOF
)
OUT=$(lint "$C6_AMBIG")
assert_eq "no-space mid-pattern on an unknown prefix warns once" 1 "$(count_matching "$OUT" '\[C6-colonStarAmbiguous\]')"
assert_contains "names the undecidability" "$OUT" "[C6-colonStarAmbiguous] user Bash(git:*push)"
assert_not_contains "documented parameter forms stay silent" "$OUT" "[C6-colonStarAmbiguous] user Agent(model:*-haiku)"

ALLOW_PARAM=$(
  printf '%s\n' "$SURFACES"
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

PARAM_CLEAN=$(
  printf '%s\n' "$SURFACES"
  cat <<'EOF'
rule user settings allow WebFetch(domain:example.com)
rule user settings allow Bash(npm:*)
rule user settings allow Bash(git:*)
EOF
)
OUT=$(lint "$PARAM_CLEAN")
assert_eq "a tool own specifier syntax never fires allowParam" 0 "$(count_matching "$OUT" '\[C6-allowParam\]')"

if command -v jq >/dev/null 2>&1; then
  WPFX="$TEST_TMPDIR/wpfx"
  mkdir -p "$WPFX/proj/.claude" "$WPFX/home/.claude" "$WPFX/pol" "$WPFX/sd/.claude"
  jq -n '{}' >"$WPFX/proj/.claude/settings.json"
  jq -n '{}' >"$WPFX/pol/managed-settings.json"
  jq -n '{permissions:{allow:["Read(C:\\Users\\alice\\**)","Read(//c/**/.env)"]}}' >"$WPFX/home/.claude/settings.json"
  E2E_WP=$(env -u CLAUDE_CONFIG_DIR HOME="$WPFX/home" \
    PERMISSION_STATE_FIXTURE_DIR="$WPFX/proj" \
    PERMISSION_STATE_STARTDIR="$WPFX/sd" \
    PERMISSION_STATE_MANAGED_PATH="$WPFX/pol/managed-settings.json" \
    PERMISSION_STATE_REGISTRY_KEYS="" \
    PERMISSION_STATE_PLIST_DOMAIN="" \
    bash "$STATE_SCRIPT" | bash "$SCRIPT")
  assert_eq "the Windows path is caught through the real reader" 1 "$(count_matching "$E2E_WP" '\[C6-winPath\]')"
  assert_contains "and it is the backslash rule, not the POSIX one" "$E2E_WP" "Read(C:\Users\alice"
else
  pass "winPath end-to-end (skipped -- jq not installed)"
fi

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

  e2e_lint() {
    env -u CLAUDE_CONFIG_DIR \
      HOME="$1/home" \
      PERMISSION_STATE_FIXTURE_DIR="$1/proj" \
      PERMISSION_STATE_STARTDIR="$1/startdir" \
      PERMISSION_STATE_MANAGED_PATH="$1/policy/managed-settings.json" \
      PERMISSION_STATE_REGISTRY_KEYS="" \
      PERMISSION_STATE_PLIST_DOMAIN="" \
      bash "$STATE_SCRIPT" | bash "$SCRIPT"
  }
  E2E=$(e2e_lint "$FX")

  assert_contains "end to end: the dead autoMode section is found" "$E2E" "[C2-autoMode] project"
  assert_contains "end to end: the dead defaultMode is found" "$E2E" "[C2-defaultMode] project"
  assert_contains "end to end: the dead plan-mode key is found" "$E2E" "[C2-planMode] project"
  assert_contains "end to end: the mistyped lock-out switch is found" "$E2E" "[C5-disableType] user"
  assert_contains "end to end: the never-consulted path rule is found" "$E2E" "[C6-uncoveredPath] project"
  assert_not_contains "end to end: the narrow allow rule is not flagged" "$E2E" "Bash(npm test)"

  FX2="$TEST_TMPDIR/fx2"
  mkdir -p "$FX2/proj/.claude" "$FX2/home/.claude" "$FX2/policy" "$FX2/startdir/.claude"
  for f in proj/.claude/settings.json proj/.claude/settings.local.json home/.claude/settings.json policy/managed-settings.json; do
    jq -n '{permissions: {defaultMode: "bypassPermissions"}}' >"$FX2/$f"
  done
  E2E_BYPASS=$(e2e_lint "$FX2")
  assert_contains "end to end: a project bypassPermissions pin is found" "$E2E_BYPASS" "[C2-defaultMode] project"
  assert_contains "end to end: a local bypassPermissions pin is found" "$E2E_BYPASS" "[C2-defaultMode] local"
  assert_eq "end to end: user and managed pins are not flagged" 0 "$(count_matching "$E2E_BYPASS" '\[C2-defaultMode\] (user|managed)')"
  assert_contains "end to end: every scope was read" "$E2E_BYPASS" "status=read"

  jq -n '{permissions: {defaultMode: "acceptEdits"}}' >"$FX2/proj/.claude/settings.json"
  jq -n '{permissions: {allow: ["Bash(ls)"], defaultMode: "plan"}}' >"$FX2/proj/.claude/settings.local.json"
  E2E_OTHER=$(e2e_lint "$FX2")
  assert_eq "end to end: acceptEdits and plan pins in project and local are not flagged" 0 "$(count_matching "$E2E_OTHER" '\[C2-defaultMode\] (project|local)')"
  assert_contains "end to end: that silence is a read plane, not an unread one" "$E2E_OTHER" "status=read"

  FX3="$TEST_TMPDIR/fx3"
  mkdir -p "$FX3/home/.claude" "$FX3/policy"
  jq -n '{autoMode: {classifyAllShell: true}, permissions: {defaultMode: "auto"}}' >"$FX3/home/.claude/settings.json"
  jq -n '{}' >"$FX3/policy/managed-settings.json"
  E2E_HOME=$(env -u CLAUDE_CONFIG_DIR \
    HOME="$FX3/home" \
    PERMISSION_STATE_FIXTURE_DIR="$FX3/home" \
    PERMISSION_STATE_STARTDIR="$FX3/home" \
    PERMISSION_STATE_MANAGED_PATH="$FX3/policy/managed-settings.json" \
    PERMISSION_STATE_REGISTRY_KEYS="" \
    PERMISSION_STATE_PLIST_DOMAIN="" \
    bash "$STATE_SCRIPT" | bash "$SCRIPT")
  assert_eq "end to end: a home-directory root raises no project C2 finding" 0 "$(count_matching "$E2E_HOME" '\[C2-[A-Za-z]+\] project')"
  assert_contains "end to end: the home-directory skip is not an unread plane" "$E2E_HOME" "status=read"
else
  pass "end-to-end reader lint (skipped — jq not installed)"
fi

UNREAD_IN=$(
  cat <<'EOF'
managed file unreadable <managed>/managed-settings.json
user settings unreadable <userhome>/.claude/settings.json
project settings invalid-json <proj>/.claude/settings.json
local settings skipped <proj>/.claude/settings.local.json
EOF
)
OUT_UNREAD=$(printf '%s\n' "$UNREAD_IN" | bash "$SCRIPT")
assert_contains "an all-unread plane reports status=incomplete" "$OUT_UNREAD" "status=incomplete"
assert_contains "and names the scopes it could not lint" "$OUT_UNREAD" "LINT-NOTE:"
assert_contains "and says the count is not a clean bill" "$OUT_UNREAD" "not a clean bill"

READ_IN=$(
  cat <<'EOF'
managed file absent <managed>/managed-settings.json
user settings present <userhome>/.claude/settings.json
project settings present <proj>/.claude/settings.json
local settings absent <proj>/.claude/settings.local.json
EOF
)
OUT_READ=$(printf '%s\n' "$READ_IN" | bash "$SCRIPT")
assert_contains "a fully-read plane reports status=read" "$OUT_READ" "status=read"
assert_not_contains "and emits no unread note" "$OUT_READ" "LINT-NOTE:"
assert_not_contains "an absent surface is not treated as unread" "$OUT_READ" "status=incomplete"

MULTI_SURFACE=$(
  cat <<'EOF'
managed file absent <managed>/managed-settings.json
managed dropin-dir absent <managed>/managed-settings.d
managed registry skipped -
managed plist not-applicable -
user settings present <userhome>/.claude/settings.json
EOF
)
OUT_MULTI=$(printf '%s\n' "$MULTI_SURFACE" | bash "$SCRIPT")
assert_contains "a skipped surface is not erased by a later surface in the same scope" "$OUT_MULTI" "status=incomplete"
assert_contains "and the note names the surface, not just the scope" "$OUT_MULTI" "registry:skipped"

REVERSED=$(
  cat <<'EOF'
managed plist not-applicable -
managed registry skipped -
user settings present <userhome>/.claude/settings.json
EOF
)
OUT_REV=$(printf '%s\n' "$REVERSED" | bash "$SCRIPT")
assert_contains "order does not change the verdict" "$OUT_REV" "status=incomplete"

ALL_ANSWERED=$(
  cat <<'EOF'
managed file absent <managed>/managed-settings.json
managed registry not-applicable -
managed plist not-applicable -
user settings present <userhome>/.claude/settings.json
EOF
)
OUT_ANSWERED=$(printf '%s\n' "$ALL_ANSWERED" | bash "$SCRIPT")
assert_contains "absent and not-applicable surfaces keep the plane read" "$OUT_ANSWERED" "status=read"
assert_not_contains "and emit no unread note" "$OUT_ANSWERED" "LINT-NOTE:"

MALFORMED=$(
  printf '%s\n' "$SURFACES"
  printf '%s\n' \
    'rule user settings deny Bash(ls) x' \
    'rule user settings deny Edit(./Finance (2024)/**)' \
    'rule user settings deny Read(./secrets/[)' \
    'rule user settings allow Read(./secrets/[)'
)
OUT=$(lint "$MALFORMED")
assert_eq "trailing text is one malformed finding" 1 "$(count_matching "$OUT" '\[C6-malformed\]')"
assert_contains "the malformed finding names the rule" "$OUT" "Bash(ls) x"
assert_eq "a path parenthesis is not malformed" 0 "$(count_matching "$OUT" 'Finance')"
assert_eq "uncompilable deny and allow each fire literal-path" 2 "$(count_matching "$OUT" '\[C6-literalPath\]')"
assert_contains "the deny guards the literal path" "$OUT" "guards that exact literal path"
assert_contains "the allow approves nothing" "$OUT" "approves nothing"

ASSIGN_STAR=$(
  printf '%s\n' "$SURFACES"
  printf '%s\n' \
    'rule user settings allow Bash(PORT=* npm run dev)' \
    'rule user settings allow Bash(CI=1 PORT=3* npm start)' \
    'rule user settings allow Bash(PORT=3000 npm run dev)' \
    'rule user settings allow Bash(PORT=4000 npm *)' \
    'rule user settings allow Bash(npm run dev --port=*)' \
    'rule user settings allow Bash(NODE_ENV*)' \
    'rule user settings allow Bash(NODE_ENV=production:*)' \
    'rule user settings allow Bash(PORT=3*:*)' \
    'rule user settings deny Bash(PORT=* rm *)' \
    'rule user settings allow PowerShell(X=* Get-Item)'
)
OUT=$(lint "$ASSIGN_STAR")
assert_eq "a wildcard in a leading assignment of a Bash allow fires" 3 "$(count_matching "$OUT" '\[C6-assignStar\]')"
assert_contains "the first assignment's wildcard fires" "$OUT" "[C6-assignStar] user Bash(PORT=* npm run dev)"
assert_contains "a wildcard in a later leading assignment fires" "$OUT" "[C6-assignStar] user Bash(CI=1 PORT=3* npm start)"
assert_not_contains "a trailing :* prefix is not a wildcard in the value" "$OUT" "[C6-assignStar] user Bash(NODE_ENV=production:*)"
assert_contains "a wildcard in the value before a trailing :* still fires" "$OUT" "[C6-assignStar] user Bash(PORT=3*:*)"
assert_contains "the finding names the startup warning's version" "$OUT" "v2.1.323"
assert_not_contains "a literal assignment value is silent" "$OUT" "PORT=3000"
assert_not_contains "a wildcard after a literal assignment is silent" "$OUT" "PORT=4000"
assert_not_contains "an = after the command name is not an assignment" "$OUT" "--port=*"
assert_not_contains "a variable name with no assignment is silent" "$OUT" "NODE_ENV*"
assert_not_contains "a deny rule is silent" "$OUT" "rm *"
assert_not_contains "a PowerShell rule is silent" "$OUT" "Get-Item"

report_and_exit
