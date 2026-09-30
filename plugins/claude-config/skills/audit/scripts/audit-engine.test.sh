#!/usr/bin/env bash
# Self-contained tests for audit-engine.sh (no external test lib; ships with the plugin).
#
# Fixture JSON carries "$schema" keys and ${CLAUDE_PLUGIN_ROOT} placeholders
# that must reach the file unexpanded, so single quotes are the correct spelling.
# shellcheck disable=SC2016
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$SCRIPT_DIR/audit-engine.sh"
TEST_TMPDIR="$(mktemp -d)" || TEST_TMPDIR=""
if [[ -z "$TEST_TMPDIR" || ! -d "$TEST_TMPDIR" ]]; then
  echo "FATAL: mktemp -d gave no directory" >&2
  exit 2
fi
trap 'rm -rf "$TEST_TMPDIR"' EXIT
# Nothing the caller exported reaches a case: every settings-path variable is
# cleared or pinned to a fixture under the suite temp dir. Each run sets the
# SETTINGS_AUDIT_ENGINE_* seams it uses.
while IFS= read -r v; do unset "$v"; done < <(compgen -e | grep -E '^SETTINGS_AUDIT_')
unset CLAUDE_PROJECT_DIR CLAUDE_PLUGIN_ROOT
mkdir -p "$TEST_TMPDIR/home/.claude"
export HOME="$TEST_TMPDIR/home"
export CLAUDE_CONFIG_DIR="$TEST_TMPDIR/home/.claude"
export CLAUDE_SETTINGS_FILE="$TEST_TMPDIR/inherited/settings.json"

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

# The docs the engine reads, in the shapes the published pages use: an llms.txt
# index linking each page, settings-reference with one ### `key` heading per key
# and a **Type** bullet, and env-vars with a backticked row per variable. No
# case reaches the network: every engine run points the docs fixture seam here
# or at another local directory.
DOCS="$TEST_TMPDIR/docs"
mkdir -p "$DOCS"
cat >"$DOCS/llms.txt" <<'EOF'
# Claude Code Docs

## Configuration

