#!/usr/bin/env bash
# permission-rule-check.sh — deterministic detector for fragile Claude Code
# permission grants across a repo's skill/command/agent frontmatter and its
# settings.json / settings.local.json permission rules.
#
# Flags three anti-patterns (criteria file: reference/criteria.md):
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
#
# Advisory about FINDINGS: they never fail the run, so a scan that completes exits 0
# whether or not it found anything. Environment gaps are the exception and exit 2 —
# missing jq, and an unresolvable scan root (below).
#
# Every run reports a DENOMINATOR — the coverage block. Without it "no fragile
# permission grants found" is the same string whether forty allowed-tools blocks
# were parsed and found healthy or none were parsed at all, and the reader cannot
# tell a clean bill from a scan of nothing. The block counts what was read AND what
# was not: files the walk could not open, settings files present but not valid JSON
# (which this script skips), files removed by an exclusion rule, and the settings
# scopes this detector never opens at all. A denominator that counts only successes
# would be the same defect in a new spelling.
#
# Project-root resolution: $PERMISSION_HYGIENE_SCAN_ROOT (or its back-compatible
# alias $PERMISSION_HYGIENE_FIXTURE_DIR), else the cwd's git toplevel, else
# $CLAUDE_PROJECT_DIR. Never the plugin's own dir, and NEVER $PWD. The scan-root
# variable is a SANCTIONED operator lever, not a test-only seam: it is the
# documented remedy for the exit-2 refusal below. The old name said "FIXTURE" and
# told operators the opposite, so it keeps working and the new name is the one
# every surface documents.
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

  (no arg)   print one finding line per fragile grant, then the coverage block; exit 0
  --count    print the integer finding count on stdout, coverage block on stderr; exit 0
  --help     this message

Scans skill/command/agent frontmatter `allowed-tools` and the `permissions.allow`
arrays of .claude/settings.json, .claude/settings.local.json, and the user-global
settings file (${CLAUDE_CONFIG_DIR:-~/.claude}/settings.json) for P1 (auto-mode
-dropped interpreter/blanket rules), P2 (hardcoded machine paths), and plugin
settings.json for P3 (unsupported self-granted `permissions`).

Every run ends with a COVERAGE BLOCK giving the denominator: how many
allowed-tools blocks and allow rules were actually read, per settings scope; how
many candidate files an exclusion rule removed; how many paths the walk could not
read; how many settings files were present but not valid JSON (skipped); and which
settings scopes this detector never opens. "No fragile permission grants found."
means the denominator was non-zero and clean. A run that read nothing says so in a
different string and never claims a clean bill.

Findings are advisory and never fail the run, so a completed scan exits 0 in both
modes. Environment gaps exit 2 instead of reporting a clean bill: missing jq, and a
scan root that resolves to neither a git toplevel nor $CLAUDE_PROJECT_DIR. Set
$PERMISSION_HYGIENE_SCAN_ROOT to scan an explicit directory — a supported operator
lever, not a test-only seam. $PERMISSION_HYGIENE_FIXTURE_DIR remains as a
back-compatible alias; the new name wins when both are set.
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

ROOT_SOURCE=""
if [[ -n "${PERMISSION_HYGIENE_SCAN_ROOT:-}" ]]; then
  ROOT="$PERMISSION_HYGIENE_SCAN_ROOT"
  ROOT_SOURCE="\$PERMISSION_HYGIENE_SCAN_ROOT"
elif [[ -n "${PERMISSION_HYGIENE_FIXTURE_DIR:-}" ]]; then
  # Back-compatible alias. Its name says "fixture", but #2249 made it the
  # documented operator remedy for the exit-2 refusal below, so it stays working
  # while $PERMISSION_HYGIENE_SCAN_ROOT is the name every surface now documents.
  ROOT="$PERMISSION_HYGIENE_FIXTURE_DIR"
  ROOT_SOURCE="\$PERMISSION_HYGIENE_FIXTURE_DIR (alias of \$PERMISSION_HYGIENE_SCAN_ROOT)"
