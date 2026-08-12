#!/usr/bin/env bash
# permission-rule-check.sh — deterministic detector for fragile Claude Code
# permission grants across a repo's skill/command/agent frontmatter and its
# settings.json / settings.local.json permission rules.
#
# Flags five anti-patterns (criteria file: reference/criteria.md):
#   P1  interpreter-wildcard / blanket allow rules that Claude Code DROPS on
#       entering auto mode (blanket Bash(*)/PowerShell(*), wildcarded
#       interpreters like Bash(python*), package-manager wildcards — runner
#       subcommands (Bash(npx *)) and bare package managers (Bash(npm:*),
#       Bash(npm *)) — script-glob interpreters like Bash(*.py:*), and Agent
#       allow rules —
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
#   P4  inert substitution tokens in a Bash allow rule — `${CLAUDE_PLUGIN_ROOT}`
#       (not substituted in allowed-tools), `%USERPROFILE%`, or
#       `$env:USERPROFILE` (unexpanded in Bash rules). The grant never matches.
#   P2b `~username/…` in a Bash rule — the portable `~/` home anchor is exempt
#       (Read/Edit resolve it per user); `~user` is not portable, names a
#       specific account, and is not expanded in Bash rules.
#
# Advisory about FINDINGS: they never fail the run, so a scan that completes exits 0
# whether or not it found anything. Environment gaps are the exception and exit 2 —
# missing jq, and an unresolvable scan root (below).
#
# Project-root resolution: $PERMISSION_HYGIENE_FIXTURE_DIR, else the cwd's git
# toplevel, else $CLAUDE_PROJECT_DIR. Never the plugin's own dir, and NEVER $PWD.
#
# Why there is no $PWD fallback: outside a git repository $PWD is whatever directory
# the session happens to stand in, which on a developer machine is typically the user
# profile. Both scans below walk the root with `find` with no depth bound and stderr
# discarded, so that fallback turned an unresolved root into an unbounded sweep of the
# user's home that still exited 0 — a timeout or a swallowed permission error was
# indistinguishable from a clean bill. An unresolvable root is an environment gap, so
# it is reported as one (exit 2) rather than scanned on a guess.
#
# User-scope resolution: $CLAUDE_CONFIG_DIR, else $HOME/.claude.
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
arrays of .claude/settings.json, .claude/settings.local.json, and the user-global
settings file (${CLAUDE_CONFIG_DIR:-~/.claude}/settings.json) for P1 (auto-mode
-dropped interpreter/blanket rules), P2 (hardcoded machine paths), and plugin
settings.json for P3 (unsupported self-granted `permissions`).

Findings are advisory and never fail the run, so a completed scan exits 0 in both
modes. Environment gaps exit 2 instead of reporting a clean bill: missing jq, and a
scan root that resolves to neither a git toplevel nor $CLAUDE_PROJECT_DIR. Set
$PERMISSION_HYGIENE_FIXTURE_DIR to scan an explicit directory.
EOF
}

case "${1:-}" in
  -h | --help)
    usage
    exit 0
    ;;
  *) ;;
esac

canonical_path() {
  local p="$1"
  if [[ -e "$p" ]]; then
    printf '%s/%s' "$(cd "$(dirname "$p")" && pwd -P)" "$(basename "$p")"
  else
    printf '%s' "$p"
  fi
}

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
  [[ -n "$ROOT" ]] || ROOT="${CLAUDE_PROJECT_DIR:-}"
fi

# No $PWD fallback — see the header. Refuse rather than sweep an unknown tree, and
# refuse in BOTH modes: a `--count` of 0 from a scan that never resolved a root reads
# exactly like a clean bill, which is the confusion this refusal exists to remove.
if [[ -z "$ROOT" ]]; then
  cat >&2 <<'EOF'
ERROR: no scan root resolved — refusing to scan.

Tried, in order: $PERMISSION_HYGIENE_FIXTURE_DIR, the current directory's git
toplevel, then $CLAUDE_PROJECT_DIR. None resolved, and there is deliberately no
fallback to the current directory: outside a repository that is usually the user
profile, and scanning it would walk the whole home tree and still report success.

