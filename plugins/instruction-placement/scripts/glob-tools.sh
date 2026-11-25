#!/usr/bin/env bash

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./lib/discover.sh
. "$SCRIPT_DIR/lib/discover.sh"

MAX_EXPANDED=1000
MAX_BYTES=4194304

usage() {
  cat <<'EOF'
glob-tools.sh — validate `paths:` globs for Claude Code path-scoped rules.

Usage:
  glob-tools.sh validate --glob <pattern> [--glob <pattern>...] [--root <dir>] [--breadth-max <pct>]
  glob-tools.sh rules [--root <dir>] [--breadth-max <pct>]
  glob-tools.sh --help

validate  check globs given on the command line
rules     check every `paths:` glob under <root>/.claude/rules (recursive), and that
          each rule's YAML frontmatter is readable: Claude Code ignores frontmatter
          that does not parse and loads the rule unscoped

Output (TSV, sorted, deterministic):
  PATTERN <tab> source <tab> pattern <tab> expanded <tab> matches <tab> status
  FRONTMATTER <tab> source <tab> line <tab> reason <tab> unparsable   (rules only)
  SUMMARY <tab> tracked <tab> patterns <tab> invalid <tab> overbroad <tab> verdict

status   ok | zero-match | bad-bracket | over-budget | over-broad
verdict  PASS | FAIL

Exit: 0 valid (over-broad warns); 1 at least one invalid or unparsable; 2 usage error.
EOF
}

die() {
  printf 'ERROR: %s\n' "$1" >&2
  exit 2
}

