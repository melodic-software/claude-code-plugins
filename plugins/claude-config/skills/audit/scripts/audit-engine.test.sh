#!/usr/bin/env bash
# Self-contained tests for audit-engine.sh (no external test lib; ships with the plugin).
#
# Fixture JSON carries "$schema" keys and ${CLAUDE_PLUGIN_ROOT} placeholders
# that must reach the file unexpanded, so single quotes are the correct spelling.
# shellcheck disable=SC2016
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$SCRIPT_DIR/audit-engine.sh"
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
if ! command -v jq >/dev/null 2>&1; then
  echo "SKIP: jq not installed" >&2
  exit 0
fi

# A baseline reference in the shape required-permissions.md uses, so the suite
# never depends on the live document's row set.
BASELINE="$TEST_TMPDIR/baseline.md"
cat >"$BASELINE" <<'EOF'
# Baseline permission patterns

## sensitive-file-deny (Read deny)

| Pattern | Purpose |
| --- | --- |
| `Read(./.env)` | Block reading .env |
| `Read(**/*.pem)` | Block PEM files |

## destructive-bash-deny (Bash deny)

| Pattern | Blocks |
| --- | --- |
| `Bash(git push --force *)` | Force push |
| `Bash(git reset --hard *)` | Hard reset |

## ask-rules (Bash ask)

| Pattern | Purpose |
| --- | --- |
| `Bash(git push *)` | Confirm pushes |

## Narrowing the baseline

Prose that must not parse as a pattern: `Bash(not a pattern)`.
EOF

# make_machine <name>: a project root and a user dir; echoes the root.
make_machine() {
  local root="$TEST_TMPDIR/$1"
  mkdir -p "$root/project/.claude" "$root/user"
  printf '%s' "$root"
}

# run <root> [args...]: run the engine against a fixture machine, drift skipped.
run() {
  SETTINGS_AUDIT_ENGINE_FIXTURE_DIR="$1/project" \
    SETTINGS_AUDIT_ENGINE_USER_DIR="$1/user" \
    SETTINGS_AUDIT_ENGINE_INSTALLED_JSON="$1/registry.json" \
    SETTINGS_AUDIT_ENGINE_BASELINE_FILE="$BASELINE" \
    SETTINGS_AUDIT_ENGINE_DEBUG_DIR="$1/debug" \
    SETTINGS_AUDIT_ENGINE_SKIP_DRIFT=1 \
    CLAUDE_CODE_DEBUG_LOGS_DIR="" \
    bash "$SCRIPT" "${@:2}"
}

CLEAN_SETTINGS='{"$schema":"https://json.schemastore.org/claude-code-settings.json","permissions":{"deny":["Read(./.env)","Read(**/*.pem)","Bash(git push --force *)","Bash(git reset --hard *)"],"ask":["Bash(git push *)"],"allow":["Bash(git commit *)","Bash(git fetch *)","Bash(git stash *)"]}}'

# --- Case 1: a clean project produces no findings and exits 0 -----------------
m="$(make_machine clean)"
printf '%s\n' "$CLEAN_SETTINGS" >"$m/project/.claude/settings.json"
rc=0
out=$(run "$m" --json 2>&1) || rc=$?
assert_exit "case 1: clean project exits 0" 0 "$rc"
assert_eq "case 1: no findings" "0" "$(jq '.summary.findings' <<<"$out")"
assert_eq "case 1: baseline rows are ok" "5" "$(jq '[.rows[] | select(.check | startswith("claude-config/audit/B/baseline-")) | select(.status=="ok")] | length' <<<"$out")"
assert_eq "case 1: engine id" "claude-config/audit-engine/1" "$(jq -r '.engine' <<<"$out")"