- [All settings](https://code.claude.com/docs/en/settings-reference.md): Complete reference for every Claude Code settings.json key.
- [Environment variables](https://code.claude.com/docs/en/env-vars.md): Reference for environment variables that control Claude Code behavior.
EOF
cat >"$DOCS/env-vars.md" <<'EOF'
# Environment variables

| Variable | Purpose |
| :--- | :--- |
| `CLAUDE_CODE_DISABLE_AUTO_MEMORY` | Disable auto memory |
| `AXB` | A variable whose name has no dot |
EOF
# section <key> [type line] [body...]: one settings-reference key section.
section() {
  local key="$1" type="${2:-* **Type**: Boolean}"
  shift 2 || shift $#
  printf '### `%s`\n\nWhat %s does.\n\n' "$key" "$key"
  [[ $# -gt 0 ]] && printf '%s\n' "$@" ''
  printf '* **Scope**: [`Any file`](#scopes)\n%s\n* **Default**: unset\n\n' "$type"
}
{
  printf '# All settings\n\n## General\n\n'
  section enabledPlugins '* **Type**: object'
  printf '## Settings index\n\n| Key | Status |\n| --- | --- |\n| `voiceEnabled` | Deprecated |\n\n'
  printf 'Deprecated keys carry a warning in their own section.\n\n## Model and responses\n\n'
  section availableModels '* **Type**: array of strings'
  printf '### `effortLevel`\n\nSet a default effort level.\n\n* **Scope**: [`Any file`](#scopes)\n* **Type**: string, one of:\n'
  printf '  * `"low"`: the least reasoning\n  * `"medium"`: reduces token usage\n  * `"high"`: balances token usage and intelligence\n  * `"xhigh"`: deeper reasoning at higher token spend\n'
  printf '* **Default**: unset\n\n```json settings.json theme={null}\n{\n  "effortLevel": "xhigh"\n}\n```\n\n'
  printf '### `enforceAvailableModels`\n\nThis key closes that gap. Requires Claude Code v2.1.175 or later.\n\n'
  printf '* **Scope**: [`Any file`](#scopes)\n* **Type**: Boolean\n  * `true`: Default resolves to the first available model\n* **Default**: `false`\n\n'
  printf 'This key has no effect when `availableModels` is unset or empty. Requires Claude Code v2.1.999 or later.\n\n'
  section fallbackModel '* **Type**: array of strings' 'Claude Code keeps at most three distinct allowed models from the list and ignores the rest.'
  printf '### `editorMode`\n\nSet the prompt input key bindings.\n\n* **Scope**: [`Any file`](#scopes)\n* **Type**: string, one of:\n'
  printf '  * `"normal"`: standard key bindings\n  * `"vim"`: vim-style editing\n* **Default**: `"normal"`\n\n'
  printf '### `theme`\n\nPick the color theme.\n\n* **Scope**: [`Any file`](#scopes)\n* **Type**: string, one of:\n'
  printf '  * `"dark"`: the dark theme\n  * `"custom:<slug>"` or `"custom:<plugin-name>:<slug>"`: a custom theme\n* **Default**: `"dark"`\n\n'
  printf '## Permission settings\n\n'
  section permissions '* **Type**: object with `allow`, `ask`, `deny`, `additionalDirectories`, `defaultMode`, and `disableAutoMode`'
  for k in permissions.allow permissions.ask permissions.deny; do section "$k" '* **Type**: array of strings'; done
  printf '## Other settings\n\n'
  for k in extraKnownMarketplaces disableAllHooks hooks env enableAllProjectMcpServers enabledMcpjsonServers disabledMcpjsonServers; do section "$k"; done
  section skillOverrides '* **Type**: object'
  section voiceEnabled '* **Type**: Boolean' '<Warning>' '  Deprecated since v2.1.92, when the [`voice`](#voice) object replaced it. Claude Code still reads it so older settings files keep working, but new configurations should set `voice.enabled`.' '</Warning>'
  section laterKey '* **Type**: Boolean' '<Warning>' '  Deprecated since v2.1.281, when a newer key replaced it.' '</Warning>'
  section disableArtifact '* **Type**: Boolean' '<Warning>' '  Deprecated, and replaced by [`enableArtifact`](#enableartifact). Claude Code still honors `disableArtifact: true`.' '</Warning>'
  section disableDeepLinkRegistration '* **Type**: the string `"disable"`'
  section fastMode '* **Type**: Boolean' '#### Fields for `fastMode`' '' 'Deprecated since v2.1.1 as a note that belongs to the subheading, not the key.'
  section codeFenced '* **Type**: Boolean' '```bash' '# a comment inside a fence, not a heading' '```' '' 'Deprecated since v2.1.100, after a fenced comment.'
} >"$DOCS/settings-reference.md"

# The hooks page in the shape the published one uses: an Event table under the
# lifecycle heading, then a later table whose first column is not events.
HOOKS_MD="$TEST_TMPDIR/hooks.md"
cat >"$HOOKS_MD" <<'EOF'
# Hooks reference

## Hook lifecycle

| Event | When it fires |
| :- | :- |
| `SessionStart` | When a session begins or resumes |
| `PreToolUse` | Before a tool call executes |

## Matcher patterns

| Tool | Meaning |
| :- | :- |
| `Bash` | A tool name, not an event |
EOF
# docs_with_link <dir> <slug>...: a docs directory whose settings-reference links each slug.
docs_with_link() {
  local d="$1" s
  shift
  mkdir -p "$d"
  cp "$DOCS/llms.txt" "$DOCS/env-vars.md" "$d/"
  {
    cat "$DOCS/settings-reference.md"
    printf '\n'
    for s in "$@"; do printf 'See [%s](/docs/en/%s#top) for more.\n' "$s" "$s"; done
  } >"$d/settings-reference.md"
}

# make_cli <path> <version line> [literal...]: a stand-in claude CLI that prints
# the version line for --version and carries each literal in its own text, the
# way the real binary carries the key names it reads.
make_cli() {
  local p="$1" v="$2"
  shift 2
  {
    printf '#!/usr/bin/env bash\n'
    [[ $# -gt 0 ]] && printf '# %s\n' "$@"
    printf 'echo "%s"\n' "$v"
  } >"$p"
  chmod +x "$p"
}
CLI="$TEST_TMPDIR/claude"
make_cli "$CLI" "2.1.281 (Claude Code)" enabledPlugins permissions internalOnlyKey

# make_machine <name>: a project root and a user dir; echoes the root.
make_machine() {
  local root="$TEST_TMPDIR/$1"
  mkdir -p "$root/project/.claude" "$root/user"
  printf '%s' "$root"
}

# run <root> [args...]: run the engine against a fixture machine, drift skipped.
# DOCS_FIXTURE and CLI_BIN, when set by the caller, replace the default docs
# fixture and stand-in CLI for that one run.
run() {
  SETTINGS_AUDIT_ENGINE_FIXTURE_DIR="$1/project" \
    SETTINGS_AUDIT_ENGINE_USER_DIR="$1/user" \
    SETTINGS_AUDIT_ENGINE_INSTALLED_JSON="$1/registry.json" \
    SETTINGS_AUDIT_ENGINE_BASELINE_FILE="$BASELINE" \
    SETTINGS_AUDIT_ENGINE_DEBUG_DIR="$1/debug" \
    SETTINGS_AUDIT_ENGINE_SKIP_DRIFT=1 \
    FETCH_DOCS_FIXTURE_DIR="${DOCS_FIXTURE:-$DOCS}" \
    SETTINGS_AUDIT_ENGINE_CLAUDE_BIN="${CLI_BIN:-$CLI}" \
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
assert_eq "case 3: a plugin with no manifest declares no dependencies" "0" "$(jq '[.rows[] | select(.claim=="dependencies-unread:guard@mkt")] | length' <<<"$out")"

# --- Case 3b: the live-hook info row for the push ask-gate still says an ask rule blocks unattended lanes ---
m="$(make_machine manifest-ask)"
mkdir -p "$m/mkt/.claude-plugin" "$m/mkt/plugins/guard/hooks"
printf '%s\n' '{"$schema":"https://json.schemastore.org/claude-code-settings.json","permissions":{"deny":["Read(./.env)","Read(**/*.pem)"]},"enabledPlugins":{"guard@mkt":true},"extraKnownMarketplaces":{"mkt":{"source":{"source":"directory","path":"../mkt"}}}}' >"$m/project/.claude/settings.json"
printf '%s\n' '{"name":"mkt","plugins":[{"name":"guard","source":"./plugins/guard"}]}' >"$m/mkt/.claude-plugin/marketplace.json"
printf '%s\n' '{"hooks":{"PreToolUse":[{"matcher":"Bash","hooks":[{"type":"command","command":"\"${CLAUDE_PLUGIN_ROOT}\"/hooks/git.sh"}]}]}}' >"$m/mkt/plugins/guard/hooks/hooks.json"
printf '%s\n' '{"schemaVersion":1,"coverage":[{"hook":"hooks/git.sh","event":"PreToolUse","matcher":"Bash","decision":"block","families":["destructive-bash-deny"],"patterns":["Bash(git push *)"],"levers":[]}]}' >"$m/mkt/plugins/guard/hooks/coverage.json"
printf '#!/usr/bin/env bash\nexit 0\n' >"$m/mkt/plugins/guard/hooks/git.sh"
rc=0
out=$(run "$m" --json 2>&1) || rc=$?
push_ask="$(jq -r '.findings[] | select(.identity.claim=="missing-pattern:Bash(git push *)") | .detail' <<<"$out")"
assert_contains "case 3b: the live-hook row is used" "$push_ask" "a live PreToolUse hook already blocks it"
assert_contains "case 3b: the live-hook row says an ask rule blocks unattended lanes" "$push_ask" "auto-denied under dontAsk"

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

# strictPluginOnlyCustomization is per-surface. "mcp" does not switch hooks off.
# "hooks" does. v2.1.257 closed the /mcp reconnect bypass; the lever row says so.
write_surface_lock() {
  local value="$1"
  m="$(make_machine "surface-$value")"
  mkdir -p "$m/mkt/.claude-plugin" "$m/mkt/plugins/guard/hooks"
  jq -n --argjson lock "$value" '{
    "$schema": "https://json.schemastore.org/claude-code-settings.json",
    strictPluginOnlyCustomization: $lock,
    permissions: {deny: ["Read(./.env)"], ask: ["Bash(git push *)"]},
    enabledPlugins: {"guard@mkt": true},
    extraKnownMarketplaces: {mkt: {source: {source: "directory", path: "../mkt"}}}
  }' >"$m/project/.claude/settings.json"
  printf '%s\n' '{"name":"mkt","plugins":[{"name":"guard","source":"./plugins/guard"}]}' >"$m/mkt/.claude-plugin/marketplace.json"
  printf '%s\n' '{"hooks":{"PreToolUse":[{"matcher":"Bash","hooks":[{"type":"command","command":"\"${CLAUDE_PLUGIN_ROOT}\"/hooks/git.sh"}]}]}}' >"$m/mkt/plugins/guard/hooks/hooks.json"
  printf '%s\n' '{"schemaVersion":1,"coverage":[{"hook":"hooks/git.sh","event":"PreToolUse","matcher":"Bash","decision":"block","families":["destructive-bash-deny"],"patterns":["Bash(git push --force *)"],"levers":[]}]}' >"$m/mkt/plugins/guard/hooks/coverage.json"
  printf '#!/usr/bin/env bash\nexit 0\n' >"$m/mkt/plugins/guard/hooks/git.sh"
}
write_surface_lock '["mcp"]'
rc=0
out=$(run "$m" --json 2>&1) || rc=$?
# Other baseline denies are still absent, so the run exits 1. The force-push
# row is the signal that the mcp-only lock did not switch hooks off.
assert_eq "case 4b: force push stays info" "info" "$(jq -r '.findings[] | select(.identity.claim=="missing-pattern:Bash(git push --force *)") | .severity' <<<"$out")"
assert_contains "case 4b: the lever row says hooks are not locked" "$(jq -r '.rows[] | select(.claim=="lever-set:strictPluginOnlyCustomization") | .detail' <<<"$out")" "hooks are not locked"
write_surface_lock '["hooks"]'
rc=0
out=$(run "$m" --json 2>&1) || rc=$?
assert_exit "case 4c: hooks lock keeps the error" 1 "$rc"
assert_eq "case 4c: force push stays error" "error" "$(jq -r '.findings[] | select(.identity.claim=="missing-pattern:Bash(git push --force *)") | .severity' <<<"$out")"

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
assert_eq "case 9: a discovered log that names no project is unverified, not clean" "skip" "$(jq -r '.rows[] | select(.check | endswith("/listing-budget")) | .status' <<<"$out")"
assert_eq "case 9: an unverified log is not counted as measured" "false" "$(jq '.skill_listing.measured' <<<"$out")"
printf '%s\n' "cwd: $m/project" 'no warning here' >"$m/debug/session.txt"
out=$(run "$m" --json 2>&1) || true
assert_eq "case 9: a log naming this project reads as fits" "false" "$(jq '.skill_listing.overflow' <<<"$out")"
assert_eq "case 9: its provenance is the project" "project" "$(jq -r '.skill_listing.provenance' <<<"$out")"
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
assert_eq "case 10: raw fallback length is not decided from the page" "skip" "$(jq -r '.rows[] | select(.claim=="fallbackModel-raw-length:5") | .status' <<<"$out")"
assert_eq "case 10: raw fallback length is not a finding" "0" "$(jq '[.findings[] | select(.identity.claim=="fallbackModel-raw-length:5")] | length' <<<"$out")"
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
assert_eq "case 11: a backslash path is not a finding" "0" "$(jq '[.findings[] | select(.identity.claim | startswith("backslash-path:"))] | length' <<<"$out")"
assert_eq "case 11: no path-separators row" "0" "$(jq '[.rows[] | select(.check | endswith("/path-separators"))] | length' <<<"$out")"
assert_eq "case 11: documented var is ok" "ok" "$(jq -r '.rows[] | select(.claim=="documented-on-env-vars:CLAUDE_CODE_DISABLE_AUTO_MEMORY") | .status' <<<"$out")"
assert_eq "case 11: undocumented var is info" "info" "$(jq -r '.findings[] | select(.identity.claim=="not-on-env-vars-page:MY_SINK") | .severity' <<<"$out")"
mkdir -p "$m/nodocs"
out=$(DOCS_FIXTURE="$m/nodocs" run "$m" --json 2>&1) || true
assert_eq "case 11: without the env-vars page the documentation row is not inspectable" "not-inspectable" "$(jq -r '.rows[] | select(.claim=="env-page-not-fetched:MY_SINK") | .status' <<<"$out")"
# Keys keep their tab-separated-values encoding, so a control character never
# splits one key into two rows and existing claim identities stay stable.
printf '%s\n' "$CLEAN_SETTINGS" | jq '. + {env:{"A\nB":"1"}}' >"$m/project/.claude/settings.json" # portability-ok: a JSON newline escape, not a regex escape
out=$(run "$m" --json --docs-dir "$m/docs" 2>&1) || true
assert_eq "case 11: a key with a newline is one row" "1" "$(jq '[.rows[] | select(.check | endswith("/documented-var"))] | length' <<<"$out")"
assert_eq "case 11: its claim carries the escaped key" "1" "$(jq '[.findings[] | select(.identity.claim=="not-on-env-vars-page:A\\nB")] | length' <<<"$out")" # portability-ok: the literal two-character escape in the claim

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
  FETCH_DOCS_FIXTURE_DIR="$DOCS" SETTINGS_AUDIT_ENGINE_CLAUDE_BIN="$CLI" \
  bash "$SCRIPT" --json 2>&1) || rc=$?
assert_exit "case 12: unknown marketplace exits 1" 1 "$rc"
assert_eq "case 12: unknown marketplace is an error" "error" "$(jq -r '.findings[] | select(.identity.claim=="unknown-marketplace:x@nowhere") | .severity' <<<"$out")"
assert_eq "case 12: no disabled-plugin finding" "0" "$(jq '[.findings[] | select(.identity.claim | startswith("disabled-plugin:"))] | length' <<<"$out")"
assert_eq "case 12: a false key is an inventory row" "ok none .claude/settings.json" "$(jq -r '.rows[] | select(.claim=="disabled-plugin:old@mkt") | "\(.status) \(.severity) \(.surface)"' <<<"$out")"
assert_eq "case 12: drift ran" "ran" "$(jq -r '.drift.state' <<<"$out")"
assert_eq "case 12: orphan disabled is info" "info" "$(jq -r '.findings[] | select(.identity.claim=="orphan-disabled:old@mkt") | .severity' <<<"$out")"
assert_eq "case 12: no new-upstream finding" "0" "$(jq '[.findings[] | select(.identity.claim | startswith("new-upstream:"))] | length' <<<"$out")"
assert_eq "case 12: one drift-new inventory row per marketplace" "ok none" "$(jq -r '[.rows[] | select(.check | endswith("/E/drift-new"))] | map("\(.status) \(.severity)") | join(",")' <<<"$out")"
dn="$(jq -r '.rows[] | select(.check | endswith("/E/drift-new")) | .detail' <<<"$out")"
assert_contains "case 12: drift-new counts the keys in no scope" "$dn" "1 plugin(s) in the mkt catalog have no enabledPlugins entry in any scope"
assert_contains "case 12: drift-new names an example" "$dn" "c@mkt"
assert_eq "case 12: a key enabled at user scope is not counted" "0" "$(jq '[.rows[] | select(.check | endswith("/E/drift-new")) | select(.detail | contains("b@mkt"))] | length' <<<"$out")"
assert_eq "case 12: no row asks for an explicit value" "0" "$(jq '[.rows[] | select(.detail | contains("record an explicit true or false"))] | length' <<<"$out")"

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
  FETCH_DOCS_FIXTURE_DIR="$DOCS" SETTINGS_AUDIT_ENGINE_CLAUDE_BIN="$CLI" \
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

# --- Case 19: a manifest naming a hook the plugin does not register ------------
# The narrowing rests on enforcement code that actually runs, so an entry whose
# hook is absent from the inventory is reported and takes no narrowing.
m="$(make_machine stale-manifest)"
mkdir -p "$m/mkt/.claude-plugin" "$m/mkt/plugins/guard/hooks"
printf '%s\n' '{"$schema":"https://json.schemastore.org/claude-code-settings.json","permissions":{"deny":["Read(./.env)","Read(**/*.pem)"],"ask":["Bash(git push *)"]},"enabledPlugins":{"guard@mkt":true},"extraKnownMarketplaces":{"mkt":{"source":{"source":"directory","path":"../mkt"}}}}' >"$m/project/.claude/settings.json"
printf '%s\n' '{"name":"mkt","plugins":[{"name":"guard","source":"./plugins/guard"}]}' >"$m/mkt/.claude-plugin/marketplace.json"
printf '%s\n' '{"hooks":{"PreToolUse":[{"matcher":"Read","hooks":[{"type":"command","command":"\"${CLAUDE_PLUGIN_ROOT}\"/hooks/read.sh"}]}]}}' >"$m/mkt/plugins/guard/hooks/hooks.json"
printf '%s\n' '{"schemaVersion":1,"coverage":[{"hook":"hooks/git.sh","event":"PreToolUse","matcher":"Bash","decision":"block","families":["destructive-bash-deny"],"patterns":["Bash(git push --force *)"],"levers":[]}]}' >"$m/mkt/plugins/guard/hooks/coverage.json"
printf '#!/usr/bin/env bash\nexit 0\n' >"$m/mkt/plugins/guard/hooks/read.sh"
rc=0
out=$(run "$m" --json 2>&1) || rc=$?
assert_exit "case 19: an uncorroborated manifest keeps the error" 1 "$rc"
assert_eq "case 19: severity stays error" "error" "$(jq -r '.findings[] | select(.identity.claim=="missing-pattern:Bash(git push --force *)") | .severity' <<<"$out")"
assert_eq "case 19: the unmatched manifest entry is reported" "1" "$(jq '[.findings[] | select(.identity.claim | startswith("manifest-hook-not-inventoried:"))] | length' <<<"$out")"

# --- Case 20: an unreadable scope makes the narrowing unavailable --------------
m="$(make_machine lever-unknown)"
mkdir -p "$m/mkt/.claude-plugin" "$m/mkt/plugins/guard/hooks"
printf '%s\n' '{"$schema":"https://json.schemastore.org/claude-code-settings.json","permissions":{"deny":["Read(./.env)","Read(**/*.pem)"],"ask":["Bash(git push *)"]},"enabledPlugins":{"guard@mkt":true},"extraKnownMarketplaces":{"mkt":{"source":{"source":"directory","path":"../mkt"}}}}' >"$m/project/.claude/settings.json"
printf '%s\n' '{not json' >"$m/project/.claude/settings.local.json"
printf '%s\n' '{"name":"mkt","plugins":[{"name":"guard","source":"./plugins/guard"}]}' >"$m/mkt/.claude-plugin/marketplace.json"
printf '%s\n' '{"hooks":{"PreToolUse":[{"matcher":"Bash|PowerShell","hooks":[{"type":"command","command":"\"${CLAUDE_PLUGIN_ROOT}\"/hooks/git.sh"}]}]}}' >"$m/mkt/plugins/guard/hooks/hooks.json"
printf '%s\n' '{"schemaVersion":1,"coverage":[{"hook":"hooks/git.sh","event":"PreToolUse","matcher":"Bash|PowerShell","decision":"block","families":["destructive-bash-deny"],"patterns":["Bash(git push --force *)"],"levers":[]}]}' >"$m/mkt/plugins/guard/hooks/coverage.json"
printf '#!/usr/bin/env bash\nexit 0\n' >"$m/mkt/plugins/guard/hooks/git.sh"
rc=0
out=$(run "$m" --json 2>&1) || rc=$?
assert_exit "case 20: an unread lever keeps the error" 1 "$rc"
assert_eq "case 20: severity stays error" "error" "$(jq -r '.findings[] | select(.identity.claim=="missing-pattern:Bash(git push --force *)") | .severity' <<<"$out")"
assert_contains "case 20: the detail names the unread levers" "$(jq -r '.findings[] | select(.identity.claim=="missing-pattern:Bash(git push --force *)") | .detail' <<<"$out")" "could not be read"
assert_eq "case 20: the lever state is reported not inspectable" "not-inspectable" "$(jq -r '.rows[] | select(.claim=="lever-state-unknown") | .status' <<<"$out")"

# --- Case 21: an oversize assembled payload still produces a document ---------
# The document assembly bound nine payloads to one jq call as --argjson values.
# The whole argv is ONE Win32 command line, and on Git for Windows an argument
# past about 32,760 bytes dies with "Argument list too long": the document came
# back EMPTY, every later `jq <<<"$DOC"` printed nothing, and the engine still
# exited 1 and still wrote --out, so the failure was silent.
#
# TOTAL PAYLOAD BYTES is the mechanism, not row count, so a few servers with very
# long names reproduce it far faster than many ordinary ones. The names are
# padded to about 3,000 characters and not to 9,000 on purpose: the fix moves
# only the ASSEMBLY off argv, and the per-row jq calls still pass claim, detail
# and anchor as --arg, so a 9,000-character name would put a single row call
# within a few kilobytes of the same cap and fail for a reason this case is not
# about.
#
# WINDOWS-ONLY. The argument cap off Windows is orders of magnitude larger, so
# this case passes on Linux and macOS whether the defect is present or not. A
# green non-Windows lane is not coverage for it.
m="$(make_machine bigpayload)"
printf '%s\n' "$CLEAN_SETTINGS" >"$m/project/.claude/settings.json"
pad="$(printf '%*s' 3000 '' | tr ' ' 'x')"
printf '{"mcpServers":{' >"$m/project/.mcp.json"
sep=""
for i in 1 2 3 4; do
  printf '%s"srv%s-%s":{"command":"jq"}' "$sep" "$i" "$pad" >>"$m/project/.mcp.json"
  sep=","
done
printf '}}\n' >>"$m/project/.mcp.json"
rc=0
# stderr is captured SEPARATELY here, unlike every other case. The usual 2>&1
# idiom merges the overflow diagnostic into the captured document, which leaves
# the assertions below nothing parseable to read.
out=$(run "$m" --json --out "$m/findings.json" 2>"$m/err") || rc=$?
assert_exit "case 21: the unlisted servers still make it exit 1" 1 "$rc"
assert_eq "case 21: the payload is over the Win32 command-line cap" "true" "$([[ ${#out} -gt 32764 ]] && echo true || echo false)"
assert_eq "case 21: assembly did not overflow the command line" "0" "$(grep -c 'Argument list too long' "$m/err")"
assert_eq "case 21: the document parses" "object" "$(jq -r 'type' <<<"$out" 2>/dev/null)"
# The padded server names are what pushes the payload over the cap, so proving
# they reached the document proves the oversize payload survived the transport.
# Counted from the document rather than hardcoded beyond the fixture's own four
# servers, so an unrelated new check does not break the case. `.summary.rows`
# against `.rows | length` would NOT do: the document builds the former from the
# latter in one jq expression, so they can never disagree.
assert_eq "case 21: every padded server name survived the transport" "4" "$(jq --arg p "$pad" '[.rows[] | select(.claim | startswith("unlisted-server:")) | select(.claim | contains($p))] | length' <<<"$out")"
assert_eq "case 21: the document carries rows" "true" "$(jq '(.rows | length) > 0' <<<"$out")"
assert_eq "case 21: findings file written" "true" "$([[ -f "$m/findings.json" ]] && echo true || echo false)"
assert_eq "case 21: the findings file carries the findings" "true" "$(jq '(.findings | length) > 0' "$m/findings.json" 2>/dev/null)"
assert_eq "case 21: findings file matches the document" "$(jq '.findings | length' <<<"$out")" "$(jq '.findings | length' "$m/findings.json")"

# --- Case 22: an env key is matched as a fixed string, not a pattern -----------
m="$(make_machine envdot)"
printf '%s\n' "$CLEAN_SETTINGS" | jq '. + {env:{"A.B":"1",AXB:"1"}}' >"$m/project/.claude/settings.json"
out=$(run "$m" --json --docs-dir "$DOCS" 2>&1) || true
assert_eq "case 22: a dot in a key does not match the page's AXB" "info" "$(jq -r '.findings[] | select(.identity.claim=="not-on-env-vars-page:A.B") | .severity' <<<"$out")"
assert_eq "case 22: the literal key is documented" "ok" "$(jq -r '.rows[] | select(.claim=="documented-on-env-vars:AXB") | .status' <<<"$out")"

# --- Case 23: the CLI version is recorded and gates version-bound rows ---------
m="$(make_machine version)"
printf '%s\n' "$CLEAN_SETTINGS" | jq '. + {voiceEnabled:true,laterKey:true,disableArtifact:true,enforceAvailableModels:true}' >"$m/project/.claude/settings.json"
rc=0
out=$(run "$m" --json 2>&1) || rc=$?
assert_exit "case 23: enforce without a list on a new enough CLI exits 1" 1 "$rc"
assert_eq "case 23: version read" "read 2.1.281" "$(jq -r '.claude_version | "\(.state) \(.version)"' <<<"$out")"
assert_eq "case 23: raw output kept" "2.1.281 (Claude Code)" "$(jq -r '.claude_version.raw' <<<"$out")"
assert_eq "case 23: a key deprecated since an older version is a warning" "warning" "$(jq -r '.findings[] | select(.identity.claim=="deprecated-key:voiceEnabled") | .severity' <<<"$out")"
assert_contains "case 23: the Deprecated line is quoted" "$(jq -r '.findings[] | select(.identity.claim=="deprecated-key:voiceEnabled") | .detail' <<<"$out")" "Deprecated since v2.1.92, when the"
assert_eq "case 23: a Deprecated line with no version is an ungated warning" "warning" "$(jq -r '.findings[] | select(.identity.claim=="deprecated-key:disableArtifact") | .severity' <<<"$out")"
assert_eq "case 23: the first Requires line gates enforceAvailableModels" "error" "$(jq -r '.findings[] | select(.identity.claim=="enforceAvailableModels-without-list") | .severity' <<<"$out")"
rc=0
out=$(CLI_BIN="$m/no-such-claude" run "$m" --json 2>&1) || rc=$?
assert_exit "case 23: an unreadable version gates the error away" 0 "$rc"
assert_eq "case 23: a missing CLI is unreadable, never the host claude" "unreadable null" "$(jq -r '.claude_version | "\(.state) \(.version)"' <<<"$out")"
assert_eq "case 23: a since-gated deprecation is a skip" "skip" "$(jq -r '.rows[] | select(.claim=="deprecated-key:voiceEnabled") | .status' <<<"$out")"
assert_eq "case 23: the ungated deprecation still stands" "warning" "$(jq -r '.findings[] | select(.identity.claim=="deprecated-key:disableArtifact") | .severity' <<<"$out")"
assert_eq "case 23: the version-gated enforce row is a skip" "skip" "$(jq -r '.rows[] | select(.claim=="enforceAvailableModels-without-list") | .status' <<<"$out")"
make_cli "$m/claude-old" "2.1.92 (Claude Code)" enabledPlugins permissions
rc=0
out=$(CLI_BIN="$m/claude-old" run "$m" --json 2>&1) || rc=$?
assert_exit "case 23: an older CLI does not read enforceAvailableModels" 0 "$rc"
assert_eq "case 23: 2.1.92 is older than 2.1.281 (numeric compare)" "ok" "$(jq -r '.rows[] | select(.claim=="deprecated-key:laterKey") | .status' <<<"$out")"
assert_eq "case 23: the enforce row is ok with the reason" "ok" "$(jq -r '.rows[] | select(.claim=="enforceAvailableModels-without-list") | .status' <<<"$out")"
assert_contains "case 23: the reason names the required version" "$(jq -r '.rows[] | select(.claim=="enforceAvailableModels-without-list") | .detail' <<<"$out")" "v2.1.175"
assert_eq "case 23: deprecated since the installed version itself is a warning" "warning" "$(jq -r '.findings[] | select(.identity.claim=="deprecated-key:voiceEnabled") | .severity' <<<"$out")"

# --- Case 24: the document lists every page it read, with byte counts ---------
m="$(make_machine coverage)"
printf '%s\n' "$CLEAN_SETTINGS" >"$m/project/.claude/settings.json"
out=$(run "$m" --json 2>&1) || true
assert_eq "case 24: index read with its byte count" "read $(wc -c <"$DOCS/llms.txt" | tr -d ' ')" "$(jq -r '.docs.index | "\(.state) \(.bytes)"' <<<"$out")"
assert_eq "case 24: settings-reference resolved from the index" "read fixture https://code.claude.com/docs/en/settings-reference.md" "$(jq -r '.docs.pages[] | select(.slug=="settings-reference") | "\(.state) \(.source) \(.url_or_path)"' <<<"$out")"
assert_eq "case 24: its byte count is the page's" "$(wc -c <"$DOCS/settings-reference.md" | tr -d ' ')" "$(jq -r '.docs.pages[] | select(.slug=="settings-reference") | .bytes' <<<"$out")"
assert_eq "case 24: env-vars read" "read" "$(jq -r '.docs.pages[] | select(.slug=="env-vars") | .state' <<<"$out")"
mkdir -p "$m/partial"
cp "$DOCS/env-vars.md" "$m/partial/"
out=$(run "$m" --json --docs-dir "$m/partial" 2>&1) || true
# Compared by suffix: on Git for Windows the path reaches jq respelled as C:/...
assert_eq "case 24: a --docs-dir page is read from there" "docs-dir true" "$(jq -r '.docs.pages[] | select(.slug=="env-vars") | "\(.source) \(.url_or_path | endswith("/partial/env-vars.md"))"' <<<"$out")"
assert_eq "case 24: a page missing from --docs-dir resolves through the index" "read fixture" "$(jq -r '.docs.pages[] | select(.slug=="settings-reference") | "\(.state) \(.source)"' <<<"$out")"
out=$(run "$m" --json --docs-dir "$DOCS" 2>&1) || true
assert_eq "case 24: every page from --docs-dir leaves the index not needed" "not-needed" "$(jq -r '.docs.index.state' <<<"$out")"

# --- Case 25: an unread index leaves every page unread, every row undecided ----
m="$(make_machine noindex)"
mkdir -p "$m/noindex"
cp "$DOCS/settings-reference.md" "$DOCS/env-vars.md" "$m/noindex/"
printf '%s\n' "$CLEAN_SETTINGS" | jq '. + {env:{MY_SINK:"x"},effortLevel:"max",enforceAvailableModels:true,disableDeepLinkRegistration:true}' >"$m/project/.claude/settings.json"
rc=0
out=$(DOCS_FIXTURE="$m/noindex" run "$m" --json 2>&1) || rc=$?
assert_exit "case 25: no row resting on an unread page is an error" 0 "$rc"
assert_eq "case 25: the index is unread" "unread" "$(jq -r '.docs.index.state' <<<"$out")"
assert_eq "case 25: both pages unread for that reason" "index-unread index-unread" "$(jq -r '[.docs.pages[] | select(.state=="unread") | .reason] | join(" ")' <<<"$out")"
assert_eq "case 25: the env row is not inspectable" "not-inspectable" "$(jq -r '.rows[] | select(.claim=="env-page-not-fetched:MY_SINK") | .status' <<<"$out")"
assert_eq "case 25: the key rows are not inspectable" "not-inspectable" "$(jq -r '.rows[] | select(.claim=="key-page-not-fetched:permissions") | .status' <<<"$out")"
assert_eq "case 25: the effortLevel row is not inspectable" "not-inspectable" "$(jq -r '.rows[] | select(.claim=="effortLevel:max") | .status' <<<"$out")"
assert_eq "case 25: the enforce row is not inspectable" "not-inspectable" "$(jq -r '.rows[] | select(.claim=="enforceAvailableModels-without-list") | .status' <<<"$out")"
assert_eq "case 25: the deep-link row is not inspectable" "not-inspectable" "$(jq -r '.rows[] | select(.claim=="disableDeepLinkRegistration:true") | .status' <<<"$out")"
assert_eq "case 25: no finding rests on an unread page" "0" "$(jq '[.findings[] | select(.category=="A" or .category=="H" or .category=="I" or (.identity.claim | startswith("not-on-env-vars-page:")))] | length' <<<"$out")"

# --- Case 26: a page the index does not link, or links off-origin, is unread ---
m="$(make_machine offorigin)"
mkdir -p "$m/docs"
cp "$DOCS/settings-reference.md" "$DOCS/env-vars.md" "$m/docs/"
printf '%s\n' '# Claude Code Docs' '' '- [All settings](https://elsewhere.example/docs/en/settings-reference.md): moved off-site.' >"$m/docs/llms.txt"
printf '%s\n' "$CLEAN_SETTINGS" >"$m/project/.claude/settings.json"
out=$(DOCS_FIXTURE="$m/docs" run "$m" --json 2>&1) || true
assert_eq "case 26: an off-origin link is not followed" "unread off-origin" "$(jq -r '.docs.pages[] | select(.slug=="settings-reference") | "\(.state) \(.reason)"' <<<"$out")"
assert_eq "case 26: a page the index does not list is unread" "unread not-in-index" "$(jq -r '.docs.pages[] | select(.slug=="env-vars") | "\(.state) \(.reason)"' <<<"$out")"

# --- Case 27: undocumented keys, settled by the installed binary ---------------
m="$(make_machine keys)"
printf '%s\n' "$CLEAN_SETTINGS" | jq '. + {internalOnlyKey:true,zzBogusKey:1,"":1} | .permissions += {disableAutoMode:"disable",zzBogusPerm:[],"":1}' >"$m/project/.claude/settings.json"
printf '%s\n' '{"zzLocalKey":1}' >"$m/project/.claude/settings.local.json"
out=$(run "$m" --json 2>&1) || true
# An empty key name is left out: it has no literal to look up.
assert_eq "case 27: an empty key name raises no shell error" "0" "$(grep -c 'bad array subscript' <<<"$out")"
assert_eq "case 27: an empty key name gets no key row" "0" "$(jq '[.rows[] | select(.check | test("/A/key-")) | select(.claim | test(":(permissions\\.)?$"))] | length' <<<"$out" 2>/dev/null || echo unparsed)"
assert_eq "case 27: the binary was searched" "searched" "$(jq -r '.claude_version.binary.key_search' <<<"$out")"
assert_eq "case 27: a key the binary carries is info" "info" "$(jq -r '.findings[] | select(.identity.claim=="undocumented-key:internalOnlyKey") | .severity' <<<"$out")"
assert_contains "case 27: it says the binary carries the name standalone" "$(jq -r '.findings[] | select(.identity.claim=="undocumented-key:internalOnlyKey") | .detail' <<<"$out")" "as a standalone name"
assert_eq "case 27: a key in neither is a warning under the same claim" "warning" "$(jq -r '.findings[] | select(.identity.claim=="undocumented-key:zzBogusKey") | .severity' <<<"$out")"
assert_eq "case 27: a nested permissions key in neither is a warning" "warning" "$(jq -r '.findings[] | select(.identity.claim=="undocumented-key:permissions.zzBogusPerm") | .severity' <<<"$out")"
assert_eq "case 27: a key named only in the permissions Type bullet is documented" "ok" "$(jq -r '.rows[] | select(.claim=="documented-key:permissions.disableAutoMode") | .status' <<<"$out")"
assert_eq "case 27: a key with its own heading is documented" "ok" "$(jq -r '.rows[] | select(.claim=="documented-key:permissions.deny") | .status' <<<"$out")"
assert_eq "case 27: the local scope is checked too" ".claude/settings.local.json" "$(jq -r '.findings[] | select(.identity.claim=="undocumented-key:zzLocalKey") | .identity.sites[0].surface' <<<"$out")"
assert_eq "case 27: \$schema is never a key row" "0" "$(jq '[.rows[] | select(.claim | test("key:\\$schema$"))] | length' <<<"$out")"
printf '%s\n' '{"describedKey":1}' >"$m/project/.claude/settings.local.json"
make_cli "$m/claude-desc" "2.1.281 (Claude Code)" enabledPlugins permissions 'describedKey:z.boolean().optional().describe("@internal Whether the user has accepted it")'
out=$(CLI_BIN="$m/claude-desc" run "$m" --json 2>&1) || true
assert_contains "case 27: the binary's describe string is quoted" "$(jq -r '.findings[] | select(.identity.claim=="undocumented-key:describedKey") | .detail' <<<"$out")" '"@internal Whether the user has accepted it"'
printf '%s\n' '{"ownKey":1,"bareKey":1}' >"$m/project/.claude/settings.local.json"
make_cli "$m/claude-neighbor" "2.1.281 (Claude Code)" enabledPlugins permissions \
  'paths:[{path:["bareKey"]},{path:["ownKey"]}],other:z.string().describe("Elsewhere text")' \
  'ownKey:z.boolean().describe("Own text"),bareKey:z.boolean().optional(),neighborKey:z.string().describe("Neighbor text")'
out=$(CLI_BIN="$m/claude-neighbor" run "$m" --json 2>&1) || true
own_detail="$(jq -r '.findings[] | select(.identity.claim=="undocumented-key:ownKey") | .detail' <<<"$out")"
bare_detail="$(jq -r '.findings[] | select(.identity.claim=="undocumented-key:bareKey") | .detail' <<<"$out")"
assert_contains "case 27: a key is described by its own entry" "$own_detail" '"Own text"'
assert_eq "case 27: a key's describe is not a neighbor's or another site's string" "0" "$(grep -c -e 'Neighbor text' -e 'Elsewhere text' <<<"$own_detail")"
assert_eq "case 27: a key with no describe of its own is quoted nothing" "0" "$(grep -c -e 'the binary describes it' -e 'Neighbor text' -e 'Elsewhere text' <<<"$bare_detail")"
printf '%s\n' '{"sharedKey":1,"repeatKey":1}' >"$m/project/.claude/settings.local.json"
make_cli "$m/claude-shared" "2.1.281 (Claude Code)" enabledPlugins permissions \
  'sharedKey:z.number().describe("A tool input text")' \
  'sharedKey:z.number().optional().describe("Another schema text")' \
  'repeatKey:z.boolean().describe("Same text")' \
  'repeatKey:z.boolean().optional().describe("Same text")'
out=$(CLI_BIN="$m/claude-shared" run "$m" --json 2>&1) || true
shared_detail="$(jq -r '.findings[] | select(.identity.claim=="undocumented-key:sharedKey") | .detail' <<<"$out")"
repeat_detail="$(jq -r '.findings[] | select(.identity.claim=="undocumented-key:repeatKey") | .detail' <<<"$out")"
assert_eq "case 27: a name declared in two schemas with different describes is quoted nothing" "0" "$(grep -c -e 'the binary describes it' -e 'A tool input text' -e 'Another schema text' <<<"$shared_detail")"
assert_contains "case 27: a name whose declarations all carry one describe is quoted" "$repeat_detail" '"Same text"'
make_cli "$m/claude-shim" "2.1.281 (Claude Code)" internalOnlyKey
out=$(CLI_BIN="$m/claude-shim" run "$m" --json 2>&1) || true
assert_eq "case 27: a file without the control literals was not searched" "not-searched" "$(jq -r '.claude_version.binary.key_search' <<<"$out")"
assert_eq "case 27: so an absent key is info, never a warning" "info 0" "$(jq -r '[(.findings[] | select(.identity.claim=="undocumented-key:zzBogusKey") | .severity), ([.findings[] | select(.identity.claim | startswith("undocumented-key:")) | select(.severity=="warning")] | length | tostring)] | join(" ")' <<<"$out")"

# --- Case 28: a key's section ends at the next heading of any level -----------
m="$(make_machine sections)"
printf '%s\n' "$CLEAN_SETTINGS" | jq '. + {enabledPlugins:{},fastMode:true,codeFenced:true}' >"$m/project/.claude/settings.json"
out=$(run "$m" --json 2>&1) || true
assert_eq "case 28: the settings index after a section does not deprecate it" "ok" "$(jq -r '.rows[] | select(.claim=="documented-key:enabledPlugins") | .status' <<<"$out")"
assert_eq "case 28: a Deprecated line under a #### subheading is not the key's" "ok" "$(jq -r '.rows[] | select(.claim=="documented-key:fastMode") | .status' <<<"$out")"
assert_eq "case 28: a # line inside a code fence does not end the section" "warning" "$(jq -r '.findings[] | select(.identity.claim=="deprecated-key:codeFenced") | .severity' <<<"$out")"

# --- Case 29: accepted values come from the key's Type bullet ------------------
m="$(make_machine typevalues)"
printf '%s\n' "$CLEAN_SETTINGS" | jq '. + {effortLevel:"bogus",disableDeepLinkRegistration:"disable"}' >"$m/project/.claude/settings.json"
printf '%s\n' '{"effortLevel":"high"}' >"$m/user/settings.json"
out=$(run "$m" --json 2>&1) || true
assert_eq "case 29: a value outside the documented set is a warning" "warning" "$(jq -r '.findings[] | select(.identity.claim=="effortLevel:bogus") | .severity' <<<"$out")"
assert_contains "case 29: the detail lists the documented set" "$(jq -r '.findings[] | select(.identity.claim=="effortLevel:bogus") | .detail' <<<"$out")" "low, medium, high, xhigh"
assert_eq "case 29: a documented value is ok" "ok" "$(jq -r '.rows[] | select(.claim=="effortLevel:high") | .status' <<<"$out")"
assert_eq "case 29: the inline string shape parses" "ok" "$(jq -r '.rows[] | select(.claim=="disableDeepLinkRegistration:disable") | .status' <<<"$out")"
mkdir -p "$m/oddtype"
cp "$DOCS/llms.txt" "$DOCS/env-vars.md" "$m/oddtype/"
sed 's/^\* \*\*Type\*\*: string, one of:$/* **Type**: string/; s/^\* \*\*Type\*\*: the string `"disable"`$/* **Type**: string/' "$DOCS/settings-reference.md" >"$m/oddtype/settings-reference.md"
out=$(DOCS_FIXTURE="$m/oddtype" run "$m" --json 2>&1) || true
assert_eq "case 29: an unparsable Type bullet is a skip" "skip" "$(jq -r '.rows[] | select(.claim=="effortLevel:bogus") | .status' <<<"$out")"
assert_eq "case 29: for the deep-link key too" "skip" "$(jq -r '.rows[] | select(.claim=="disableDeepLinkRegistration:disable") | .status' <<<"$out")"

# --- Case 30: the table prints the version and the docs coverage --------------
m="$(make_machine tablecoverage)"
printf '%s\n' "$CLEAN_SETTINGS" >"$m/project/.claude/settings.json"
out=$(run "$m" --table 2>&1) || true
assert_contains "case 30: table prints the version" "$out" "Claude Code: 2.1.281 (read"
assert_contains "case 30: table prints the index" "$out" "index: read $(wc -c <"$DOCS/llms.txt" | tr -d ' ') bytes"
assert_contains "case 30: table prints each page" "$out" "settings-reference: read $(wc -c <"$DOCS/settings-reference.md" | tr -d ' ') bytes"

# --- Case 31: the default route fetches the index, then the pages it links ----
# The one case with the docs fixture seam unset: a curl stand-in first on PATH
# serves local files and logs every request, so nothing reaches the network.
m="$(make_machine fetch)"
printf '%s\n' "$CLEAN_SETTINGS" >"$m/project/.claude/settings.json"
mkdir -p "$m/shim" "$m/served"
cat >"$m/shim/curl" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"$CURL_SHIM_LOG"
out="" url="" wfmt=""
while [[ $# -gt 0 ]]; do
  case "$1" in
  -o | -w | --connect-timeout | --max-time | --proto | --proto-redir | --max-redirs)
    [[ "$1" == "-o" ]] && out="$2"
    [[ "$1" == "-w" ]] && wfmt="$2"
    shift 2
    ;;
  -*) shift ;;
  *) url="$1"; shift ;;
  esac
done
name="${url##*/}"
src="$CURL_SHIM_SRC/$name"
[[ -f "$src" ]] || exit 22
cp "$src" "$out"
# A <name>.status or <name>.ctype sidecar overrides the HTTP status or content type.
status=200
[[ -f "$src.status" ]] && status="$(cat "$src.status")"
ctype="text/markdown; charset=utf-8"
[[ "$name" == llms.txt ]] && ctype="text/plain; charset=utf-8"
[[ -f "$src.ctype" ]] && ctype="$(cat "$src.ctype")"
# The final URL, after any redirect.
effective="$url"
[[ -n "${CURL_SHIM_REDIRECT:-}" && "$url" == *settings-reference.md ]] && effective="$CURL_SHIM_REDIRECT"
wfmt="${wfmt//%\{http_code\}/$status}"
wfmt="${wfmt//%\{url_effective\}/$effective}"
wfmt="${wfmt//%\{content_type\}/$ctype}"
printf '%s' "$wfmt"
exit 0
EOF
chmod +x "$m/shim/curl"
cp "$DOCS/settings-reference.md" "$DOCS/env-vars.md" "$m/served/"
printf '%s\n' '# Docs' '- [All settings](https://docs.test/docs/en/settings-reference.md): keys' '- [Environment variables](https://other.test/docs/en/env-vars.md): vars' >"$m/served/llms.txt"
fetch_run() {
  env -u FETCH_DOCS_FIXTURE_DIR PATH="$m/shim:$PATH" CURL_SHIM_LOG="$m/curl.log" CURL_SHIM_SRC="$m/served" \
    CURL_SHIM_REDIRECT="${CURL_SHIM_REDIRECT:-}" \
    SETTINGS_AUDIT_ENGINE_FIXTURE_DIR="$m/project" SETTINGS_AUDIT_ENGINE_USER_DIR="$m/user" \
    SETTINGS_AUDIT_ENGINE_INSTALLED_JSON="$m/registry.json" SETTINGS_AUDIT_ENGINE_BASELINE_FILE="$BASELINE" \
    SETTINGS_AUDIT_ENGINE_DEBUG_DIR="$m/debug" SETTINGS_AUDIT_ENGINE_SKIP_DRIFT=1 CLAUDE_CODE_DEBUG_LOGS_DIR="" \
    FETCH_DOCS_INDEX_URL="https://docs.test/docs/llms.txt" SETTINGS_AUDIT_ENGINE_CLAUDE_BIN="$CLI" \
    bash "$SCRIPT" --json 2>&1
}
out=$(fetch_run) || true
assert_eq "case 31: the index is fetched" "read fetch" "$(jq -r '.docs.index | "\(.state) \(.source)"' <<<"$out")"
assert_eq "case 31: a page is fetched from the URL the index links" "read fetch https://docs.test/docs/en/settings-reference.md" "$(jq -r '.docs.pages[] | select(.slug=="settings-reference") | "\(.state) \(.source) \(.url_or_path)"' <<<"$out")"
assert_eq "case 31: an off-origin page is not fetched" "unread off-origin" "$(jq -r '.docs.pages[] | select(.slug=="env-vars") | "\(.state) \(.reason)"' <<<"$out")"
assert_eq "case 31: two requests, the index then the one page" "https://docs.test/docs/llms.txt https://docs.test/docs/en/settings-reference.md" "$(awk '{print $NF}' "$m/curl.log" | paste -sd' ' -)"
assert_eq "case 31: every request carries a connect timeout and a max time" "2" "$(grep -c -- '--connect-timeout .* --max-time ' "$m/curl.log")"
assert_eq "case 31: every request is HTTPS only, redirects included and capped" "2" "$(grep -c -- '--proto =https --proto-redir =https --max-redirs 5 ' "$m/curl.log")"
rm -f "$m/curl.log"
out=$(CURL_SHIM_REDIRECT="https://elsewhere.example/docs/en/settings-reference.md" fetch_run) || true
assert_eq "case 31: a page redirected off-origin is unread" "unread redirected-off-origin" "$(jq -r '.docs.pages[] | select(.slug=="settings-reference") | "\(.state) \(.reason)"' <<<"$out")"
rm -f "$m/curl.log" "$m/served/llms.txt"
out=$(fetch_run) || true
assert_eq "case 31: an index that fails to fetch is unread" "unread fetch-failed" "$(jq -r '.docs.index | "\(.state) \(.reason)"' <<<"$out")"
assert_eq "case 31: and no page is requested after it" "1" "$(wc -l <"$m/curl.log" | tr -d ' ')"

# The fetcher's manifest fields ride into the --json record of a fetched page.
printf '%s\n' '# Docs' '- [All settings](https://docs.test/docs/en/settings-reference.md): keys' >"$m/served/llms.txt"
rm -f "$m/curl.log"
out=$(fetch_run) || true
page_json="$(jq -c '.docs.pages[] | select(.slug=="settings-reference")' <<<"$out")"
assert_eq "case 31: a fetched page records its sha256" "$(sha256sum <"$m/served/settings-reference.md" | cut -d" " -f1)" "$(jq -r '.sha256' <<<"$page_json")"
assert_eq "case 31: a fetched page records its content type" "text/markdown; charset=utf-8" "$(jq -r '.content_type' <<<"$page_json")"
assert_eq "case 31: a fetched page records its line count" "$(awk 'END { print NR }' "$m/served/settings-reference.md")" "$(jq -r '.lines' <<<"$page_json")"
assert_eq "case 31: a fetched page records its byte count" "$(wc -c <"$m/served/settings-reference.md" | tr -d ' ')" "$(jq -r '.bytes' <<<"$page_json")"
assert_eq "case 31: a fetched page records when it was read" "1" "$(jq -r '.retrieved | test("^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9:]{8}Z$") | if . then 1 else 0 end' <<<"$page_json")"
assert_eq "case 31: a fetched page carries no failure reason" "" "$(jq -r '.reason' <<<"$page_json")"
assert_eq "case 31: the index records its sha256 too" "$(sha256sum <"$m/served/llms.txt" | cut -d" " -f1)" "$(jq -r '.docs.index.sha256' <<<"$out")"

# A 404 or a text/html body is unread, and every row resting on the page stays
# not-inspectable.
printf '%s\n' "$CLEAN_SETTINGS" | jq '. + {effortLevel:"max",zzBogusKey:1}' >"$m/project/.claude/settings.json"
for bad in status ctype; do
  rm -f "$m/served/settings-reference.md.status" "$m/served/settings-reference.md.ctype"
  if [[ $bad == status ]]; then
    printf '404' >"$m/served/settings-reference.md.status"
    want="http-404"
  else
    printf 'text/html; charset=utf-8' >"$m/served/settings-reference.md.ctype"
    want="unexpected-content-type"
  fi
  out=$(fetch_run) || true
  assert_eq "case 31 ($bad): the page is unread with the reason" "unread $want" "$(jq -r '.docs.pages[] | select(.slug=="settings-reference") | "\(.state) \(.reason)"' <<<"$out")"
  assert_eq "case 31 ($bad): the page has no hash" "null" "$(jq -r '.docs.pages[] | select(.slug=="settings-reference") | .sha256' <<<"$out")"
  assert_eq "case 31 ($bad): the key row is not inspectable" "not-inspectable" "$(jq -r '.rows[] | select(.claim=="key-page-not-fetched:zzBogusKey") | .status' <<<"$out")"
  assert_eq "case 31 ($bad): the value row is not inspectable" "not-inspectable" "$(jq -r '.rows[] | select(.claim=="effortLevel:max") | .status' <<<"$out")"
done
rm -f "$m/served/settings-reference.md.status" "$m/served/settings-reference.md.ctype"

# A page settings-reference links to is a second fetcher call: the index again,
# then that page, from the URL the index gives it.
docs_with_link "$m/linked" hooks
cp "$m/linked/settings-reference.md" "$m/served/settings-reference.md"
cp "$HOOKS_MD" "$m/served/hooks.md"
printf '%s\n' '# Docs' '- [All settings](https://docs.test/docs/en/settings-reference.md): keys' '- [Hooks](https://docs.test/docs/en/hooks.md): hooks' >"$m/served/llms.txt"
rm -f "$m/curl.log"
out=$(fetch_run) || true
assert_eq "case 31: a linked page is fetched from the URL the index gives it" "read fetch https://docs.test/docs/en/hooks.md" "$(jq -r '.docs.pages[] | select(.slug=="hooks") | "\(.state) \(.source) \(.url_or_path)"' <<<"$out")"
assert_eq "case 31: the linked page costs one more index read and one page read" "https://docs.test/docs/llms.txt https://docs.test/docs/en/settings-reference.md https://docs.test/docs/llms.txt https://docs.test/docs/en/hooks.md" "$(awk '{print $NF}' "$m/curl.log" | paste -sd' ' -)"

# --- Case 32: a read page that does not parse fails closed --------------------
# A soft 404 arrives as a page with a body and no key headings. Read at face
# value it would make every key undocumented; the positive control stops that.
m="$(make_machine soft404)"
mkdir -p "$m/docs"
cp "$DOCS/llms.txt" "$DOCS/env-vars.md" "$m/docs/"
printf '%s\n' '<!DOCTYPE html>' '<html><body><h1>Page not found</h1></body></html>' >"$m/docs/settings-reference.md"
printf '%s\n' "$CLEAN_SETTINGS" | jq '. + {effortLevel:"max",enforceAvailableModels:true,zzBogusKey:1}' >"$m/project/.claude/settings.json"
rc=0
out=$(DOCS_FIXTURE="$m/docs" run "$m" --json 2>&1) || rc=$?
assert_exit "case 32: nothing resting on the unparsed page is an error" 0 "$rc"
assert_eq "case 32: the page is recorded unparsed, not read" "unparsed no-key-headings" "$(jq -r '.docs.pages[] | select(.slug=="settings-reference") | "\(.state) \(.reason)"' <<<"$out")"
assert_eq "case 32: key rows are not inspectable" "not-inspectable" "$(jq -r '.rows[] | select(.claim=="key-page-not-fetched:zzBogusKey") | .status' <<<"$out")"
assert_contains "case 32: the reason names the page as unparsed" "$(jq -r '.rows[] | select(.claim=="key-page-not-fetched:zzBogusKey") | .detail' <<<"$out")" "did not parse"
assert_eq "case 32: the derived value row is not inspectable" "not-inspectable" "$(jq -r '.rows[] | select(.claim=="effortLevel:max") | .status' <<<"$out")"
assert_eq "case 32: the gated enforce row is not inspectable" "not-inspectable" "$(jq -r '.rows[] | select(.claim=="enforceAvailableModels-without-list") | .status' <<<"$out")"
assert_eq "case 32: no undocumented-key finding" "0" "$(jq '[.findings[] | select(.identity.claim | startswith("undocumented-key:"))] | length' <<<"$out")"

# --- Case 33: CRLF pages parse the same as LF pages ----------------------------
m="$(make_machine crlf)"
mkdir -p "$m/docs"
sed 's/$/\r/' "$DOCS/llms.txt" >"$m/docs/llms.txt"
sed 's/$/\r/' "$DOCS/settings-reference.md" >"$m/docs/settings-reference.md"
cp "$DOCS/env-vars.md" "$m/docs/"
printf '%s\n' "$CLEAN_SETTINGS" | jq '. + {voiceEnabled:true,effortLevel:"bogus",disableDeepLinkRegistration:"disable"} | .permissions += {disableAutoMode:"disable"}' >"$m/project/.claude/settings.json"
out=$(DOCS_FIXTURE="$m/docs" run "$m" --json 2>&1) || true
assert_eq "case 33: the CRLF page resolves and reads" "read read" "$(jq -r '[.docs.index.state, (.docs.pages[] | select(.slug=="settings-reference") | .state)] | join(" ")' <<<"$out")"
assert_eq "case 33: the deprecation is found" "warning" "$(jq -r '.findings[] | select(.identity.claim=="deprecated-key:voiceEnabled") | .severity' <<<"$out")"
assert_eq "case 33: the quoted line carries no CR" "false" "$(jq -r '.findings[] | select(.identity.claim=="deprecated-key:voiceEnabled") | .detail | test("\r")' <<<"$out")"
assert_contains "case 33: the list-shaped Type bullet parses" "$(jq -r '.findings[] | select(.identity.claim=="effortLevel:bogus") | .detail' <<<"$out")" "low, medium, high, xhigh"
assert_eq "case 33: the inline Type bullet parses" "ok" "$(jq -r '.rows[] | select(.claim=="disableDeepLinkRegistration:disable") | .status' <<<"$out")"
assert_eq "case 33: the permissions Type bullet parses" "ok" "$(jq -r '.rows[] | select(.claim=="documented-key:permissions.disableAutoMode") | .status' <<<"$out")"

# --- Case 34: control characters in the CLI's output never reach the document -
m="$(make_machine cntrl)"
printf '%s\n' "$CLEAN_SETTINGS" >"$m/project/.claude/settings.json"
make_cli "$m/claude-esc" $'\e[1m2.1.281\e[0m (Claude Code)' enabledPlugins permissions
out=$(CLI_BIN="$m/claude-esc" run "$m" --json 2>&1) || true
assert_eq "case 34: the version still parses" "2.1.281" "$(jq -r '.claude_version.version' <<<"$out")"
assert_eq "case 34: the raw line carries no control character" "0" "$(jq '[.claude_version.raw | explode[] | select(. < 32 or . == 127)] | length' <<<"$out" | tr -d '\r')"
assert_contains "case 34: the printable text survives" "$(jq -r '.claude_version.raw' <<<"$out")" "(Claude Code)"

# --- Case 35: a multi-line value is matched as one whole string ----------------
# grep reads each line of a multi-line pattern on its own, so a value whose
# second line is a documented one would pass.
m="$(make_machine multiline)"
printf '%s\n' "$CLEAN_SETTINGS" | jq '. + {effortLevel:"bogus\nhigh",disableDeepLinkRegistration:"disable\nzzz"}' >"$m/project/.claude/settings.json"
out=$(run "$m" --json 2>&1) || true
assert_eq "case 35: an effortLevel with a documented second line is a warning" "warning" "$(jq -r '.findings[] | select(.identity.claim=="effortLevel:bogus\nhigh") | .severity' <<<"$out")"
assert_eq "case 35: a deep-link value with a documented first line is a warning" "warning" "$(jq -r '.findings[] | select(.identity.claim=="disableDeepLinkRegistration:disable\nzzz") | .severity' <<<"$out")"

# --- Case 36: key identity carries the key exactly as written -------------------
m="$(make_machine rawkeys)"
printf '%s\n' "$CLEAN_SETTINGS" | jq '. + {"a\tb":1,"c\\d":1}' >"$m/project/.claude/settings.json"
out=$(run "$m" --json 2>&1) || true
assert_eq "case 36: a key with a tab keeps the tab in its claim" "1" "$(jq '[.findings[] | select(.identity.claim=="undocumented-key:a\tb")] | length' <<<"$out")"
assert_eq "case 36: a key with a backslash keeps one backslash" "1" "$(jq '[.findings[] | select(.identity.claim=="undocumented-key:c\\d")] | length' <<<"$out")"
assert_eq "case 36: no claim carries tab-separated escaping" "0" "$(jq '[.findings[] | select(.identity.claim | test("a\\\\tb|c\\\\\\\\d"))] | length' <<<"$out")"

# --- Case 37: the binary tie-breaker needs a standalone, searchable name --------
m="$(make_machine standalone)"
printf '%s\n' "$CLEAN_SETTINGS" | jq '. + {e:1,Plugins:1}' >"$m/project/.claude/settings.json"
out=$(run "$m" --json 2>&1) || true
assert_eq "case 37: a name that only occurs inside a longer one is absent" "warning" "$(jq -r '.findings[] | select(.identity.claim=="undocumented-key:Plugins") | .severity' <<<"$out")"
assert_eq "case 37: a one-letter name is not settled by the binary" "info" "$(jq -r '.findings[] | select(.identity.claim=="undocumented-key:e") | .severity' <<<"$out")"
assert_contains "case 37: and says why" "$(jq -r '.findings[] | select(.identity.claim=="undocumented-key:e") | .detail' <<<"$out")" "too short or not identifier-shaped"

# add_plugin <root> <name> <plugin.json text | -> [<name> <text> ...]: installed
# plugin directories under <root>/plugins and a registry naming each as
# <name>@mkt at user scope. "-" writes no plugin.json.
add_plugin() {
  local root="$1" reg='{"plugins":{}}' dir
  shift
  while [[ $# -ge 2 ]]; do
    dir="$root/plugins/$1"
    mkdir -p "$dir/.claude-plugin"
    [[ "$2" != "-" ]] && printf '%s\n' "$2" >"$dir/.claude-plugin/plugin.json"
    reg="$(jq -c --arg k "$1@mkt" --arg p "$dir" '.plugins[$k] = [{installPath: $p, scope: "user"}]' <<<"$reg")"
    shift 2
  done
  printf '%s\n' "$reg" >"$root/registry.json"
}
MKT_DECL='{"extraKnownMarketplaces":{"mkt":{"source":{"source":"github","repo":"o/r"}},"other":{"source":{"source":"github","repo":"o/s"}}}}'

# --- Case 38: a user-scope false dependency of a project-enabled plugin ---------
m="$(make_machine depuser)"
printf '%s\n' "$CLEAN_SETTINGS" | jq --argjson d "$MKT_DECL" '. + $d + {enabledPlugins:{"app@mkt":true}}' >"$m/project/.claude/settings.json"
printf '%s\n' '{"enabledPlugins":{"lib@mkt":false}}' >"$m/user/settings.json"
add_plugin "$m" app '{"name":"app","dependencies":["lib"]}'
rc=0
out=$(run "$m" --json 2>&1) || rc=$?
assert_exit "case 38: a disabled dependency is a warning, not an error" 0 "$rc"
assert_eq "case 38: the dependency is a warning finding" "warning" "$(jq -r '.findings[] | select(.identity.claim=="dependency-disabled:lib@mkt") | .severity' <<<"$out")"
assert_eq "case 38: its surface is the user file" "user:settings.json" "$(jq -r '.findings[] | select(.identity.claim=="dependency-disabled:lib@mkt") | .identity.sites[0].surface' <<<"$out")"
assert_contains "case 38: the detail names the dependent" "$(jq -r '.findings[] | select(.identity.claim=="dependency-disabled:lib@mkt") | .detail' <<<"$out")" "enabled plugin(s) app@mkt declare it"
assert_eq "case 38: no inventory row for the same key" "0" "$(jq '[.rows[] | select(.claim=="disabled-plugin:lib@mkt")] | length' <<<"$out")"
assert_eq "case 38: the check is E/dependency-disabled" "1" "$(jq '[.rows[] | select(.check=="claude-config/audit/E/dependency-disabled" and .status=="finding")] | length' <<<"$out")"

# --- Case 39: a false shadowed by a true at a higher scope is inventory ---------
m="$(make_machine depshadow)"
printf '%s\n' "$CLEAN_SETTINGS" | jq --argjson d "$MKT_DECL" '. + $d + {enabledPlugins:{"app@mkt":true,"lib@mkt":true}}' >"$m/project/.claude/settings.json"
printf '%s\n' '{"enabledPlugins":{"lib@mkt":false}}' >"$m/user/settings.json"
add_plugin "$m" app '{"name":"app","dependencies":["lib"]}' lib '{"name":"lib"}'
rc=0
out=$(run "$m" --json 2>&1) || rc=$?
assert_exit "case 39: a shadowed false exits 0" 0 "$rc"
assert_eq "case 39: no dependency finding" "0" "$(jq '[.rows[] | select(.claim | startswith("dependency-disabled:"))] | length' <<<"$out")"
assert_eq "case 39: the false is an inventory row" "ok none user:settings.json" "$(jq -r '.rows[] | select(.claim=="disabled-plugin:lib@mkt") | "\(.status) \(.severity) \(.surface)"' <<<"$out")"
assert_contains "case 39: the row says it is shadowed" "$(jq -r '.rows[] | select(.claim=="disabled-plugin:lib@mkt") | .detail' <<<"$out")" "shadowed by true at project"

# --- Case 40: object, name@marketplace and bare dependency forms ----------------
m="$(make_machine depforms)"
printf '%s\n' "$CLEAN_SETTINGS" | MSYS2_ARG_CONV_EXCL="*" jq --argjson d "$MKT_DECL" '. + $d + {enabledPlugins:{"app@mkt":true,"x@other":false,"y@mkt":false,"z@mkt":false,"w@mkt":false,"k=/x@mkt":false}}' >"$m/project/.claude/settings.json"
printf '%s\n' '{"enabledPlugins":{"y@mkt":false}}' >"$m/user/settings.json"
add_plugin "$m" app '{"name":"app","dependencies":[{"name":"x","marketplace":"other"},"y@mkt",{"name":"z","version":"^1"},"k=/x@mkt"]}'
rc=0
out=$(run "$m" --json 2>&1) || rc=$?
assert_eq "case 40: object form with a marketplace" "1" "$(jq '[.findings[] | select(.identity.claim=="dependency-disabled:x@other")] | length' <<<"$out")"
assert_eq "case 40: name@marketplace string form" "1" "$(jq '[.findings[] | select(.identity.claim=="dependency-disabled:y@mkt")] | length' <<<"$out")"
assert_eq "case 40: one finding when several scopes hold false, at the effective one" ".claude/settings.json" "$(jq -r '[.findings[] | select(.identity.claim=="dependency-disabled:y@mkt") | .identity.sites[0].surface] | join(",")' <<<"$out")"
assert_eq "case 40: the lower-scope false is inventory" "ok" "$(jq -r '.rows[] | select(.claim=="disabled-plugin:y@mkt" and .surface=="user:settings.json") | .status' <<<"$out")"
assert_eq "case 40: object form without a marketplace takes the dependent's" "1" "$(jq '[.findings[] | select(.identity.claim=="dependency-disabled:z@mkt")] | length' <<<"$out")"
# Only Git Bash with a native (non-MSYS) jq rewrites `k=/x@mkt`, so this can fail nowhere else.
assert_eq "case 40: a key with = and / keeps its spelling" "1" "$(MSYS2_ARG_CONV_EXCL="*" jq '[.findings[] | select(.identity.claim=="dependency-disabled:k=/x@mkt")] | length' <<<"$out")"
assert_eq "case 40: a false nothing depends on is inventory" "ok none" "$(jq -r '.rows[] | select(.claim=="disabled-plugin:w@mkt") | "\(.status) \(.severity)"' <<<"$out")"
assert_eq "case 40: no disabled-plugin finding at all" "0" "$(jq '[.findings[] | select(.identity.claim | startswith("disabled-plugin:"))] | length' <<<"$out")"

# --- Case 41: an enabled plugin whose dependencies cannot be read ----------------
m="$(make_machine depunread)"
printf '%s\n' "$CLEAN_SETTINGS" | jq --argjson d "$MKT_DECL" '. + $d + {enabledPlugins:{"app@mkt":true,"ghost@mkt":true,"bad@mkt":true,"bare@mkt":true,"strdeps@mkt":true}}' >"$m/project/.claude/settings.json"
add_plugin "$m" app '{"name":"app"}' bad '{not json' bare - strdeps '{"name":"strdeps","dependencies":"lib"}'
rc=0
out=$(run "$m" --json 2>&1) || rc=$?
assert_eq "case 41: an unresolved install path is not inspectable" "not-inspectable" "$(jq -r '.rows[] | select(.claim=="dependencies-unread:ghost@mkt") | .status' <<<"$out")"
assert_eq "case 41: an invalid plugin.json is not inspectable" "not-inspectable" "$(jq -r '.rows[] | select(.claim=="dependencies-unread:bad@mkt") | .status' <<<"$out")"
assert_eq "case 41: a resolved path without plugin.json declares no dependencies" "0" "$(jq '[.rows[] | select(.claim=="dependencies-unread:bare@mkt")] | length' <<<"$out")"
assert_eq "case 41: a non-array dependencies is not inspectable" "not-inspectable" "$(jq -r '.rows[] | select(.claim=="dependencies-unread:strdeps@mkt") | .status' <<<"$out")"
assert_eq "case 41: a readable plugin.json is not reported unread" "0" "$(jq '[.rows[] | select(.claim=="dependencies-unread:app@mkt")] | length' <<<"$out")"
assert_eq "case 41: the rows sit under E/dependency-disabled" "3" "$(jq '[.rows[] | select(.check=="claude-config/audit/E/dependency-disabled" and .status=="not-inspectable")] | length' <<<"$out")"

# --- Case 42: keys the drift check never diffs are named, per file --------------
m="$(make_machine coverage)"
mkdir -p "$m/user/plugins"
printf '%s\n' "$CLEAN_SETTINGS" | jq '. + {extraKnownMarketplaces:{mkt:{source:{source:"github",repo:"o/r"}}},enabledPlugins:{"a@reg":true,"b@mkt":true,"c@nowhere":true}}' >"$m/project/.claude/settings.json"
jq -n '{enabledPlugins:{"d@usr":false,"e@reg":true,"f\tg@reg":true}}' >"$m/project/.claude/settings.local.json"
printf '%s\n' '{"extraKnownMarketplaces":{"usr":{"source":{"source":"github","repo":"o/u"}}}}' >"$m/user/settings.json"
printf '%s\n' '{"reg":{"source":{"source":"github","repo":"o/g"}}}' >"$m/user/plugins/known_marketplaces.json"
rc=0
out=$(run "$m" --json 2>&1) || rc=$?
cov_p="$(jq -r '.rows[] | select(.claim=="drift-coverage:.claude/settings.json") | "\(.status) \(.severity) \(.detail)"' <<<"$out")"
cov_l="$(jq -r '.rows[] | select(.claim=="drift-coverage:.claude/settings.local.json") | "\(.status) \(.severity) \(.detail)"' <<<"$out")"
assert_contains "case 42: the project row is a skip with its count" "$cov_p" "skip none 1 enabledPlugins key(s) in .claude/settings.json"
assert_contains "case 42: a marketplace registered only in known_marketplaces.json is listed" "$cov_p" "not diffed: a@reg"
assert_eq "case 42: a declared or unregistered marketplace is not listed" "0" "$(jq '[.rows[] | select(.claim=="drift-coverage:.claude/settings.json") | select(.detail | test("b@mkt|c@nowhere"))] | length' <<<"$out")"
assert_contains "case 42: the local file's keys are named too" "$cov_l" "skip none 3 enabledPlugins key(s) in .claude/settings.local.json"
assert_contains "case 42: control characters display as ?" "$cov_l" "d@usr, e@reg, f?g@reg"
assert_eq "case 42: the unregistered marketplace stays an error" "error" "$(jq -r '.findings[] | select(.identity.claim=="unknown-marketplace:c@nowhere") | .severity' <<<"$out")"
assert_eq "case 42: the check is E/drift" "2" "$(jq '[.rows[] | select(.check=="claude-config/audit/E/drift" and (.claim | startswith("drift-coverage:")))] | length' <<<"$out")"

# --- Case 43: a key with a carriage return is one key, never its stripped twin ---
m="$(make_machine crkeys)"
printf '%s\n' "$CLEAN_SETTINGS" | jq --argjson d "$MKT_DECL" '. + $d + {enabledPlugins:{"app@mkt":true,"a\r@mkt":false,"q@mkt\r":true}}' >"$m/project/.claude/settings.json"
add_plugin "$m" app '{"name":"app","dependencies":["a"]}'
rc=0
out=$(run "$m" --json 2>&1) || rc=$?
assert_eq "case 43: the CR key is one inventory row with its CR" "1" "$(jq '[.rows[] | select(.claim=="disabled-plugin:a\r@mkt")] | length' <<<"$out")"
assert_eq "case 43: the stripped twin is never matched as the dependency" "0" "$(jq '[.rows[] | select(.claim=="dependency-disabled:a@mkt" or .claim=="disabled-plugin:a@mkt")] | length' <<<"$out")"
assert_eq "case 43: a CR in the marketplace makes it unregistered" "error" "$(jq -r '.findings[] | select(.identity.claim=="unknown-marketplace:q@mkt\r") | .severity' <<<"$out")"
assert_exit "case 43: that error sets the exit" 1 "$rc"

# --- Case 44: drift keys with a tab or backslash reach their claims exactly -------
m="$(make_machine driftkeys)"
mkdir -p "$m/fixtures"
jq -n --argjson c "$CLEAN_SETTINGS" '$c + {
  extraKnownMarketplaces: {mkt: {source: {source: "github", repo: "o/r"}}, "t\tb": {source: {source: "github"}}},
  enabledPlugins: {"a\tb@mkt": false, "c\\d@mkt": true, "p@mkt": "yes", "ren\tx@mkt": false}}' >"$m/project/.claude/settings.json"
printf '%s\n' '{"name":"mkt","plugins":[{"name":"ren\txy"}]}' >"$m/fixtures/mkt.json"
out=$(SETTINGS_AUDIT_ENGINE_FIXTURE_DIR="$m/project" SETTINGS_AUDIT_ENGINE_USER_DIR="$m/user" \
  SETTINGS_AUDIT_ENGINE_INSTALLED_JSON="$m/registry.json" SETTINGS_AUDIT_ENGINE_BASELINE_FILE="$BASELINE" \
  SETTINGS_AUDIT_ENGINE_DEBUG_DIR="$m/debug" SETTINGS_AUDIT_FIXTURE_DIR="$m/fixtures" CLAUDE_CODE_DEBUG_LOGS_DIR="" \
  FETCH_DOCS_FIXTURE_DIR="$DOCS" SETTINGS_AUDIT_ENGINE_CLAUDE_BIN="$CLI" \
  bash "$SCRIPT" --json 2>&1) || true
assert_eq "case 44: a tab in an orphan key is kept" "info" "$(jq -r '.rows[] | select(.claim=="orphan-disabled:a\tb@mkt") | .severity' <<<"$out")"
assert_eq "case 44: a backslash in an orphan key is kept" "warning" "$(jq -r '.rows[] | select(.claim=="orphan-enabled:c\\d@mkt") | .severity' <<<"$out")"
assert_eq "case 44: a non-boolean orphan is never removable" "warning" "$(jq -r '.rows[] | select(.claim=="orphan-nonboolean:p@mkt") | .severity' <<<"$out")"
assert_eq "case 44: a rename pair keeps its tab" "1" "$(jq '[.rows[] | select(.claim=="possible-rename:ren\tx->ren\txy@mkt")] | length' <<<"$out")"
assert_eq "case 44: a skipped marketplace keeps its tab" "skip" "$(jq -r '.rows[] | select(.claim=="drift-skipped:t\tb") | .status' <<<"$out")"

# --- Case 45: a category E row is never dropped silently -------------------------
# The decoder and the row reader, with a stub row, fed the emit encoding directly.
E_DEFS=""
eval "$(sed -n "/^unb64_to() {/,/^}/p; /^E_ROW_BAD=/p; /^e_rows() {/,/^}/p; /^E_DEFS='/,/^'\$/p" "$SCRIPT")"
SEEN=()
# shellcheck disable=SC2329  # called by the e_rows the eval above defined
row() { SEEN+=("$(printf '%s|' "$@")"); }
enc() { jq -rn --arg su u --arg sp p --arg sl l "$E_DEFS \$ARGS.positional | emit" --args "$@" | tr -d '\r'; }
e_rows <<<"$(enc s ok none surf claim "" ex)"
assert_eq "case 45: an empty field keeps its row" "E|s|ok|none|surf|claim||ex|" "${SEEN[0]:-none}"
SEEN=()
e_rows <<<"$(enc s ok none surf claim detail ex | sed 's/^[^ ]*/@@@@/')"
assert_contains "case 45: an undecodable field is a not-inspectable row" "${SEEN[0]:-none}" "E|plugin-state|not-inspectable|"
SEEN=()
e_rows <<<"$(enc s ok none surf claim detail)"
assert_contains "case 45: a short row is a not-inspectable row" "${SEEN[0]:-none}" "E|plugin-state|not-inspectable|"
unset -f row enc

# --- Case 46: consent receipts are labeled from the per-owner record ------------
m="$(make_machine consent)"
printf '%s\n' "$CLEAN_SETTINGS" | jq '. + {skipWorkflowUsageWarning:true}' >"$m/project/.claude/settings.json"
printf '%s\n' '{"skipWorkflowUsageWarning":true,"permissions":{"skipWorkflowUsageWarning":[]}}' >"$m/user/settings.json"
make_cli "$m/claude" "2.1.281 (Claude Code)" enabledPlugins permissions skipWorkflowUsageWarning
out=$(CLI_BIN="$m/claude" run "$m" --json 2>&1) || true
cr='.rows[] | select(.claim=="consent-receipt:skipWorkflowUsageWarning")'
assert_eq "case 46: the user-scope receipt is labeled" "claude-config/audit/A/consent-receipt ok user:settings.json" "$(jq -r "$cr | \"\(.check) \(.status) \(.surface)\"" <<<"$out")"
assert_contains "case 46: the label names the owner and meaning" "$(jq -r "$cr | .detail" <<<"$out")" "claude-code"
assert_eq "case 46: the labeled key is no undocumented-key finding at user scope" "0" "$(jq '[.rows[] | select(.claim=="undocumented-key:skipWorkflowUsageWarning" and .surface=="user:settings.json")] | length' <<<"$out")"
pd="$(jq -r '.findings[] | select(.identity.claim=="undocumented-key:skipWorkflowUsageWarning") | "\(.identity.sites[0].surface) \(.detail)"' <<<"$out")"
assert_contains "case 46: the same key in project settings stays a finding" "$pd" ".claude/settings.json"
assert_contains "case 46: and names the scope the record does not declare" "$pd" "declares scope user, not project"
assert_eq "case 46: a permissions leaf of the same name is never labeled" "0" "$(jq '[.rows[] | select(.claim | startswith("consent-receipt:permissions."))] | length' <<<"$out")"
assert_eq "case 46: it stays an undocumented-key finding" "1" "$(jq '[.findings[] | select(.identity.claim=="undocumented-key:permissions.skipWorkflowUsageWarning")] | length' <<<"$out")"
make_cli "$m/claude-lacks" "2.1.281 (Claude Code)" enabledPlugins permissions
out=$(CLI_BIN="$m/claude-lacks" run "$m" --json 2>&1) || true
assert_eq "case 46: a searched binary lacking the name leaves no label" "0" "$(jq "[$cr] | length" <<<"$out")"
stale='.findings[] | select(.identity.claim=="undocumented-key:skipWorkflowUsageWarning" and .identity.sites[0].surface=="user:settings.json")'
assert_contains "case 46: and the finding says the receipt is stale" "$(jq -r "$stale | .detail" <<<"$out")" "stale consent receipt, recheck"
assert_eq "case 46: the stale receipt is a warning" "warning" "$(jq -r "$stale | .severity" <<<"$out")"
make_cli "$m/claude-shim" "2.1.281 (Claude Code)"
out=$(CLI_BIN="$m/claude-shim" run "$m" --json 2>&1) || true
assert_contains "case 46: an unsearched binary labels with binary not checked" "$(jq -r "$cr | .detail" <<<"$out")" "binary not checked"
# A plugin-owned receipt is labeled only while its owner is enabled.
printf '%s\n' '{"consentReceipt":{"own@mkt":[{"key":"ownAccepted","scopes":["project"],"meaning":"the user accepted own","basis":"fixture","as_of":"2026-09-26","recheck":"never"}],"claude-code":[{"key":"disableAllHooks","scopes":["project"],"meaning":"documented","basis":"fixture","as_of":"2026-09-26","recheck":"never"}]}}' >"$m/receipts.json"
printf '%s\n' "$CLEAN_SETTINGS" | jq '. + {ownAccepted:true,disableAllHooks:false,enabledPlugins:{"own@mkt":true}}' >"$m/project/.claude/settings.json"
printf '%s\n' '{}' >"$m/user/settings.json"
out=$(SETTINGS_AUDIT_ENGINE_CONSENT_RECEIPTS_FILE="$m/receipts.json" run "$m" --json 2>&1) || true
assert_eq "case 46: an enabled owner's receipt is labeled" "ok" "$(jq -r '.rows[] | select(.claim=="consent-receipt:ownAccepted") | .status' <<<"$out")"
assert_eq "case 46: a documented key is never relabeled" "ok 0" "$(jq -r '"\(.rows[] | select(.claim=="documented-key:disableAllHooks") | .status) \([.rows[] | select(.claim=="consent-receipt:disableAllHooks")] | length)"' <<<"$out")"
printf '%s\n' '{"enabledPlugins":{"own@mkt":false}}' >"$m/project/.claude/settings.local.json"
out=$(SETTINGS_AUDIT_ENGINE_CONSENT_RECEIPTS_FILE="$m/receipts.json" run "$m" --json 2>&1) || true
assert_eq "case 46: a disabled owner's receipt is not labeled" "0" "$(jq '[.rows[] | select(.claim=="consent-receipt:ownAccepted")] | length' <<<"$out")"
assert_contains "case 46: and the finding says the owner is not enabled" "$(jq -r '.findings[] | select(.identity.claim=="undocumented-key:ownAccepted") | .detail' <<<"$out")" "own@mkt is not enabled"
printf '%s\n' '{}' >"$m/project/.claude/settings.local.json"
printf '%s\n' '{"consentReceipt":' >"$m/receipts-invalid.json"
for bad in missing invalid; do
  out=$(SETTINGS_AUDIT_ENGINE_CONSENT_RECEIPTS_FILE="$m/receipts-$bad.json" run "$m" --json 2>&1) || true
  assert_eq "case 46: a $bad record file is one not-inspectable row" "1" "$(jq '[.rows[] | select(.check=="claude-config/audit/A/consent-receipt" and .status=="not-inspectable")] | length' <<<"$out")"
  assert_eq "case 46: and a $bad record file falls back to the finding" "1" "$(jq '[.findings[] | select(.identity.claim=="undocumented-key:ownAccepted")] | length' <<<"$out")"
done
# A key that only differs by a carriage return is not the record's key.
printf '%s\n' '{"skipWorkflowUsageWarning\r":true}' >"$m/user/settings.json"
out=$(CLI_BIN="$m/claude" run "$m" --json 2>&1) || true
assert_eq "case 46: a carriage-return twin of the key is never labeled" "0" "$(jq '[.rows[] | select(.claim | startswith("consent-receipt:"))] | length' <<<"$out")"
# The key beside its carriage-return twin is ambiguous: neither is labeled.
printf '%s\n' '{"skipWorkflowUsageWarning":true,"skipWorkflowUsageWarning\r":true}' >"$m/user/settings.json"
out=$(CLI_BIN="$m/claude" run "$m" --json 2>&1) || true
assert_eq "case 46: a key beside its carriage-return twin is never labeled" "0" "$(jq '[.rows[] | select(.claim | startswith("consent-receipt:"))] | length' <<<"$out")"
assert_contains "case 46: and the finding names the carriage-return variant" "$(jq -r '[.rows[] | select(.claim=="undocumented-key:skipWorkflowUsageWarning" and .surface=="user:settings.json") | .detail] | join(" ")' <<<"$out")" "carriage-return variant"
# A control character in a record field makes the record file invalid.
printf '%s\n' '{"skipWorkflowUsageWarning":true}' >"$m/user/settings.json"
for cc in '\u0000' '\n'; do
  printf '%s\n' "{\"consentReceipt\":{\"claude-code\":[{\"key\":\"skipWorkflowUsageWarning\",\"scopes\":[\"user\"],\"meaning\":\"a${cc}b\",\"basis\":\"fixture\",\"as_of\":\"2026-09-26\",\"recheck\":\"never\"}]}}" >"$m/receipts-cc.json"
  out=$(CLI_BIN="$m/claude" SETTINGS_AUDIT_ENGINE_CONSENT_RECEIPTS_FILE="$m/receipts-cc.json" run "$m" --json 2>&1) || true
  assert_eq "case 46: a control character ($cc) in a record is not-inspectable, no label" "1 0" "$(jq -r '"\([.rows[] | select(.claim=="consent-receipts-unread")] | length) \([.rows[] | select(.claim | startswith("consent-receipt:"))] | length)"' <<<"$out")"
done
# A key listed under two owners makes the record file invalid. With own@mkt
# enabled and the binary lacking the name, own@mkt alone labels the key, so the
# duplicate is what withholds the label.
rec='{"key":"skipWorkflowUsageWarning","scopes":["user"],"meaning":"accepted","basis":"fixture","as_of":"2026-09-26","recheck":"never"}'
printf '%s\n' "{\"consentReceipt\":{\"own@mkt\":[$rec]}}" >"$m/receipts-own.json"
printf '%s\n' "{\"consentReceipt\":{\"claude-code\":[$rec],\"own@mkt\":[$rec]}}" >"$m/receipts-dup.json"
out=$(CLI_BIN="$m/claude-lacks" SETTINGS_AUDIT_ENGINE_CONSENT_RECEIPTS_FILE="$m/receipts-own.json" run "$m" --json 2>&1) || true
assert_contains "case 46: an enabled owner alone labels the key" "$(jq -r "$cr | .detail" <<<"$out")" "owned by own@mkt"
out=$(CLI_BIN="$m/claude-lacks" SETTINGS_AUDIT_ENGINE_CONSENT_RECEIPTS_FILE="$m/receipts-dup.json" run "$m" --json 2>&1) || true
assert_eq "case 46: a key under two owners is not-inspectable, no label" "1 0" "$(jq -r '"\([.rows[] | select(.claim=="consent-receipts-unread")] | length) \([.rows[] | select(.claim | startswith("consent-receipt:"))] | length)"' <<<"$out")"
assert_eq "case 46: and the key stays an undocumented-key finding" "1" "$(jq "[$stale] | length" <<<"$out")"

# --- Case 47: a stale claude-code record is terminal for its key -----------------
# A valid record file cannot list the key under claude-code and a second owner
# (case 46 proves that file is not-inspectable), so this guard is reached only
# through cr_match itself: it runs here past the file check, in both owner orders.
eval "$(sed -n '/^cr_match() {/,/^}/p' "$SCRIPT")"
# shellcheck disable=SC2034  # read by the cr_match the eval above defined
{
  SURF_USER="user:settings.json" SURF_SETTINGS=".claude/settings.json" SURF_LOCAL=".claude/settings.local.json"
  CR_STATE=ok BIN_SEARCH=searched CR_WHY=""
  declare -A BIN_HAS=([skipWorkflowUsageWarning]=no)
}
# shellcheck disable=SC2329  # called by the cr_match the eval above defined
row() { SEEN+=("$(printf '%s|' "$@")"); }
for order in "claude-code own@mkt" "own@mkt claude-code"; do
  CR_KEY=() CR_OWNER=() CR_SCOPES=() CR_MEANING=() CR_ON=() CR_IN=() CR_AMB=()
  for o in $order; do
    on=yes
    [[ "$o" == claude-code ]] && on=-
    CR_KEY+=(skipWorkflowUsageWarning) CR_OWNER+=("$o") CR_SCOPES+=(user) CR_MEANING+=(accepted) CR_ON+=("$on") CR_IN+=(user) CR_AMB+=("")
  done
  SEEN=() rc=0
  cr_match "user:settings.json" skipWorkflowUsageWarning skipWorkflowUsageWarning || rc=$?
  assert_eq "case 47: ($order) a stale claude-code record withholds every label" "1 0" "$rc ${#SEEN[@]}"
  assert_contains "case 47: ($order) and names the stale receipt" "$CR_WHY" "stale consent receipt, recheck"
done
unset -f row cr_match

# --- Case 48: skillOverrides entries that can never take effect ------------------
# Plugin skills are not affected by skillOverrides, so a key naming a known
# plugin is a warning; a colon key whose prefix names no known plugin is not
# decided. Plugin names come from the installed registry and enabledPlugins.
so_row() { jq -c --arg c "$1" '[.rows[] | select(.claim == $c)]' <<<"$2"; }
m="$(make_machine overrides)"
printf '%s\n' '{"plugins":{"tools@mkt":[{"scope":"user"}]}}' >"$m/registry.json"
printf '%s\n' "$CLEAN_SETTINGS" | jq '. + {skillOverrides:{"tools:lint":"off","tools:a/b~c":"name-only","plain":"off","apps/web:deploy":"off","anthropic-skills:pdf":"off"}}' >"$m/project/.claude/settings.json"
printf '%s\n' '{"enabledPlugins":{"other@mkt2":false},"skillOverrides":{"other:x":"off"}}' >"$m/user/settings.json"
printf '%s\n' '{"skillOverrides":{"tools:a\nb":"off"}}' >"$m/project/.claude/settings.local.json" # portability-ok: a JSON newline escape, not a regex escape
rc=0
out=$(run "$m" --json 2>&1) || rc=$?
assert_exit "case 48: override findings are warnings, exit 0" 0 "$rc"
assert_eq "case 48: every scope read is a fixture file" "0" "$(jq --arg m "$m" '[.scopes[] | select(.path | startswith($m) | not)] | length' <<<"$out")"
r="$(so_row "skill-override-plugin:tools:lint" "$out")"
assert_eq "case 48: a registry plugin key is a warning finding on its file" "finding warning .claude/settings.json" "$(jq -r '.[0] | "\(.status) \(.severity) \(.surface)"' <<<"$r")"
assert_eq "case 48: its anchor is the escaped JSON pointer" "$(bash "$SCRIPT" anchor --excerpt "/skillOverrides/tools:lint")" "$(jq -r '.[0].anchor' <<<"$r")"
assert_contains "case 48: the detail quotes the docs" "$(jq -r '.[0].detail' <<<"$r")" "Plugin skills are not affected by"
assert_contains "case 48: the detail names the reachable lever" "$(jq -r '.[0].detail' <<<"$r")" "enabledPlugins"
assert_eq "case 48: slash and tilde are pointer-escaped" "$(bash "$SCRIPT" anchor --excerpt "/skillOverrides/tools:a~1b~0c")" "$(jq -r '.[0].anchor' <<<"$(so_row "skill-override-plugin:tools:a/b~c" "$out")")"
assert_eq "case 48: a disabled enabledPlugins key still names a plugin" "finding warning user:settings.json" "$(jq -r '.[0] | "\(.status) \(.severity) \(.surface)"' <<<"$(so_row "skill-override-plugin:other:x" "$out")")"
assert_eq "case 48: a nested directory-qualified key is a skip, not a finding" "skip none" "$(jq -r '.[0] | "\(.status) \(.severity)"' <<<"$(so_row "skill-override-plugin:apps/web:deploy" "$out")")"
assert_eq "case 48: a synced-skill namespace key is a skip" "skip" "$(jq -r '.[0].status' <<<"$(so_row "skill-override-plugin:anthropic-skills:pdf" "$out")")"
assert_eq "case 48: an unresolved key is never a finding" "0" "$(jq '[.findings[] | select(.identity.claim | test("apps/web|anthropic-skills"))] | length' <<<"$out")"
assert_eq "case 48: a plain key gets no override row" "0" "$(jq '[.rows[] | select(.check | endswith("/G/skill-override-plugin")) | select(.claim | test("plain"))] | length' <<<"$out")"
assert_eq "case 48: a key with a newline is one row" "1" "$(jq '[.rows[] | select(.check | endswith("/G/skill-override-plugin")) | select(.surface == ".claude/settings.local.json")] | length' <<<"$out")"
assert_eq "case 48: its claim carries the escaped key" "1" "$(jq '[.findings[] | select(.identity.claim == "skill-override-plugin:tools:a\\nb")] | length' <<<"$out")" # portability-ok: the literal two-character escape in the claim
assert_eq "case 48: no override value reaches a row" "0" "$(jq '[.rows[] | select(.check | contains("/G/skill-override")) | select(.detail | test("name-only"))] | length' <<<"$out")"
assert_eq "case 48: an ordinary project with no user-dir local file has no home-local row" "0" "$(jq '[.rows[] | select(.check | endswith("/G/skill-override-home-local"))] | length' <<<"$out")"
ul_scope() { jq -r '[.scopes[] | select(.label == "user-local") | "\(.state) \(.path | sub(".*/"; ""))"] | join(",")' <<<"$1"; }
assert_eq "case 48: the user-dir local file is listed as a scope even when absent" "absent settings.local.json" "$(ul_scope "$out")"
# The user dir's own settings.local.json is read whatever the project root.
printf '%s\n' '{"skillOverrides":{"mine":"off"}}' >"$m/user/settings.local.json"
out=$(run "$m" --json 2>&1) || true
assert_eq "case 48: a user-dir local file with overrides is an info finding" "finding info user:settings.local.json" "$(jq -r '.rows[] | select(.check | endswith("/G/skill-override-home-local")) | "\(.status) \(.severity) \(.surface)"' <<<"$out")"
assert_contains "case 48: and says a user-wide override belongs in settings.json" "$(jq -r '.rows[] | select(.check | endswith("/G/skill-override-home-local")) | .detail' <<<"$out")" "settings.json"
assert_eq "case 48: the read is disclosed in scopes" "ok settings.local.json" "$(ul_scope "$out")"
assert_eq "case 48: the disclosed path is the user dir's file" "1" "$(jq --arg p "$m/user/settings.local.json" '[.scopes[] | select(.label == "user-local" and .path == $p)] | length' <<<"$out")"
printf '%s\n' '{"skillOverrides":{}}' >"$m/user/settings.local.json"
out=$(run "$m" --json 2>&1) || true
assert_eq "case 48: an empty skillOverrides object has no home-local row" "0" "$(jq '[.rows[] | select(.check | endswith("/G/skill-override-home-local"))] | length' <<<"$out")"
assert_eq "case 48: a clean user-dir local file is still disclosed as read" "ok settings.local.json" "$(ul_scope "$out")"
printf '%s\n' '{not json' >"$m/user/settings.local.json"
out=$(run "$m" --json 2>&1) || true
assert_eq "case 48: an invalid user-dir local file is not inspectable, never clean" "not-inspectable" "$(jq -r '.rows[] | select(.check | endswith("/G/skill-override-home-local")) | .status' <<<"$out")"
assert_eq "case 48: and its scope state says invalid" "invalid settings.local.json" "$(ul_scope "$out")"
out=$(run "$m" --table 2>&1) || true
assert_contains "case 48: the table report lists the user-local scope" "$out" "user-local: invalid"

# A home-rooted run: the project's .claude is the user dir, so settings.json is
# one file under two labels and is scanned once, and the local file is the
# user-dir local file. Checked with USER_DIR spelled unlike PROJECT_ROOT.
m="$(make_machine home-overrides)"
mkdir -p "$m/home/.claude"
printf '%s\n' '{"plugins":{"tools@mkt":[{"scope":"user"}]}}' >"$m/registry.json"
printf '%s\n' "$CLEAN_SETTINGS" | jq '. + {skillOverrides:{"tools:lint":"off","tools:fmt":"off"}}' >"$m/home/.claude/settings.json"
printf '%s\n' '{"skillOverrides":{"mine":"off","tools:x":"off"}}' >"$m/home/.claude/settings.local.json"
spellings=("$m/home/.claude/")
command -v cygpath >/dev/null 2>&1 && spellings+=("$(cygpath -w "$m/home/.claude")")
for ud in "$m/home/.claude" "${spellings[@]}"; do
  rc=0
  out=$(SETTINGS_AUDIT_ENGINE_FIXTURE_DIR="$m/home" SETTINGS_AUDIT_ENGINE_USER_DIR="$ud" \
    SETTINGS_AUDIT_ENGINE_INSTALLED_JSON="$m/registry.json" SETTINGS_AUDIT_ENGINE_BASELINE_FILE="$BASELINE" \
    SETTINGS_AUDIT_ENGINE_DEBUG_DIR="$m/debug" SETTINGS_AUDIT_ENGINE_SKIP_DRIFT=1 CLAUDE_CODE_DEBUG_LOGS_DIR="" \
    FETCH_DOCS_FIXTURE_DIR="$DOCS" SETTINGS_AUDIT_ENGINE_CLAUDE_BIN="$CLI" \
    bash "$SCRIPT" --json 2>&1) || rc=$?
  assert_exit "case 48 ($ud): home-rooted run exits 0" 0 "$rc"
  assert_eq "case 48 ($ud): the user file is read" "ok" "$(jq -r '.scopes[] | select(.label == "user") | .state' <<<"$out")"
  assert_eq "case 48 ($ud): the local scope is the user-dir local file, listed once" "" "$(ul_scope "$out")"
  assert_eq "case 48 ($ud): one finding per settings.json key, on the user surface" "user:settings.json user:settings.json" "$(jq -r '[.findings[] | select(.identity.check | endswith("/G/skill-override-plugin")) | select(.identity.claim | test("lint|fmt")) | .identity.sites[0].surface] | join(" ")' <<<"$out")"
  assert_eq "case 48 ($ud): the local file's plugin key is one finding" "1" "$(jq '[.findings[] | select(.identity.claim == "skill-override-plugin:tools:x")] | length' <<<"$out")"
  assert_eq "case 48 ($ud): one home-local info finding" "info" "$(jq -r '[.findings[] | select(.identity.check | endswith("/G/skill-override-home-local")) | .severity] | join(" ")' <<<"$out")"
done

# --- Case 49: a declared unattended-push lane narrows the push ask-gate only ----
# Settings lack the push ask rule and the force-push deny. The team-tracked
# source-control file decides whether the ask row is info (the lane's signal
# named) or warning; the deny row keeps its severity either way, and every ask
# row says an ask rule blocks an unattended lane.
lane_settings='{"$schema":"https://json.schemastore.org/claude-code-settings.json","permissions":{"deny":["Read(./.env)","Read(**/*.pem)","Bash(git reset --hard *)"]}}'
ask_row() { jq -r --arg f "$2" '.findings[] | select(.identity.claim=="missing-pattern:Bash(git push *)") | .[$f]' <<<"$1"; }
force_sev() { jq -r '.findings[] | select(.identity.claim=="missing-pattern:Bash(git push --force *)") | .severity' <<<"$1"; }
for lane in c3-autonomous adopted human-only none; do
  m="$(make_machine "lane-$lane")"
  printf '%s\n' "$lane_settings" >"$m/project/.claude/settings.json"
  case "$lane" in
  c3-autonomous | human-only)
    printf '# source-control configuration\n\n## babysit_loop_tier\n\nworker\n\n## babysit_loop_merge\n\n%s\n' "$lane" >"$m/project/.claude/source-control.md"
    ;;
  adopted)
    printf '# source-control configuration\n\n## babysit_loop_tier\n\nworker\n' >"$m/project/.claude/source-control.md"
    ;;
  *) ;;
  esac
  rc=0
  out=$(run "$m" --json 2>&1) || rc=$?
  assert_eq "case 49 ($lane): force-push deny stays error" "error" "$(force_sev "$out")"
  assert_contains "case 49 ($lane): ask row says it blocks unattended lanes" "$(ask_row "$out" detail)" "auto-denied under dontAsk"
  case "$lane" in
  c3-autonomous)
    assert_eq "case 49 ($lane): ask row is info" "info" "$(ask_row "$out" severity)"
    assert_contains "case 49 ($lane): the signal is named" "$(ask_row "$out" detail)" "babysit_loop_merge: c3-autonomous in the team-tracked .claude/source-control.md"
    ;;
  adopted)
    assert_eq "case 49 ($lane): ask row is info" "info" "$(ask_row "$out" severity)"
    assert_contains "case 49 ($lane): the baseline rung is named" "$(ask_row "$out" detail)" "baseline c2-mechanical"
    ;;
  *)
    assert_eq "case 49 ($lane): ask row stays warning" "warning" "$(ask_row "$out" severity)"
    ;;
  esac
