#!/usr/bin/env bash
# Regression tests for automode-entry-diff.sh (self-contained — ships with the plugin).
#
# Classification cases feed hand-written merge records on stdin. Oracle cases
# use a fixture capture (ENTRY_DIFF_ORACLE_CAPTURE) or a recording stub claude
# on PATH — no case ever spawns a real session, and no test reads the
# operator's real ~/.claude.
#
# portability-scope: the oracle fixture reproduces Claude Code's own [DEBUG]
# narration byte for byte, and that narration prints Windows settings paths in
# native form (C:\Users\...\.claude\settings.json — see the recorded capture in
# the permission-model research corpus). The backslash runs the gate reads as
# regex escapes are those paths inside heredoc DATA, not shell code. Rewriting
# them to POSIX form would make the fixture stop matching what the parser must
# survive on the plugin's primary platform, which is the whole point of the case.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$SCRIPT_DIR/automode-entry-diff.sh"
STATE_SCRIPT="$SCRIPT_DIR/permission-state.sh"
MERGE_SCRIPT="$SCRIPT_DIR/permission-merge.sh"

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

diff_only() { printf '%s\n' "$1" | bash "$SCRIPT" --diff-only; }

# --- Case 1: one rule of each documented drop class, plus a narrow survivor ---
# "On entering auto mode, broad allow rules that grant arbitrary code execution
# are dropped: Blanket Bash(*) or PowerShell(*); Wildcarded interpreters like
# Bash(python*); Package-manager run commands; Agent allow rules. Narrow rules
# like Bash(npm test) carry over."
FOUR_CLASSES=$(
  cat <<'EOF'
user settings present /fx/home/.claude/settings.json
effective allow scopes=user precedence_basis=uncontested Bash(*)
effective allow scopes=user precedence_basis=uncontested Bash(python3 *)
effective allow scopes=user precedence_basis=uncontested Bash(npx *)
effective allow scopes=user precedence_basis=uncontested Agent
effective allow scopes=user precedence_basis=uncontested Bash(git status)
EOF
)
OUT=$(diff_only "$FOUR_CLASSES")
assert_contains "blanket Bash(*) is dropped" "$OUT" "entry-diff dropped class=blanket scopes=user Bash(*)"
assert_contains "a wildcarded interpreter is dropped" "$OUT" "entry-diff dropped class=interpreter-wildcard scopes=user Bash(python3 *)"
assert_contains "a package-manager run command is dropped" "$OUT" "entry-diff dropped class=package-manager-run scopes=user Bash(npx *)"
assert_contains "a bare Agent allow rule is dropped" "$OUT" "entry-diff dropped class=agent scopes=user Agent"
assert_contains "a narrow exact rule carries over" "$OUT" "entry-diff kept scopes=user Bash(git status)"
assert_eq "all four classes appear in the dropped set" 4 "$(count_matching "$OUT" '^entry-diff dropped ')"
assert_contains "the summary reconciles" "$OUT" "entry-diff summary allow_before=5 dropped=4 suspended=0 kept=1"

# A SCOPED Agent rule is dropped too: auto mode drops all Agent allow rules
# categorically, unlike Bash where narrow rules survive.
SCOPED_AGENT=$(
  cat <<'EOF'
user settings present /fx/home/.claude/settings.json
effective allow scopes=user precedence_basis=uncontested Agent(model:haiku)
EOF
)
OUT=$(diff_only "$SCOPED_AGENT")
assert_contains "a scoped Agent allow rule is dropped like a bare one" "$OUT" "entry-diff dropped class=agent scopes=user Agent(model:haiku)"

# Deny and ask rules are evaluated before the classifier in every mode; the
# entry diff must not touch them.
DENY_ASK=$(
  cat <<'EOF'
user settings present /fx/home/.claude/settings.json
effective deny scopes=user precedence_basis=uncontested Bash(*)
effective ask scopes=user precedence_basis=uncontested Agent
EOF
)
OUT=$(diff_only "$DENY_ASK")
assert_eq "deny and ask rules produce no diff records" 0 "$(count_matching "$OUT" '^entry-diff (dropped|suspended|kept) ')"
assert_contains "the summary shows an empty allow set, not a missing one" "$OUT" "entry-diff summary allow_before=0"