else
  ROOT="$(git rev-parse --show-toplevel 2>/dev/null | tr -d '\r')"
  ROOT_SOURCE="git toplevel"
  if [[ -z "$ROOT" ]]; then
    ROOT="${CLAUDE_PROJECT_DIR:-}"
    ROOT_SOURCE="\$CLAUDE_PROJECT_DIR"
  fi
fi

# No $PWD fallback — see the header. Refuse rather than sweep an unknown tree, and
# refuse in BOTH modes: a `--count` of 0 from a scan that never resolved a root reads
# exactly like a clean bill, which is the confusion this refusal exists to remove.
if [[ -z "$ROOT" ]]; then
  cat >&2 <<'EOF'
ERROR: no scan root resolved — refusing to scan.

Tried, in order: $PERMISSION_HYGIENE_SCAN_ROOT (alias:
$PERMISSION_HYGIENE_FIXTURE_DIR), the current directory's git toplevel, then
$CLAUDE_PROJECT_DIR. None resolved, and there is deliberately no fallback to the
current directory: outside a repository that is usually the user profile, and
scanning it would walk the whole home tree and still report success.

Fix by running from inside the repository you mean to scan, or set
$PERMISSION_HYGIENE_SCAN_ROOT to the directory to scan explicitly. That variable is
a supported operator lever, not a test-only seam.
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
P2_ERE="${_sl}Users${_sl}${_seg}"                                    # macOS + POSIX-normalized Windows (/c/Users/…)
P2_ERE="${P2_ERE}|${_sl}home${_sl}${_seg}"                           # Linux
P2_ERE="${P2_ERE}|[A-Za-z]:[${_sl}${_bs}]Users[${_sl}${_bs}]${_seg}" # raw Windows drive

findings=()

# --- Denominator ---------------------------------------------------------------
# What the coverage block reports. Successes and non-successes are counted
# separately on purpose: the point of the block is that a reader can tell a clean
# bill from a scan that read nothing, or from one whose inputs it could not open.
fm_candidates=0        # frontmatter files the walk returned
fm_excluded_vendor=0   # …of those, removed by the vendor/ exclusion
fm_with_block=0        # …of the rest, carrying a non-empty allowed-tools block
allow_rules_read=0     # allow rules actually parsed, across all settings scopes
scopes_read=0          # settings scopes successfully read
unparsable_settings=0  # settings files present but not valid JSON — SKIPPED, not clean
plugin_manifests=0
plugin_settings_parsed=0
plugin_settings_unparsable=0
scope_status=()