done

# CRLF + backticked rung (mawk-safe parse).
m="$(make_machine "lane-crlf-bt")"
printf '%s\n' "$lane_settings" >"$m/project/.claude/settings.json"
printf '# source-control configuration\r\n\r\n## babysit_loop_merge\r\n\r\n`full-autonomy`\r\n' >"$m/project/.claude/source-control.md"
rc=0
out=$(run "$m" --json 2>&1) || rc=$?
assert_eq "case 49 (crlf-bt): ask row is info" "info" "$(ask_row "$out" severity)"
assert_contains "case 49 (crlf-bt): backticked rung is read" "$(ask_row "$out" detail)" "babysit_loop_merge: full-autonomy"
assert_eq "case 49 (crlf-bt): force-push deny stays error" "error" "$(force_sev "$out")"

# Explicit awk shim: first awk on PATH is the impl under test.
for impl in gawk mawk; do
  command -v "$impl" >/dev/null 2>&1 || { echo "skip case 49 ($impl): not installed"; continue; }
  m="$(make_machine "lane-awk-$impl")"
  printf '%s\n' "$lane_settings" >"$m/project/.claude/settings.json"
  printf '## babysit_loop_merge\n\n  c2-mechanical  \n' >"$m/project/.claude/source-control.md"
  shim="$m/bin"
  mkdir -p "$shim"
  ln -sf "$(command -v "$impl")" "$shim/awk"
  rc=0
  out=$(PATH="$shim:$PATH" run "$m" --json 2>&1) || rc=$?
  assert_eq "case 49 ($impl): ask row is info" "info" "$(ask_row "$out" severity)"
  assert_contains "case 49 ($impl): the rung is read and trimmed" "$(ask_row "$out" detail)" "babysit_loop_merge: c2-mechanical"
