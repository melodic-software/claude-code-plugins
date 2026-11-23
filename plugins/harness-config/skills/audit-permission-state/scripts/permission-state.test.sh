#!/usr/bin/env bash
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$SCRIPT_DIR/permission-state.sh"

TEST_TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TEST_TMPDIR"' EXIT

# shellcheck source=test-helpers.sh
source "$SCRIPT_DIR/test-helpers.sh"

# The fixture cases expect the local file at the fixture's repository root. On
# Windows the reader anchors it on the start directory instead, so the suite pins
# a non-Windows platform through the reader's seam, and the Windows-branch cases
# (Case 14) set PERMISSION_STATE_OSTYPE per call.
export PERMISSION_STATE_OSTYPE=linux-gnu

if ! command -v jq >/dev/null 2>&1; then
  echo "SKIP: jq not installed" >&2
  exit 0
fi

FX="$TEST_TMPDIR/fx"
mkdir -p "$FX/proj/.claude" "$FX/home/.claude" "$FX/policy/managed-settings.d" "$FX/startdir/.claude"
jq -n '{permissions:{allow:["Bash(git status)"],deny:["WebFetch"]}}' >"$FX/proj/.claude/settings.json"
jq -n '{permissions:{allow:["Bash(npm test)"]}}' >"$FX/proj/.claude/settings.local.json"
jq -n '{permissions:{allow:["Bash(python*)"]}}' >"$FX/home/.claude/settings.json"
jq -n '{permissions:{deny:["Read(./.env)"]}}' >"$FX/policy/managed-settings.json"
jq -n '{permissions:{ask:["Bash(rm *)"]}}' >"$FX/policy/managed-settings.d/20-second.json"
jq -n '{permissions:{ask:["Bash(dd *)"]}}' >"$FX/policy/managed-settings.d/10-first.json"
jq -n '{permissions:{allow:["Bash(ls)"]}}' >"$FX/policy/managed-settings.d/.hidden.json"
jq -n '{permissions:{allow:["Bash(ls)"]}}' >"$FX/startdir/.claude/settings.local.json"

run() {
  env -u CLAUDE_CONFIG_DIR -u CLAUDE_CODE_REMOTE \
    ${TEST_CLOUD_REMOTE:+CLAUDE_CODE_REMOTE="$TEST_CLOUD_REMOTE"} \
    HOME="$FX/home" \
    PERMISSION_STATE_FIXTURE_DIR="$FX/proj" \
    PERMISSION_STATE_STARTDIR="$FX/startdir" \
    PERMISSION_STATE_MANAGED_PATH="$FX/policy/managed-settings.json" \
    PERMISSION_STATE_REGISTRY_KEYS="${STUB_REGISTRY_KEYS:-}" \
    PERMISSION_STATE_PLIST_DOMAIN="${STUB_PLIST_DOMAIN:-}" \
    bash "$SCRIPT" "$@"
}

run_tree() {
  env -u CLAUDE_CONFIG_DIR HOME="$1/home" \
    PERMISSION_STATE_FIXTURE_DIR="$1/proj" \
    PERMISSION_STATE_STARTDIR="$1/sd" \
    PERMISSION_STATE_MANAGED_PATH="$1/pol/managed-settings.json" \
    PERMISSION_STATE_REGISTRY_KEYS="" \
    PERMISSION_STATE_PLIST_DOMAIN="" \
    bash "$SCRIPT"
}

rc=0
OUT=$(bash "$SCRIPT" --help) || rc=$?
assert_exit "--help exits 0" 0 "$rc"
assert_contains "--help prints usage" "$OUT" "Usage:"

rc=0
OUT=$(run) || rc=$?
assert_exit "full run exits 0" 0 "$rc"
assert_eq "user scope appears exactly once" "1" "$(count_matching "$OUT" '^user ')"
assert_eq "project settings surface appears exactly once" "1" "$(count_matching "$OUT" '^project settings ')"
assert_eq "project toplevel surface appears exactly once" "1" "$(count_matching "$OUT" '^project toplevel ')"
assert_eq "local scope appears exactly once" "1" "$(count_matching "$OUT" '^local ')"
assert_eq "start-directory scope appears exactly once" "1" "$(count_matching "$OUT" '^startdir-local ')"

