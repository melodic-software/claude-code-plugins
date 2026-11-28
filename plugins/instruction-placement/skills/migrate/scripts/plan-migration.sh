#!/usr/bin/env bash
# Exit: 0 the plan printed; 1 not a git repository; 2 usage error.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../../../scripts/lib/discover.sh
source "$SCRIPT_DIR/../../../scripts/lib/discover.sh" || {
  echo "plan-migration: cannot load $SCRIPT_DIR/../../../scripts/lib/discover.sh" >&2
  exit 2
}
[[ -n "${IP_EXCLUDED_TREES:-}" && -n "${IP_FOREIGN_AGENT_TREES:-}" ]] || {
  echo "plan-migration: lib/discover.sh defined no exclusion lists; refusing to plan" >&2
  exit 2
}

CODEX_PROJECT_DOC_BUDGET=32768

ROOT="."
HOME_DIR="${HOME:-}"
EXPAND_MENTIONS=0

while [[ $# -gt 0 ]]; do
  case "$1" in
  --help | -h)
    cat <<'EOF'
plan-migration.sh — what a repository's move to AGENTS.md would touch.

Usage: plan-migration.sh [--root <dir>] [--home <dir>] [--expand-mentions] [--help]

  --root <dir>        the repository to plan; any path inside it resolves to its
                      toplevel (default: the current directory)
  --home <dir>        where to look for the bare ~/CLAUDE.md suppressors
                      (default: $HOME)
  --expand-mentions   list every MENTION row instead of rolling up a directory
                      that holds more than 10 of them. `.claude/` and `.github/`
                      are never rolled up: a leak lives in configuration
  --dry-run           accepted and ignored; this script only ever reads
  --help              this message

Row kinds and their columns, tab-separated after the kind:

  DIR       <path> <state> <CLAUDE.md bytes> <AGENTS.md bytes>
  BUDGET    <path> <cumulative AGENTS.md bytes, root to that path> <OK|OVER>
  CASE      <path>
  SUPPRESS  <path> <yes|no>
  PATHDET   <file>:<line>:<text>
  CITE      <file>:<line>:<text>
  MENTION   <file>:<line>:<text>, or <dir>/ <count> rows when rolled up
  RULES     <total> <unscoped> <unscoped bytes>
  DOCSHOME  <dir> <found|absent>
  ACTION    <workflow>:<line>:<text>

Every row is a fact about the repository; the content split is judgment and
stays in the skill. A kind with nothing to report prints NONE in place of its
columns, so "checked, none" never looks like "did not run".

Exit: 0 printed, 1 not a git repository, 2 usage error.
EOF
    exit 0
    ;;
  --dry-run) shift ;;
  --expand-mentions)
    EXPAND_MENTIONS=1
    shift
    ;;
  --root)
    [[ $# -ge 2 ]] || {
      echo "plan-migration: --root needs a directory" >&2
      exit 2
    }
    ROOT="$2"
    shift 2
    ;;
  --home)
    [[ $# -ge 2 ]] || {
      echo "plan-migration: --home needs a directory" >&2
      exit 2
    }
    HOME_DIR="$2"
    shift 2
    ;;
  *)
    echo "plan-migration: unknown argument: $1" >&2
    exit 2
    ;;
  esac
done

cd "$ROOT" 2>/dev/null || {
  echo "plan-migration: cannot enter $ROOT" >&2
  exit 2
}

REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null | tr -d '\r')"
[[ -n "$REPO_ROOT" ]] || {
  echo "plan-migration: not inside a git repository" >&2
  exit 1
}
cd "$REPO_ROOT" || exit 1

file_bytes() {
  [[ -f "$1" ]] || {
    printf '0\n'
    return 0
  }
  wc -c <"$1" | tr -d ' \t\r'
}