done

# --- Case 50: engine defects: a key holding U+0000, and the section index ---------
# jq -j writes U+0000 as a NUL byte, which would split the key into two rows.
m="$(make_machine nulkey)"
printf '%s\n' "$CLEAN_SETTINGS" | jq '. + {"ab\u0000cd":1} | .permissions += {"xy\u0000zw":1}' >"$m/project/.claude/settings.json"
out=$(run "$m" --json 2>&1) || true
assert_eq "case 50: a top-level key holding U+0000 is one row" "1" "$(jq '[.rows[] | select(.claim | startswith("undocumented-key:ab"))] | length' <<<"$out")"
assert_eq "case 50: the row spells U+0000 as text" 'undocumented-key:ab\u0000cd' "$(jq -r '.rows[] | select(.claim | startswith("undocumented-key:ab")) | .claim' <<<"$out")"
assert_eq "case 50: a permissions key holding U+0000 is one row" "1" "$(jq '[.rows[] | select(.claim | startswith("undocumented-key:permissions.xy"))] | length' <<<"$out")"
assert_eq "case 50: no row carries the key's second half" "0" "$(jq '[.rows[] | select(.claim | startswith("undocumented-key:cd") or startswith("undocumented-key:zw"))] | length' <<<"$out")"
# A repeated heading keeps its first section, so the value set is the first list only.
m="$(make_machine dupsection)"
mkdir -p "$m/docs"
cp "$DOCS/llms.txt" "$DOCS/env-vars.md" "$m/docs/"
{
  cat "$DOCS/settings-reference.md"
  printf '### `effortLevel`\n\nAgain.\n\n* **Type**: string, one of:\n  * `"later"`: from the second section\n\n'
} >"$m/docs/settings-reference.md"
printf '%s\n' "$CLEAN_SETTINGS" | jq '. + {effortLevel:"bogus"}' >"$m/project/.claude/settings.json"
out=$(DOCS_FIXTURE="$m/docs" run "$m" --json 2>&1) || true
assert_contains "case 50: a repeated heading keeps the first value set" "$(jq -r '.findings[] | select(.identity.claim=="effortLevel:bogus") | .detail' <<<"$out")" "low, medium, high, xhigh"
assert_eq "case 50: and not the second" "0" "$(jq '[.findings[] | select(.identity.claim=="effortLevel:bogus") | select(.detail | contains("later"))] | length' <<<"$out")"

