#!/usr/bin/env bash
# Regression tests for permission-merge.sh (self-contained — ships with the plugin).
#
# Most cases feed hand-written scope records on stdin, so they exercise the merge
# without touching any settings file anywhere. The one end-to-end case pipes the
# real reader through the merge against a fully fixtured tree — project root,
# start directory, managed policy and user home all inside a temp directory, with
# CLAUDE_CONFIG_DIR unset. No test reads the operator's real ~/.claude.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$SCRIPT_DIR/permission-merge.sh"
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

merge() { printf '%s\n' "$1" | bash "$SCRIPT" --merge-only; }

# --- Case 1: a rule in two KINDS has exactly one winner -----------------------
# The only election this script makes. "if user settings allow a permission and
# project settings deny it, the deny rule blocks it."
CROSS_KIND=$(
  cat <<'EOF'
user settings present /home/.claude/settings.json
project settings present /proj/.claude/settings.json
rule user settings allow Bash(git status)
rule project settings deny Bash(git status)
EOF
)
OUT=$(merge "$CROSS_KIND")
assert_eq "cross-kind contest yields exactly one effective record" 1 "$(count_matching "$OUT" '^effective .*Bash\(git status\)$')"
assert_contains "the deny wins" "$OUT" "effective deny scopes=project precedence_basis=evaluation-order Bash(git status)"
assert_contains "the beaten allow is reported inert" "$OUT" "inert allow scopes=user outranked_by=deny Bash(git status)"

# The reverse direction is documented just as explicitly and is the one a
# scope-ranked implementation would get wrong: user is the LOWEST scope, and its
# deny still blocks a project allow.
REVERSE=$(
  cat <<'EOF'
user settings present /home/.claude/settings.json
project settings present /proj/.claude/settings.json
rule user settings deny Bash(git push)
rule project settings allow Bash(git push)
EOF
)
OUT=$(merge "$REVERSE")
assert_contains "a user-level deny blocks a project-level allow" "$OUT" "effective deny scopes=user precedence_basis=evaluation-order Bash(git push)"
assert_contains "the project allow is inert, not the winner" "$OUT" "inert allow scopes=project outranked_by=deny Bash(git push)"

# ask beats allow by the same mechanic.
ASK=$(
  cat <<'EOF'
user settings present /home/.claude/settings.json
project settings present /proj/.claude/settings.json
rule user settings allow WebFetch
rule project settings ask WebFetch
EOF
)
OUT=$(merge "$ASK")
assert_contains "ask outranks allow" "$OUT" "effective ask scopes=project precedence_basis=evaluation-order WebFetch"
assert_contains "the allow beneath an ask is inert" "$OUT" "inert allow scopes=user outranked_by=ask WebFetch"

# --- Case 2: the same rule in the same KIND at two scopes elects NOTHING ------
# "Permission rules behave differently because they merge across scopes rather
# than override." Naming one scope the origin here would be a precedence claim
# no documented mechanic supports, so both contributors are carried instead.
SAME_KIND=$(
  cat <<'EOF'
managed file present /policy/managed-settings.json
user settings present /home/.claude/settings.json
project settings present /proj/.claude/settings.json
rule managed file deny Read(./.env)
rule user settings deny Read(./.env)
rule project settings deny Read(./.env)
EOF
)
OUT=$(merge "$SAME_KIND")
assert_eq "same-kind duplication yields one effective record" 1 "$(count_matching "$OUT" '^effective .*Read')"
assert_contains "every contributing scope is named" "$OUT" "effective deny scopes=managed,user,project precedence_basis=merged-across-scopes Read(./.env)"
assert_not_contains "nothing is reported as beaten when nothing lost" "$OUT" "inert"

# Both mechanics at once stay both, rather than one silently swallowing the other.
BOTH=$(
  cat <<'EOF'
user settings present /home/.claude/settings.json
project settings present /proj/.claude/settings.json
rule user settings deny Bash(curl *)
rule project settings deny Bash(curl *)
rule project settings allow Bash(curl *)
EOF
)
OUT=$(merge "$BOTH")
assert_contains "both mechanics are cited when both applied" "$OUT" "precedence_basis=evaluation-order+merged-across-scopes"

# --- Case 2b: a whole-tool rule reaches every call of that tool ---------------
# Decidable with no pattern matcher: the tool token is the text before the first
# "(", and a rule that IS its own token names the whole tool. Reporting a scoped
# allow as effective under a bare deny would claim access to a tool that is no
# longer in the model context at all.
BARE=$(
  cat <<'EOF'
managed file present /policy/managed-settings.json
user settings present /home/.claude/settings.json
rule managed file deny Bash
rule user settings allow Bash(git status)
rule user settings deny Bash(rm *)
EOF
)
OUT=$(merge "$BARE")
assert_contains "the bare deny itself is effective" "$OUT" "effective deny scopes=managed precedence_basis=uncontested Bash"
assert_contains "a scoped allow under a bare deny is inert" "$OUT" "inert allow scopes=user removed_by=deny@Bash Bash(git status)"
assert_contains "a scoped deny under a bare deny is moot too" "$OUT" "inert deny scopes=user removed_by=deny@Bash Bash(rm *)"
assert_eq "removal leaves exactly one effective record for the tool" 1 "$(count_matching "$OUT" '^effective .*Bash')"
assert_contains "removal is announced, not just implied" "$OUT" "removes Bash from the model context entirely"

