#!/usr/bin/env bash
# This script is a candidate enumerator, not a violation adjudicator. Exit 1
# means candidates exist after mechanical filters — not that those hits are
# illegal. Classify via the skill's filter taxonomy before treating any hit as
# a violation. Do not hard-gate CI on this exit code alone.
# Exit: 0 no candidates, 1 candidates exist, 2 environment error.
set -euo pipefail

REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null | tr -d '\r' || pwd)"
cd "$REPO_ROOT"

INCLUDE_SKILLS=0
APPLY_FILTERS=0
ALLOWLIST_FILE="docs/conventions/audit-encapsulation-allowlist.tsv"
while [[ $# -gt 0 ]]; do
  arg="$1"
  shift
  case "$arg" in
  --include-skills) INCLUDE_SKILLS=1 ;;
  --apply-filters) APPLY_FILTERS=1 ;;
  --allowlist)
    if [[ $# -eq 0 ]]; then
      echo "audit-encapsulation/detect: --allowlist needs a file" >&2
      exit 2
    fi
    ALLOWLIST_FILE="$1"
    shift
    ;;
  --help | -h)
    cat <<'USAGE'
Usage: audit-encapsulation detect [--include-skills] [--apply-filters] [--allowlist <file>]

Enumerate candidate citations into private skill internals.
Output TSV: file, line, match-text.
Exit: 0 no candidates, 1 candidates exist, 2 environment error.

Exit 1 means candidates remain after mechanical filters — not adjudicated
violations. Classify via the skill filter taxonomy before gating. Do not
hard-gate CI on this exit code alone.

Matched path prefixes: .claude/skills/<X>/..., plugins/<plugin>/skills/<X>/...,
and relative forms (skills/<X>/... plugin-README short cites, plus ../-prefixed
cites whose lexical resolution lands on a private skill surface). Every text
file type under the scanned surfaces is read.

In a marketplace monorepo (plugins/ present), a file under plugins/<q>/ that
cites another plugin's skill folder is flagged for the skill root, a bare
SKILL.md, and the scripts/ entry surface, whether spelled as a path, a ../ path
or a github.com tree/blob or raw.githubusercontent.com URL. A cite inside the
same plugin stays legal. When .claude-plugin/marketplace.json names the
marketplace, <plugin>@<marketplace-id> outside an install recipe line is flagged.

  --include-skills    Include .claude/skills/ in scope (intra-skill self-citation review)
  --apply-filters     Drop self-citation and worktree path hits (mechanical filters only)
  --allowlist <file>  Rows of `path<TAB>reason` (path or dir/ prefix) the scan skips;
                      default docs/conventions/audit-encapsulation-allowlist.tsv
USAGE
    exit 0
    ;;
  *)
    echo "audit-encapsulation/detect: unknown arg '$arg'" >&2
    exit 2
    ;;
  esac
done

ALLOW_PATHS=()
if [[ -f "$ALLOWLIST_FILE" ]]; then
  allow_n=0
  while IFS= read -r allow_line || [[ -n "$allow_line" ]]; do
    allow_n=$((allow_n + 1))
    allow_line="${allow_line%$'\r'}"
    [[ -z "${allow_line//[[:space:]]/}" || "$allow_line" == '#'* ]] && continue
    allow_path="${allow_line%%$'\t'*}"
    allow_reason=""
    [[ "$allow_line" == *$'\t'* ]] && allow_reason="${allow_line#*$'\t'}"
    if [[ -z "$allow_path" || -z "${allow_reason//[[:space:]]/}" ]]; then
      echo "audit-encapsulation/detect: $ALLOWLIST_FILE:$allow_n needs a path and a reason, tab-separated" >&2
      exit 2
    fi
    ALLOW_PATHS+=("$allow_path")
  done <"$ALLOWLIST_FILE"
elif [[ "$ALLOWLIST_FILE" != "docs/conventions/audit-encapsulation-allowlist.tsv" ]]; then
  echo "audit-encapsulation/detect: allowlist '$ALLOWLIST_FILE' not found" >&2
  exit 2
fi

is_allowlisted() {
  local file="$1" p
  for p in ${ALLOW_PATHS[@]+"${ALLOW_PATHS[@]}"}; do
    if [[ "$p" == */ ]]; then
      [[ "$file" == "$p"* ]] && return 0
    else
      [[ "$file" == "$p" ]] && return 0
    fi
  done
  return 1
}

