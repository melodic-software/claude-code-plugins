#!/usr/bin/env bash
# permission-rule-check.sh — deterministic detector for fragile Claude Code
# permission grants across a repo's skill/command/agent frontmatter and its
# settings.json / settings.local.json permission rules.
#
# Flags three anti-patterns (criteria file: reference/criteria.md):
#   P1  interpreter-wildcard / blanket allow rules that Claude Code DROPS on
#       entering auto mode (blanket Bash(*)/PowerShell(*), wildcarded
#       interpreters like Bash(python*), package-manager run wildcards,
#       script-glob interpreters like Bash(*.py:*), and Agent allow rules —
#       both bare Agent and Agent(...), which auto mode drops categorically).
#       Narrow rules such as Bash(npm test) carry over and are NOT flagged.
#   P2  hardcoded absolute user/machine home paths inside a rule. Bash rules
#       match the command string literally — no ~, $HOME, or env expansion — so
#       an absolute path breaks on other machines/usernames and leaks a
#       username into version control.
#   P3  a plugin settings.json that declares a `permissions` block. A plugin's
#       settings.json supports only the `agent` and `subagentStatusLine` keys,
#       so a self-granted permission rule is silently ignored; the operative
#       allow-rule has to be added by the operator to ~/.claude/settings.json.
#
# Advisory: prints findings, ALWAYS exits 0 (findings never fail the run).
# Requires jq for the settings-file half; exits 2 when jq is absent.
#
# Root resolution: $PERMISSION_HYGIENE_FIXTURE_DIR, else the cwd's git
# toplevel, else $CLAUDE_PROJECT_DIR, else $PWD. Never the plugin's own dir.
#
# Usage:
#   permission-rule-check.sh            # human-readable findings, one per line
#   permission-rule-check.sh --count    # integer finding count only
#   permission-rule-check.sh --help

set -uo pipefail

usage() {
  cat <<'EOF'
permission-rule-check.sh — flag fragile Claude Code permission grants.

Usage: permission-rule-check.sh [--count|--help]

  (no arg)   print one finding line per fragile grant; exit 0
  --count    print the integer finding count only; exit 0
  --help     this message

Scans skill/command/agent frontmatter `allowed-tools` and the `permissions.allow`
arrays of .claude/settings.json and .claude/settings.local.json for P1 (auto-mode
-dropped interpreter/blanket rules), P2 (hardcoded machine paths), and plugin
settings.json for P3 (unsupported self-granted `permissions`). Advisory — exit 0.
Requires jq (exit 2 when absent).
EOF
}

case "${1:-}" in
  -h | --help)
    usage
    exit 0
    ;;
  *) ;;
esac

if ! command -v jq >/dev/null 2>&1; then
  echo "ERROR: jq required" >&2
  exit 2
fi

mode="report"
[[ "${1:-}" == "--count" ]] && mode="count"

if [[ -n "${PERMISSION_HYGIENE_FIXTURE_DIR:-}" ]]; then
  ROOT="$PERMISSION_HYGIENE_FIXTURE_DIR"
else
  ROOT="$(git rev-parse --show-toplevel 2>/dev/null | tr -d '\r')"
  [[ -n "$ROOT" ]] || ROOT="${CLAUDE_PROJECT_DIR:-$PWD}"
fi

# --- Detection patterns -------------------------------------------------------
#
# P1 — one ERE, case-sensitive on the tool name. Each alternative requires a
# wildcard so an exact narrow rule (Bash(npm test)) never matches:
#   1. blanket Bash(*) / PowerShell(*)
#   2. an interpreter at the command position followed (eventually) by a *
#   3. a package-manager run/exec command followed by a *
#   4. a leading-glob command that resolves to a script (Bash(*.py:*))
_interp='python3?|node|deno|bun|ruby|perl|php|bash|sh|zsh|pwsh|osascript|Rscript'
_runner='npx|bunx|uvx|pnpm dlx|yarn dlx|pipx run|uv run|npm run|pnpm run|yarn run'
_script='py|sh|rb|js|ts|mjs|cjs|pl|php'
# Each alternative captures the whole Tool(...) spec (trailing [^)]*\) ) so a
# finding reports the full offending rule, not a substring truncated at the *.
P1_ERE="(Bash|PowerShell)\\(\\*\\)"
P1_ERE="${P1_ERE}|(Bash|PowerShell)\\([\"' ]*(${_interp})([^A-Za-z0-9_)][^)]*)?\\*[^)]*\\)"
P1_ERE="${P1_ERE}|(Bash|PowerShell)\\([\"' ]*(${_runner})([^A-Za-z0-9_)][^)]*)?\\*[^)]*\\)"
P1_ERE="${P1_ERE}|(Bash|PowerShell)\\([\"' ]*\\*[^)]*\\.(${_script})[^)]*\\)"