# --- Case 51: a page settings-reference links to is acquired and feeds a check ----
m="$(make_machine linked)"
printf '%s\n' "$CLEAN_SETTINGS" | jq '. + {hooks:{PreToolUse:[{matcher:"Bash",hooks:[{type:"command",command:"true"}]}],Bash:[{hooks:[{type:"command",command:"true"}]}]}}' >"$m/project/.claude/settings.json"
pages() { jq -r '[.docs.pages[] | .slug] | join(" ")' <<<"$1"; }
hook_row() { jq -r --arg c "$2" '.rows[] | select(.claim == $c) | "\(.status) \(.severity)"' <<<"$1"; }

# --docs-dir supplies the linked page; an unlinked sandboxing page is not acquired.
docs_with_link "$m/docs" hooks sandboxing
cp "$HOOKS_MD" "$m/docs/hooks.md"
cp "$HOOKS_MD" "$m/docs/sandboxing.md"
out=$(run "$m" --json --docs-dir "$m/docs" 2>&1) || true
assert_eq "case 51: the linked page joins the docs pages, one no check reads does not" "settings-reference env-vars hooks" "$(pages "$out")"
assert_eq "case 51: it is read from --docs-dir" "read docs-dir true" "$(jq -r '.docs.pages[] | select(.slug=="hooks") | "\(.state) \(.source) \(.url_or_path | endswith("/docs/hooks.md"))"' <<<"$out")"
assert_eq "case 51: an event in the Event table is ok" "ok none" "$(hook_row "$out" documented-hook-event:PreToolUse)"
assert_eq "case 51: a name from another table is not an event" "finding error" "$(hook_row "$out" undocumented-hook-event:Bash)"