SCOPE_DIRS=()
for d in .claude/*/; do
  d="${d%/}"
  [[ -d "$d" ]] || continue
  [[ "$d" == ".claude/worktrees" ]] && continue
  [[ "$d" == ".claude/skills" && "$INCLUDE_SKILLS" -eq 0 ]] && continue
  SCOPE_DIRS+=("$d")
done
for d in .github docs .lefthook plugins; do
  [[ -d "$d" ]] && SCOPE_DIRS+=("$d")
done

SCOPE_FILES=()
for f in AGENTS.md CLAUDE.md README.md CONTRIBUTING.md lefthook.yml \
  .claude/*.md .claude/*.json .claude/*.yml .claude/*.yaml; do
  [[ -f "$f" ]] && SCOPE_FILES+=("$f")
done

if [[ ${#SCOPE_DIRS[@]} -eq 0 && ${#SCOPE_FILES[@]} -eq 0 ]]; then
  echo "audit-encapsulation: no in-scope dirs or files present" >&2
  exit 2
fi

PATTERN='\.claude/skills/[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+/|\.claude/skills/[A-Za-z0-9_.-]+/SKILL\.md#|\.claude/skills/[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+\.schema\.json|plugins/[A-Za-z0-9_.-]+/skills/[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+/|plugins/[A-Za-z0-9_.-]+/skills/[A-Za-z0-9_.-]+/SKILL\.md#|plugins/[A-Za-z0-9_.-]+/skills/[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+\.schema\.json|skills/[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+/|skills/[A-Za-z0-9_.-]+/SKILL\.md#|skills/[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+\.schema\.json'

SCRIPTS_RE='^(\.claude/skills/[A-Za-z0-9_.-]+/scripts/|plugins/[A-Za-z0-9_.-]+/skills/[A-Za-z0-9_.-]+/scripts/|skills/[A-Za-z0-9_.-]+/scripts/)'

lex_resolve() {
  local raw="$1" seg
  [[ "$raw" == /* ]] && return 1
  local -a out=()
  while IFS= read -r seg; do
    case "$seg" in
    '' | '.') continue ;;
    '..')
      ((${#out[@]})) || return 1
      out=("${out[@]:0:${#out[@]}-1}")
      ;;
    *) out+=("$seg") ;;
    esac
  done < <(printf '%s\n' "${raw//\//$'\n'}")
  local joined="" part
  for part in ${out[@]+"${out[@]}"}; do
    joined="${joined:+$joined/}$part"
  done
  printf '%s' "$joined"
}

is_private_skill_path() {
  local p="$1"
  [[ "$p" =~ ^(\.claude/skills/|plugins/[^/]+/skills/)[A-Za-z0-9_.-]+/scripts(/|$) ]] && return 1
  [[ "$p" =~ ^(\.claude/skills/|plugins/[^/]+/skills/)[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+(/|$) ]] && return 0
  [[ "$p" =~ ^(\.claude/skills/|plugins/[^/]+/skills/)[A-Za-z0-9_.-]+/SKILL\.md# ]] && return 0
  [[ "$p" =~ ^(\.claude/skills/|plugins/[^/]+/skills/)[A-Za-z0-9_.-]+/[^/]+\.schema\.json ]] && return 0
  return 1
}

recover_dotdot_prefix() {
  local file="$1" line_no="$2" text="$3" src before
  src="$(sed -n "${line_no}p" "$file" 2>/dev/null || true)"
  [[ -n "$src" && "$src" == *"$text"* ]] || return 1
  before="${src%%"$text"*}"
  if [[ "$before" =~ ((\.\./)+([A-Za-z0-9_.-]+/)*)$ ]]; then
    printf '%s%s' "${BASH_REMATCH[1]}" "$text"
    return 0
  fi
  return 1
}

resolves_into_self() {
  local file="$1" line_no="$2" text="$3" self_root="$4"
  local full resolved
  if [[ "$text" == ../* ]]; then
    full="$text"
  else
    # shellcheck disable=SC2310  # recover miss → bare same-root short cite
    full="$(recover_dotdot_prefix "$file" "$line_no" "$text")" || return 0
  fi
  # shellcheck disable=SC2310  # lex_resolve miss → leave as candidate
  resolved="$(lex_resolve "$(dirname "$file")/$full")" || return 1
  [[ -n "$resolved" && "$resolved" == "$self_root"* ]]
}

plugin_of() {
  [[ "$1" =~ ^plugins/([^/]+)/ ]] || return 1
  printf '%s' "${BASH_REMATCH[1]}"
}

cite_target() {
  local file="$1" line_no="$2" text="$3" full
  if [[ "$text" == plugins/* ]]; then
    printf '%s' "$text"
    return 0
  fi
  if [[ "$text" == ../* ]]; then
    full="$text"
  else
    # shellcheck disable=SC2310  # recover miss → no target
    full="$(recover_dotdot_prefix "$file" "$line_no" "$text")" || return 1
  fi
  # shellcheck disable=SC2310  # lex_resolve miss → no target
  lex_resolve "$(dirname "$file")/$full" || return 1
}

is_cross_plugin_scripts() {
  local file="$1" line_no="$2" text="$3" q p target
  # shellcheck disable=SC2310  # status 1 = file outside plugins/
  q="$(plugin_of "$file")" || return 1
  # shellcheck disable=SC2310  # status 1 = unplaceable cite
  target="$(cite_target "$file" "$line_no" "$text")" || return 1
  [[ "$target" =~ ^plugins/([^/]+)/skills/ ]] || return 1
  p="${BASH_REMATCH[1]}"
  [[ "$p" != "$q" ]]
}

is_cross_plugin_surface() {
  local file="$1" line_no="$2" text="$3" q p rest target
  [[ "$text" == *'#' ]] && return 1
  # shellcheck disable=SC2310  # status 1 = file outside plugins/
  q="$(plugin_of "$file")" || return 1
  # shellcheck disable=SC2310  # status 1 = unplaceable cite
  target="$(cite_target "$file" "$line_no" "$text")" || return 1
  [[ "$target" =~ ^plugins/([^/]+)/skills/[^/]+(/.*)?$ ]] || return 1
  p="${BASH_REMATCH[1]}"
  rest="${BASH_REMATCH[2]}"
  [[ "$p" != "$q" ]] || return 1
  [[ -z "$rest" || "$rest" == "/SKILL.md" ]]
}

is_mechanically_legal() {
  local file="$1" line_no="$2" text="$3" self self_root
  if [[ "$file" =~ ^\.claude/skills/([^/]+)/ ]]; then
    self="${BASH_REMATCH[1]}"
    self_root=".claude/skills/${self}/"
    [[ "$text" == *"$self_root"* ]] && return 0
  elif [[ "$file" =~ ^(plugins/[^/]+)/skills/([^/]+)/ ]]; then
    self="${BASH_REMATCH[2]}"
    self_root="${BASH_REMATCH[1]}/skills/${self}/"
    [[ "$text" == "$self_root"* || "$text" == *"/$self_root"* ]] && return 0
  else
    [[ "$file" == *".worktrees/"* || "$text" == *".worktrees/"* ||
      "$file" == *".claude/worktrees/"* || "$text" == *".claude/worktrees/"* ||
      "$file" == *".git/worktrees/"* || "$text" == *".git/worktrees/"* ]]
    return
  fi
  [[ "$text" == "skills/${self}/"* || "$text" == ../* ]] || return 1
  resolves_into_self "$file" "$line_no" "$text" "$self_root"
}

split_hit() {
  file="${1%%:*}"
  local rest="${1#*:}"
  line_no="${rest%%:*}"
  text="${rest#*:}"
}

HITS_FILE="$(mktemp)"
trap 'rm -f "$HITS_FILE"' EXIT

scan_scope() {
  local pattern="$1"
  if [[ ${#SCOPE_DIRS[@]} -gt 0 ]]; then
    grep -ErnoI --exclude-dir=node_modules --exclude-dir=.git \
      "$pattern" "${SCOPE_DIRS[@]}" 2>/dev/null || true
  fi
  if [[ ${#SCOPE_FILES[@]} -gt 0 ]]; then
    # -H forces the file prefix even when only one file exists.
    grep -EHnoI "$pattern" "${SCOPE_FILES[@]}" 2>/dev/null || true
  fi
}

while IFS= read -r line; do
  [[ -z "$line" ]] && continue
  split_hit "$line"
  # shellcheck disable=SC2310  # pure predicate; both branches handled
  if [[ "$text" =~ $SCRIPTS_RE ]] && ! is_cross_plugin_scripts "$file" "$line_no" "$text"; then
    continue
  fi
  printf '%s\n' "$line" >>"$HITS_FILE"
done < <(scan_scope "$PATTERN")

CROSS_PATTERN='plugins/[A-Za-z0-9_.-]+/skills/[A-Za-z0-9_.-]+(/[A-Za-z0-9_.-]+)*#?|(\.\./)+([A-Za-z0-9_.-]+/)*skills/[A-Za-z0-9_.-]+(/[A-Za-z0-9_.-]+)*#?'
while IFS= read -r line; do
  [[ -z "$line" ]] && continue
  split_hit "$line"
  text="${text%"${text##*[!.]}"}"
  # shellcheck disable=SC2310  # pure predicate; both branches handled
  is_cross_plugin_surface "$file" "$line_no" "$text" || continue
  printf '%s:%s:%s\n' "$file" "$line_no" "$text" >>"$HITS_FILE"
done < <(scan_scope "$CROSS_PATTERN")

MARKETPLACE_ID=""
if [[ -f .claude-plugin/marketplace.json ]]; then
  MARKETPLACE_ID="$(sed -n 's/^[[:space:]]*"name"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' \
    .claude-plugin/marketplace.json | head -n 1 || true)"
  [[ "$MARKETPLACE_ID" =~ ^[A-Za-z0-9_.-]+$ ]] || MARKETPLACE_ID=""
fi
if [[ -n "$MARKETPLACE_ID" ]]; then
  ID_ESCAPED="${MARKETPLACE_ID//./\\.}"
  RECIPE_RE='plugin[[:space:]]+(install|uninstall|update|enable|disable)'
  while IFS= read -r line; do
    [[ -z "$line" ]] && continue
    split_hit "$line"
    [[ "$text" =~ [^A-Za-z0-9_.-]$ ]] && text="${text%?}"
    text="${text%"${text##*[!.]}"}"
    src="$(sed -n "${line_no}p" "$file" 2>/dev/null || true)"
    [[ "$src" =~ $RECIPE_RE ]] && continue
    printf '%s:%s:%s\n' "$file" "$line_no" "$text" >>"$HITS_FILE"
  done < <(scan_scope "[A-Za-z0-9_.-]+@${ID_ESCAPED}\\.?([^A-Za-z0-9_.-]|\$)")
fi

DOTDOT_PATTERN='(\.\./)+([A-Za-z0-9_.-]+/)+([A-Za-z0-9_.-]+/|SKILL\.md#|[A-Za-z0-9_.-]+\.schema\.json)'
while IFS= read -r line; do
  [[ -z "$line" ]] && continue
  split_hit "$line"
  [[ "$text" == *"/skills/"* || "$text" == skills/* ]] && continue
  # shellcheck disable=SC2310  # lex_resolve returns status; continue is the handled miss
  resolved="$(lex_resolve "$(dirname "$file")/$text")" || continue
  # shellcheck disable=SC2310  # is_private_skill_path is a pure predicate; both branches handled
  is_private_skill_path "$resolved" || continue
  printf '%s:%s:%s\n' "$file" "$line_no" "$text" >>"$HITS_FILE"
done < <(scan_scope "$DOTDOT_PATTERN")

raw=0
candidates=0
while IFS= read -r line; do
  [[ -z "$line" ]] && continue
  split_hit "$line"
  # shellcheck disable=SC2310  # pure predicate; both branches handled
  is_allowlisted "$file" && continue
  raw=$((raw + 1))
  # shellcheck disable=SC2310  # pure predicate; both branches handled
  if [[ "$APPLY_FILTERS" -eq 1 ]] && is_mechanically_legal "$file" "$line_no" "$text"; then
    continue
  fi
  candidates=$((candidates + 1))
  printf '%s\t%s\t%s\n' "$file" "$line_no" "$text"
done <"$HITS_FILE"

if [[ "$APPLY_FILTERS" -eq 1 ]]; then
  printf 'Summary: raw=%s mech-filtered=%s candidates=%s\n' \
    "$raw" "$((raw - candidates))" "$candidates" >&2
fi

exit "$((candidates > 0))"