# --- Case 2: missing baseline patterns are findings with a stable identity -----
m="$(make_machine missing)"
printf '%s\n' '{"$schema":"https://json.schemastore.org/claude-code-settings.json","permissions":{}}' >"$m/project/.claude/settings.json"
rc=0
out=$(run "$m" --json --out "$m/findings.json" 2>&1) || rc=$?
assert_exit "case 2: error-severity findings exit 1" 1 "$rc"
assert_eq "case 2: four deny patterns are errors" "4" "$(jq '[.findings[] | select(.identity.check | endswith("-deny")) | select(.severity=="error")] | length' <<<"$out")"
assert_eq "case 2: ask pattern is a warning" "warning" "$(jq -r '.findings[] | select(.identity.claim=="missing-pattern:Bash(git push *)") | .severity' <<<"$out")"
assert_eq "case 2: allow-completeness rows are info" "3" "$(jq '[.findings[] | select(.identity.check | endswith("/allow-completeness")) | select(.severity=="info")] | length' <<<"$out")"
assert_eq "case 2: findings file written" "true" "$([[ -f "$m/findings.json" ]] && echo true || echo false)"
assert_eq "case 2: findings file rows match the document" "$(jq '.findings | length' <<<"$out")" "$(jq '.findings | length' "$m/findings.json")"
fid="$(jq -r '.findings[] | select(.identity.claim=="missing-pattern:Read(./.env)") | .finding_id' <<<"$out")"
assert_eq "case 2: finding_id is 16 hex" "16" "${#fid}"
site_anchor="$(jq -r '.findings[] | select(.identity.claim=="missing-pattern:Read(./.env)") | .identity.sites[0]["anchor/v1"]' <<<"$out")"
assert_contains "case 2: excerpt anchor shape" "$site_anchor" "e:"
assert_eq "case 2: rows carry the audit-pass lane and tier" "claude-config/audit derived" "$(jq -r '.findings[0] | "\(.lane) \(.tier)"' <<<"$out")"
# The same identity through the subcommands reproduces the id.
anchor="$(bash "$SCRIPT" anchor --excerpt "/permissions/deny")"
recomputed="$(bash "$SCRIPT" finding-id --check "claude-config/audit/B/baseline-sensitive-file-deny" --claim "missing-pattern:Read(./.env)" --site ".claude/settings.json" "$anchor")"
assert_eq "case 2: subcommands reproduce the id" "$fid" "$recomputed"
if command -v python3 >/dev/null 2>&1; then
  py_id="$(
    python3 - "$anchor" <<'PY'
import hashlib, sys
US = '\x1f'
anchor = sys.argv[1]
parts = ["claude-config/audit/B/baseline-sensitive-file-deny", "missing-pattern:Read(./.env)", ".claude/settings.json", anchor]
print(hashlib.sha256(US.join(parts).encode()).hexdigest()[:16])
PY
  )"
  assert_eq "case 2: id matches the convention's reference derivation" "$py_id" "$fid"
  py_anchor="$(
    python3 - <<'PY'
import hashlib
e = hashlib.sha256(b"/permissions/deny").hexdigest()[:12]
n = hashlib.sha256(b"\x00").hexdigest()[:8]
print(f"e:{e}:{n}")
PY
  )"
  assert_eq "case 2: anchor matches the reference derivation" "$py_anchor" "$anchor"
fi

# --- Case 3: a coverage manifest from a live hook demotes the family to info ---
m="$(make_machine manifest)"
mkdir -p "$m/mkt/.claude-plugin" "$m/mkt/plugins/guard/hooks"
printf '%s\n' '{"$schema":"https://json.schemastore.org/claude-code-settings.json","permissions":{"deny":["Read(./.env)","Read(**/*.pem)"],"ask":["Bash(git push *)"]},"enabledPlugins":{"guard@mkt":true},"extraKnownMarketplaces":{"mkt":{"source":{"source":"directory","path":"../mkt"}}}}' >"$m/project/.claude/settings.json"
printf '%s\n' '{"name":"mkt","plugins":[{"name":"guard","source":"./plugins/guard"}]}' >"$m/mkt/.claude-plugin/marketplace.json"
printf '%s\n' '{"hooks":{"PreToolUse":[{"matcher":"Bash|PowerShell","hooks":[{"type":"command","command":"\"${CLAUDE_PLUGIN_ROOT}\"/hooks/git.sh"}]}]}}' >"$m/mkt/plugins/guard/hooks/hooks.json"
printf '%s\n' '{"schemaVersion":1,"coverage":[{"hook":"hooks/git.sh","event":"PreToolUse","matcher":"Bash|PowerShell","decision":"block","families":["destructive-bash-deny"],"patterns":["Bash(git push --force *)","Bash(git reset --hard *)","Read(./.env)"],"levers":[{"kind":"userConfig","name":"git_enabled","effect":"off switch"}]}]}' >"$m/mkt/plugins/guard/hooks/coverage.json"
printf '#!/usr/bin/env bash\nexit 0\n' >"$m/mkt/plugins/guard/hooks/git.sh"
rc=0
out=$(run "$m" --json 2>&1) || rc=$?
assert_exit "case 3: covered families leave no error" 0 "$rc"
assert_eq "case 3: force push demoted to info" "info" "$(jq -r '.findings[] | select(.identity.claim=="missing-pattern:Bash(git push --force *)") | .severity' <<<"$out")"
assert_contains "case 3: the manifest and lever are cited" "$(jq -r '.findings[] | select(.identity.claim=="missing-pattern:Bash(git push --force *)") | .detail' <<<"$out")" "git_enabled"
assert_eq "case 3: a Read pattern on a Bash matcher is not covered" "0" "$(jq '[.rows[] | select(.claim=="missing-pattern:Read(./.env)")] | length' <<<"$out")"
assert_eq "case 3: manifest recorded" "1" "$(jq '.coverage_manifests | length' <<<"$out")"