# The fixture seam supplies it through the index, the route a fetched page takes.
docs_with_link "$m/fx" hooks
cp "$HOOKS_MD" "$m/fx/hooks.md"
printf '%s\n' '- [Hooks](https://code.claude.com/docs/en/hooks.md): hooks' >>"$m/fx/llms.txt"
out=$(DOCS_FIXTURE="$m/fx" run "$m" --json 2>&1) || true
assert_eq "case 51: the linked page resolves through the index" "read fixture https://code.claude.com/docs/en/hooks.md" "$(jq -r '.docs.pages[] | select(.slug=="hooks") | "\(.state) \(.source) \(.url_or_path)"' <<<"$out")"
assert_eq "case 51: and feeds the same check" "ok none" "$(hook_row "$out" documented-hook-event:PreToolUse)"

# The index does not list it: unread, and the event rows are not decided.
rm -f "$m/fx/hooks.md"
grep -v 'hooks.md' "$m/fx/llms.txt" >"$m/fx/llms.new" && mv "$m/fx/llms.new" "$m/fx/llms.txt"
out=$(DOCS_FIXTURE="$m/fx" run "$m" --json 2>&1) || true
assert_eq "case 51: a linked page the index lacks is unread" "unread not-in-index" "$(jq -r '.docs.pages[] | select(.slug=="hooks") | "\(.state) \(.reason)"' <<<"$out")"
assert_eq "case 51: its event rows are not inspectable" "not-inspectable none" "$(hook_row "$out" hook-event-page-not-read:PreToolUse)"

