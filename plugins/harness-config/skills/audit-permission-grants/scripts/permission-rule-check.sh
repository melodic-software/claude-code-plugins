#!/usr/bin/env bash
set -uo pipefail

usage() {
  cat <<'EOF'
permission-rule-check.sh — flag fragile Claude Code permission grants.

Usage: permission-rule-check.sh [--count|--check|--strict|--help]

  (no arg)   print one finding line per fragile grant, then the coverage block; exit 0
  --count    print the integer finding count on stdout, coverage block on stderr; exit 0
  --check    gate mode: print findings and the coverage block exactly as the
             default does, then exit 1 if any ERROR-tier finding (P2, P2b, P4,
             P5) was emitted, else 0
  --strict   gate mode: as --check, and WARNING-tier findings (P1, P3) also exit 1
  --help     this message

ARGUMENTS. Flags may appear in any order and may be combined; the STRICTEST one
wins, ordered (no arg) < --count < --check < --strict. So `--check --strict` and
`--strict --check` both run as --strict; neither flag is silently discarded. An
ARGUMENT THAT IS NOT A RECOGNIZED FLAG IS REFUSED: this message goes to stderr and
the run exits 2 (cannot determine) without scanning. It never falls through to the
advisory report, because a typo'd flag in a CI invocation would otherwise leave the
gate exiting 0 forever on a tree full of findings. A literal empty argument (what a
quoted-but-unset "$MODE" expands to) is the sole exception: it is ignored, so
`"" --check` runs as --check.

Scans skill/command/agent frontmatter `allowed-tools` and the `permissions.allow`
arrays of .claude/settings.json, .claude/settings.local.json, and the user-global
settings file (${CLAUDE_CONFIG_DIR:-~/.claude}/settings.json) for P1 (auto-mode
-dropped interpreter/blanket rules), P2 (hardcoded machine paths), P2b (tilde-user
paths) and P4 (inert substitution tokens), and plugin settings.json for P3
(unsupported self-granted `permissions`). With the root taken from git, a run
started in a subdirectory also reads that directory's .claude/settings.json, and
a run in a linked worktree also reads the main checkout's
.claude/settings.local.json, the files Claude Code reads there.

Every run ends with a COVERAGE BLOCK giving the denominator: how many
allowed-tools blocks and allow rules were actually read, per settings scope; how
many candidate files an exclusion rule removed; how many paths the walk could not
read; how many settings files were present but not valid JSON (skipped); and which
settings scopes this detector never opens. "No fragile permission grants found."
means the denominator was non-zero and clean. A run that read nothing says so in a
different string and never claims a clean bill.

Findings are advisory in the default and --count modes, which always exit 0 however
many findings they print. --check and --strict are the opt-in gate: they print the
same findings and the same coverage block, and only the exit code differs. In BOTH
gate modes a NOTHING TO AUDIT result exits 2, never 0 — a scan that examined nothing
on any axis has no denominator, so it may not pass a gate. For the same reason a
PARTIALLY BLIND scan — anything counted under "NOT read" in the coverage block:
an unopenable frontmatter file, a settings.json that is not valid JSON, a walk
error — exits 2 rather than 0 in both gate modes, and the default mode reports it
as an INCOMPLETE SCAN rather than as a clean bill. A gate may not pass while its
own inputs were unreadable, and an unreadable input is exactly where a fragile
grant sits unexamined.

Environment gaps exit 2 in every mode instead of reporting a clean bill: missing jq,
and a scan root that resolves to neither a git toplevel nor $CLAUDE_PROJECT_DIR. Set
$PERMISSION_HYGIENE_SCAN_ROOT to scan an explicit directory — a supported operator
lever, not a test-only seam. $PERMISSION_HYGIENE_FIXTURE_DIR remains as a
back-compatible alias; the new name wins when both are set.
EOF
}