# `find` stderr was discarded outright. This file's own header argues why that
# matters — "a swallowed permission error was indistinguishable from a clean bill"
# — so capture it and count it into the block instead of throwing it away.
WALK_ERR="$(mktemp)"
trap 'rm -f "$WALK_ERR"' EXIT

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
    [[ -n "$m" ]] && emit error P2 "$src" "hardcoded machine path in '$m' — the rule names a concrete user home, so it breaks on other machines and usernames and leaks a username into source control. Portable forms: \${CLAUDE_SKILL_DIR} for a skill's own bundled script (substituted in allowed-tools Bash rules), a bare-name command on PATH, or the ~/ home anchor for Read/Edit rules."
  done < <(printf '%s\n' "$text" | grep -oE "$P2_ERE" 2>/dev/null | sort -u)
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
#
# The exclusion moved OUT of the `find` predicate and into the loop so the run can
# say how many files it removed. An exclusion nothing counts is invisible, and an
# invisible exclusion is indistinguishable from a tree that had nothing in it —
# the same confusion the coverage block exists to remove. Same predicate, same
# result set; only the accounting changed.
while IFS= read -r file; do
  [[ -f "$file" ]] || continue
  fm_candidates=$((fm_candidates + 1))
  case "$file" in
    */vendor/*)
      fm_excluded_vendor=$((fm_excluded_vendor + 1))
      continue
      ;;
  esac
  at="$(extract_allowed_tools "$file")"
  [[ -n "${at//[[:space:]]/}" ]] || continue
  fm_with_block=$((fm_with_block + 1))
  rel="${file#"$ROOT"/}"
  scan_rule "$at" "$rel allowed-tools"
  scan_bare_tool "$at" "$rel allowed-tools"
  scan_agent "$at" "$rel allowed-tools"
done < <(
  find "$ROOT" -type f \( \
    -name 'SKILL.md' \
    -o \( -name '*.md' -path '*/agents/*' \) \
    -o \( -name '*.md' -path '*/commands/*' \) \
    \) 2>>"$WALK_ERR" | sort -u
)

# --- Settings permissions.allow scan -----------------------------------------
scan_settings_allow() {
  # scan_settings_allow <file> <finding-label> <coverage-label>
  #
  # Both early returns used to be silent, so a scope that was absent and a scope
  # whose JSON would not parse left no trace and the run still printed a clean
  # bill. They now record which one happened. An unparsable settings file is the
  # sharper of the two: its rules were never read, and a rules file that fails to
  # parse is exactly where a fragile grant would sit unexamined.
  local file="$1" label="$2" short="$3" rule n=0
  if [[ ! -f "$file" ]]; then
    scope_status+=("$short: absent")
    return 0
  fi
  if ! tr -d '\r' <"$file" | jq -e . >/dev/null 2>&1; then
    scope_status+=("$short: NOT VALID JSON — its rules were not read")
    unparsable_settings=$((unparsable_settings + 1))
    return 0
  fi
  while IFS= read -r rule; do
    [[ -n "$rule" ]] || continue
    n=$((n + 1))
    scan_bare_tool "$rule" "$label"
    scan_agent "$rule" "$label"
    scan_rule "$rule" "$label"
    # Trailing tr strips CR: jq emits CRLF on Windows, which would otherwise
    # leave a \r on each rule and pollute the token the scans above match.
  done < <(tr -d '\r' <"$file" | jq -r '.permissions.allow // [] | .[]' 2>/dev/null | tr -d '\r')
  allow_rules_read=$((allow_rules_read + n))
  scopes_read=$((scopes_read + 1))
  scope_status+=("$short: $n rule(s)")
}

scan_settings_allow "$ROOT/.claude/settings.json" ".claude/settings.json permissions.allow" "project"
scan_settings_allow "$ROOT/.claude/settings.local.json" ".claude/settings.local.json permissions.allow" "local"

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
    scan_settings_allow "$user_settings" "$user_settings permissions.allow" "user-global ($user_settings)"
  else
    scope_status+=("user-global: same file as the project scope, counted once")
  fi
else
  # An unresolvable user scope is a skipped check, not a clean one. Silence here
  # would let a report claiming "no fragile grants" rest on a scope never read.
  scope_status+=("user-global: NOT RESOLVED (neither CLAUDE_CONFIG_DIR nor HOME is set)")
  echo "NOTE: user-global scope not scanned — neither CLAUDE_CONFIG_DIR nor HOME is set, so ~/.claude could not be resolved." >&2
fi

# --- Plugin self-grant scan (P3) ---------------------------------------------
# A settings.json sitting at a plugin root (sibling .claude-plugin/plugin.json)
# may only carry `agent` / `subagentStatusLine`; a `permissions` block is inert.
while IFS= read -r manifest; do
  plugin_manifests=$((plugin_manifests + 1))
  plugin_dir="$(dirname "$(dirname "$manifest")")"
  settings="$plugin_dir/settings.json"
  [[ -f "$settings" ]] || continue
  if ! tr -d '\r' <"$settings" | jq -e . >/dev/null 2>&1; then
    plugin_settings_unparsable=$((plugin_settings_unparsable + 1))
    continue
  fi
  plugin_settings_parsed=$((plugin_settings_parsed + 1))
  if tr -d '\r' <"$settings" | jq -e 'has("permissions")' >/dev/null 2>&1; then
    rel="${settings#"$ROOT"/}"
    emit warning P3 "$rel" "plugin settings.json declares 'permissions' — a plugin's settings.json supports only the agent and subagentStatusLine keys, so this grant is ignored. The operative allow-rule must be added by the operator to ~/.claude/settings.json."
  fi
done < <(find "$ROOT" -type f -path '*/.claude-plugin/plugin.json' 2>>"$WALK_ERR" | sort -u)