assert_eq "managed base file surface" "1" "$(count_matching "$OUT" '^managed file ')"
assert_eq "managed drop-in directory surface" "1" "$(count_matching "$OUT" '^managed dropin-dir ')"
assert_eq "managed registry surface" "1" "$(count_matching "$OUT" '^managed registry ')"
assert_eq "managed preferences-domain surface" "1" "$(count_matching "$OUT" '^managed plist ')"

assert_contains "managed deny rule" "$OUT" "rule managed file deny Read(./.env)"
assert_contains "user allow rule" "$OUT" "rule user settings allow Bash(python*)"
assert_contains "project allow rule" "$OUT" "rule project settings allow Bash(git status)"
assert_contains "project deny rule" "$OUT" "rule project settings deny WebFetch"
assert_contains "local allow rule" "$OUT" "rule local settings allow Bash(npm test)"
assert_contains "start-directory allow rule" "$OUT" "rule startdir-local settings allow Bash(ls)"

dropins=$(printf '%s\n' "$OUT" | grep -oE '^managed dropin-file:[^ ]+' | sed 's/^managed dropin-file://')
assert_eq "drop-ins emitted in alphabetical order" "$(printf '10-first.json\n20-second.json')" "$dropins"
assert_not_contains "hidden drop-in ignored" "$OUT" ".hidden.json"

OUT_SCOPES=$(run --scopes)
assert_eq "no rule records under --scopes" "0" "$(count_matching "$OUT_SCOPES" '^rule ')"
assert_eq "surface records survive --scopes" "1" "$(count_matching "$OUT_SCOPES" '^managed file ')"

assert_contains "server-managed settings disclosed" "$OUT" "Server-managed settings"
assert_contains "managed-policy diagnosis routes to /status" "$OUT" "Organization policy"

BAD="$TEST_TMPDIR/bad"
mkdir -p "$BAD/proj/.claude" "$BAD/home/.claude" "$BAD/sd"
printf '{invalid\n' >"$BAD/proj/.claude/settings.json"
OUT_BAD=$(run_tree "$BAD")
assert_contains "malformed settings reported as invalid-json" "$OUT_BAD" "project settings invalid-json"
assert_contains "missing settings reported as absent" "$OUT_BAD" "user settings absent"
assert_contains "missing managed file reported as absent" "$OUT_BAD" "managed file absent"
assert_eq "a malformed file contributes no rules" "0" "$(count_matching "$OUT_BAD" '^rule project ')"

SHAPE="$TEST_TMPDIR/shape"
mkdir -p "$SHAPE/proj/.claude" "$SHAPE/home/.claude" "$SHAPE/pol" "$SHAPE/sd/.claude"
jq -n '{}' >"$SHAPE/pol/managed-settings.json"
printf '["Bash(danger)"]\n' >"$SHAPE/proj/.claude/settings.json"
printf '{"permissions":{"allow":"Bash(*)","deny":{"x":"y"}}}\n' >"$SHAPE/home/.claude/settings.json"
OUT_SHAPE=$(run_tree "$SHAPE")
assert_contains "a top-level array is invalid-json, not present" "$OUT_SHAPE" "project settings invalid-json"
assert_contains "a string-valued permissions key is invalid-json too" "$OUT_SHAPE" "user settings invalid-json"
assert_eq "and neither contributes rules" 0 "$(count_matching "$OUT_SHAPE" '^rule (user|project) ')"

printf '{}\n' >"$SHAPE/proj/.claude/settings.json"
printf '{"permissions":null}\n' >"$SHAPE/home/.claude/settings.json"
OUT_OKSHAPE=$(run_tree "$SHAPE")
assert_contains "an empty object is present" "$OUT_OKSHAPE" "project settings present"
assert_contains "a null permissions key is present" "$OUT_OKSHAPE" "user settings present"