mode="report"
mode_rank=0
raise_mode() {
  if [[ "$2" -gt "$mode_rank" ]]; then
    mode_rank="$2"
    mode="$1"
  fi
}
for arg in "$@"; do
  case "$arg" in
  -h | --help)
    usage
    exit 0
    ;;
  --count) raise_mode count 1 ;;
  --check) raise_mode check 2 ;;
  --strict) raise_mode strict 3 ;;
  "") ;;
  *)
    printf 'ERROR: unrecognized argument: %s\n\n' "$arg" >&2
    usage >&2
    exit 2
    ;;
  esac
done

canonical_path() {
  local p="$1"
  if [[ -e "$p" ]]; then
    printf '%s/%s' "$(cd "$(dirname "$p")" && pwd -P)" "$(basename "$p")"
  else
    printf '%s' "$p"
  fi
}

PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-$(cd "${BASH_SOURCE[0]%/*}/../../.." && pwd)}"

if ! command -v jq >/dev/null 2>&1; then
  # shellcheck source=../../../lib/jq-install-hint.sh
  if [[ -r "$PLUGIN_ROOT/lib/jq-install-hint.sh" ]] && source "$PLUGIN_ROOT/lib/jq-install-hint.sh"; then
    jqhint::missing_message permission-rule-check.sh "${OSTYPE:-}" >&2
  else
    echo "ERROR: jq required" >&2
  fi
  exit 2
fi

ROOT_SOURCE=""
if [[ -n "${PERMISSION_HYGIENE_SCAN_ROOT:-}" ]]; then
  ROOT="$PERMISSION_HYGIENE_SCAN_ROOT"
  ROOT_SOURCE="\$PERMISSION_HYGIENE_SCAN_ROOT"
elif [[ -n "${PERMISSION_HYGIENE_FIXTURE_DIR:-}" ]]; then
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