ours_agents_bytes() {
  local dir="$1" seg
  for seg in $IP_FOREIGN_AGENT_TREES; do
    case "/$dir/" in
    */"$seg"/*)
      printf '0\n'
      return 0
      ;;
    *) ;;
    esac
  done
  file_bytes "$dir/AGENTS.md"
}

classify_claude_md() {
  local file="$1" import=0 comment=0 other=0 inblock=0 line trimmed
  [[ -f "$file" ]] || {
    printf 'content\n'
    return 0
  }
  while IFS= read -r line || [[ -n "$line" ]]; do
    trimmed="${line%$'\r'}"
    trimmed="${trimmed#"${trimmed%%[![:space:]]*}"}"
    trimmed="${trimmed%"${trimmed##*[![:space:]]}"}"
    [[ -z "$trimmed" ]] && continue
    if ((inblock)); then
      comment=1
      [[ "$trimmed" == *"-->"* ]] && inblock=0
      continue
    fi
    case "$trimmed" in
    "@AGENTS.md" | "@./AGENTS.md") import=$((import + 1)) ;;
    "<!--"*"-->") comment=1 ;;
    "<!--"*)
      comment=1
      inblock=1
      ;;
    *) other=1 ;;
    esac
  done <"$file"
  if ((other)) || ((import != 1)); then
    printf 'content\n'
  elif ((comment)); then
    printf 'shim-with-comment\n'
  else
    printf 'shim\n'
  fi
}

is_exact_shim() {
  local file="$1" bytes="$2"
  [[ "$bytes" -eq 10 || "$bytes" -eq 11 ]] && [[ "$(<"$file")" == "@AGENTS.md" ]]
}

instruction_dirs() {
  git ls-files -z 2>/dev/null | tr '\0' '\n' |
    awk -v excluded="$IP_EXCLUDED_TREES" -v foreign="$IP_FOREIGN_AGENT_TREES" '
    BEGIN {
      split(excluded, ex, " "); for (k in ex) skip[ex[k]] = 1
      split(foreign, others, " "); for (k in others) theirs[others[k]] = 1
    }
    $0 == "" { next }
    {
      n = split($0, seg, "/")
      base = seg[n]
      if (base != "CLAUDE.md" && base != "AGENTS.md") next
      for (i = 1; i < n; i++) {
        if (seg[i] in skip) next
        if (base == "AGENTS.md" && seg[i] in theirs) next
      }
      if (n == 1) { print "."; next }
      dir = seg[1]
      for (i = 2; i < n; i++) dir = dir "/" seg[i]
      print dir
    }
  ' | LC_ALL=C sort -u
}

while IFS= read -r dir; do
  [[ -n "$dir" ]] || continue
  claude="$dir/CLAUDE.md"
  cb="$(file_bytes "$claude")"
  ab="$(ours_agents_bytes "$dir")"

  if [[ "$cb" -eq 0 && "$ab" -eq 0 ]]; then
    state="zero-byte"
  elif [[ "$cb" -eq 0 ]]; then
    state="agents-only"
  elif [[ "$ab" -eq 0 ]]; then
    state="content-in-claude"
    if [[ "$(classify_claude_md "$claude")" == "shim" ]] && is_exact_shim "$claude" "$cb"; then
      state="shim-empty-target"
    fi
  else
    case "$(classify_claude_md "$claude")" in
    shim)
      state="shim-noncanonical"
      is_exact_shim "$claude" "$cb" && state="shim"
      ;;
    shim-with-comment) state="shim-with-comment" ;;
    *) state="both-with-content" ;;
    esac
  fi
  printf 'DIR\t%s\t%s\t%s\t%s\n' "$dir" "$state" "$cb" "$ab"

  cum=0
  walk="$dir"
  while :; do
    cum=$((cum + $(ours_agents_bytes "$walk")))
    [[ "$walk" != "." && "$walk" != "/" ]] || break
    walk="$(dirname "$walk")"
  done
  verdict="OK"
  [[ "$cum" -gt "$CODEX_PROJECT_DOC_BUDGET" ]] && verdict="OVER"
  printf 'BUDGET\t%s\t%s\t%s\n' "$dir" "$cum" "$verdict"
done < <(instruction_dirs)

emit_rows() {
  local kind="$1" rows
  rows="$(cat)"
  if [[ -z "${rows//[$' \t\n']/}" ]]; then
    printf '%s\tNONE\n' "$kind"
  else
    printf '%s\n' "$rows"
  fi
}

MENTION_ROLLUP_THRESHOLD=10

MENTION_NEVER_ROLLUP=".claude/ .github/ .lefthook/ .husky/ .githooks/"

roll_up_mentions() {
  if ((EXPAND_MENTIONS)); then
    cat
    return 0
  fi
  awk -v n="$MENTION_ROLLUP_THRESHOLD" -v keep="$MENTION_NEVER_ROLLUP" '
    BEGIN { split(keep, k, " "); for (i in k) never[k[i]] = 1 }
    { line[NR] = $0
      slash = index($0, "/")
      top = (slash ? substr($0, 1, slash) : "")
      if (top in never) top = ""
      dir[NR] = top
      if (top != "") count[top]++
    }
    END {
      for (i = 1; i <= NR; i++) {
        top = dir[i]
        if (top != "" && count[top] > n) {
          if (!(top in done)) { printf "%s\t%d rows\n", top, count[top]; done[top] = 1 }
          continue
        }
        print line[i]
      }
    }
  '
}

PATHDET_HITS="$(mktemp)"
PATHDET_RAW="$(mktemp)"
CITE_HITS="$(mktemp)"
ALREADY_REPORTED="$(mktemp)"
trap 'rm -f "$PATHDET_HITS" "$PATHDET_RAW" "$CITE_HITS" "$ALREADY_REPORTED"' EXIT

scan_failed() { (($1 > 1)); }

git ls-files -z 2>/dev/null | tr '\0' '\n' | awk '
  $0 == "" { next }
  {
    n = split($0, seg, "/")
    base = seg[n]
    if (base == "CLAUDE.md" || base == "AGENTS.md" || base == "CLAUDE.local.md") next
    lower = tolower(base)
    if (lower == "claude.md" || lower == "agents.md" || lower == "claude.local.md")
      printf "CASE\t%s\n", $0
  }
' | emit_rows CASE

native_path() {
  if command -v cygpath >/dev/null 2>&1; then
    cygpath -m "$1" 2>/dev/null || printf '%s' "$1"
  else
    printf '%s' "$1"
  fi
}

if [[ -n "$HOME_DIR" ]]; then
  for suppressor in "$HOME_DIR/CLAUDE.md" "$HOME_DIR/CLAUDE.local.md"; do
    exists="no"
    [[ -f "$suppressor" ]] && exists="yes"
    printf 'SUPPRESS\t%s\t%s\n' "$(native_path "$suppressor")" "$exists"
  done
fi

BENIGN_COMMENT=':[0-9]+:[[:space:]]*(#|//|\*|--|<!--|;)'

PATHDET_PATTERN='(\[\[|\[|\(|^|[[:space:];&|]|!)[[:space:]]*-(e|f|s|r|h|L|name)[[:space:]][^;&|]{0,60}CLAUDE\.md'
PATHDET_PATTERN="$PATHDET_PATTERN"'|([Ee]xists?|EXISTS|[Ii]s_?[Ff]ile|[Ii]sFile|[Ss]tat|[Tt]est-[Pp]ath|[Aa]ccess(Sync)?|existsSync|statSync|[Ff]ile[Ee]xists|[Pp]ath\.[a-z]+|[Ff]ind[A-Za-z]*[Rr]oot|[Ll]ocate)[^;]{0,60}CLAUDE\.md'
# shellcheck disable=SC2016 # the quote characters are part of the pattern, not a shell expansion
PATHDET_PATTERN="$PATHDET_PATTERN"'|[A-Za-z_][A-Za-z0-9_]*[[:space:]]*(=|:=|<-)[[:space:]]*("|'"'"')?CLAUDE\.md'
# shellcheck disable=SC2016 # the quote characters are part of the pattern, not a shell expansion
PATHDET_PATTERN="$PATHDET_PATTERN"'|CLAUDE\.md("|'"'"')?[[:space:]]*\)?[[:space:]]*\.[[:space:]]*([Ee]xists?|[Ii]s_?[Ff]ile|[Ss]tat|exist\?)'

pathdet_rc=0
git grep -n -I -E 'CLAUDE\.md' \
  -- ':!*.md' ':!*.mdc' ':!.claude/cutover-pathdet-ack.txt' ':!**/.claude/cutover-pathdet-ack.txt' \
  ':!CHANGELOG.md' ':!**/CHANGELOG.md' \
  >"$PATHDET_RAW" 2>/dev/null || pathdet_rc=$?
if scan_failed "$pathdet_rc"; then
  : >"$PATHDET_HITS"
  printf 'PATHDET\tERROR\tgit grep exited %s; the scan did not complete\n' "$pathdet_rc"
else
  grep -vE "$BENIGN_COMMENT" "$PATHDET_RAW" |
    grep -E 'CLAUDE\.md([^A-Za-z0-9._-]|$)' |
    grep -E "$PATHDET_PATTERN" >"$PATHDET_HITS"
  sed 's/^/PATHDET\t/' "$PATHDET_HITS" | emit_rows PATHDET
fi

SECTION_SIGN=$'\302\247'
# shellcheck disable=SC2016 # the backtick is markdown in the pattern, not a command substitution
CITE_PATTERN='\]\([^)]*CLAUDE\.md(#[A-Za-z0-9_-]+)?\)|`?CLAUDE\.md`?[[:space:]]+("[^"]+"|'"$SECTION_SIGN"'[^[:space:]])'
git grep -n -I -E "$CITE_PATTERN" -- '*.md' '*.mdc' 2>/dev/null >"$CITE_HITS"
sed 's/^/CITE\t/' "$CITE_HITS" | emit_rows CITE

cat "$CITE_HITS" "$PATHDET_HITS" >"$ALREADY_REPORTED"
printf '\x01no-such-line\n' >>"$ALREADY_REPORTED"
git grep -n -I -F 'CLAUDE.md' \
  -- ':!CLAUDE.md' ':!AGENTS.md' ':!**/CLAUDE.md' ':!**/AGENTS.md' \
  ':!CLAUDE.local.md' ':!**/CLAUDE.local.md' \
  ':!CHANGELOG.md' ':!**/CHANGELOG.md' \
  ':!.claude/CLAUDE.md' ':!**/.claude/CLAUDE.md' 2>/dev/null |
  grep -vxF -f "$ALREADY_REPORTED" |
  roll_up_mentions |
  sed 's/^/MENTION\t/' | emit_rows MENTION

rules_total=0
rules_unscoped=0
rules_unscoped_bytes=0
while IFS= read -r rule; do
  [[ -n "$rule" ]] || continue
  rules_total=$((rules_total + 1))
  if ! grep -qE '^paths:' "$rule" 2>/dev/null; then
    rules_unscoped=$((rules_unscoped + 1))
    rules_unscoped_bytes=$((rules_unscoped_bytes + $(file_bytes "$rule")))
  fi
done < <(git ls-files -z -- '.claude/rules/*.md' '.claude/rules/**/*.md' 2>/dev/null | tr '\0' '\n')
printf 'RULES\t%s\t%s\t%s\n' "$rules_total" "$rules_unscoped" "$rules_unscoped_bytes"

docs_home="docs"
docs_state="absent"
for candidate in docs doc documentation Documentation; do
  if [[ -d "$candidate" ]] && git ls-files --error-unmatch "$candidate" >/dev/null 2>&1; then
    docs_home="$candidate"
    docs_state="found"
    break
  fi
done
printf 'DOCSHOME\t%s\t%s\n' "$docs_home" "$docs_state"

ACTION_DIRS=()
[[ -d ".github/workflows" ]] && ACTION_DIRS+=(".github/workflows")
[[ -d ".github/actions" ]] && ACTION_DIRS+=(".github/actions")
if [[ ${#ACTION_DIRS[@]} -gt 0 ]]; then
  action_rc=0
  action_rows="$(grep -rn -E '^[[:space:]]*-?[[:space:]]*uses:[[:space:]]*[^#]*claude-code-action(/[A-Za-z0-9._-]+)*@' \
    "${ACTION_DIRS[@]}" 2>/dev/null)" || action_rc=$?
  if scan_failed "$action_rc"; then
    printf 'ACTION\tERROR\tgrep exited %s; the scan did not complete\n' "$action_rc"
  else
    printf '%s' "$action_rows" | sed 's/^/ACTION\t/' | emit_rows ACTION
  fi
else
  printf 'ACTION\tNONE\n'
fi

exit 0