# EndConversation is the documented exception: a deny rule cannot remove it while
# any other tool remains, so its scoped rules stay live.
END_CONV=$(
  cat <<'EOF'
managed file present /policy/managed-settings.json
user settings present /home/.claude/settings.json
rule managed file deny EndConversation
rule user settings allow EndConversation(x)
EOF
)
OUT=$(merge "$END_CONV")
assert_not_contains "EndConversation is exempt from bare-name removal" "$OUT" "removed_by"
assert_contains "its scoped rule stays effective" "$OUT" "effective allow scopes=user precedence_basis=uncontested EndConversation(x)"

# A whole-tool ask prompts for every call, so no scoped allow for that tool can
# take effect — the ask/allow half of the same mechanic.
BARE_ASK=$(
  cat <<'EOF'
user settings present /home/.claude/settings.json
project settings present /proj/.claude/settings.json
rule user settings ask WebFetch
rule project settings allow WebFetch(domain:example.com)
EOF
)
OUT=$(merge "$BARE_ASK")
assert_contains "a scoped allow under a whole-tool ask is inert" "$OUT" "inert allow scopes=project outranked_by=ask@WebFetch WebFetch(domain:example.com)"
assert_eq "and it is not also reported effective" 0 "$(count_matching "$OUT" '^effective .*WebFetch\(')"

# --- Case 3: no merged rule ships without a basis -----------------------------
MIXED=$(
  cat <<'EOF'
managed file present /policy/managed-settings.json
user settings present /home/.claude/settings.json
project settings present /proj/.claude/settings.json
rule managed file deny Read(./.env)
rule user settings allow Bash(git status)
rule project settings deny Bash(git status)
rule user settings allow Bash(npm test)
rule project settings allow Bash(npm test)
rule project settings ask Bash(rm *)
EOF
)
OUT=$(merge "$MIXED")
assert_eq "every effective record carries a precedence_basis" \
  "$(count_matching "$OUT" '^effective ')" "$(count_matching "$OUT" '^effective .* precedence_basis=')"
assert_eq "four distinct rule texts, four effective records" 4 "$(count_matching "$OUT" '^effective ')"
assert_not_contains "inert records never carry a basis they did not earn" \
  "$(printf '%s\n' "$OUT" | grep '^inert ')" "precedence_basis"

# --- Case 4: two managed surfaces are one contributing scope ------------------
# The drop-in files and the base file are separate surfaces at the same scope;
# listing "managed" twice would read as two independent sources agreeing.
DUP_SURFACE=$(
  cat <<'EOF'
managed file present /policy/managed-settings.json
managed dropin-file:10-first.json present /policy/managed-settings.d/10-first.json
rule managed file deny Read(./.env)
rule managed dropin-file:10-first.json deny Read(./.env)
EOF
)
OUT=$(merge "$DUP_SURFACE")
assert_contains "one scope, however many of its surfaces carry the rule" "$OUT" "scopes=managed precedence_basis=uncontested Read(./.env)"

# --- Case 5: rule text containing spaces survives intact ----------------------
SPACED=$(
  cat <<'EOF'
user settings present /home/.claude/settings.json
rule user settings allow Bash(git commit -m *)
EOF
)
OUT=$(merge "$SPACED")
assert_contains "spaces inside a rule are preserved" "$OUT" "precedence_basis=uncontested Bash(git commit -m *)"

# --- Case 6: unread surfaces bound the claim; empty ones do not ---------------
STATUSES=$(
  cat <<'EOF'
managed registry skipped -
managed plist not-applicable -
user settings absent /home/.claude/settings.json
project settings invalid-json /proj/.claude/settings.json
local settings unreadable /proj/.claude/settings.local.json
startdir-local settings not-applicable /start/.claude/settings.local.json
EOF
)
OUT=$(merge "$STATUSES")
assert_eq "one caveat per surface that could not be read" 3 "$(count_matching "$OUT" '^CAVEAT: .*could not be read')"
assert_contains "a skipped surface is named" "$OUT" "managed registry (skipped)"
assert_contains "invalid JSON is not an empty scope" "$OUT" "project settings (invalid-json)"
assert_not_contains "an absent scope raises no caveat" "$OUT" "user settings (absent)"
assert_not_contains "a not-applicable scope raises no caveat" "$OUT" "not-applicable"