# P2 — machine home-path shapes, ASSEMBLED FROM FRAGMENTS so no contiguous
# home-path literal appears in this file's source bytes and trips the repo's
# own machine-specific-path scanner. `seg` is one
# real segment character: not a separator, wildcard, or a placeholder/expansion
# lead (<, $, {, ~), so `${CLAUDE_PROJECT_DIR}/…`, `~/…`, and doc placeholders
# like `<name>` are not matched — only concrete usernames are.
_sl='/'
# shellcheck disable=SC1003  # _bs is a literal single backslash, not an escape
_bs='\'
_seg="[^${_sl}${_bs}*<>\${}~ ]"
P2_ERE="${_sl}Users${_sl}${_seg}"                                    # macOS + POSIX-normalized Windows (/c/Users/…)
P2_ERE="${P2_ERE}|${_sl}home${_sl}${_seg}"                           # Linux
P2_ERE="${P2_ERE}|[A-Za-z]:[${_sl}${_bs}]Users[${_sl}${_bs}]${_seg}" # raw Windows drive

findings=()

emit() {
  # emit <severity> <check> <source> <detail>
  findings+=("$1 [$2] $3: $4")
}

scan_rule() {
  # scan_rule <rule-string> <source-label> — one allow rule or one frontmatter token region
  local text="$1" src="$2" m
  while IFS= read -r m; do
    [[ -n "$m" ]] && emit warning P1 "$src" "'$m' is an interpreter/runner-led grant, not the portable bare-name pattern; Claude Code drops the broad forms of this shape (blanket, package-manager runners, and wildcarded/globbed-target interpreters) on entering auto mode. Expose the guarded script as a bare PATH command and allow that, e.g. Bash(babysit_merge.sh:*)."
  done < <(printf '%s\n' "$text" | grep -oE "$P1_ERE" 2>/dev/null | sort -u)
  while IFS= read -r m; do
    [[ -n "$m" ]] && emit error P2 "$src" "hardcoded machine path in '$m' — Bash rules match literally (no ~/\$HOME/env expansion), so this breaks on other machines/usernames and leaks a username into source control. Use a machine-independent bare-name rule."
  done < <(printf '%s\n' "$text" | grep -oE "$P2_ERE" 2>/dev/null | sort -u)
}

scan_bare_tool() {
  # scan_bare_tool <text> <source-label> — flag a bare `Bash`/`PowerShell`
  # token (the whole-tool grant that auto mode drops). scan_settings_allow
  # exact-matches this per rule; frontmatter arrives as a blob the parenthesized
  # P1 ERE cannot see, so it needs a token-level scan. A token immediately
  # followed by `(` (e.g. Bash(npm test)) is a scoped rule, not a bare grant,
  # and is excluded so an interpreter rule is not double-flagged.
  local text="$1" src="$2" tool
  for tool in Bash PowerShell; do
    if printf '%s\n' "$text" | grep -qE "(^|[^[:alnum:]_])${tool}([^[:alnum:]_(]|\$)"; then
      emit warning P1 "$src" "bare '$tool' allow rule grants the whole tool and is dropped in auto mode. Allow a specific bare-name command instead, e.g. Bash(babysit_merge.sh:*)."
    fi
  done
}

scan_agent() {
  # scan_agent <text> <source-label> — flag an `Agent` allow rule, whether bare
  # `Agent` or scoped `Agent(...)`. Unlike Bash/PowerShell, a scoped Agent rule
  # is NOT a narrow carry-over: auto mode drops all Agent allow rules
  # categorically, and Agent has no bare-PATH-command analog to re-scope to.
  #
  # The word "Agent" must be the rule's own tool token, not a fragment inside
  # another tool's payload (e.g. Bash(echo Agent), Bash(find *Agent*)). So the
  # text is first split into top-level `Tool` / `Tool(...)` tokens — the greedy
  # `(\(...\))?` consumes a tool's whole parenthesized payload as one token, so
  # an inner "Agent" never surfaces as its own token — then only a token that IS
  # `Agent` or begins `Agent(` is flagged.
  local text="$1" src="$2" tok
  while IFS= read -r tok; do
    if [[ "$tok" == "Agent" || "$tok" == "Agent("* ]]; then
      emit warning P1 "$src" "Agent allow rules are dropped in auto mode and have no PATH-durable analog — remove/re-scope, or run outside auto mode."
      break
    fi
  done < <(printf '%s\n' "$text" | grep -oE '[A-Za-z_][A-Za-z0-9_]*(\([^)]*\))?' 2>/dev/null)
}

