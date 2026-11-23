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

# shellcheck source=test-helpers.sh
source "$SCRIPT_DIR/test-helpers.sh"

diff_only() { printf '%s\n' "$1" | bash "$SCRIPT" --diff-only; }

FIVE_CLASSES=$(
  cat <<'EOF'
user settings present /fx/home/.claude/settings.json
effective allow scopes=user precedence_basis=uncontested Bash(*)
effective allow scopes=user precedence_basis=uncontested Bash(python3 *)
effective allow scopes=user precedence_basis=uncontested Bash(npx *)
effective allow scopes=user precedence_basis=uncontested Agent
effective allow scopes=user precedence_basis=uncontested Monitor
effective allow scopes=user precedence_basis=uncontested Bash(git status)
EOF
)
OUT=$(diff_only "$FIVE_CLASSES")
assert_contains "blanket Bash(*) is dropped" "$OUT" "entry-diff dropped class=blanket scopes=user Bash(*)"
assert_contains "a wildcarded interpreter is dropped" "$OUT" "entry-diff dropped class=interpreter-wildcard scopes=user Bash(python3 *)"
assert_contains "a package-manager run command is dropped" "$OUT" "entry-diff dropped class=package-manager-run scopes=user Bash(npx *)"
assert_contains "a bare Agent allow rule is dropped" "$OUT" "entry-diff dropped class=agent scopes=user Agent"
assert_contains "a bare Monitor allow rule is dropped" "$OUT" "entry-diff dropped class=monitor scopes=user Monitor"
assert_contains "a narrow exact rule carries over" "$OUT" "entry-diff kept scopes=user Bash(git status)"
assert_eq "all five classes appear in the dropped set" 5 "$(count_matching "$OUT" '^entry-diff dropped ')"
assert_contains "the summary reconciles" "$OUT" "entry-diff summary allow_before=6 dropped=5 suspended=0 kept=1"

assert_contains "a monitor verdict carries its version bound" "$OUT" \
  "Requires Claude Code v2.1.236 or later"