# A read page with no Event table is unparsed, never a run of unknown events.
docs_with_link "$m/bad" hooks
printf '%s\n' '# Hooks reference' 'A soft 404 body.' >"$m/bad/hooks.md"
out=$(run "$m" --json --docs-dir "$m/bad" 2>&1) || true
assert_eq "case 51: a page with no Event table is unparsed" "unparsed no-event-table" "$(jq -r '.docs.pages[] | select(.slug=="hooks") | "\(.state) \(.reason)"' <<<"$out")"
assert_eq "case 51: no event is called unknown on it" "not-inspectable none" "$(hook_row "$out" hook-event-page-not-read:Bash)"

# No link, no request: a lookalike slug does not count, whatever --docs-dir holds.
docs_with_link "$m/nolink" hooks-guide
cp "$HOOKS_MD" "$m/nolink/hooks.md"
out=$(run "$m" --json --docs-dir "$m/nolink" 2>&1) || true
assert_eq "case 51: a page settings-reference does not link is not acquired" "settings-reference env-vars" "$(pages "$out")"

# --- Case 52: the fallbackModel cap and enum values come from the page ----------
m="$(make_machine caps)"
printf '%s\n' "$CLEAN_SETTINGS" | jq '. + {fallbackModel:["a","b","c"]}' >"$m/project/.claude/settings.json"
fb_rows() { jq -r --arg c "$2" '[.rows[] | select(.claim | startswith($c)) | "\(.status) \(.claim)"] | join(",")' <<<"$1"; }
# A page stating a cap of two, as a word and as a digit: three distinct is above it.
mkdir -p "$m/two" "$m/nine"
cp "$DOCS/llms.txt" "$DOCS/env-vars.md" "$m/two/"
cp "$DOCS/llms.txt" "$DOCS/env-vars.md" "$m/nine/"
sed 's/at most three distinct/at most two distinct/' "$DOCS/settings-reference.md" >"$m/two/settings-reference.md"
sed 's/at most three distinct/up to 9 distinct/' "$DOCS/settings-reference.md" >"$m/nine/settings-reference.md"
out=$(run "$m" --json --docs-dir "$m/two" 2>&1) || true
assert_eq "case 52: three distinct entries above a stated cap of two are flagged" "finding fallbackModel-dedup-length:3" "$(fb_rows "$out" fallbackModel-dedup)"
assert_contains "case 52: the finding names the page's cap" "$(jq -r '.findings[] | select(.identity.claim=="fallbackModel-dedup-length:3") | .detail' <<<"$out")" "at most 2 distinct"
out=$(run "$m" --json --docs-dir "$m/nine" 2>&1) || true
assert_eq "case 52: a digit cap of nine leaves three distinct entries clean" "" "$(fb_rows "$out" fallbackModel)"
# A page stating three: at the cap, not above it.
out=$(run "$m" --json 2>&1) || true
assert_eq "case 52: three distinct entries at a stated cap of three are clean" "" "$(fb_rows "$out" fallbackModel)"
# A page that states no cap: one skip row, and no finding is invented from a number.
mkdir -p "$m/nocap"
cp "$DOCS/llms.txt" "$DOCS/env-vars.md" "$m/nocap/"
grep -v 'keeps at most three distinct' "$DOCS/settings-reference.md" >"$m/nocap/settings-reference.md"
printf '%s\n' "$CLEAN_SETTINGS" | jq '. + {fallbackModel:["a","b","c","d","e","f"]}' >"$m/project/.claude/settings.json"
out=$(run "$m" --json --docs-dir "$m/nocap" 2>&1) || true
assert_eq "case 52: a page with no cap gives one skip row" "skip fallbackModel-cap" "$(fb_rows "$out" fallbackModel)"
assert_eq "case 52: and no fallbackModel finding" "0" "$(jq '[.findings[] | select(.identity.claim | startswith("fallbackModel"))] | length' <<<"$out")"
out=$(run "$m" --json 2>&1) || true
assert_eq "case 52: six distinct entries above the cap are flagged" "finding fallbackModel-dedup-length:6" "$(fb_rows "$out" fallbackModel-dedup)"
assert_eq "case 52: six raw entries above the cap are not decided from the page" "skip fallbackModel-raw-length:6" "$(fb_rows "$out" fallbackModel-raw)"