# --- Frontmatter allowed-tools scan ------------------------------------------
# allowed-tools value + its block-list continuation lines, from the leading
# --- frontmatter block only.
extract_allowed_tools() {
  awk '
    NR==1 && $0 !~ /^---[[:space:]]*$/ { exit }
    NR==1 { infm=1; next }
    infm && /^---[[:space:]]*$/ { exit }
    infm {
      if (cap) {
        if ($0 ~ /^[[:space:]]/ || $0 ~ /^[[:space:]]*-/) { print; next }
        else { cap=0 }
      }
      if ($0 ~ /^allowed-tools:[[:space:]]*/) { sub(/^allowed-tools:/, ""); print; cap=1 }
    }
  ' "$1" | tr -d '\r'
}

# SKILL.md anywhere, plus markdown directly under an agents/ or commands/ dir.
while IFS= read -r file; do
  [[ -f "$file" ]] || continue
  at="$(extract_allowed_tools "$file")"
  [[ -n "${at//[[:space:]]/}" ]] || continue
  rel="${file#"$ROOT"/}"
  scan_rule "$at" "$rel allowed-tools"
  scan_bare_tool "$at" "$rel allowed-tools"
  scan_agent "$at" "$rel allowed-tools"
done < <(
  find "$ROOT" -type f \( \
    -name 'SKILL.md' \
    -o \( -name '*.md' -path '*/agents/*' \) \
    -o \( -name '*.md' -path '*/commands/*' \) \
    \) 2>/dev/null | sort -u
)

# --- Settings permissions.allow scan -----------------------------------------
scan_settings_allow() {
  local file="$1" label="$2" rule
  [[ -f "$file" ]] || return 0
  tr -d '\r' <"$file" | jq -e . >/dev/null 2>&1 || return 0
  while IFS= read -r rule; do
    [[ -n "$rule" ]] || continue
    scan_bare_tool "$rule" "$label"
    scan_agent "$rule" "$label"
    scan_rule "$rule" "$label"
    # Trailing tr strips CR: jq emits CRLF on Windows, which would otherwise
    # leave a \r on each rule and pollute the token the scans above match.
  done < <(tr -d '\r' <"$file" | jq -r '.permissions.allow // [] | .[]' 2>/dev/null | tr -d '\r')
}

scan_settings_allow "$ROOT/.claude/settings.json" ".claude/settings.json permissions.allow"
scan_settings_allow "$ROOT/.claude/settings.local.json" ".claude/settings.local.json permissions.allow"

# --- Plugin self-grant scan (P3) ---------------------------------------------
# A settings.json sitting at a plugin root (sibling .claude-plugin/plugin.json)
# may only carry `agent` / `subagentStatusLine`; a `permissions` block is inert.
while IFS= read -r manifest; do
  plugin_dir="$(dirname "$(dirname "$manifest")")"
  settings="$plugin_dir/settings.json"
  [[ -f "$settings" ]] || continue
  tr -d '\r' <"$settings" | jq -e . >/dev/null 2>&1 || continue
  if tr -d '\r' <"$settings" | jq -e 'has("permissions")' >/dev/null 2>&1; then
    rel="${settings#"$ROOT"/}"
    emit warning P3 "$rel" "plugin settings.json declares 'permissions' — a plugin's settings.json supports only the agent and subagentStatusLine keys, so this grant is ignored. The operative allow-rule must be added by the operator to ~/.claude/settings.json."
  fi
done < <(find "$ROOT" -type f -path '*/.claude-plugin/plugin.json' 2>/dev/null | sort -u)

# --- Output -------------------------------------------------------------------
if [[ "$mode" == "count" ]]; then
  printf '%s\n' "${#findings[@]}"
  exit 0
fi

if [[ "${#findings[@]}" -eq 0 ]]; then
  echo "No fragile permission grants found."
else
  printf '%s\n' "${findings[@]}"
fi
exit 0