# --- Case 4: a suppression lever makes the manifest coverage not live ----------
m="$(make_machine lever)"
mkdir -p "$m/mkt/.claude-plugin" "$m/mkt/plugins/guard/hooks"
printf '%s\n' '{"$schema":"https://json.schemastore.org/claude-code-settings.json","disableAllHooks":true,"permissions":{"deny":["Read(./.env)","Read(**/*.pem)"],"ask":["Bash(git push *)"]},"enabledPlugins":{"guard@mkt":true},"extraKnownMarketplaces":{"mkt":{"source":{"source":"directory","path":"../mkt"}}}}' >"$m/project/.claude/settings.json"
printf '%s\n' '{"name":"mkt","plugins":[{"name":"guard","source":"./plugins/guard"}]}' >"$m/mkt/.claude-plugin/marketplace.json"
printf '%s\n' '{"hooks":{"PreToolUse":[{"matcher":"Bash","hooks":[{"type":"command","command":"\"${CLAUDE_PLUGIN_ROOT}\"/hooks/git.sh"}]}]}}' >"$m/mkt/plugins/guard/hooks/hooks.json"
printf '%s\n' '{"schemaVersion":1,"coverage":[{"hook":"hooks/git.sh","event":"PreToolUse","matcher":"Bash","decision":"block","families":["destructive-bash-deny"],"patterns":["Bash(git push --force *)","Bash(git reset --hard *)"],"levers":[]}]}' >"$m/mkt/plugins/guard/hooks/coverage.json"
printf '#!/usr/bin/env bash\nexit 0\n' >"$m/mkt/plugins/guard/hooks/git.sh"
rc=0
out=$(run "$m" --json 2>&1) || rc=$?
assert_exit "case 4: not-live coverage keeps the error" 1 "$rc"
assert_eq "case 4: severity stays error" "error" "$(jq -r '.findings[] | select(.identity.claim=="missing-pattern:Bash(git push --force *)") | .severity' <<<"$out")"
assert_contains "case 4: lever named in the detail" "$(jq -r '.findings[] | select(.identity.claim=="missing-pattern:Bash(git push --force *)") | .detail' <<<"$out")" "lever is set"
assert_contains "case 4: lever row reports it set" "$(jq -r '.rows[] | select(.claim=="lever-set:disableAllHooks") | .detail' <<<"$out")" "project=true"

# --- Case 5: the suppression record retires a finding by identity --------------
m="$(make_machine suppress)"
printf '%s\n' '{"$schema":"https://json.schemastore.org/claude-code-settings.json","permissions":{"deny":["Read(./.env)","Read(**/*.pem)","Bash(git push --force *)","Bash(git reset --hard *)"]}}' >"$m/project/.claude/settings.json"
anchor="$(bash "$SCRIPT" anchor --excerpt "/permissions/ask")"
good_id="$(bash "$SCRIPT" finding-id --check "claude-config/audit/B/baseline-ask-rules" --claim "missing-pattern:Bash(git push *)" --site ".claude/settings.json" "$anchor")"
cat >"$m/project/.claude/audit-pass.md" <<EOF
# audit-pass suppressions