NEWER_CLASSES=$(
  cat <<'EOF'
user settings present /fx/home/.claude/settings.json
effective allow scopes=user precedence_basis=uncontested Bash(timeout *)
effective allow scopes=user precedence_basis=uncontested Bash(timeout 30 git status)
effective allow scopes=user precedence_basis=uncontested Bash(* --version)
effective allow scopes=user precedence_basis=uncontested Bash($HOME/bin/*)
effective allow scopes=user precedence_basis=uncontested Bash($HOME/bin/deploy.sh)
effective allow scopes=user precedence_basis=uncontested PowerShell(C:\tools\x.exe *)
effective allow scopes=user precedence_basis=uncontested PowerShell(.\tools\x.ps1 *)
effective allow scopes=user precedence_basis=uncontested Bash(/usr/bin/npm run:*)
effective allow scopes=user precedence_basis=uncontested Bash(/usr/bin/npm test)
effective allow scopes=user precedence_basis=uncontested Bash(pnpm@9 dlx *)
effective allow scopes=user precedence_basis=uncontested Bash(pnpm@9 install)
EOF
)
OUT=$(diff_only "$NEWER_CLASSES")
assert_contains "a wrapper followed only by a wildcard is dropped" "$OUT" "entry-diff dropped class=wrapper-wildcard scopes=user Bash(timeout *)"
assert_contains "a wrapper with a fixed command carries over" "$OUT" "entry-diff kept scopes=user Bash(timeout 30 git status)"
assert_contains "a leading-wildcard rule is dropped" "$OUT" "entry-diff dropped class=leading-wildcard scopes=user Bash(* --version)"
assert_contains "a \$HOME-led wildcard is dropped" "$OUT" "entry-diff dropped class=path-wildcard scopes=user Bash(\$HOME/bin/*)"
assert_contains "an exact \$HOME path carries over" "$OUT" "entry-diff kept scopes=user Bash(\$HOME/bin/deploy.sh)"
assert_contains "a Windows backslash program wildcard is dropped" "$OUT" 'entry-diff dropped class=path-wildcard scopes=user PowerShell(C:\tools\x.exe *)'
assert_contains "a .\\ script wildcard carries over" "$OUT" 'entry-diff kept scopes=user PowerShell(.\tools\x.ps1 *)'
assert_contains "a path-prefixed runner is dropped" "$OUT" "entry-diff dropped class=package-manager-run scopes=user Bash(/usr/bin/npm run:*)"
assert_contains "a narrow path-prefixed runner carries over" "$OUT" "entry-diff kept scopes=user Bash(/usr/bin/npm test)"
assert_contains "a version-suffixed runner is dropped" "$OUT" "entry-diff dropped class=package-manager-run scopes=user Bash(pnpm@9 dlx *)"
assert_contains "a narrow version-suffixed runner carries over" "$OUT" "entry-diff kept scopes=user Bash(pnpm@9 install)"
assert_contains "the newer-class summary reconciles" "$OUT" "entry-diff summary allow_before=11 dropped=6 suspended=0 kept=5"

SCOPED_AGENT=$(
  cat <<'EOF'
user settings present /fx/home/.claude/settings.json
effective allow scopes=user precedence_basis=uncontested Agent(model:haiku)
EOF
)
OUT=$(diff_only "$SCOPED_AGENT")
assert_contains "a scoped Agent allow rule is dropped like a bare one" "$OUT" "entry-diff dropped class=agent scopes=user Agent(model:haiku)"

SCOPED_MONITOR=$(
  cat <<'EOF'
user settings present /fx/home/.claude/settings.json
effective allow scopes=user precedence_basis=uncontested Monitor(npm test)
EOF
)
OUT=$(diff_only "$SCOPED_MONITOR")
assert_contains "a scoped Monitor allow rule is dropped like a bare one" "$OUT" "entry-diff dropped class=monitor scopes=user Monitor(npm test)"
assert_not_contains "a scoped Monitor rule is never reported kept" "$OUT" "entry-diff kept"

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
assert_not_contains "no monitor note when no Monitor allow rule was classified" "$OUT" \
  "Requires Claude Code v2.1.236 or later"

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

CAS_STRING=$(
  cat <<'EOF'
user settings present /fx/home/.claude/settings.json
conf user settings classifyAllShell "true"
effective allow scopes=user precedence_basis=uncontested Bash(git status)
EOF
)
OUT=$(diff_only "$CAS_STRING")
assert_eq "a string-typed value suspends nothing" 0 "$(count_matching "$OUT" '^entry-diff suspended ')"
assert_contains "the type mismatch is called out" "$OUT" "neither of the documented boolean values"

CAS_FALSE=$(
  cat <<'EOF'
user settings present /fx/home/.claude/settings.json
conf user settings classifyAllShell false
effective allow scopes=user precedence_basis=uncontested Bash(git status)
EOF
)
OUT=$(diff_only "$CAS_FALSE")
assert_eq "false suspends nothing" 0 "$(count_matching "$OUT" '^entry-diff suspended ')"
assert_contains "and is described as the default, not as malformed" "$OUT" "(the default)"
assert_not_contains "false is never called a type error" "$OUT" "neither of the documented boolean values"

OUT=$(diff_only "$CAS_FALSE")
assert_contains "the unreadable inline scope is disclosed" "$OUT" "inline --settings and Agent SDK JSON"
assert_contains "and the disclosure says what it would change" "$OUT" "every Bash and PowerShell verdict below is inverted"

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
assert_not_contains "--diff-only drops the per-rule input records" "$OUT" "effective allow scopes=user"
assert_contains "--diff-only keeps the NOTE records" "$OUT" "NOTE: something the operator"

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

ORACLE_INPUT=$(
  cat <<'EOF'
user settings present /fx/home/.claude/settings.json
effective allow scopes=user precedence_basis=uncontested Bash(*)
effective allow scopes=user precedence_basis=uncontested Bash(python3 *)
effective allow scopes=user precedence_basis=uncontested Bash(npx *)
effective allow scopes=user precedence_basis=uncontested Agent
effective allow scopes=user precedence_basis=uncontested Bash(git status)
EOF
)

STUB="$TEST_TMPDIR/stub"
mkdir -p "$STUB"
cat >"$STUB/claude" <<EOF
#!/usr/bin/env bash
echo "invoked \$*" >>"$TEST_TMPDIR/claude-invocations.txt"
exit 0
EOF
chmod +x "$STUB/claude"

OUT=$(printf '%s\n' "$ORACLE_INPUT" | PATH="$STUB:$PATH" bash "$SCRIPT" --diff-only 2>&1)
if [[ -e "$TEST_TMPDIR/claude-invocations.txt" ]]; then
  fail "no flag, no spawn" "stub claude was invoked: $(cat "$TEST_TMPDIR/claude-invocations.txt")"
else
  pass "no flag, no spawn"
fi
assert_not_contains "no flag, no oracle output" "$OUT" "oracle"

OUT=$(printf '%s\n' "$ORACLE_INPUT" | PATH="$STUB:$PATH" bash "$SCRIPT" --diff-only --oracle 2>&1)
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

NOCLAUDE="$TEST_TMPDIR/noclaude"
make_stub_path "$NOCLAUDE" cat grep sed sort mktemp rm tr
OUT=$(printf '%s\n' "$ORACLE_INPUT" | PATH="$NOCLAUDE" "$real_bash" "$SCRIPT" --diff-only --oracle 2>&1)
assert_contains "notice before any spawn attempt" "$OUT" "ORACLE COST NOTICE"
assert_contains "a missing claude degrades to unavailable" "$OUT" "'claude' is not on PATH"

BARE_SHELL=$(
  cat <<'EOF'
user settings present /fx/home/.claude/settings.json
effective allow scopes=user precedence_basis=uncontested Bash
effective allow scopes=user precedence_basis=uncontested PowerShell
effective allow scopes=user precedence_basis=uncontested Bash(*)
EOF
)
OUT=$(diff_only "$BARE_SHELL")
assert_eq "a bare shell grant is never reported kept" 0 "$(count_matching "$OUT" '^entry-diff kept ')"
assert_contains "bare Bash drops as blanket" "$OUT" "entry-diff dropped class=blanket scopes=user Bash"
assert_contains "bare PowerShell drops as blanket" "$OUT" "entry-diff dropped class=blanket scopes=user PowerShell"
assert_eq "all three shell grants drop" 3 "$(count_matching "$OUT" '^entry-diff dropped ')"

CAPTURE="$TEST_TMPDIR/capture.log"
cat >"$CAPTURE" <<'EOF'
[DEBUG] Applying permission update: Adding 3 allow rule(s) to destination 'userSettings': [...]
[DEBUG] Ignoring dangerous permission Bash(*) from C:\Users\x\.claude\settings.json (bypasses classifier)
[DEBUG] Ignoring dangerous permission Bash(python3 *) from C:\Users\x\.claude\settings.json (bypasses classifier)
[DEBUG] Ignoring dangerous permission Bash(uv run *) from C:\Users\x\.claude\settings.json (bypasses classifier)
[DEBUG] Applying permission update: Removing 3 allow rule(s) from source 'userSettings'
EOF
OUT=$(printf '%s\n' "$ORACLE_INPUT" | ENTRY_DIFF_ORACLE_CAPTURE="$CAPTURE" bash "$SCRIPT" --diff-only --oracle 2>&1)
assert_eq "one verdict line per rule in the union, exactly" 5 "$(count_matching "$OUT" '^oracle (AGREES|DIVERGES) ')"
assert_contains "agreement is stated per rule" "$OUT" "oracle AGREES Bash(*)"
assert_contains "a predicted drop the oracle kept diverges" "$OUT" "oracle DIVERGES prediction=dropped oracle=kept Bash(npx *)"
assert_contains "an oracle drop the prediction kept diverges too" "$OUT" "oracle DIVERGES prediction=kept oracle=dropped Bash(uv run *)"

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

CAPTURE_FROM_PATH="$TEST_TMPDIR/capture-from-path.log"
cat >"$CAPTURE_FROM_PATH" <<'EOF'
[DEBUG] Applying permission update: Adding 1 allow rule(s) to destination 'userSettings'
[DEBUG] Ignoring dangerous permission Bash(uv run *) from C:\Users\x\notes from work\.claude\settings.json (bypasses classifier)
EOF
FROM_PATH_IN=$(
  cat <<'EOF'
user settings present /fx/home/.claude/settings.json
effective allow scopes=user precedence_basis=uncontested Bash(uv run *)
EOF
)
OUT=$(printf '%s\n' "$FROM_PATH_IN" | ENTRY_DIFF_ORACLE_CAPTURE="$CAPTURE_FROM_PATH" bash "$SCRIPT" --diff-only --oracle 2>&1)
assert_contains "a PATH containing 'from' does not truncate the rule" "$OUT" "oracle AGREES Bash(uv run *)"
assert_eq "and produces no phantom rule" 0 "$(count_matching "$OUT" 'oracle DIVERGES')"

CAPTURE_UNSPLIT="$TEST_TMPDIR/capture-unsplit.log"
cat >"$CAPTURE_UNSPLIT" <<'EOF'
[DEBUG] Applying permission update: Adding 1 allow rule(s) to destination 'userSettings'
[DEBUG] Ignoring dangerous permission not a rule at all from somewhere (bypasses classifier)
[DEBUG] Ignoring dangerous permission Bash(npx *) from C:\Users\x\.claude\settings.json (bypasses classifier)
EOF
UNSPLIT_IN=$(
  cat <<'EOF'
user settings present /fx/home/.claude/settings.json
effective allow scopes=user precedence_basis=uncontested Bash(npx *)
EOF
)
OUT=$(printf '%s\n' "$UNSPLIT_IN" | ENTRY_DIFF_ORACLE_CAPTURE="$CAPTURE_UNSPLIT" bash "$SCRIPT" --diff-only --oracle 2>&1)
assert_contains "an unresolvable drop line is announced" "$OUT" "could not be split into rule and source path"
assert_contains "and the comparison is called incomplete, not clean" "$OUT" "incomplete rather than clean"
assert_contains "the resolvable line is still compared" "$OUT" "oracle AGREES Bash(npx *)"

CAPTURE_NODROPS="$TEST_TMPDIR/capture-nodrops.log"
cat >"$CAPTURE_NODROPS" <<'EOF'
[DEBUG] Applying permission update: Adding 3 allow rule(s) to destination 'userSettings': [...]
EOF
OUT=$(printf '%s\n' "$ORACLE_INPUT" | ENTRY_DIFF_ORACLE_CAPTURE="$CAPTURE_NODROPS" bash "$SCRIPT" --diff-only --oracle 2>&1)
assert_contains "zero drop lines with predicted drops reads as unavailable" "$OUT" "treat the oracle as unavailable rather than as an empty drop set"
assert_eq "no verdict is emitted from it" 0 "$(count_matching "$OUT" '^oracle (AGREES|DIVERGES) ')"

CAPTURE_ALIEN="$TEST_TMPDIR/capture-alien.log"
cat >"$CAPTURE_ALIEN" <<'EOF'
[DEBUG] something else entirely
EOF
OUT=$(printf '%s\n' "$ORACLE_INPUT" | ENTRY_DIFF_ORACLE_CAPTURE="$CAPTURE_ALIEN" bash "$SCRIPT" --diff-only --oracle 2>&1)
assert_contains "a capture without merge narration is unavailable" "$OUT" "no permission-merge narration"

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

BASE_IN=$(
  cat <<'EOF'
user settings present <userhome>/.claude/settings.json
effective allow scopes=user precedence_basis=uncontested Bash(*)
EOF
)
OUT_BASE=$(printf '%s\n' "$BASE_IN" | bash "$SCRIPT" --diff-only)
assert_contains "the diff names the transition it describes" "$OUT_BASE" "applies only to a session that ENTERS auto mode"
assert_contains "and names a run shape that never makes it" "$OUT_BASE" "claude -p"
assert_contains "and points at the live start-mode table" "$OUT_BASE" "permission-modes#which-mode-a-session-starts-in"
assert_contains "the diff says both classes are restored on leaving" "$OUT_BASE" "RESTORED"
assert_contains "the broad rule is still classified" "$OUT_BASE" "entry-diff dropped class=blanket"

assert_contains "a fully-read diff reports status=read" "$OUT_BASE" "status=read"
UNREAD_DIFF=$(
  cat <<'EOF'
managed file unreadable <managed>/managed-settings.json
user settings present <userhome>/.claude/settings.json
EOF
)
OUT_UNREAD_DIFF=$(printf '%s\n' "$UNREAD_DIFF" | bash "$SCRIPT" --diff-only)
assert_contains "an unread scope makes the diff incomplete" "$OUT_UNREAD_DIFF" "status=incomplete"
assert_contains "and says which scope was not classified" "$OUT_UNREAD_DIFF" "managed scope(s) could not be read"

report_and_exit