printf '{"permissions":{}}\n' >"$SHAPE/pol/managed-settings.json"
printf '{"permissions":{"defaultMode":"bypassPermissions"}}\n' >"$SHAPE/proj/.claude/settings.json"
printf '{"permissions":{"allow":["Bash(ls)"],"defaultMode":"acceptEdits"}}\n' >"$SHAPE/home/.claude/settings.json"
OUT_SCALAR=$(run_tree "$SHAPE")
assert_contains "a permissions object holding only a string key is present" "$OUT_SCALAR" "project settings present"
assert_contains "a string key after the rule lists is present" "$OUT_SCALAR" "user settings present"
assert_contains "an empty permissions object is present" "$OUT_SCALAR" "managed file present"
assert_contains "the string-only file's defaultMode is read" "$OUT_SCALAR" 'conf project settings defaultMode "bypassPermissions"'
assert_contains "rules before a trailing string key still count" "$OUT_SCALAR" "rule user settings allow Bash(ls)"

printf '{"permissions":{"deny":"Bash(x)","defaultMode":"plan"}}\n' >"$SHAPE/home/.claude/settings.json"
OUT_SCALAR_BAD=$(run_tree "$SHAPE")
assert_contains "a string rule list is invalid-json whatever follows it" "$OUT_SCALAR_BAD" "user settings invalid-json"

printf '{"permissions":{"defaultMode":{}},"disableAutoMode":true}\n' >"$SHAPE/home/.claude/settings.json"
OUT_SCALAR_OBJ=$(run_tree "$SHAPE")
assert_contains "an object defaultMode leaves the file present" "$OUT_SCALAR_OBJ" "user settings present"
assert_contains "and its mistyped disableAutoMode is still read" "$OUT_SCALAR_OBJ" "conf user settings disableAutoMode true"

for entry in '"x"' '[1]' '7'; do
  printf '{"allowManagedPermissionRulesOnly":true,"pluginConfigs":{"cc-plugin-sec-default@builtin":%s}}\n' "$entry" >"$SHAPE/pol/managed-settings.json"
  OUT_GUARD_SHAPE=$(run_tree "$SHAPE")
  assert_contains "a $entry guard entry keeps the managed lock record" "$OUT_GUARD_SHAPE" "conf managed file allowManagedPermissionRulesOnly true"
  assert_not_contains "a $entry guard entry yields no override record" "$OUT_GUARD_SHAPE" "modsOverrideDenyRules"
done

OUT_SAME=$(env -u CLAUDE_CONFIG_DIR HOME="$FX/home" \
  PERMISSION_STATE_FIXTURE_DIR="$FX/proj" \
  PERMISSION_STATE_STARTDIR="$FX/proj" \
  PERMISSION_STATE_MANAGED_PATH="$FX/policy/managed-settings.json" \
  PERMISSION_STATE_REGISTRY_KEYS="" PERMISSION_STATE_PLIST_DOMAIN="" \
  bash "$SCRIPT")
assert_contains "same directory reported not-applicable" "$OUT_SAME" "startdir-local settings not-applicable"
assert_eq "its rules are not counted twice" "1" "$(count_matching "$OUT_SAME" '^rule local settings allow Bash\(npm test\)')"

OUT_NOHOME=$(env -u CLAUDE_CONFIG_DIR -u HOME \
  PERMISSION_STATE_FIXTURE_DIR="$FX/proj" \
  PERMISSION_STATE_STARTDIR="$FX/startdir" \
  PERMISSION_STATE_MANAGED_PATH="$FX/policy/managed-settings.json" \
  PERMISSION_STATE_REGISTRY_KEYS="" PERMISSION_STATE_PLIST_DOMAIN="" \
  bash "$SCRIPT")
assert_contains "unresolvable user scope is skipped, not absent" "$OUT_NOHOME" "user settings skipped"
assert_contains "and says why" "$OUT_NOHOME" "neither CLAUDE_CONFIG_DIR nor HOME"

