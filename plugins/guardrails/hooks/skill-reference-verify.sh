#!/usr/bin/env bash
# PostToolUse hook: verify `/<plugin>:<skill>` references written to markdown
# resolve to a skill that exists in the working tree.
# Triggered on Write|Edit of *.md files.
#
# Catches subagent / training-recall hallucinations — a slash-command reference
# written AS a capability that does not exist, or one left behind by a rename.
# Sibling of cli-flag-verify and asserted-path-verify: same defect class, third
# oracle.
#
# ENFORCEABILITY TIER: Detect-then-judge — ADVISORY PLUS A HUMAN VERDICT, never
# an auto-fix. Globbing a plugins tree is exact only inside a marketplace repo
# that owns the referenced plugin. In a consuming repo the reference may name a
# plugin from another marketplace, or one the operator has simply not installed,
# and this hook cannot distinguish that from a hallucination. Per the org
# convention on enforceability tiers, that means the finding is a prompt for a
# human decision, not a determination. The plugins-root gate below is what keeps
# the noise inside the one context where the oracle is meaningful.
#
# PLUGINS-ROOT GATE: the hook does nothing unless the file being written lives in
# a repo with a `plugins/` directory containing at least one `.claude-plugin/`
# manifest — i.e. a marketplace repo. Outside one there is no local authority to
# resolve a reference against, so the guard stays silent rather than guessing.
#
# PLUGIN-SCOPE GATE: within a marketplace repo, a reference is only adjudicated
# when its PLUGIN half resolves locally. `/some-other-marketplace:thing` is left
# alone; `/guardrails:nonexistent` is reported, because this repo owns
# `guardrails` and can therefore say the skill is not there.
#
# NON-BLOCKING (advisory): exits 0 with hookSpecificOutput additionalContext.
#
# Disable with the skill_reference_verify_enabled userConfig option set to false.

set -uo pipefail

# High-res start stamp for telemetry (Bash 5.0+; empty on older bash → skip).
start=${EPOCHREALTIME:-}

# shellcheck source=hook-utils.sh
source "$(dirname "${BASH_SOURCE[0]}")/hook-utils.sh"

hook::check_enabled "SKILL_REFERENCE_VERIFY"

hook::ctx_reset

INPUT=$(hook::buffer_stdin) || exit 0

hook::require_jq "PostToolUse" "guardrails-skill-reference-verify" "$INPUT"

FILE=$(printf '%s' "$INPUT" | hook::read_file_path) || exit 0
case "$FILE" in
*.md) ;;
*) exit 0 ;;
esac

# Diff-scope: verify only the content THIS tool call wrote, never re-read the
# whole file from disk.
TOOL=$(printf '%s' "$INPUT" | jq -r '.tool_name // empty' 2>/dev/null | tr -d '\r')
case "$TOOL" in
Edit) SCAN_CONTENT=$(printf '%s' "$INPUT" | jq -r '.tool_input.new_string // empty' 2>/dev/null | tr -d '\r') ;;
Write) SCAN_CONTENT=$(printf '%s' "$INPUT" | jq -r '.tool_input.content // empty' 2>/dev/null | tr -d '\r') ;;
*) exit 0 ;;
esac
[[ -n "$SCAN_CONTENT" ]] || exit 0

REPO_ROOT="$(hook::repo_root "$(dirname "$FILE")")"
PLUGINS_DIR="$REPO_ROOT/plugins"

# PLUGINS-ROOT GATE. Outside a marketplace repo there is no local authority.
[[ -d "$PLUGINS_DIR" ]] || exit 0
shopt -s nullglob
manifests=("$PLUGINS_DIR"/*/.claude-plugin/plugin.json)
shopt -u nullglob
((${#manifests[@]} > 0)) || exit 0

# A plugin's command namespace is its manifest `name`, which need not equal its
# directory name. Build the name → directory map from the manifests themselves so
# a renamed directory or a name override resolves correctly.
declare -A PLUGIN_DIR=()
for m in "${manifests[@]}"; do
  pdir="${m%/.claude-plugin/plugin.json}"
  pname=$(jq -r '.name // empty' "$m" 2>/dev/null | tr -d '\r')
  [[ -n "$pname" ]] || pname="${pdir##*/}"
  PLUGIN_DIR["$pname"]="$pdir"
done