START_DIR=""
MAIN_ROOT=""
if [[ "$ROOT_SOURCE" == "git toplevel" ]]; then
  root_real="$(cd "$ROOT" && pwd -P)"
  start_real="$(pwd -P)"
  [[ "$start_real" == "$root_real" ]] || START_DIR="$start_real"
  common_dir="$(git rev-parse --path-format=absolute --git-common-dir 2>/dev/null | tr -d '\r')"
  if [[ "${common_dir##*/}" == .git && -d "${common_dir%/*}" ]]; then
    main_real="$(cd "${common_dir%/*}" && pwd -P)"
    [[ "$main_real" == "$root_real" ]] || MAIN_ROOT="$main_real"
  fi
fi

PATTERNS_LIB="$PLUGIN_ROOT/lib/permission-patterns.sh"
if [[ ! -r "$PATTERNS_LIB" ]]; then
  echo "ERROR: cannot read $PATTERNS_LIB — the plugin's shared permission-pattern library is missing" >&2
  exit 2
fi
# shellcheck source=../../../lib/permission-patterns.sh
source "$PATTERNS_LIB"

_sl='/'
# shellcheck disable=SC1003  # _bs is a literal single backslash, not an escape
_bs='\'
_seg="[^${_sl}${_bs}*<>\${}~ ]"
_p2_path="${_sl}Users${_sl}${_seg}|${_sl}home${_sl}${_seg}|[A-Za-z]:[${_sl}${_bs}]Users[${_sl}${_bs}]${_seg}"
P2_RULE_ERE="[A-Za-z_][A-Za-z0-9_]*\\(${CCPERM_BALANCED_ERE}(${_p2_path})${CCPERM_BALANCED_ERE}\\)"
P2_TILDE_USER_RULE_ERE='Bash\((~[^/[:space:]~]+/|[[:space:]]+~[^/[:space:]~]+/)[^)]*\)'

# Inert tokens inside Bash(...) only — not Read/Edit or other tools.
# shellcheck disable=SC2016  # single quotes deliberate: \$ and % are literal ERE, not shell expansion
P4_INERT_TOKEN_ERE='%USERPROFILE%|\$env:USERPROFILE'
P4_BASH_INERT_ERE="Bash\\(${CCPERM_BALANCED_ERE}(${P4_INERT_TOKEN_ERE})${CCPERM_BALANCED_ERE}\\)"

# The ${CLAUDE_*} tokens below are literal rule text, not shell expansions.
# shellcheck disable=SC2016
P4_PLUGIN_ONLY_TOKEN_ERE='\$\{CLAUDE_PLUGIN_ROOT\}|\$\{CLAUDE_PLUGIN_DATA\}'
P4_BASH_PLUGIN_ONLY_ERE="Bash\\(${CCPERM_BALANCED_ERE}(${P4_PLUGIN_ONLY_TOKEN_ERE})${CCPERM_BALANCED_ERE}\\)"

findings=()
error_findings=0
warning_findings=0

fm_candidates=0
fm_excluded_non_loadable=0
fm_unreadable=0
fm_no_block=0
fm_with_block=0
allow_rules_read=0
scopes_read=0
unparsable_settings=0
plugin_manifests=0
plugin_settings_parsed=0
plugin_settings_unparsable=0
scope_status=()

WALK_ERR="$(mktemp)"
trap 'rm -f "$WALK_ERR"' EXIT

emit() {
  case "$1" in
  error) error_findings=$((error_findings + 1)) ;;
  warning) warning_findings=$((warning_findings + 1)) ;;
  *)
    printf 'DENOMINATOR BUG: emit() called with unknown severity %s for check %s — this is a defect in permission-rule-check.sh; the finding is reported but cannot be gated.\n' "$1" "$2" >&2
    ;;
  esac
  findings+=("$1 [$2] $3: $4")
}

inert_grant_remedy() {
  local file="$1"
  case "$file" in
  */skills/*/SKILL.md)
    printf '%s' "replace with \${CLAUDE_SKILL_DIR} for a script bundled in this skill (substituted in allowed-tools Bash rules per the skills page — as is \${CLAUDE_PLUGIN_ROOT}, but only when the skill ships inside a plugin)"
    ;;
  *)
    printf '%s' "relocate the helper to a stable bare command on PATH and allow that name narrowly — do not prescribe plugin bin/ (see permission-rule-hygiene convention known gap)"
    ;;
  esac
}

portable_path_remedy() {
  local file="$1"
  case "$file" in
  */skills/*/SKILL.md)
    printf '%s' "Portable forms: \${CLAUDE_SKILL_DIR} for this skill's own bundled script (substituted in allowed-tools Bash rules), a bare-name command on PATH, or the ~/ home anchor for Read/Edit rules."
    ;;
  *)
    printf '%s' "Portable forms: a bare-name command on PATH, or the ~/ home anchor for Read/Edit rules."
    ;;
  esac
}

is_plugin_skill() {
  local file="$1" rel="${1#"$ROOT"/}" plugin_dir
  [[ -n "$file" ]] || return 1
  case "$file" in
  */skills/*/SKILL.md) ;;
  *) return 1 ;;
  esac
  plugin_dir="${file%/skills/*/SKILL.md}"
  [[ -f "$plugin_dir/.claude-plugin/plugin.json" ]] && return 0
  [[ "$rel" =~ ^plugins/[^/]+/skills/[^/]+/SKILL\.md$ ]] && return 0
  return 1
}

rule_matches() {
  printf '%s\n' "$1" | grep -oE "$2" 2>/dev/null | sort -u
}