Fix by running from inside the repository you mean to scan, or set
$PERMISSION_HYGIENE_FIXTURE_DIR to the directory to scan explicitly.
EOF
  exit 2
fi

if [[ ! -d "$ROOT" ]]; then
  printf 'ERROR: scan root does not exist or is not a directory: %s\n' "$ROOT" >&2
  exit 2
fi

# --- Detection patterns -------------------------------------------------------
#
# P1's auto-mode drop vocabulary is shared with audit-permission-state's entry
# diff, so it lives in a define-only library rather than here. Resolve the plugin
# root the way every other component in this marketplace does: Claude Code sets
# CLAUDE_PLUGIN_ROOT in plugin form, and the BASH_SOURCE fallback keeps a direct
# invocation (the test harness, a developer running the script) working.
PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-$(cd "${BASH_SOURCE[0]%/*}/../../.." && pwd)}"
PATTERNS_LIB="$PLUGIN_ROOT/lib/permission-patterns.sh"
if [[ ! -r "$PATTERNS_LIB" ]]; then
  echo "ERROR: cannot read $PATTERNS_LIB — the plugin's shared permission-pattern library is missing" >&2
  exit 2
fi
# shellcheck source=../../../lib/permission-patterns.sh
source "$PATTERNS_LIB"
P1_ERE="$CCPERM_P1_ERE"

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
_p2_path="${_sl}Users${_sl}${_seg}|${_sl}home${_sl}${_seg}|[A-Za-z]:[${_sl}${_bs}]Users[${_sl}${_bs}]${_seg}"
# Capture the WHOLE `Tool(...)` spec so a finding reports the offending rule rather
# than an eight-character path fragment — the intent already stated for P1 above.
#
# The tool name is the OPEN grammar, not an enumerated list. `(Read|Edit|Write|Bash
# |PowerShell)` would silently stop flagging a hardcoded path in a `WebFetch(...)`,
# `Glob(...)`, `NotebookEdit(...)`, `mcp__server__tool(...)` or `Agent(...)` rule —
# and this file has a dedicated `scan_agent()`, so `Agent` is unambiguously in
# scope. Narrowing an `error`-tier check's reach is not a reporting-format change.
# The leading `[A-Za-z_][A-Za-z0-9_]*` is `CCPERM_TOOL_TOKEN_ERE`'s own tool-name
# grammar, kept consistent with the library #2260 extracted.
P2_RULE_ERE="[A-Za-z_][A-Za-z0-9_]*\\([^)]*(${_p2_path})[^)]*\\)"
# `~user/…` in a Bash rule — not the portable `~/` anchor (Read/Edit resolve that
# per user). Bash rules match literally and do not expand tilde-user forms.
P2_TILDE_USER_RULE_ERE='Bash\([^)]*~[^/[:space:]~]+/[^)]*\)'

# Inert tokens: not among the two substitutions expanded in allowed-tools Bash
# rules, or unexpandable env-var spellings that make the rule a literal no-op.
# shellcheck disable=SC2016  # single quotes deliberate: \$ and % are literal ERE, not shell expansion
P4_INERT_ERE='\$\{CLAUDE_PLUGIN_ROOT\}|%USERPROFILE%|\$env:USERPROFILE'

findings=()

emit() {
  # emit <severity> <check> <source> <detail>
  findings+=("$1 [$2] $3: $4")
}