# --- Case 2: classifyAllShell inverts the carry-over answer -------------------
# "suspend[s] every Bash and PowerShell allow rule while auto mode is active."
CAS_ON=$(
  cat <<'EOF'
user settings present /fx/home/.claude/settings.json
conf user settings classifyAllShell true
effective allow scopes=user precedence_basis=uncontested Bash(git status)
effective allow scopes=user precedence_basis=uncontested PowerShell(Get-ChildItem *)
effective allow scopes=user precedence_basis=uncontested WebFetch(domain:example.com)
effective allow scopes=user precedence_basis=uncontested Bash(*)
EOF
)
OUT=$(diff_only "$CAS_ON")
assert_contains "a narrow Bash rule is suspended, not kept" "$OUT" "entry-diff suspended reason=classifyAllShell scopes=user Bash(git status)"
assert_contains "PowerShell rules are suspended too" "$OUT" "entry-diff suspended reason=classifyAllShell scopes=user PowerShell(Get-ChildItem *)"
assert_contains "a non-shell rule is untouched by classifyAllShell" "$OUT" "entry-diff kept scopes=user WebFetch(domain:example.com)"
assert_contains "a blanket rule still reports its drop class, not suspension" "$OUT" "entry-diff dropped class=blanket scopes=user Bash(*)"
assert_contains "the inversion is announced with its version gate" "$OUT" "v2.1.193"

# Managed is the highest scope: a managed false beats a user true.
CAS_MANAGED=$(
  cat <<'EOF'
managed file present /policy/managed-settings.json
user settings present /fx/home/.claude/settings.json
conf managed file classifyAllShell false
conf user settings classifyAllShell true
effective allow scopes=user precedence_basis=uncontested Bash(git status)
EOF
)
OUT=$(diff_only "$CAS_MANAGED")
assert_eq "a managed false overrides a user true" 0 "$(count_matching "$OUT" '^entry-diff suspended ')"
assert_contains "the narrow rule stays kept" "$OUT" "entry-diff kept scopes=user Bash(git status)"

# "The classifier doesn't read autoMode from project settings in
# .claude/settings.json or .claude/settings.local.json."
CAS_PROJECT=$(
  cat <<'EOF'
project settings present /proj/.claude/settings.json
conf project settings classifyAllShell true
effective allow scopes=project precedence_basis=uncontested Bash(git status)
EOF
)
OUT=$(diff_only "$CAS_PROJECT")
assert_eq "a project-scope classifyAllShell suspends nothing" 0 "$(count_matching "$OUT" '^entry-diff suspended ')"
assert_contains "the ignored scope is named, not silently honored" "$OUT" "scope(s) the classifier does not read (project)"

# A string "true" is not the documented boolean and must not activate.
CAS_STRING=$(
  cat <<'EOF'
user settings present /fx/home/.claude/settings.json
conf user settings classifyAllShell "true"
effective allow scopes=user precedence_basis=uncontested Bash(git status)
EOF
)
OUT=$(diff_only "$CAS_STRING")
assert_eq "a string-typed value suspends nothing" 0 "$(count_matching "$OUT" '^entry-diff suspended ')"
assert_contains "the type mismatch is called out" "$OUT" "not the documented boolean true"

# --- Case 3: pass-through default, --diff-only suppression --------------------
PASS_IN=$(
  cat <<'EOF'
user settings present /fx/home/.claude/settings.json
NOTE: something the operator must know
effective allow scopes=user precedence_basis=uncontested Bash(git status)
EOF
)
OUT=$(printf '%s\n' "$PASS_IN" | bash "$SCRIPT")
assert_contains "input records pass through by default" "$OUT" "NOTE: something the operator must know"
assert_contains "the diff section follows" "$OUT" "entry-diff kept scopes=user Bash(git status)"
OUT=$(diff_only "$PASS_IN")
assert_not_contains "--diff-only drops the input records" "$OUT" "NOTE: something the operator"

# --- Case 4: no records is an error, never an empty diff ----------------------
rc=0
err_out=$(printf '' | bash "$SCRIPT" --diff-only 2>&1) || rc=$?
assert_exit "exit 2 on empty input" 2 "$rc"
assert_contains "the empty-input error says why" "$err_out" "no records on input"

rc=0
err_out=$(bash "$SCRIPT" --bogus </dev/null 2>&1) || rc=$?
assert_exit "exit 2 on an unknown argument" 2 "$rc"

rc=0
help_out=$(bash "$SCRIPT" --help </dev/null 2>&1) || rc=$?
assert_exit "--help exits 0" 0 "$rc"
assert_contains "--help prices the oracle" "$help_out" "real token cost"

# --- Case 5: oracle OFF by default — no spawn, no scratch file ----------------
# A recording stub claude sits FIRST on PATH; if anything invoked it, the
# marker file would exist.
STUB="$TEST_TMPDIR/stub"
mkdir -p "$STUB"
cat >"$STUB/claude" <<EOF
#!/usr/bin/env bash
echo "invoked \$*" >>"$TEST_TMPDIR/claude-invocations.txt"
exit 0
EOF
chmod +x "$STUB/claude"