# --- Output -------------------------------------------------------------------
walk_errors="$(awk 'NF{n++} END{print n+0}' "$WALK_ERR" 2>/dev/null)"
[[ -n "$walk_errors" ]] || walk_errors=0

# The denominator: every unit this run could have produced a finding about. All
# THREE axes count, including P3's — a plugin settings.json that parsed is a
# surface the run examined, so a root holding only clean plugin settings has a
# denominator and gets a clean bill. Folding P3 in is not cosmetic: leaving it out
# made a run that examined two plugin settings files report "this run has no
# denominator" two lines above the count of the files it examined, which is the
# exact defect this block exists to remove, in a new spelling.
audited=$((fm_with_block + allow_rules_read + plugin_settings_parsed))

coverage_block() {
  local s joined=""
  # Guarded: under `set -u` an empty array must not be expanded at all.
  if [[ "${#scope_status[@]}" -gt 0 ]]; then
    for s in "${scope_status[@]}"; do
      [[ -n "$joined" ]] && joined="$joined; "
      joined="$joined$s"
    done
  fi
  [[ -n "$joined" ]] || joined="(no settings scope was attempted)"
  printf '\nScan coverage (the denominator — what this run actually read):\n'
  printf '  root: %s (resolved from %s)\n' "$ROOT" "$ROOT_SOURCE"
  printf '  frontmatter: %d allowed-tools block(s) parsed from %d candidate file(s); %d excluded under a vendor/ path segment as non-loadable\n' \
    "$fm_with_block" "$fm_candidates" "$fm_excluded_vendor"
  printf '  settings: %d allow rule(s) from %d scope(s) read — %s\n' \
    "$allow_rules_read" "$scopes_read" "$joined"
  printf '  plugins: %d manifest(s); %d settings.json parsed\n' \
    "$plugin_manifests" "$plugin_settings_parsed"
  printf '  NOT read: %d path(s) the walk could not open; %d settings file(s) and %d plugin settings.json present but not valid JSON\n' \
    "$walk_errors" "$unparsable_settings" "$plugin_settings_unparsable"
  printf '  never in scope here: managed-policy and enterprise settings, a --settings flag file, and the pre-v2.1.211 start-directory copy. Which scopes exist and what each holds is audit-permission-state, not this detector.\n'
  printf '  exemptions applied by consumer declaration: none (this detector reads no consumer declaration; see the skill body, which requires every one it applies to be named in the report).\n'
}

if [[ "$mode" == "count" ]]; then
  # stdout stays the bare integer — that is the machine contract. The block goes
  # to stderr so a `--count` of 0 from a scan of nothing is still distinguishable
  # from a 0 from a healthy tree, which is the whole point of the denominator.
  printf '%s\n' "${#findings[@]}"
  coverage_block >&2
  exit 0
fi

if [[ "${#findings[@]}" -eq 0 ]]; then
  if [[ "$audited" -eq 0 ]]; then
    # NOT a clean bill. "No fragile permission grants found." and "there was
    # nothing here to find them in" were the same string; they are now different
    # strings, because only one of them is a statement about the grants.
    echo "NOTHING TO AUDIT: 0 allowed-tools block(s), 0 allow rule(s) and 0 plugin settings.json were read under this root, so this run has no denominator on any of the three axes. That is a scan of nothing, not a clean bill — do not report it as one. See the coverage block below for what was and was not read."
  else
    echo "No fragile permission grants found."
  fi
else
  printf '%s\n' "${findings[@]}"
fi
coverage_block
exit 0