STUB="$TEST_TMPDIR/stub-path"
make_stub_path "$STUB" jq git tr find sort sed head grep cat mktemp rm
rc=0
ADMIN_POLICY_KEY='HKLM\SOFTWARE\Policies\ClaudeCode' # portability-ok: a Windows registry key path, passed through as a literal; no regex engine sees it
OUT_NOREG=$(env -u CLAUDE_CONFIG_DIR PATH="$STUB" HOME="$FX/home" \
  PERMISSION_STATE_FIXTURE_DIR="$FX/proj" \
  PERMISSION_STATE_STARTDIR="$FX/startdir" \
  PERMISSION_STATE_MANAGED_PATH="$FX/policy/managed-settings.json" \
  PERMISSION_STATE_REGISTRY_KEYS="$ADMIN_POLICY_KEY" \
  PERMISSION_STATE_PLIST_DOMAIN="" \
  "$real_bash" "$SCRIPT" 2>&1) || rc=$?
assert_exit "missing optional tool does not fail the run" 0 "$rc"
assert_contains "registry surface marked skipped" "$OUT_NOREG" "managed registry skipped"
assert_contains "and the skip is announced" "$OUT_NOREG" "'reg' is not on PATH"
assert_contains "portable core still read: base file" "$OUT_NOREG" "managed file present"
assert_contains "portable core still read: drop-in dir" "$OUT_NOREG" "managed dropin-dir present"
assert_contains "other scopes unaffected" "$OUT_NOREG" "rule user settings allow Bash(python*)"

if command -v reg >/dev/null 2>&1; then
  EXISTING_KEY='HKCU\SOFTWARE'                           # portability-ok: a Windows registry key path, not a regex
  ABSENT_KEY='HKCU\SOFTWARE\ClaudeCodeNoSuchKeyExists'   # portability-ok: a Windows registry key path, not a regex
  SECOND_ABSENT_KEY='HKCU\SOFTWARE\ClaudeCodeAlsoAbsent' # portability-ok: a Windows registry key path, not a regex
  ABSENT_THEN_PRESENT_KEYS="$ABSENT_KEY
$EXISTING_KEY"
  BOTH_ABSENT_KEYS="$ABSENT_KEY
$SECOND_ABSENT_KEY"

  OUT_REG=$(env -u CLAUDE_CONFIG_DIR HOME="$FX/home" \
    PERMISSION_STATE_FIXTURE_DIR="$FX/proj" \
    PERMISSION_STATE_STARTDIR="$FX/startdir" \
    PERMISSION_STATE_MANAGED_PATH="$FX/policy/managed-settings.json" \
    PERMISSION_STATE_REGISTRY_KEYS="$ABSENT_THEN_PRESENT_KEYS" \
    PERMISSION_STATE_PLIST_DOMAIN="" \
    bash "$SCRIPT")
  assert_contains "an absent key is skipped, the existing one is selected" "$OUT_REG" "managed registry unreadable $EXISTING_KEY"
  assert_contains "a key with no readable value is not a license to fall through" "$OUT_REG" "Lower-priority policy keys are NOT consulted"
  assert_eq "no rules are claimed from an unreadable key" "0" "$(count_matching "$OUT_REG" '^rule managed registry ')"

  OUT_REG_NONE=$(env -u CLAUDE_CONFIG_DIR HOME="$FX/home" \
    PERMISSION_STATE_FIXTURE_DIR="$FX/proj" \
    PERMISSION_STATE_STARTDIR="$FX/startdir" \
    PERMISSION_STATE_MANAGED_PATH="$FX/policy/managed-settings.json" \
    PERMISSION_STATE_REGISTRY_KEYS="$BOTH_ABSENT_KEYS" \
    PERMISSION_STATE_PLIST_DOMAIN="" \
    bash "$SCRIPT")
  assert_contains "no policy keys at all reports absent" "$OUT_REG_NONE" "managed registry absent"
else
  pass "registry key selection (skipped — reg not on PATH)"
  pass "registry absence reporting (skipped — reg not on PATH)"
fi