OUT=$(printf '%s\n' "$FOUR_CLASSES" | PATH="$STUB:$PATH" bash "$SCRIPT" --diff-only 2>&1)
if [[ -e "$TEST_TMPDIR/claude-invocations.txt" ]]; then
  fail "no flag, no spawn" "stub claude was invoked: $(cat "$TEST_TMPDIR/claude-invocations.txt")"
else
  pass "no flag, no spawn"
fi
assert_not_contains "no flag, no oracle output" "$OUT" "oracle"

# --- Case 6: oracle ON spawns only after the cost notice ----------------------
# The stub writes an empty capture, so this also proves a dead spawn is
# reported as unavailable rather than as an empty drop set.
OUT=$(printf '%s\n' "$FOUR_CLASSES" | PATH="$STUB:$PATH" bash "$SCRIPT" --diff-only --oracle 2>&1)
assert_contains "the cost notice printed" "$OUT" "ORACLE COST NOTICE"
if [[ -s "$TEST_TMPDIR/claude-invocations.txt" ]]; then
  pass "with the flag, the spawn happened"
else
  fail "with the flag, the spawn happened" "stub claude was never invoked"
fi
assert_contains "the stub session is in auto mode explicitly" "$(cat "$TEST_TMPDIR/claude-invocations.txt")" "--permission-mode auto"
assert_contains "an empty capture is unavailable, not an empty drop set" "$OUT" "oracle UNAVAILABLE"
assert_not_contains "no verdicts from a dead capture" "$OUT" "oracle AGREES"
rm -f "$TEST_TMPDIR/claude-invocations.txt"

# claude missing entirely: the notice still precedes the (refused) spawn.
# Wrappers exec the real binaries by absolute path (a copied MSYS binary loses
# the msys-2.0.dll beside it); bash is invoked by absolute path so the stub
# PATH cannot hide the interpreter itself.
NOCLAUDE="$TEST_TMPDIR/noclaude"
mkdir -p "$NOCLAUDE"
real_bash="$(command -v bash)"
for tool in cat grep sed sort mktemp rm tr; do
  src="$(command -v "$tool" 2>/dev/null)" || continue
  printf '#!%s\nexec "%s" "$@"\n' "$real_bash" "$src" >"$NOCLAUDE/$tool"
  chmod +x "$NOCLAUDE/$tool"
done
OUT=$(printf '%s\n' "$FOUR_CLASSES" | PATH="$NOCLAUDE" "$real_bash" "$SCRIPT" --diff-only --oracle 2>&1)
assert_contains "notice before any spawn attempt" "$OUT" "ORACLE COST NOTICE"
assert_contains "a missing claude degrades to unavailable" "$OUT" "'claude' is not on PATH"

# --- Case 7: oracle comparison — one verdict per compared rule, exactly -------
CAPTURE="$TEST_TMPDIR/capture.log"
cat >"$CAPTURE" <<'EOF'
[DEBUG] Applying permission update: Adding 3 allow rule(s) to destination 'userSettings': [...]
[DEBUG] Ignoring dangerous permission Bash(*) from C:\Users\x\.claude\settings.json (bypasses classifier)
[DEBUG] Ignoring dangerous permission Bash(python3 *) from C:\Users\x\.claude\settings.json (bypasses classifier)
[DEBUG] Ignoring dangerous permission Bash(uv run *) from C:\Users\x\.claude\settings.json (bypasses classifier)
[DEBUG] Applying permission update: Removing 3 allow rule(s) from source 'userSettings'
EOF
# Prediction: Bash(*), Bash(python3 *), Bash(npx *), Agent dropped. Oracle:
# Bash(*), Bash(python3 *), Bash(uv run *). Union: 5 rules, 2 agreements,
# 2 predicted-only, 1 oracle-only.
OUT=$(printf '%s\n' "$FOUR_CLASSES" | ENTRY_DIFF_ORACLE_CAPTURE="$CAPTURE" bash "$SCRIPT" --diff-only --oracle 2>&1)
assert_eq "one verdict line per rule in the union, exactly" 5 "$(count_matching "$OUT" '^oracle (AGREES|DIVERGES) ')"
assert_contains "agreement is stated per rule" "$OUT" "oracle AGREES Bash(*)"
assert_contains "a predicted drop the oracle kept diverges" "$OUT" "oracle DIVERGES prediction=dropped oracle=kept Bash(npx *)"
assert_contains "an oracle drop the prediction kept diverges too" "$OUT" "oracle DIVERGES prediction=kept oracle=dropped Bash(uv run *)"