# Enum keys the page lists values for: a value outside the set is flagged, one inside is not.
printf '%s\n' "$CLEAN_SETTINGS" | jq '. + {editorMode:"emacs",theme:"custom:mine",promptCacheTtl:"1h"}' >"$m/project/.claude/settings.json"
printf '%s\n' '{"editorMode":"vim"}' >"$m/user/settings.json"
printf '%s\n' '{"editorMode":"secret-value"}' >"$m/project/.claude/settings.local.json"
out=$(run "$m" --json 2>&1) || true
assert_eq "case 52: an enum value outside the documented set is flagged" "warning" "$(jq -r '.findings[] | select(.identity.claim=="editorMode:emacs") | .severity' <<<"$out")"
assert_contains "case 52: the finding lists the documented values" "$(jq -r '.findings[] | select(.identity.claim=="editorMode:emacs") | .detail' <<<"$out")" "normal, vim"
assert_eq "case 52: an in-set value in the user file is ok" "ok" "$(jq -r '.rows[] | select(.claim=="editorMode:vim") | .status' <<<"$out")"
assert_eq "case 52: a custom:<slug> theme matches its placeholder entry" "ok" "$(jq -r '.rows[] | select(.claim=="theme:custom:mine") | .status' <<<"$out")"
assert_eq "case 52: a key the fixture page does not document has no row" "0" "$(jq '[.rows[] | select(.claim | startswith("promptCacheTtl:"))] | length' <<<"$out")"
assert_eq "case 52: settings.local.json values are never echoed" "0" "$(jq '[.rows[] | select(.claim=="editorMode:secret-value")] | length' <<<"$out")"

# A list with a bullet that is not a literal value (a pattern) is open: the literals are
# not the whole set, so a value outside them is not flagged. The same list without that
# bullet is closed and flags the value.
time_docs() {
  mkdir -p "$m/$1"
  cp "$DOCS/llms.txt" "$DOCS/env-vars.md" "$m/$1/"
  {
    cat "$DOCS/settings-reference.md"
    printf '%s\n' '### `timeFormat`' '' 'Choose how times are written.' '' '* **Scope**: [`Any file`](#scopes)' '* **Type**: string, one of:' \
      '  * `"auto"`: the same as unset' '  * `"24-hour"`: a 24-hour clock' "${@:2}" '* **Default**: `"auto"`' ''
  } >"$m/$1/settings-reference.md"
}
time_docs open '  * A strftime pattern such as `"%H:%M"`: any value that contains a `%` is a pattern'
time_docs closed
printf '%s\n' "$CLEAN_SETTINGS" | jq '. + {timeFormat:"%H:%M"}' >"$m/project/.claude/settings.json"
out=$(run "$m" --json --docs-dir "$m/closed" 2>&1) || true
assert_eq "case 52: a value outside a closed list is flagged" "warning" "$(jq -r '.findings[] | select(.identity.claim=="timeFormat:%H:%M") | .severity' <<<"$out")"
out=$(run "$m" --json --docs-dir "$m/open" 2>&1) || true
assert_eq "case 52: a list with a pattern bullet is open, so a pattern value has no row" "0" "$(jq '[.rows[] | select(.claim | startswith("timeFormat:"))] | length' <<<"$out")"

# --- Case 53: nested keys are checked inside objects the page documents children of ----
m="$(make_machine nested)"
mkdir -p "$m/docs"
cp "$DOCS/llms.txt" "$DOCS/env-vars.md" "$m/docs/"
{
  cat "$DOCS/settings-reference.md"
  printf '## Sandbox settings\n\n'
  section sandbox '* **Type**: object with `enabled` and `network`'
  section sandbox.enabled
  section sandbox.network '* **Type**: object with the sub-keys below'
  section sandbox.network.allowedDomains '* **Type**: array of strings'
  section statusLine '* **Type**: object with `type` set to `"command"` and a `command` string, plus optional `padding` as a number'
} >"$m/docs/settings-reference.md"
make_cli "$m/claude-nested" "2.1.281 (Claude Code)" enabledPlugins permissions zzBinaryOnly
printf '%s\n' "$CLEAN_SETTINGS" | jq '. + {sandbox:{enabled:true,zzBinaryOnly:1,zzMissing:1,network:{allowedDomains:[],zzNetMissing:1}},statusLine:{type:"command",command:"x",padding:1,zzStatusMissing:1},env:{ANY_VARIABLE:"1"}}' >"$m/project/.claude/settings.json"
out=$(CLI_BIN="$m/claude-nested" DOCS_FIXTURE="$m/docs" run "$m" --json 2>&1) || true
nested_status() { jq -r --arg c "$1" '.rows[] | select(.claim == $c) | "\(.status) \(.severity)"' <<<"$out"; }
assert_eq "case 53: a nested key with its own heading is documented" "ok none" "$(nested_status documented-key:sandbox.enabled)"
assert_eq "case 53: a key two objects deep is documented" "ok none" "$(nested_status documented-key:sandbox.network.allowedDomains)"
assert_eq "case 53: a key named only in the Type bullet is documented" "ok none" "$(nested_status documented-key:statusLine.padding)"
assert_eq "case 53: the object itself is still a documented key" "ok none" "$(nested_status documented-key:sandbox.network)"
assert_eq "case 53: an unknown nested key the binary carries is info" "finding info" "$(nested_status undocumented-key:sandbox.zzBinaryOnly)"
assert_eq "case 53: an unknown nested key in neither is a warning" "finding warning" "$(nested_status undocumented-key:sandbox.zzMissing)"
assert_eq "case 53: an unknown key two objects deep is a warning" "finding warning" "$(nested_status undocumented-key:sandbox.network.zzNetMissing)"
assert_eq "case 53: an unknown key of a Type-bullet object is a warning" "finding warning" "$(nested_status undocumented-key:statusLine.zzStatusMissing)"
assert_eq "case 53: the anchor is the nested JSON pointer's" "$(bash "$SCRIPT" anchor --excerpt "/sandbox/network/zzNetMissing")" "$(jq -r '.findings[] | select(.identity.claim=="undocumented-key:sandbox.network.zzNetMissing") | .identity.sites[0]["anchor/v1"]' <<<"$out")"
assert_eq "case 53: an object the page documents no child of is not descended into" "0" "$(jq '[.rows[] | select(.claim | test("key:env\\."))] | length' <<<"$out")"

# --- Case 54: known-issues fix versions are compared with the installed version
# The fixture is the shipped table with the documented `Fixed in vX.Y.Z` start of the third column
# added to two rows, so the test reads the same layout the reference file describes.
ki_real="$SCRIPT_DIR/../reference/known-issues.md"
ki="$TEST_TMPDIR/known-issues.md"
sed -e '/#8961\]/s/| Place all/| Fixed in v2.1.270. Place all/' \
  -e '/#36808\]/s/| Wrap npx/| Fixed in 2.1.290. Wrap npx/' "$ki_real" >"$ki"
assert_eq "case 54: the fixture edits landed on the two table rows" "2" "$(grep -cE '^\| \[#(8961|36808)\].*Fixed in v?[0-9]' "$ki")"
m="$(make_machine known-issues)"
printf '%s\n' "$CLEAN_SETTINGS" >"$m/project/.claude/settings.json"
out=$(SETTINGS_AUDIT_ENGINE_KNOWN_ISSUES_FILE="$ki" run "$m" --json 2>&1) || true
ki_status() { jq -r --arg c "$1" '.rows[] | select(.claim == $c) | "\(.status) \(.severity)"' <<<"$out"; }
assert_eq "case 54: an issue fixed in an older version is info" "finding info" "$(ki_status 'fix-version:#8961')"
assert_eq "case 54: an issue fixed in a newer version is ok" "ok none" "$(ki_status 'fix-version:#36808')"
assert_eq "case 54: a row with no fix version has no row" "" "$(ki_status 'fix-version:#23869')"
make_cli "$m/claude-none" ""
out=$(SETTINGS_AUDIT_ENGINE_KNOWN_ISSUES_FILE="$ki" CLI_BIN="$m/claude-none" run "$m" --json 2>&1) || true
assert_eq "case 54: an unreadable version skips" "skip none" "$(ki_status 'fix-version:#8961')"

if [[ "$FAILED" -eq 0 ]]; then
  printf '\nAll %d checks passed.\n' "$CASE_NUM"
  exit 0
fi
printf '\n%d/%d checks failed.\n' "$FAILED" "$CASE_NUM" >&2
exit 1