NLFX="$TEST_TMPDIR/nlfx"
mkdir -p "$NLFX/proj/.claude" "$NLFX/home/.claude" "$NLFX/pol" "$NLFX/sd/.claude"
jq -n '{}' >"$NLFX/proj/.claude/settings.json"
jq -n '{}' >"$NLFX/pol/managed-settings.json"
jq -n '{permissions:{allow:["Bash(echo hi\nthere *)","Bash(npm test)"]}}' >"$NLFX/home/.claude/settings.json"
OUT_NL=$(run_tree "$NLFX")
assert_eq "the multi-line rule yields no rule record" 0 "$(count_matching "$OUT_NL" '^rule user settings allow Bash\(echo')"
assert_eq "and no fragment record either" 0 "$(count_matching "$OUT_NL" '^rule user settings allow there')"
assert_contains "it is reported as unrepresentable" "$OUT_NL" "cannot be represented as one record"
assert_contains "with the rule text rendered on one line" "$OUT_NL" "Bash(echo hi there *)"
assert_contains "the well-formed sibling rule is unaffected" "$OUT_NL" "rule user settings allow Bash(npm test)"

CRFX="$TEST_TMPDIR/crfx"
mkdir -p "$CRFX/proj/.claude" "$CRFX/home/.claude" "$CRFX/pol" "$CRFX/sd/.claude"
jq -n '{}' >"$CRFX/proj/.claude/settings.json"
jq -n '{}' >"$CRFX/pol/managed-settings.json"
jq -n '{permissions:{allow:["Bash(a\rb *)","Bash(npm test)"]}}' >"$CRFX/home/.claude/settings.json"
OUT_CR=$(run_tree "$CRFX")
assert_eq "a CR-carrying rule yields no rule record" 0 "$(count_matching "$OUT_CR" '^rule user settings allow Bash.a')"
assert_contains "it is reported rather than silently stripped" "$OUT_CR" "carriage return"
assert_contains "the sibling rule is unaffected by the CR case" "$OUT_CR" "rule user settings allow Bash(npm test)"

empty_path_dir="$TEST_TMPDIR/empty-path"
mkdir -p "$empty_path_dir"
rc=0
err_out=$(PATH="$empty_path_dir" "$real_bash" "$SCRIPT" 2>&1) || rc=$?
assert_exit "exit 2 when jq missing" 2 "$rc"
assert_contains "jq required message" "$err_out" "jq required"

apt_path_dir="$TEST_TMPDIR/apt-path"
mkdir -p "$apt_path_dir"
printf '#!%s\nexit 0\n' "$real_bash" >"$apt_path_dir/apt-get"
chmod +x "$apt_path_dir/apt-get"
nojq() { (
  unset CLAUDE_PLUGIN_ROOT
  PATH="$1" PERMISSION_STATE_OSTYPE="$2" "$real_bash" "$SCRIPT" 2>&1
); }
rc=0
err_out=$(nojq "$apt_path_dir" linux-gnu) || rc=$?
assert_exit "exit 2 when jq missing on an apt host" 2 "$rc"
assert_contains "an apt host is told the apt-get command" "$err_out" "Install it: sudo apt-get install jq"
assert_contains "the stop points at the prerequisites check" "$err_out" "/harness-ops:prerequisites"
assert_contains "macOS is told the brew command" "$(nojq "$empty_path_dir" darwin23)" "Install it: brew install jq"
assert_contains "Windows is told the winget command" "$(nojq "$empty_path_dir" msys)" "Install it: winget install jqlang.jq"
err_out=$(nojq "$empty_path_dir" linux-gnu)
assert_not_contains "no package manager found: no guessed command" "$err_out" "Install it:"
assert_contains "no package manager found: the download page instead" "$err_out" "https://jqlang.org/download/"

# --- Case 14: all four documented local-file exceptions -----------------------
# The documented list is "outside a git repository, when the repository root is
# your home directory, on Windows, or when the repository root or its .git or
# .claude entry isn't owned by your user". Two of the four used to be resolved;
# a native-Windows machine therefore had its local file reported absent while it
# was live beside settings.json.
OUT_DEFAULT=$(run)
assert_contains "the default anchor is the repository root" "$OUT_DEFAULT" "anchored on the repository root"