# A rule containing the word "from" must not truncate itself.
CAPTURE_FROM="$TEST_TMPDIR/capture-from.log"
cat >"$CAPTURE_FROM" <<'EOF'
[DEBUG] Applying permission update: Adding 1 allow rule(s) to destination 'userSettings': [...]
[DEBUG] Ignoring dangerous permission Bash(python3 import from x *) from C:\Users\x\.claude\settings.json (bypasses classifier)
EOF
FROM_IN=$(
  cat <<'EOF'
user settings present /fx/home/.claude/settings.json
effective allow scopes=user precedence_basis=uncontested Bash(python3 import from x *)
EOF
)
OUT=$(printf '%s\n' "$FROM_IN" | ENTRY_DIFF_ORACLE_CAPTURE="$CAPTURE_FROM" bash "$SCRIPT" --diff-only --oracle 2>&1)
assert_contains "a rule containing 'from' survives parsing intact" "$OUT" "oracle AGREES Bash(python3 import from x *)"

# --- Case 8: capture without drop strings never becomes an empty drop set -----
CAPTURE_NODROPS="$TEST_TMPDIR/capture-nodrops.log"
cat >"$CAPTURE_NODROPS" <<'EOF'
[DEBUG] Applying permission update: Adding 3 allow rule(s) to destination 'userSettings': [...]
EOF
OUT=$(printf '%s\n' "$FOUR_CLASSES" | ENTRY_DIFF_ORACLE_CAPTURE="$CAPTURE_NODROPS" bash "$SCRIPT" --diff-only --oracle 2>&1)
assert_contains "zero drop lines with predicted drops reads as unavailable" "$OUT" "treat the oracle as unavailable rather than as an empty drop set"
assert_eq "no verdict is emitted from it" 0 "$(count_matching "$OUT" '^oracle (AGREES|DIVERGES) ')"

# A capture with no permission narration at all (the [DEBUG] strings changed,
# or the session died before the merge) is unavailable, with the reason named.
CAPTURE_ALIEN="$TEST_TMPDIR/capture-alien.log"
cat >"$CAPTURE_ALIEN" <<'EOF'
[DEBUG] something else entirely
EOF
OUT=$(printf '%s\n' "$FOUR_CLASSES" | ENTRY_DIFF_ORACLE_CAPTURE="$CAPTURE_ALIEN" bash "$SCRIPT" --diff-only --oracle 2>&1)
assert_contains "a capture without merge narration is unavailable" "$OUT" "no permission-merge narration"

# --- Case 9: end to end — reader conf record reaches the diff -----------------
if command -v jq >/dev/null 2>&1; then
  FX="$TEST_TMPDIR/fx"
  mkdir -p "$FX/proj/.claude" "$FX/home/.claude"
  jq -n '{autoMode:{classifyAllShell:true},permissions:{allow:["Bash(npm test)","Bash(*)"]}}' >"$FX/home/.claude/settings.json"
  jq -n '{permissions:{allow:["WebFetch(domain:example.com)"]}}' >"$FX/proj/.claude/settings.json"

  E2E=$(env -u CLAUDE_CONFIG_DIR \
    HOME="$FX/home" \
    PERMISSION_STATE_FIXTURE_DIR="$FX/proj" \
    PERMISSION_STATE_STARTDIR="$FX/proj" \
    PERMISSION_STATE_MANAGED_PATH="$FX/nonexistent/managed-settings.json" \
    PERMISSION_STATE_REGISTRY_KEYS="" \
    PERMISSION_STATE_PLIST_DOMAIN="" \
    bash "$STATE_SCRIPT" | bash "$MERGE_SCRIPT" | bash "$SCRIPT" --diff-only)

  assert_contains "the reader's conf record survives the merge pass-through" "$E2E" "entry-diff suspended reason=classifyAllShell scopes=user Bash(npm test)"
  assert_contains "the blanket rule is dropped, not suspended" "$E2E" "entry-diff dropped class=blanket scopes=user Bash(*)"
  assert_contains "the non-shell project rule is kept" "$E2E" "entry-diff kept scopes=project WebFetch(domain:example.com)"
else
  pass "end-to-end conf record flow (skipped — jq not installed)"
fi

if [[ "$FAILED" -eq 0 ]]; then
  printf '\nAll %d checks passed.\n' "$CASE_NUM"
  exit 0
fi
printf '\n%d/%d checks failed.\n' "$FAILED" "$CASE_NUM" >&2
exit 1