expand_braces() {
  local pattern="$1"
  local -a queue=("$pattern")
  local -a done_list=()
  local bytes=0

  while ((${#queue[@]} > 0)); do
    local current="${queue[0]}"
    queue=("${queue[@]:1}")

    local i char depth=0 open=-1 close=-1
    for ((i = 0; i < ${#current}; i++)); do
      char="${current:i:1}"
      if [[ "$char" == "\\" ]]; then
        ((i++))
        continue
      fi
      if [[ "$char" == "{" ]]; then
        if ((depth == 0)); then open=$i; fi
        ((depth++))
      elif [[ "$char" == "}" ]]; then
        ((depth--))
        if ((depth == 0)); then
          close=$i
          break
        fi
      fi
    done

    if ((open < 0 || close < 0)); then
      done_list+=("$current")
      bytes=$((bytes + ${#current}))
      if ((${#done_list[@]} > MAX_EXPANDED)) || ((bytes > MAX_BYTES)); then
        return 1
      fi
      continue
    fi

    local prefix="${current:0:open}"
    local suffix="${current:close+1}"
    local body="${current:open+1:close-open-1}"

    local -a parts=()
    local part="" d=0 j c
    for ((j = 0; j < ${#body}; j++)); do
      c="${body:j:1}"
      if [[ "$c" == "\\" ]]; then
        part+="$c${body:j+1:1}"
        ((j++))
        continue
      fi
      if [[ "$c" == "{" ]]; then
        ((d++))
      elif [[ "$c" == "}" ]]; then
        ((d--))
      elif [[ "$c" == "," && $d -eq 0 ]]; then
        parts+=("$part")
        part=""
        continue
      fi
      part+="$c"
    done
    parts+=("$part")

    local p
    for p in "${parts[@]}"; do
      queue+=("${prefix}${p}${suffix}")
    done

    if ((${#queue[@]} + ${#done_list[@]} > MAX_EXPANDED)); then
      return 1
    fi
  done

  printf '%s\n' "${done_list[@]}"
  return 0
}

brackets_valid() {
  local pattern="$1"
  local i char len="${#pattern}"
  for ((i = 0; i < len; i++)); do
    char="${pattern:i:1}"
    if [[ "$char" == "\\" ]]; then
      ((i++))
      continue
    fi
    [[ "$char" != "[" ]] && continue

    local j=$((i + 1))
    if [[ "${pattern:j:1}" == "!" || "${pattern:j:1}" == "^" ]]; then ((j++)); fi
    if [[ "${pattern:j:1}" == "]" ]]; then ((j++)); fi

    local closed=0
    for (( ; j < len; j++)); do
      if [[ "${pattern:j:1}" == "\\" ]]; then
        ((j++))
        continue
      fi
      if [[ "${pattern:j:1}" == "]" ]]; then
        closed=1
        break
      fi
    done
    ((closed == 0)) && return 1
    i=$j
  done
  return 0
}

glob_to_ere() {
  local pattern="$1"
  local out="" i=0 len char
  case "$pattern" in
  /*) pattern="${pattern#/}" ;;
  */*) ;;
  *) out="(.*/)?" ;;
  esac
  len="${#pattern}"
  while ((i < len)); do
    char="${pattern:i:1}"
    case "$char" in
    "\\")
      out+="\\${pattern:i+1:1}"
      i=$((i + 2))
      continue
      ;;
    "*")
      if [[ "${pattern:i:3}" == "**/" ]]; then
        out+="(.*/)?"
        i=$((i + 3))
        continue
      fi
      if [[ "${pattern:i:2}" == "**" ]]; then
        out+=".*"
        i=$((i + 2))
        continue
      fi
      out+="[^/]*"
      ;;
    "?") out+="[^/]" ;;
    "[")
      local j=$((i + 1)) body="["
      if [[ "${pattern:j:1}" == "!" || "${pattern:j:1}" == "^" ]]; then
        body+="^"
        ((j++))
      fi
      if [[ "${pattern:j:1}" == "]" ]]; then
        body+="]"
        ((j++))
      fi
      while ((j < len)) && [[ "${pattern:j:1}" != "]" ]]; do
        if [[ "${pattern:j:1}" == "\\" ]]; then
          body+="${pattern:j:2}"
          j=$((j + 2))
          continue
        fi
        body+="${pattern:j:1}"
        ((j++))
      done
      body+="]"
      out+="$body"
      i=$((j + 1))
      continue
      ;;
    "." | "^" | "$" | "+" | "(" | ")" | "|" | "{" | "}") out+="\\$char" ;;
    *) out+="$char" ;;
    esac
    ((i++))
  done
  printf '%s' "$out"
}


[[ $# -eq 0 ]] && {
  usage >&2
  exit 2
}

case "$1" in
-h | --help)
  usage
  exit 0
  ;;
validate | rules)
  SUBCOMMAND="$1"
  shift
  ;;
*) die "unknown subcommand: $1 (expected validate or rules)" ;;
esac

ROOT="$PWD"
BREADTH_MAX="${CLAUDE_PLUGIN_OPTION_BREADTH_MAX:-75}"
[[ "$BREADTH_MAX" =~ ^[0-9]+$ ]] || BREADTH_MAX=75
declare -a CLI_GLOBS=()

while [[ $# -gt 0 ]]; do
  case "$1" in
  -h | --help)
    usage
    exit 0
    ;;
  --root)
    [[ $# -lt 2 ]] && die "--root needs a path"
    ROOT="$2"
    shift 2
    ;;
  --glob)
    [[ $# -lt 2 ]] && die "--glob needs a pattern"
    CLI_GLOBS+=("$2")
    shift 2
    ;;
  --breadth-max)
    [[ $# -lt 2 ]] && die "--breadth-max needs an integer percent"
    [[ "$2" =~ ^[0-9]+$ ]] || die "--breadth-max must be an integer percent"
    BREADTH_MAX="$2"
    shift 2
    ;;
  *) die "unknown argument: $1" ;;
  esac
done

[[ -d "$ROOT" ]] || die "--root is not a directory: $ROOT"
cd "$ROOT" || die "cannot enter --root: $ROOT"

if [[ "$SUBCOMMAND" == "validate" && ${#CLI_GLOBS[@]} -eq 0 ]]; then
  die "validate needs at least one --glob"
fi

TRACKED_FILE="$(mktemp)"
ROWS_FILE="$(mktemp)"
BASE_TRACKED_FILE="$(mktemp)"
trap 'rm -f "$TRACKED_FILE" "$ROWS_FILE" "$BASE_TRACKED_FILE"' EXIT
if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  git ls-files -z 2>/dev/null | tr '\0' '\n' | LC_ALL=C sort >"$TRACKED_FILE"
else
  find . -type f -not -path './.git/*' 2>/dev/null |
    sed 's|^\./||' | LC_ALL=C sort >"$TRACKED_FILE"
fi
TRACKED_TOTAL=$(wc -l <"$TRACKED_FILE" | tr -d ' ')

declare -a SOURCES=() BUDGET_KEYS=() PATTERNS=()
FM_BAD=0
if [[ "$SUBCOMMAND" == "validate" ]]; then
  for cli_i in "${!CLI_GLOBS[@]}"; do
    SOURCES+=("<cli>")
    BUDGET_KEYS+=("<cli>#$cli_i")
    PATTERNS+=("${CLI_GLOBS[cli_i]}")
  done
else
  while IFS= read -r rule; do
    [[ -z "$rule" ]] && continue
    while IFS= read -r pat; do
      [[ -z "$pat" ]] && continue
      SOURCES+=("$rule")
      BUDGET_KEYS+=("$rule")
      PATTERNS+=("$pat")
    done < <(ip_parse_paths "$rule")
    fm_problem="$(ip_frontmatter_problem "$rule")"
    if [[ -n "$fm_problem" ]]; then
      FM_BAD=$((FM_BAD + 1))
      fm_line="${fm_problem%%$'\t'*}"
      fm_reason="${fm_problem#*$'\t'}"
      printf 'FRONTMATTER\t%s\t%s\t%s\tunparsable\n' "$rule" "$fm_line" "$fm_reason" >>"$ROWS_FILE"
    fi
  done < <(ip_discover_rules .)
fi

INVALID=$FM_BAD
OVERBROAD=0

PREV_BUDGET_KEY=""
RUNNING_EXPANDED=0

for idx in "${!PATTERNS[@]}"; do
  pattern="${PATTERNS[$idx]}"
  source="${SOURCES[$idx]}"
  budget_key="${BUDGET_KEYS[$idx]}"
  status="ok"
  expanded_count=0
  match_count=0
  expansions=()

  if [[ "$budget_key" != "$PREV_BUDGET_KEY" ]]; then
    PREV_BUDGET_KEY="$budget_key"
    RUNNING_EXPANDED=0

    UNIVERSE="$TRACKED_FILE"
    UNIVERSE_TOTAL="$TRACKED_TOTAL"
    if [[ "$source" == */.claude/rules/* ]]; then
      UNIVERSE="$BASE_TRACKED_FILE"
      IP_BASE="${source%%/.claude/rules/*}/" awk '
        index($0, ENVIRON["IP_BASE"]) == 1 { print substr($0, length(ENVIRON["IP_BASE"]) + 1) }
      ' "$TRACKED_FILE" >"$BASE_TRACKED_FILE"
      UNIVERSE_TOTAL=$(($(wc -l <"$BASE_TRACKED_FILE")))
    fi
  fi

  if ! brackets_valid "$pattern"; then
    status="bad-bracket"
  elif ! expansions_raw="$(expand_braces "$pattern")"; then
    status="over-budget"
  else
    while IFS= read -r one_expansion; do
      expansions+=("$one_expansion")
    done <<<"$expansions_raw"
    expanded_count=${#expansions[@]}

    if ((expanded_count > 1)); then
      RUNNING_EXPANDED=$((RUNNING_EXPANDED + expanded_count))
      if ((RUNNING_EXPANDED > MAX_EXPANDED)); then
        status="over-budget"
      fi
    fi
    if [[ "$status" != "over-budget" ]]; then
      match_count=$(
        for exp in "${expansions[@]}"; do
          [[ -z "$exp" ]] && continue
          ere="$(glob_to_ere "$exp")"
          grep -E "^${ere}$" "$UNIVERSE" 2>/dev/null
        done | LC_ALL=C sort -u | grep -c . || true
      )

      if ((match_count == 0)); then
        status="zero-match"
      elif ((UNIVERSE_TOTAL > 0)) && ((match_count * 100 >= UNIVERSE_TOTAL * BREADTH_MAX)); then
        status="over-broad"
      fi
    fi
  fi

  case "$status" in
  bad-bracket | over-budget | zero-match) INVALID=$((INVALID + 1)) ;;
  over-broad) OVERBROAD=$((OVERBROAD + 1)) ;;
  *) ;;
  esac

  printf 'PATTERN\t%s\t%s\t%s\t%s\t%s\n' \
    "$source" "$pattern" "$expanded_count" "$match_count" "$status" >>"$ROWS_FILE"
done

LC_ALL=C sort "$ROWS_FILE"

verdict="PASS"
((INVALID > 0)) && verdict="FAIL"
printf 'SUMMARY\t%s\t%s\t%s\t%s\t%s\n' \
  "$TRACKED_TOTAL" "${#PATTERNS[@]}" "$INVALID" "$OVERBROAD" "$verdict"

((INVALID > 0)) && exit 1
exit 0