\`\`\`yaml
suppressions:
  $good_id:
    check: claude-config/audit/B/baseline-ask-rules
    claim: "missing-pattern:Bash(git push *)"
    sites:
      - surface: .claude/settings.json
        anchor/v1: "$anchor"
    reason: "Pushes are mandated by the harness in this repository's cloud sessions."
    date: 2026-09-08
  0000000000000000:
    check: claude-config/audit/B/baseline-ask-rules
    claim: "missing-pattern:Bash(git push *)"
    sites:
      - surface: .claude/settings.json
        anchor/v1: "$anchor"
    reason: "stale key"
    date: 2026-09-08
  1111111111111111:
    check: claude-config/audit/A/schema-present
    reason: "no claim or sites"
    date: 2026-09-08
\`\`\`
EOF
cat >"$m/project/.claude/audit-pass.local.md" <<EOF
\`\`\`yaml
suppressions:
  $(bash "$SCRIPT" finding-id --check "claude-config/audit/B/allow-completeness" --claim "missing-allow:git commit" --site ".claude/settings.json" "$(bash "$SCRIPT" anchor --excerpt "/permissions/allow")"):
    check: claude-config/audit/B/allow-completeness
    claim: "missing-allow:git commit"
    sites:
      - surface: .claude/settings.json
        anchor/v1: "$(bash "$SCRIPT" anchor --excerpt "/permissions/allow")"
    reason: "personal preference"
    date: 2026-09-08
\`\`\`
EOF
rc=0
out=$(run "$m" --json 2>&1) || rc=$?
assert_exit "case 5: suppressed warning leaves no error" 0 "$rc"
assert_eq "case 5: the ask finding is suppressed" "suppressed" "$(jq -r '.rows[] | select(.claim=="missing-pattern:Bash(git push *)") | .status' <<<"$out")"
assert_contains "case 5: reason carried" "$(jq -r '.suppressions.applied[0].suppressed.reason' <<<"$out")" "mandated by the harness"
assert_eq "case 5: suppressed row is not a finding" "0" "$(jq '[.findings[] | select(.identity.claim=="missing-pattern:Bash(git push *)")] | length' <<<"$out")"
assert_eq "case 5: two malformed entries reported" "2" "$(jq '.suppressions.malformed | length' <<<"$out")"
assert_contains "case 5: stale key named" "$(jq -r '.suppressions.malformed | join("\n")' <<<"$out")" "0000000000000000 constituents hash to"
assert_contains "case 5: missing keys named" "$(jq -r '.suppressions.malformed | join("\n")' <<<"$out")" "1111111111111111 missing a required key"
assert_eq "case 5: local-only entry is personal-only, not applied" "1" "$(jq '.suppressions.personal_only | length' <<<"$out")"
assert_eq "case 5: the personal-only finding still stands" "1" "$(jq '[.findings[] | select(.identity.claim=="missing-allow:git commit")] | length' <<<"$out")"

# --- Case 6: structure rows (schema, misplaced keys, local deny) ---------------
m="$(make_machine structure)"
printf '%s\n' '{"mcpServers":{"x":{}},"permissions":{"deny":["Read(./.env)","Read(**/*.pem)","Bash(git push --force *)","Bash(git reset --hard *)"],"ask":["Bash(git push *)"]}}' >"$m/project/.claude/settings.json"
printf '%s\n' '{"permissions":{"deny":["Bash(rm -rf *)"]},"hooks":{},"mcpServers":{}}' >"$m/project/.claude/settings.local.json"
rc=0
out=$(run "$m" --json 2>&1) || rc=$?
assert_exit "case 6: exit 1" 1 "$rc"
assert_eq "case 6: missing schema is a warning" "warning" "$(jq -r '.findings[] | select(.identity.claim=="missing-key:$schema") | .severity' <<<"$out")"
assert_eq "case 6: mcpServers in settings is an error" "error" "$(jq -r '.findings[] | select(.identity.claim=="misplaced-key:mcpServers" and .identity.sites[0].surface==".claude/settings.json") | .severity' <<<"$out")"
assert_eq "case 6: mcpServers in local is an error" "error" "$(jq -r '.findings[] | select(.identity.claim=="misplaced-key:mcpServers" and .identity.sites[0].surface==".claude/settings.local.json") | .severity' <<<"$out")"
assert_eq "case 6: hooks in local is info" "info" "$(jq -r '.findings[] | select(.identity.claim=="personal-key:hooks") | .severity' <<<"$out")"
assert_eq "case 6: deny in local is an error" "error" "$(jq -r '.findings[] | select(.identity.claim=="misplaced-rules:permissions.deny") | .severity' <<<"$out")"

# --- Case 7: MCP server rows ---------------------------------------------------
m="$(make_machine mcp)"
printf '%s\n' "$CLEAN_SETTINGS" | jq '. + {enableAllProjectMcpServers:true, enabledMcpjsonServers:["ok"], disabledMcpjsonServers:["ghost"]}' >"$m/project/.claude/settings.json"
printf '%s\n' '{"mcpServers":{"ok":{"command":"jq","env":{"TOKEN":"$RAW"}},"nocmd":{},"missing":{"command":"/definitely/not/here"},"web":{"type":"http","url":"not a url"}}}' >"$m/project/.mcp.json"
rc=0
out=$(run "$m" --json 2>&1) || rc=$?
assert_exit "case 7: exit 1" 1 "$rc"
assert_eq "case 7: resolvable command is ok" "ok" "$(jq -r '.rows[] | select(.claim=="command-resolves:ok") | .status' <<<"$out")"
assert_eq "case 7: missing command is an error" "error" "$(jq -r '.findings[] | select(.identity.claim=="missing-command:nocmd") | .severity' <<<"$out")"
assert_eq "case 7: absent path is an error" "error" "$(jq -r '.findings[] | select(.identity.claim=="command-missing:missing") | .severity' <<<"$out")"
assert_eq "case 7: bare env reference is a warning" "warning" "$(jq -r '.findings[] | select(.identity.claim=="bare-env-reference:ok:TOKEN") | .severity' <<<"$out")"
assert_eq "case 7: malformed url is a warning" "warning" "$(jq -r '.findings[] | select(.identity.claim=="url-malformed:web") | .severity' <<<"$out")"
assert_eq "case 7: enableAllProjectMcpServers is an error" "error" "$(jq -r '.findings[] | select(.identity.claim=="enableAllProjectMcpServers:true") | .severity' <<<"$out")"
assert_eq "case 7: unlisted servers are errors" "3" "$(jq '[.findings[] | select(.identity.claim | startswith("unlisted-server:"))] | length' <<<"$out")"
assert_eq "case 7: unknown listed server is an error" "error" "$(jq -r '.findings[] | select(.identity.claim=="unknown-server:ghost") | .severity' <<<"$out")"

# --- Case 8: hook rows from the inventory --------------------------------------
m="$(make_machine hooks)"
printf '#!/usr/bin/env bash\nexit 0\n' >"$m/project/fmt.sh"
mkdir -p "$m/project/my hooks"
printf '#!/usr/bin/env bash\nexit 0\n' >"$m/project/my hooks/space.sh"
printf '%s\n' "$CLEAN_SETTINGS" | jq '. + {"hooks":{"PostToolUse":[{"matcher":"Edit.*","hooks":[{"type":"command","command":"$CLAUDE_PROJECT_DIR/fmt.sh","timeout":30000},{"type":"command","command":"$CLAUDE_PROJECT_DIR/fmt.sh","timeout":30000}]}],"PreToolUse":[{"matcher":"Bash","hooks":[{"type":"command","command":"\"$CLAUDE_PROJECT_DIR\"/gone.sh","timeout":10},{"type":"command","command":"\"$CLAUDE_PROJECT_DIR/my hooks/space.sh\" --strict","timeout":10}]}]}}' >"$m/project/.claude/settings.json"
rc=0
out=$(run "$m" --json 2>&1) || rc=$?
assert_exit "case 8: exit 1 on the missing hook path" 1 "$rc"
assert_eq "case 8: a quoted path with a space resolves whole" "ok" "$(jq -r '[.rows[] | select(.claim | startswith("hook-path-resolves:PreToolUse:"))] | .[0].status' <<<"$out")"
assert_eq "case 8: only the absent path is missing" "1" "$(jq '[.findings[] | select(.identity.claim | startswith("hook-path-missing:"))] | length' <<<"$out")"
assert_eq "case 8: millisecond timeout flagged" "2" "$(jq '[.findings[] | select(.identity.claim | startswith("millisecond-timeout:"))] | length' <<<"$out")"
assert_eq "case 8: unanchored regex matcher flagged" "1" "$(jq '[.findings[] | select(.identity.claim=="unanchored-regex-matcher:PostToolUse:Edit.*")] | length' <<<"$out")"
assert_eq "case 8: unquoted placeholder flagged" "2" "$(jq '[.findings[] | select(.identity.claim | startswith("unquoted-placeholder:"))] | length' <<<"$out")"
assert_eq "case 8: duplicate flagged once" "1" "$(jq '[.findings[] | select(.identity.claim | startswith("duplicate-hook:"))] | length' <<<"$out")"
assert_eq "case 8: existing path is ok" "ok" "$(jq -r '[.rows[] | select(.claim | startswith("hook-path-resolves:PostToolUse"))] | .[0].status' <<<"$out")"
assert_eq "case 8: missing path is an error" "error" "$(jq -r '.findings[] | select(.identity.claim | startswith("hook-path-missing:PreToolUse")) | .severity' <<<"$out")"
assert_eq "case 8: quoted placeholder is not flagged" "0" "$(jq '[.findings[] | select(.identity.claim | startswith("unquoted-placeholder:PreToolUse"))] | length' <<<"$out")"

# --- Case 9: skill-listing measurement from a debug log ------------------------
m="$(make_machine listing)"
printf '%s\n' "$CLEAN_SETTINGS" >"$m/project/.claude/settings.json"
mkdir -p "$m/debug"
printf '%s\n' '2026-09-08T17:07:55.925Z [WARN] Skill listing over budget: 211 skills, 155730 chars > 150000 budget — descriptions will be truncated.' >"$m/debug/session.txt"
rc=0
out=$(run "$m" --json 2>&1) || rc=$?
assert_exit "case 9: overflow is a warning, exit 0" 0 "$rc"
assert_eq "case 9: measured" "true" "$(jq '.skill_listing.measured' <<<"$out")"
assert_eq "case 9: numbers parsed" "211 155730 150000 5730" "$(jq -r '.skill_listing | "\(.skills) \(.chars) \(.budget) \(.over_by)"' <<<"$out")"
assert_eq "case 9: overflow finding" "warning" "$(jq -r '.findings[] | select(.identity.claim=="listing-over-budget") | .severity' <<<"$out")"
printf '%s\n' 'no warning here' >"$m/debug/session.txt"
out=$(run "$m" --json 2>&1) || true
assert_eq "case 9: a log without the warning reads as fits" "false" "$(jq '.skill_listing.overflow' <<<"$out")"
rm -rf "$m/debug"
out=$(run "$m" --json 2>&1) || true
assert_eq "case 9: no log means not measured, never clean" "skip" "$(jq -r '.rows[] | select(.check | endswith("/listing-budget")) | .status' <<<"$out")"
out=$(run "$m" --json --debug-log "$m/project/fmt.sh" 2>&1) || true
assert_eq "case 9: an explicit missing --debug-log falls through" "false" "$(jq '.skill_listing.measured' <<<"$out")"

# --- Case 10: model, effort and deep-link values --------------------------------
m="$(make_machine values)"
printf '%s\n' "$CLEAN_SETTINGS" | jq '. + {effortLevel:"max",fallbackModel:["sonnet","haiku","sonnet","opus","haiku"],availableModels:["sonnet","claude-sonnet-4-5"],enforceAvailableModels:true,disableDeepLinkRegistration:true}' >"$m/project/.claude/settings.json"
printf '%s\n' '{"enforceAvailableModels":true,"availableModels":[]}' >"$m/user/settings.json"
rc=0
out=$(run "$m" --json 2>&1) || rc=$?
assert_exit "case 10: exit 1" 1 "$rc"
assert_eq "case 10: effortLevel max is a warning" "warning" "$(jq -r '.findings[] | select(.identity.claim=="effortLevel:max") | .severity' <<<"$out")"
assert_eq "case 10: raw fallback length flagged" "1" "$(jq '[.findings[] | select(.identity.claim=="fallbackModel-raw-length:5")] | length' <<<"$out")"
assert_eq "case 10: dedup length under the cap not flagged" "0" "$(jq '[.findings[] | select(.identity.claim | startswith("fallbackModel-dedup-length:"))] | length' <<<"$out")"
assert_eq "case 10: wildcard mix flagged" "1" "$(jq '[.findings[] | select(.identity.claim=="availableModels-wildcard-mix:sonnet")] | length' <<<"$out")"
assert_eq "case 10: project enforce with a list is not flagged" "0" "$(jq '[.findings[] | select(.identity.claim=="enforceAvailableModels-without-list" and .identity.sites[0].surface==".claude/settings.json")] | length' <<<"$out")"
assert_eq "case 10: user enforce without a list is an error" "error" "$(jq -r '.findings[] | select(.identity.claim=="enforceAvailableModels-without-list" and .identity.sites[0].surface=="user:settings.json") | .severity' <<<"$out")"
assert_eq "case 10: deep-link boolean is a warning" "warning" "$(jq -r '.findings[] | select(.identity.claim=="disableDeepLinkRegistration:true") | .severity' <<<"$out")"

# --- Case 11: environment variables ---------------------------------------------
m="$(make_machine env)"
mkdir -p "$m/docs"
printf '%s\n' '| `CLAUDE_CODE_DISABLE_AUTO_MEMORY` | documented |' >"$m/docs/env-vars.md"
printf '%s\n' "$CLEAN_SETTINGS" | jq '. + {env:{CLAUDE_CODE_DISABLE_AUTO_MEMORY:"1",MY_SINK:"C:\\tools\\sink.sh",GH:"ghp_abcdefghijklmnopqrstuvwxyz0123"}}' >"$m/project/.claude/settings.json" # portability-ok: a Windows path inside a JSON string, not a regex escape
rc=0
out=$(run "$m" --json --docs-dir "$m/docs" 2>&1) || rc=$?
assert_exit "case 11: secret-shaped value exits 1" 1 "$rc"
assert_eq "case 11: secret is an error" "error" "$(jq -r '.findings[] | select(.identity.claim=="secret-shaped-value") | .severity' <<<"$out")"
assert_eq "case 11: backslash path is info" "info" "$(jq -r '.findings[] | select(.identity.claim=="backslash-path:MY_SINK") | .severity' <<<"$out")"
assert_eq "case 11: documented var is ok" "ok" "$(jq -r '.rows[] | select(.claim=="documented-on-env-vars:CLAUDE_CODE_DISABLE_AUTO_MEMORY") | .status' <<<"$out")"
assert_eq "case 11: undocumented var is info" "info" "$(jq -r '.findings[] | select(.identity.claim=="not-on-env-vars-page:MY_SINK") | .severity' <<<"$out")"
out=$(run "$m" --json 2>&1) || true
assert_eq "case 11: without docs the documentation row is a skip" "skip" "$(jq -r '.rows[] | select(.claim=="env-page-not-fetched:MY_SINK") | .status' <<<"$out")"

# --- Case 12: plugin membership and drift against merged scopes -----------------
m="$(make_machine plugins)"
mkdir -p "$m/fixtures"
printf '%s\n' "$CLEAN_SETTINGS" | jq '. + {enabledPlugins:{"a@mkt":true,"old@mkt":false,"x@nowhere":true},extraKnownMarketplaces:{mkt:{source:{source:"github",repo:"o/r"}}}}' >"$m/project/.claude/settings.json"
printf '%s\n' '{"enabledPlugins":{"b@mkt":true}}' >"$m/user/settings.json"
printf '%s\n' '{"name":"mkt","plugins":[{"name":"a"},{"name":"b"},{"name":"c"}]}' >"$m/fixtures/mkt.json"
rc=0
out=$(SETTINGS_AUDIT_ENGINE_FIXTURE_DIR="$m/project" SETTINGS_AUDIT_ENGINE_USER_DIR="$m/user" \
  SETTINGS_AUDIT_ENGINE_INSTALLED_JSON="$m/registry.json" SETTINGS_AUDIT_ENGINE_BASELINE_FILE="$BASELINE" \
  SETTINGS_AUDIT_ENGINE_DEBUG_DIR="$m/debug" SETTINGS_AUDIT_FIXTURE_DIR="$m/fixtures" CLAUDE_CODE_DEBUG_LOGS_DIR="" \
  bash "$SCRIPT" --json 2>&1) || rc=$?
assert_exit "case 12: unknown marketplace exits 1" 1 "$rc"
assert_eq "case 12: unknown marketplace is an error" "error" "$(jq -r '.findings[] | select(.identity.claim=="unknown-marketplace:x@nowhere") | .severity' <<<"$out")"
assert_eq "case 12: disabled plugin is info" "info" "$(jq -r '.findings[] | select(.identity.claim=="disabled-plugin:old@mkt") | .severity' <<<"$out")"
assert_eq "case 12: drift ran" "ran" "$(jq -r '.drift.state' <<<"$out")"
assert_eq "case 12: orphan disabled is info" "info" "$(jq -r '.findings[] | select(.identity.claim=="orphan-disabled:old@mkt") | .severity' <<<"$out")"
assert_eq "case 12: a key enabled at user scope is not new" "0" "$(jq '[.findings[] | select(.identity.claim=="new-upstream:b@mkt")] | length' <<<"$out")"
assert_eq "case 12: a key in no scope is new" "1" "$(jq '[.findings[] | select(.identity.claim=="new-upstream:c@mkt")] | length' <<<"$out")"

# --- Case 13: a not-inspectable scope is never reported clean --------------------
m="$(make_machine unreadable)"
printf '%s\n' "$CLEAN_SETTINGS" >"$m/project/.claude/settings.json"
printf '%s\n' '{"permissions":{"deny":["Bash(rm -rf *)"]}}' >"$m/project/.claude/settings.local.json"
chmod 000 "$m/project/.claude/settings.local.json"
if : 2>/dev/null <"$m/project/.claude/settings.local.json"; then
  echo "SKIP: case 13 needs a non-root user (the file stays readable)" >&2
else
  rc=0
  out=$(run "$m" --json 2>&1) || rc=$?
  assert_exit "case 13: unreadable local is not an error" 0 "$rc"
  assert_eq "case 13: scope state" "unreadable" "$(jq -r '.scopes[] | select(.label=="local") | .state' <<<"$out")"
  assert_eq "case 13: not-inspectable row" "not-inspectable" "$(jq -r '.rows[] | select(.check | endswith("/local-readable")) | .status' <<<"$out")"
  assert_eq "case 13: no deny-in-local verdict either way" "0" "$(jq '[.rows[] | select(.check | endswith("/deny-in-local"))] | length' <<<"$out")"
fi
chmod 644 "$m/project/.claude/settings.local.json"

# --- Case 14: table mode and invalid JSON --------------------------------------
m="$(make_machine table)"
printf '%s\n' '{not json' >"$m/project/.claude/settings.json"
rc=0
out=$(run "$m" --table 2>&1) || rc=$?
assert_exit "case 14: invalid settings exits 1" 1 "$rc"
assert_contains "case 14: table names the invalid file" "$out" "invalid-json"
assert_contains "case 14: table prints a suppress line" "$out" "suppress: id"

# --- Case 15: argument and tool errors -----------------------------------------
rc=0
bash "$SCRIPT" --nope >/dev/null 2>&1 || rc=$?
assert_exit "case 15: unknown argument exits 2" 2 "$rc"
rc=0
bash "$SCRIPT" finding-id --check x >/dev/null 2>&1 || rc=$?
assert_exit "case 15: finding-id without a site exits 2" 2 "$rc"
m="$(make_machine nosettings)"
rc=0
run "$m" --json >/dev/null 2>&1 || rc=$?
assert_exit "case 15: no project settings exits 2" 2 "$rc"

# --- Case 16: a personal or token-bearing hook command is never echoed ---------
m="$(make_machine redact)"
printf '%s\n' "$CLEAN_SETTINGS" | jq '. + {"hooks":{"PreToolUse":[{"matcher":"Bash","hooks":[{"type":"command","command":"\"$CLAUDE_PROJECT_DIR\"/gone.sh ghp_zyxwvutsrqponmlkjihgfedcba9876"}]}]}}' >"$m/project/.claude/settings.json"
printf '%s\n' '{"hooks":{"PreToolUse":[{"matcher":"Bash","hooks":[{"type":"command","command":"\"$CLAUDE_PROJECT_DIR\"/gone.sh --token ghp_abcdefghijklmnopqrstuvwxyz0123","timeout":5000}]}]}}' >"$m/project/.claude/settings.local.json"
rc=0
out=$(run "$m" --json 2>&1) || rc=$?
assert_exit "case 16: missing hook paths exit 1" 1 "$rc"
if [[ "$out" != *"ghp_abcdefghijklmnopqrstuvwxyz0123"* && "$out" != *"ghp_zyxwvutsrqponmlkjihgfedcba9876"* ]]; then
  pass "case 16: no token-shaped value reaches the document"
else
  fail "case 16: no token-shaped value reaches the document" "a hook command was echoed verbatim"
fi
assert_eq "case 16: the local hook is named by its excerpt hash" "1" "$(jq '[.findings[] | select(.identity.sites[0].surface==".claude/settings.local.json") | select(.identity.claim | startswith("hook-path-missing:PreToolUse:cmd:e:"))] | length' <<<"$out")"
assert_eq "case 16: the local timeout claim is redacted too" "1" "$(jq '[.findings[] | select(.identity.claim | startswith("millisecond-timeout:PreToolUse:cmd:e:"))] | length' <<<"$out")"
assert_eq "case 16: a token-bearing project hook is redacted" "1" "$(jq '[.findings[] | select(.identity.sites[0].surface==".claude/settings.json") | select(.identity.claim | startswith("hook-path-missing:PreToolUse:cmd:e:"))] | length' <<<"$out")"
assert_eq "case 16: the project detail names no path" "the resolved first token does not exist" "$(jq -r '.findings[] | select(.identity.sites[0].surface==".claude/settings.json") | select(.identity.claim | startswith("hook-path-missing:")) | .detail' <<<"$out")"

# --- Case 17: a baseline reference that parses to nothing is a skip, not clean --
m="$(make_machine unparsed)"
printf '%s\n' "$CLEAN_SETTINGS" >"$m/project/.claude/settings.json"
printf '%s\n' '# Baseline' '' '## Sensitive File Deny' '' '| Pattern | Why |' '| --- | --- |' '| `Read(./.env)` | secrets |' >"$m/baseline-renamed.md"
rc=0
out=$(SETTINGS_AUDIT_ENGINE_FIXTURE_DIR="$m/project" SETTINGS_AUDIT_ENGINE_USER_DIR="$m/user" \
  SETTINGS_AUDIT_ENGINE_INSTALLED_JSON="$m/registry.json" SETTINGS_AUDIT_ENGINE_BASELINE_FILE="$m/baseline-renamed.md" \
  SETTINGS_AUDIT_ENGINE_DEBUG_DIR="$m/debug" SETTINGS_AUDIT_ENGINE_SKIP_DRIFT=1 CLAUDE_CODE_DEBUG_LOGS_DIR="" \
  bash "$SCRIPT" --json 2>&1) || rc=$?
assert_exit "case 17: an unparsed baseline is not an error" 0 "$rc"
assert_eq "case 17: the reference is reported unparsed" "skip" "$(jq -r '.rows[] | select(.claim=="reference-unparsed") | .status' <<<"$out")"
assert_eq "case 17: no baseline pattern row is emitted" "0" "$(jq '[.rows[] | select(.check | test("/B/baseline-(sensitive|destructive|ask)"))] | length' <<<"$out")"

# --- Case 18: a marketplace name is matched as a string, not a pattern ---------
m="$(make_machine regexmkt)"
printf '%s\n' "$CLEAN_SETTINGS" | jq '. + {enabledPlugins:{"mine@.*":true}}' >"$m/project/.claude/settings.json"
rc=0
out=$(run "$m" --json 2>&1) || rc=$?
assert_exit "case 18: an unregistered marketplace exits 1" 1 "$rc"
assert_eq "case 18: a pattern-shaped name does not match the empty registry" "error" "$(jq -r '.findings[] | select(.identity.claim=="unknown-marketplace:mine@.*") | .severity' <<<"$out")"

if [[ "$FAILED" -eq 0 ]]; then
  printf '\nAll %d checks passed.\n' "$CASE_NUM"
  exit 0
fi
printf '\n%d/%d checks failed.\n' "$FAILED" "$CASE_NUM" >&2
exit 1