scan_rule() {
  local text="$1" src="$2" file="${3:-}" m remedy path_remedy
  path_remedy="$(portable_path_remedy "$file")"
  remedy="$(inert_grant_remedy "$file")"
  while IFS= read -r m; do
    [[ -n "$m" ]] && emit warning P1 "$src" "'$m' is a broad interpreter-, runner- or wildcard-led grant, not the portable bare-name pattern; Claude Code drops the broad forms of this shape (blanket, package-manager runners, wildcarded/globbed-target interpreters, wrapper-only and leading wildcards, and \$HOME or Windows backslash wildcarded paths) on entering auto mode. Expose the guarded script as a bare PATH command and allow that, e.g. Bash(babysit_merge.sh:*)."
  done < <(rule_matches "$text" "$CCPERM_P1_ERE")
  while IFS= read -r m; do
    [[ -n "$m" ]] && emit error P2 "$src" "hardcoded machine path in '$m' — the rule names a concrete user home, so it breaks on other machines and usernames and leaks a username into source control. $path_remedy"
  done < <(rule_matches "$text" "$P2_RULE_ERE")
  while IFS= read -r m; do
    [[ -n "$m" ]] && emit error P2b "$src" "tilde-user path in '$m' — Bash rules match literally and do not expand ~username forms, so the rule names a specific account, leaks a username into version control, and breaks on other machines. $path_remedy"
  done < <(rule_matches "$text" "$P2_TILDE_USER_RULE_ERE")
  while IFS= read -r m; do
    [[ -n "$m" ]] && emit error P4 "$src" "inert substitution token in '$m' — the grant never matches at runtime. Remedy: $remedy."
  done < <(rule_matches "$text" "$P4_BASH_INERT_ERE")
  if ! is_plugin_skill "$file"; then
    while IFS= read -r m; do
      [[ -n "$m" ]] && emit error P4 "$src" "plugin-scoped substitution token in '$m' outside a plugin skill — \${CLAUDE_PLUGIN_ROOT} and \${CLAUDE_PLUGIN_DATA} are substituted only in plugin skills, so here the rule stays a literal string and never matches. Remedy: $remedy."
    done < <(rule_matches "$text" "$P4_BASH_PLUGIN_ONLY_ERE")
  fi
}

top_level_tokens() {
  printf '%s\n' "$1" | grep -oE "$CCPERM_TOOL_TOKEN_ERE" 2>/dev/null
}

scan_malformed_rule() {
  local text="$1" src="$2" rest tok
  rest="${text#"${text%%[![:space:]]*}"}"
  [[ -n "$rest" ]] || return 0
  tok="$(printf '%s\n' "$rest" | grep -oE "^${CCPERM_TOOL_TOKEN_ERE}" 2>/dev/null | head -n 1 || true)"
  if [[ -z "$tok" ]]; then
    emit error P5 "$src" "malformed Tool(content) rule '$text' — it is not Tool or Tool(specifier). Claude Code reports this shape as invalid settings."
    return 0
  fi
  rest="${rest#"$tok"}"
  rest="${rest#"${rest%%[![:space:]]*}"}"
  if [[ -n "$rest" ]]; then
    emit error P5 "$src" "malformed Tool(content) rule '$text' — text after the closing parenthesis is not part of a rule. Claude Code reports this shape (for example Bash(ls) x) as invalid settings instead of ignoring it."
  fi
}

scan_bare_tool() {
  local tool tokens
  tokens=$'\n'"$(top_level_tokens "$1")"$'\n'
  for tool in Bash PowerShell; do
    if [[ "$tokens" == *$'\n'"$tool"$'\n'* ]]; then
      emit warning P1 "$2" "bare '$tool' allow rule grants the whole tool and is dropped in auto mode. Allow a specific bare-name command instead, e.g. Bash(babysit_merge.sh:*)."
    fi
  done
}