inert_grant_remedy() {
  # inert_grant_remedy <source-file-path> — branch the P4 remedy per #2397 A7b.
  local file="$1"
  case "$file" in
    */skills/*/SKILL.md)
      printf '%s' "replace with \${CLAUDE_SKILL_DIR} for a script bundled in this skill (substituted in allowed-tools Bash rules per the skills page)"
      ;;
    *)
      printf '%s' "relocate the helper to a stable bare command on PATH and allow that name narrowly — do not prescribe plugin bin/ (see permission-rule-hygiene convention known gap)"
      ;;
  esac
}

scan_rule() {
  # scan_rule <rule-string> <source-label> [<source-file>] — one allow rule or
  # one frontmatter token region. source-file enables the P4 remedy branch.
  local text="$1" src="$2" file="${3:-}" m remedy
  while IFS= read -r m; do
    [[ -n "$m" ]] && emit warning P1 "$src" "'$m' is an interpreter/runner-led grant, not the portable bare-name pattern; Claude Code drops the broad forms of this shape (blanket, package-manager runners, and wildcarded/globbed-target interpreters) on entering auto mode. Expose the guarded script as a bare PATH command and allow that, e.g. Bash(babysit_merge.sh:*)."
  done < <(printf '%s\n' "$text" | grep -oE "$P1_ERE" 2>/dev/null | sort -u)
  while IFS= read -r m; do
    [[ -z "$m" ]] && continue
    # No `//…` carve-out. `//` is the ABSOLUTE anchor, not a portable one: the
    # permissions page's own row is `//path` = "Absolute path from filesystem
    # root", with `Read(//Users/<name>/secrets/**)` -> `/Users/<name>/secrets/**`.
    # So `//Users/<name>/…` names a concrete user home and leaks the username,
    # exactly like `/Users/<name>/…`. `~/…` and `${CLAUDE_PROJECT_DIR}/…` are the
    # genuinely portable forms and are already excluded by `_seg` above.
    emit error P2 "$src" "hardcoded machine path in '$m' — the rule names a concrete user home, so it breaks on other machines and usernames and leaks a username into source control. Portable forms: \${CLAUDE_SKILL_DIR} for a skill's own bundled script (substituted in allowed-tools Bash rules), a bare-name command on PATH, or the ~/ home anchor for Read/Edit rules."
  done < <(printf '%s\n' "$text" | grep -oE "$P2_RULE_ERE" 2>/dev/null | sort -u)
  while IFS= read -r m; do
    [[ -z "$m" ]] && continue
    emit error P2 "$src" "tilde-user path in '$m' — Bash rules match literally and do not expand ~username forms, so the rule names a specific account, leaks a username into version control, and breaks on other machines. Use \${CLAUDE_SKILL_DIR} for a skill's own script, a bare-name command on PATH, or the ~/ home anchor for Read/Edit rules."
  done < <(printf '%s\n' "$text" | grep -oE "$P2_TILDE_USER_RULE_ERE" 2>/dev/null | sort -u)
  if printf '%s' "$text" | grep -qE "$P4_INERT_ERE"; then
    remedy="$(inert_grant_remedy "$file")"
    emit error P4 "$src" "inert substitution token in allow rule — the grant never matches at runtime ($text). Remedy: $remedy."
  fi
}

top_level_tokens() {
  # top_level_tokens <text> — split rule text into top-level `Tool` /
  # `Tool(...)` tokens, one per line. The token grammar is shared vocabulary;
  # this wrapper is the driver's own I/O around it.
  printf '%s\n' "$1" | grep -oE "$CCPERM_TOOL_TOKEN_ERE" 2>/dev/null
}

scan_bare_tool() {
  # scan_bare_tool <text> <source-label> — flag a bare `Bash`/`PowerShell`
  # token (the whole-tool grant that auto mode drops). Matching runs on
  # top-level tokens, so a scoped rule (Bash(npm test)) is not double-flagged
  # as a bare grant, and a tool name embedded in another rule's payload
  # (Bash(echo Bash)) is not flagged at all.
  local text="$1" src="$2" tool tok
  for tool in Bash PowerShell; do
    while IFS= read -r tok; do
      if [[ "$tok" == "$tool" ]]; then
        emit warning P1 "$src" "bare '$tool' allow rule grants the whole tool and is dropped in auto mode. Allow a specific bare-name command instead, e.g. Bash(babysit_merge.sh:*)."
        break
      fi
    done < <(top_level_tokens "$text")
  done
}

scan_agent() {
  # scan_agent <text> <source-label> — flag an `Agent` allow rule, whether bare
  # `Agent` or scoped `Agent(...)`. Unlike Bash/PowerShell, a scoped Agent rule
  # is NOT a narrow carry-over: auto mode drops all Agent allow rules
  # categorically, and Agent has no bare-PATH-command analog to re-scope to.
  # Matching runs on top-level tokens so only a rule whose own tool token IS
  # `Agent` or begins `Agent(` is flagged.
  local text="$1" src="$2" tok
  while IFS= read -r tok; do
    if [[ "$tok" == "Agent" || "$tok" == "Agent("* ]]; then
      emit warning P1 "$src" "Agent allow rules are dropped in auto mode and have no PATH-durable analog — remove/re-scope, or run outside auto mode."
      break
    fi
  done < <(top_level_tokens "$text")
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
# A file under a `vendor/` path segment is a vendored upstream reference, not a
# loadable skill/agent/command (Claude Code loads a skill from
# skills/<name>/SKILL.md, not from a nested vendor/ copy), so its `allowed-tools`
# never take effect and must not be flagged. Excluding the whole `vendor/`
# segment is a principled, path-based exclusion that covers both a direct child
# (vendor/SKILL.md) and a nested one (vendor/<tool>/SKILL.md).
while IFS= read -r file; do
  [[ -f "$file" ]] || continue
  at="$(extract_allowed_tools "$file")"
  [[ -n "${at//[[:space:]]/}" ]] || continue
  rel="${file#"$ROOT"/}"
  scan_rule "$at" "$rel allowed-tools" "$file"
  scan_bare_tool "$at" "$rel allowed-tools"
  scan_agent "$at" "$rel allowed-tools"
done < <(
  find "$ROOT" -type f \( \
    -name 'SKILL.md' \
    -o \( -name '*.md' -path '*/agents/*' \) \
    -o \( -name '*.md' -path '*/commands/*' \) \
    \) ! -path '*/vendor/*' 2>/dev/null | sort -u
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
    scan_rule "$rule" "$label" ""
    # Trailing tr strips CR: jq emits CRLF on Windows, which would otherwise
    # leave a \r on each rule and pollute the token the scans above match.
  done < <(tr -d '\r' <"$file" | jq -r '.permissions.allow // [] | .[]' 2>/dev/null | tr -d '\r')
}

scan_settings_allow "$ROOT/.claude/settings.json" ".claude/settings.json permissions.allow"
scan_settings_allow "$ROOT/.claude/settings.local.json" ".claude/settings.local.json permissions.allow"

# User-global scope. A project-only scan cannot see it, yet it is where Claude
# Code's own "Always allow" path writes, so it is the scope most likely to
# accumulate the broad rules auto mode drops. CLAUDE_CONFIG_DIR relocates the
# whole ~/.claude tree when set (official .claude-directory doc), so it wins over
# $HOME; with neither resolvable there is no user scope to scan. The label is the
# resolved absolute path — reporting "~/.claude/settings.json" would name the
# wrong file whenever CLAUDE_CONFIG_DIR has moved the tree.
#
# This resolution IS the fixture seam: a test points $HOME at a fixture home and
# unsets CLAUDE_CONFIG_DIR, the same seam claude-memory's resolver already uses.
# No test may read the operator's real ~/.claude.
if [[ -n "${CLAUDE_CONFIG_DIR:-}" ]]; then
  USER_CONFIG_ROOT="$CLAUDE_CONFIG_DIR"
elif [[ -n "${HOME:-}" ]]; then
  USER_CONFIG_ROOT="$HOME/.claude"
else
  USER_CONFIG_ROOT=""
fi
if [[ -n "$USER_CONFIG_ROOT" ]]; then
  user_settings="$USER_CONFIG_ROOT/settings.json"
  project_settings="$ROOT/.claude/settings.json"
  user_canonical="$(canonical_path "$user_settings")"
  project_canonical="$(canonical_path "$project_settings")"
  if [[ "$user_canonical" != "$project_canonical" ]]; then
    scan_settings_allow "$user_settings" "$user_settings permissions.allow"
  fi
else
  # An unresolvable user scope is a skipped check, not a clean one. Silence here
  # would let a report claiming "no fragile grants" rest on a scope never read.
  echo "NOTE: user-global scope not scanned — neither CLAUDE_CONFIG_DIR nor HOME is set, so ~/.claude could not be resolved." >&2
fi

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