OUT_WIN=$(PERMISSION_STATE_OSTYPE=msys run)
assert_contains "on Windows the file stays in the start directory" "$OUT_WIN" "start directory (on Windows)"
OUT_CYG=$(PERMISSION_STATE_OSTYPE=cygwin run)
assert_contains "the cygwin OSTYPE takes the same branch" "$OUT_CYG" "start directory (on Windows)"
OUT_LINUX=$(PERMISSION_STATE_OSTYPE=linux-gnu run)
assert_contains "a non-Windows OSTYPE keeps the repository-root anchor" "$OUT_LINUX" "anchored on the repository root"

OUT_OWNED=$(PERMISSION_STATE_OWNER_OVERRIDE=foreign run)
assert_contains "a foreign-owned repository root moves the anchor" "$OUT_OWNED" "not owned by this user"
OUT_SELF=$(PERMISSION_STATE_OWNER_OVERRIDE=self run)
assert_contains "a self-owned root keeps the repository-root anchor" "$OUT_SELF" "anchored on the repository root"

assert_contains "the SDK caveat names resolveSettings()" "$OUT_DEFAULT" "resolveSettings()"
assert_not_contains "it does not claim to describe a session class" "$OUT_DEFAULT" "In an Agent SDK session"

OUT_CLOUD=$(TEST_CLOUD_REMOTE=true run)
assert_contains "a cloud session says which scopes it does not read" "$OUT_CLOUD" "CLAUDE_CODE_REMOTE=true"
assert_contains "and that the user scope shown is not the operator's" "$OUT_CLOUD" "not yours"
OUT_LOCAL_SESSION=$(run)
assert_not_contains "a local session emits no cloud note" "$OUT_LOCAL_SESSION" "CLAUDE_CODE_REMOTE=true"

HOMEFX="$TEST_TMPDIR/homefx"
mkdir -p "$HOMEFX/home/.claude" "$HOMEFX/pol"
jq -n '{}' >"$HOMEFX/pol/managed-settings.json"
jq -n '{autoMode:{classifyAllShell:true},permissions:{defaultMode:"auto",allow:["Bash(ls)"]}}' >"$HOMEFX/home/.claude/settings.json"
home_root() {
  env -u CLAUDE_CONFIG_DIR -u CLAUDE_CODE_REMOTE "$@" \
    PERMISSION_STATE_FIXTURE_DIR="$HOMEFX/home" \
    PERMISSION_STATE_STARTDIR="$HOMEFX/home" \
    PERMISSION_STATE_MANAGED_PATH="$HOMEFX/pol/managed-settings.json" \
    PERMISSION_STATE_REGISTRY_KEYS="" PERMISSION_STATE_PLIST_DOMAIN="" \
    bash "$SCRIPT"
}
OUT_HOME=$(home_root HOME="$HOMEFX/home")
assert_contains "the user file is reported under user" "$OUT_HOME" "user settings present $HOMEFX/home/.claude/settings.json"
assert_eq "the user file is reported once" 1 "$(count_matching "$OUT_HOME" " present $HOMEFX/home/\.claude/settings\.json$")"
assert_contains "the project scope is not applicable" "$OUT_HOME" "project settings not-applicable $HOMEFX/home/.claude/settings.json"
assert_contains "and the skip names its reason" "$OUT_HOME" "project scope skipped: $HOMEFX/home/.claude/settings.json is the user settings file"
assert_eq "no project rule records" 0 "$(count_matching "$OUT_HOME" '^rule project ')"
assert_eq "no project conf records" 0 "$(count_matching "$OUT_HOME" '^conf project ')"
assert_contains "the user rules are still read" "$OUT_HOME" "rule user settings allow Bash(ls)"

OUT_CFG=$(home_root HOME="$TEST_TMPDIR/nohome" CLAUDE_CONFIG_DIR="$HOMEFX/pol/../home/.claude")
assert_contains "a differently spelled CLAUDE_CONFIG_DIR is the same file" "$OUT_CFG" "project settings not-applicable"
assert_eq "and its file is reported once" 1 "$(count_matching "$OUT_CFG" ' present .*/home/\.claude/settings\.json$')"

report_and_exit