scan_agent() {
  local tokens
  tokens=$'\n'"$(top_level_tokens "$1")"$'\n'
  if [[ "$tokens" == *$'\n'Agent$'\n'* || "$tokens" == *$'\n'Agent\(* ]]; then
    emit warning P1 "$2" "Agent allow rules are dropped in auto mode and have no PATH-durable analog — remove/re-scope, or run outside auto mode."
  fi
}

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

if [[ -n "${CLAUDE_CONFIG_DIR:-}" ]]; then
  USER_CONFIG_ROOT="$CLAUDE_CONFIG_DIR"
elif [[ -n "${HOME:-}" ]]; then
  USER_CONFIG_ROOT="$HOME/.claude"
else
  USER_CONFIG_ROOT=""
fi
USER_PLUGINS_REAL=""
[[ -n "$USER_CONFIG_ROOT" && -d "$USER_CONFIG_ROOT/plugins" ]] &&
  USER_PLUGINS_REAL="$(cd "$USER_CONFIG_ROOT/plugins" && pwd -P)"
ROOT_REAL="$(cd "$ROOT" && pwd -P)"
under_user_plugins() {
  [[ -n "$USER_PLUGINS_REAL" && "$ROOT_REAL/$1" == "$USER_PLUGINS_REAL"/* ]]
}
plugin_root_has_manifest() {
  [[ -f "$ROOT${1:+/$1}/.claude-plugin/plugin.json" ]]
}
frontmatter_is_loadable() {
  local file="$1" rel="${1#"$ROOT"/}"
  case "$file" in
  */SKILL.md)
    if [[ "$rel" =~ (^|/)\.claude/skills/[^/]+/SKILL\.md$ ]]; then
      [[ "$rel" == .claude/skills/* ]] && return 0
      under_user_plugins "$rel" && return 1
      return 0
    fi
    [[ "$rel" =~ ^plugins/[^/]+/skills/[^/]+/SKILL\.md$ ]] && return 0
    if [[ "$rel" =~ ^(.+/)?skills/[^/]+/SKILL\.md$ ]]; then
      plugin_root_has_manifest "${BASH_REMATCH[1]%/}" && return 0
    fi
    return 1
    ;;
  *)
    [[ "$rel" =~ (^|/)\.claude/agents/[^/]+\.md$ ]] && return 0
    [[ "$rel" =~ (^|/)\.claude/commands/[^/]+\.md$ ]] && return 0
    [[ "$rel" =~ ^plugins/[^/]+/agents/[^/]+\.md$ ]] && return 0
    [[ "$rel" =~ ^plugins/[^/]+/commands/[^/]+\.md$ ]] && return 0
    if [[ "$rel" =~ ^(.+/)?(agents|commands)/[^/]+\.md$ ]]; then
      plugin_root_has_manifest "${BASH_REMATCH[1]%/}" && return 0
    fi
    return 1
    ;;
  esac
}
while IFS= read -r file; do
  [[ -n "$file" ]] || continue
  fm_candidates=$((fm_candidates + 1))
  if ! frontmatter_is_loadable "$file"; then
    fm_excluded_non_loadable=$((fm_excluded_non_loadable + 1))
    continue
  fi
  if [[ ! -f "$file" || ! -r "$file" ]]; then
    fm_unreadable=$((fm_unreadable + 1))
    continue
  fi
  at="$(extract_allowed_tools "$file" 2>>"$WALK_ERR")"
  if [[ -z "${at//[[:space:]]/}" ]]; then
    fm_no_block=$((fm_no_block + 1))
    continue
  fi
  fm_with_block=$((fm_with_block + 1))
  rel="${file#"$ROOT"/}"
  scan_rule "$at" "$rel allowed-tools" "$file"
  scan_bare_tool "$at" "$rel allowed-tools"
  scan_agent "$at" "$rel allowed-tools"
done < <(
  find "$ROOT" -type f \( \
    -name 'SKILL.md' \
    -o \( -name '*.md' -path '*/agents/*' \) \
    -o \( -name '*.md' -path '*/commands/*' \) \
    \) 2>>"$WALK_ERR" | sort -u
)

scan_settings_allow() {
  local file="$1" label="$2" short="$3" rule n=0
  if [[ ! -f "$file" ]]; then
    scope_status+=("$short: absent")
    return 0
  fi
  if ! tr -d '\r' <"$file" | jq -e . >/dev/null 2>&1; then
    scope_status+=("$short: NOT VALID JSON — its rules were not read. An interactive session shows a Settings Error for a user, project, or local file; after continue, /status names the file. A -p run skips the broken file. A managed settings file, drop-in, MDM plist, or HKLM value that cannot be parsed refuses startup instead (exit 1, source named, v2.1.259+).")
    unparsable_settings=$((unparsable_settings + 1))
    return 0
  fi
  while IFS= read -r rule; do
    [[ -n "$rule" ]] || continue
    n=$((n + 1))
    scan_malformed_rule "$rule" "$label"
    scan_bare_tool "$rule" "$label"
    scan_agent "$rule" "$label"
    scan_rule "$rule" "$label" ""
  done < <(tr -d '\r' <"$file" | jq -r '.permissions.allow // [] | .[]' 2>/dev/null | tr -d '\r')
  allow_rules_read=$((allow_rules_read + n))
  scopes_read=$((scopes_read + 1))
  scope_status+=("$short: $n rule(s)")
}

scan_settings_allow "$ROOT/.claude/settings.json" ".claude/settings.json permissions.allow" "project"
if [[ -n "$START_DIR" ]]; then
  start_rel="${START_DIR#"$root_real"/}"
  scan_settings_allow "$START_DIR/.claude/settings.json" "$start_rel/.claude/settings.json permissions.allow" \
    "project (start directory $start_rel)"
fi
scan_settings_allow "$ROOT/.claude/settings.local.json" ".claude/settings.local.json permissions.allow" "local"
if [[ -n "$MAIN_ROOT" ]]; then
  scan_settings_allow "$MAIN_ROOT/.claude/settings.local.json" "$MAIN_ROOT/.claude/settings.local.json permissions.allow" \
    "local (main checkout $MAIN_ROOT)"
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
  scope_status+=("user-global: NOT RESOLVED (neither CLAUDE_CONFIG_DIR nor HOME is set)")
  echo "NOTE: user-global scope not scanned — neither CLAUDE_CONFIG_DIR nor HOME is set, so ~/.claude could not be resolved." >&2
fi

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
    emit warning P3 "$rel" "plugin settings.json declares 'permissions' — a plugin's settings.json takes effect only for the deprecated agent key (Claude Code 2.1.323 removed subagentStatusLine), so this grant is ignored. The operative allow-rule must be added by the operator to ~/.claude/settings.json."
  fi
done < <(find "$ROOT" -type f -path '*/.claude-plugin/plugin.json' 2>>"$WALK_ERR" | sort -u)

walk_errors="$(awk 'NF{n++} END{print n+0}' "$WALK_ERR" 2>/dev/null)"
[[ -n "$walk_errors" ]] || walk_errors=0

fm_examined=$((fm_no_block + fm_with_block))
audited=$((fm_examined + scopes_read + plugin_settings_parsed))

blocked=$((fm_unreadable + unparsable_settings + plugin_settings_unparsable + walk_errors))

reconcile_frontmatter() {
  local sum=$((fm_excluded_non_loadable + fm_unreadable + fm_no_block + fm_with_block))
  if [[ "$sum" -ne "$fm_candidates" ]]; then
    printf '  DENOMINATOR BUG: %d candidate(s) enumerated but %d accounted for (non-loadable=%d unreadable=%d no-block=%d parsed=%d). A candidate escaped every bucket: this is a defect in permission-rule-check.sh, not a property of the scanned tree, and the coverage above is incomplete. Do not report this run as clean.\n' \
      "$fm_candidates" "$sum" "$fm_excluded_non_loadable" "$fm_unreadable" "$fm_no_block" "$fm_with_block"
    return 1
  fi
  printf '  reconciled: %d candidate(s) = %d non-loadable-excluded + %d unreadable + %d without an allowed-tools block + %d parsed\n' \
    "$fm_candidates" "$fm_excluded_non_loadable" "$fm_unreadable" "$fm_no_block" "$fm_with_block"
  return 0
}

coverage_block() {
  local joined="(no settings scope was attempted)"
  if [[ "${#scope_status[@]}" -gt 0 ]]; then
    joined="$(printf '%s; ' "${scope_status[@]}")"
    joined="${joined%; }"
  fi
  printf '\nScan coverage (the denominator — what this run actually read):\n'
  printf '  root: %s (resolved from %s)\n' "$ROOT" "$ROOT_SOURCE"
  printf '  DENOMINATOR = %d input(s) successfully examined: %d frontmatter file(s) + %d settings scope(s) + %d plugin settings.json. The unit on every axis is "read and examined", never "produced a finding".\n' \
    "$audited" "$fm_examined" "$scopes_read" "$plugin_settings_parsed"
  printf '  frontmatter: %d allowed-tools block(s) parsed from %d candidate file(s); %d excluded as non-loadable (not at a documented skills/agents/commands path)\n' \
    "$fm_with_block" "$fm_candidates" "$fm_excluded_non_loadable"
  reconcile_frontmatter
  printf '  settings: %d allow rule(s) from %d scope(s) read — %s\n' \
    "$allow_rules_read" "$scopes_read" "$joined"
  printf '  plugins: %d manifest(s); %d settings.json parsed\n' \
    "$plugin_manifests" "$plugin_settings_parsed"
  printf '  NOT read: %d frontmatter candidate(s) enumerated but unopenable; %d error line(s) from the walk/extraction; %d settings file(s) and %d plugin settings.json present but not valid JSON\n' \
    "$fm_unreadable" "$walk_errors" "$unparsable_settings" "$plugin_settings_unparsable"
  printf '  never in scope here: managed-policy and enterprise settings, a --settings flag file, and the pre-v2.1.211 start-directory copy. Which scopes exist and what each holds is audit-permission-state, not this detector.\n'
  printf '  consumer declarations: NOT READ by this detector, ever — so this line is not the answer to "were any exemptions applied?". The skill body owns that question and requires every declaration it reads to be named in the report.\n'
}

if [[ "$mode" == "count" ]]; then
  printf '%s\n' "${#findings[@]}"
  coverage_block >&2
  exit 0
fi

if [[ "${#findings[@]}" -eq 0 ]]; then
  if [[ "$audited" -eq 0 ]]; then
    if [[ "$blocked" -gt 0 ]]; then
      printf 'NOTHING TO AUDIT, AND %d INPUT(S) COULD NOT BE READ: nothing was successfully examined on any of the three axes, and the run failed to open or parse %d of its own inputs. This is neither a clean bill nor an empty tree — it is a scan whose inputs were unavailable. See the coverage block below.\n' "$blocked" "$blocked"
    else
      echo "NOTHING TO AUDIT: 0 frontmatter file(s), 0 settings scope(s) and 0 plugin settings.json were successfully read under this root, so this run has no denominator on any of the three axes. That is a scan of nothing, not a clean bill — do not report it as one. See the coverage block below for what was and was not read."
    fi
  elif [[ "$blocked" -gt 0 ]]; then
    printf 'INCOMPLETE SCAN, NOT A CLEAN BILL: no fragile permission grants were found in the %d input(s) this run successfully examined, but %d input(s) could not be read or parsed and were NOT audited. A fragile grant inside an input the run could not open is precisely what it could not see, so this is not a statement about the grants in this tree. See the coverage block below for which inputs were not read.\n' \
      "$audited" "$blocked"
  elif [[ "$fm_candidates" -gt 0 && "$fm_excluded_non_loadable" -eq "$fm_candidates" ]]; then
    printf 'NO FRONTMATTER AUDITED, NOT A CLEAN BILL: all %d frontmatter candidate(s) under this root were excluded as non-loadable, so no skill, agent or command allowed-tools block was parsed. The %d settings input(s) this run examined hold no fragile grant, but that says nothing about frontmatter it never read. A plugin directory loads here when it sits at plugins/<name>/ or holds .claude-plugin/plugin.json. See the coverage block below.\n' \
      "$fm_candidates" "$audited"
  else
    echo "No fragile permission grants found."
  fi
else
  printf '%s\n' "${findings[@]}"
fi
coverage_block

case "$mode" in
check | strict)
  if [[ "$audited" -eq 0 ]]; then
    exit 2
  fi
  if [[ "$error_findings" -gt 0 ]]; then
    exit 1
  fi
  if [[ "$mode" == "strict" && "$warning_findings" -gt 0 ]]; then
    exit 1
  fi
  if [[ "$blocked" -gt 0 ]]; then
    exit 2
  fi
  ;;
*) ;;
esac
exit 0