# A plugin skill's command segment comes from its frontmatter `name` when set,
# and from the directory name otherwise. Resolve a (plugin, skill) pair against
# both so a skill whose directory and command name diverge still resolves.
skill_resolves() {
  local pdir="$1" skill="$2" sd fname
  [[ -d "$pdir/skills/$skill" ]] && return 0
  for sd in "$pdir"/skills/*/SKILL.md; do
    [[ -f "$sd" ]] || continue
    # Frontmatter `name:`, unquoted or quoted, first occurrence only.
    fname=$(sed -n '1,40{s/^name:[[:space:]]*["'\'']\{0,1\}\([A-Za-z0-9_-]\{1,\}\)["'\'']\{0,1\}[[:space:]]*$/\1/p;}' "$sd" 2>/dev/null | head -1)
    [[ "$fname" == "$skill" ]] && return 0
  done
  return 1
}

# Candidate references: `/<plugin>:<skill>` inside inline-code spans only. Prose
# is not scanned — an unbackticked `/a:b` is as likely to be a URL fragment, a
# Windows drive path, or a time range as a command.
emit_refs() {
  # shellcheck disable=SC2016  # backticks are literal ERE data, not expansions
  printf '%s' "$SCAN_CONTENT" | grep -oE '`/[a-z][a-z0-9-]*:[a-z][a-z0-9-]*`' 2>/dev/null |
    tr -d '`'
}

declare -A CHECKED=()
UNRESOLVED=()

while IFS= read -r ref; do
  [[ -n "$ref" ]] || continue
  [[ -n "${CHECKED[$ref]:-}" ]] && continue
  CHECKED["$ref"]=1
  plugin="${ref#/}"
  plugin="${plugin%%:*}"
  skill="${ref##*:}"
  # PLUGIN-SCOPE GATE: only adjudicate a plugin this repo owns.
  pdir="${PLUGIN_DIR[$plugin]:-}"
  [[ -n "$pdir" ]] || continue
  skill_resolves "$pdir" "$skill" && continue
  UNRESOLVED+=("$ref")
done < <(emit_refs)

emit_tel() {
  [[ -n "$start" ]] || return 0
  hook::telemetry_enabled || return 0
  local file_rel="$FILE" findings_json="[]"
  if command -v cygpath >/dev/null 2>&1; then
    local _file_lm _root_lm
    _file_lm=$(cygpath -lm "$FILE" 2>/dev/null)
    _root_lm=$(cygpath -lm "$REPO_ROOT" 2>/dev/null)
    [[ -n "$_file_lm" && -n "$_root_lm" ]] && file_rel="${_file_lm#"$_root_lm"/}"
  else
    file_rel="${FILE#"$REPO_ROOT"/}"
  fi
  # Redaction: a path that could not be made repo-relative degrades to its
  # basename — never an absolute path, which would embed the developer's
  # username.
  case "$file_rel" in
  /* | [A-Za-z]:*)
    file_rel="${file_rel##*/}"
    file_rel="${file_rel##*\\}"
    ;;
  *) ;;
  esac
  if ((${#UNRESOLVED[@]} > 0)); then
    local r raw_list=""
    for r in "${UNRESOLVED[@]}"; do raw_list+="$r"$'\n'; done
    findings_json=$(printf '%s' "$raw_list" | jq -R . | jq -s . 2>/dev/null) || findings_json="[]"
  fi
  local data
  data=$(jq -n --arg file "$file_rel" --argjson findings "$findings_json" \
    '{tool:"",file:$file,findings:$findings}' 2>/dev/null) ||
    data='{"tool":"","file":"","findings":[]}'
  hook::emit_telemetry "skill-reference-verify" "PostToolUse" "ok" "$start" "$data" "$REPO_ROOT"
}

if ((${#UNRESOLVED[@]} > 0)); then
  hook::ctx_append "skill-reference-verify: ${#UNRESOLVED[@]} skill reference(s) do not resolve in $FILE"
  hook::ctx_append "This repo owns each plugin named below, so it can say the skill is not there:"
  for r in "${UNRESOLVED[@]}"; do
    plugin="${r#/}"
    plugin="${plugin%%:*}"
    hook::ctx_append "  UNRESOLVED_SKILL: $r (no such skill under plugins/${PLUGIN_DIR[$plugin]##*/}/skills/)"
  done
  hook::ctx_append ""
  hook::ctx_append "Detect-then-judge: this is a prompt for your verdict, not a determination."
  hook::ctx_append "Confirm against the tree. A reference retained deliberately — documenting"
  hook::ctx_append "a rename, or a capability another marketplace ships — is correct as written."
  hook::ctx_flush PostToolUse
fi

emit_tel
exit 0