# --- Case 7: the two standing bounds are always stated ------------------------
OUT=$(merge "$MIXED")
assert_contains "the invisible command-line scope is stated" "$OUT" "CAVEAT: the command-line scope"
assert_contains "the exact-text limitation states its error direction" "$OUT" "over-reporting allow"

# --- Case 8: no scope records is an error, never an empty merge ---------------
# A reader that died and a machine with no settings must not look the same.
rc=0
err_out=$(printf '' | bash "$SCRIPT" --merge-only 2>&1) || rc=$?
assert_exit "exit 2 on empty input" 2 "$rc"
assert_contains "the empty-input error says why" "$err_out" "no scope records on input"

rc=0
printf 'NOTE: a note and nothing else\n' | bash "$SCRIPT" >/dev/null 2>&1 || rc=$?
assert_exit "notes alone are not scope records" 2 "$rc"

rc=0
err_out=$(bash "$SCRIPT" --bogus </dev/null 2>&1) || rc=$?
assert_exit "exit 2 on an unknown argument" 2 "$rc"
assert_contains "the unknown argument is named" "$err_out" "unknown argument"

rc=0
help_out=$(bash "$SCRIPT" --help </dev/null 2>&1) || rc=$?
assert_exit "--help exits 0" 0 "$rc"
assert_contains "--help documents the merge-only mode" "$help_out" "--merge-only"

# --- Case 9: pass-through is the default, and is suppressible -----------------
PASS_IN=$(
  cat <<'EOF'
user settings present /home/.claude/settings.json
NOTE: something the operator must know
rule user settings allow Bash(ls)
EOF
)
OUT=$(printf '%s\n' "$PASS_IN" | bash "$SCRIPT")
assert_contains "the reader's surface records pass through" "$OUT" "user settings present"
assert_contains "the reader's notes pass through" "$OUT" "NOTE: something the operator must know"
assert_contains "the merge section follows them" "$OUT" "effective allow scopes=user"
OUT=$(merge "$PASS_IN")
assert_not_contains "--merge-only drops the input records" "$OUT" "NOTE: something the operator"

# --- Case 10: end to end, real reader into the merge --------------------------
if command -v jq >/dev/null 2>&1; then
  FX="$TEST_TMPDIR/fx"
  mkdir -p "$FX/proj/.claude" "$FX/home/.claude" "$FX/policy/managed-settings.d" "$FX/startdir/.claude"
  jq -n '{permissions:{allow:["Bash(git status)"],deny:["WebFetch"]}}' >"$FX/proj/.claude/settings.json"
  jq -n '{permissions:{allow:["Bash(npm test)"]}}' >"$FX/proj/.claude/settings.local.json"
  jq -n '{permissions:{allow:["Bash(npm test)","WebFetch"]}}' >"$FX/home/.claude/settings.json"
  jq -n '{permissions:{deny:["Read(./.env)"]}}' >"$FX/policy/managed-settings.json"
  jq -n '{permissions:{allow:["Bash(ls)"]}}' >"$FX/startdir/.claude/settings.local.json"

  E2E=$(env -u CLAUDE_CONFIG_DIR \
    HOME="$FX/home" \
    PERMISSION_STATE_FIXTURE_DIR="$FX/proj" \
    PERMISSION_STATE_STARTDIR="$FX/startdir" \
    PERMISSION_STATE_MANAGED_PATH="$FX/policy/managed-settings.json" \
    PERMISSION_STATE_REGISTRY_KEYS="" \
    PERMISSION_STATE_PLIST_DOMAIN="" \
    bash "$STATE_SCRIPT" | bash "$SCRIPT" --merge-only)

  assert_contains "the project deny beats both allows of the same tool" "$E2E" "effective deny scopes=project precedence_basis=evaluation-order WebFetch"
  assert_contains "the user allow of that tool is inert" "$E2E" "inert allow scopes=user outranked_by=deny WebFetch"
  assert_contains "a rule at user and local scope merges without an election" "$E2E" "effective allow scopes=user,local precedence_basis=merged-across-scopes Bash(npm test)"
  assert_contains "the start-directory copy contributes its own rules" "$E2E" "scopes=startdir-local precedence_basis=uncontested Bash(ls)"
  assert_contains "managed policy contributes" "$E2E" "scopes=managed precedence_basis=uncontested Read(./.env)"
  assert_eq "every end-to-end effective record carries a basis" \
    "$(count_matching "$E2E" '^effective ')" "$(count_matching "$E2E" 'precedence_basis=')"
else
  pass "end-to-end reader merge (skipped — jq not installed)"
fi

if [[ "$FAILED" -eq 0 ]]; then
  printf '\nAll %d checks passed.\n' "$CASE_NUM"
  exit 0
fi
printf '\n%d/%d checks failed.\n' "$FAILED" "$CASE_NUM" >&2
exit 1
