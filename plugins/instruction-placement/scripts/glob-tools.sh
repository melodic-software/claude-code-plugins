#!/usr/bin/env bash
# glob-tools.sh — validate `paths:` globs for Claude Code path-scoped rules.
#
# WHY. A path-scoped rule is only as useful as its glob, and every way a glob can
# be wrong fails SILENTLY: a zero-match pattern is a rule that never fires, an
# unbalanced `[` matches nothing while the rule's other patterns keep working,
# and a pattern past the brace-expansion budget is used UNEXPANDED so its literal
# braces match no file. Claude Code reports none of these. This script turns each
# one into an exit code.
#
# The budgets and semantics implemented here are Anthropic-documented
# (code.claude.com/docs/en/memory, "Path-specific rules"):
#   - brace groups multiply; a rule's whole `paths:` list shares one budget of
#     1,000 expanded patterns and 4 MiB, and brace-free patterns do not count
#   - a pattern over budget is used unexpanded and its braces match nothing
#   - `[` opens a bracket expression; one that cannot be read as such matches
#     nothing, and a literal `[` is escaped as `\[`
#
# Brace expansion is implemented by hand rather than by shell `eval`, because the
# input is repository content: eval on a `paths:` value read off disk would let a
# crafted rule file run commands.
#
# Subcommands:
#   validate  validate one or more globs handed in on the command line
#   rules     validate every `paths:` glob in a repository's .claude/rules tree
#
# Output is deterministic TSV on stdout: sorted, no timestamps, no absolute
# paths. Facts only — the caller adjudicates.
#
# Usage:
#   glob-tools.sh validate --glob <pattern> [--glob <pattern>...] [options]
#   glob-tools.sh rules [options]
#   glob-tools.sh --help
#
# Options:
#   --root <dir>          repository root to match against (default: cwd)
#   --breadth-max <pct>   integer percent of tracked files above which a pattern
#                         is reported over-broad (default: 75)
#   --help                this message
#
# Exit: 0 all patterns valid (over-broad is a warning, not a failure)
#       1 at least one pattern invalid (zero-match, bad bracket, over budget)
#       2 usage error or unusable --root

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
rules     check every `paths:` glob under <root>/.claude/rules (recursive)

Output (TSV, sorted, deterministic):
  PATTERN <tab> source <tab> pattern <tab> expanded <tab> matches <tab> status
  SUMMARY <tab> tracked <tab> patterns <tab> invalid <tab> overbroad <tab> verdict

status   ok | zero-match | bad-bracket | over-budget | over-broad
verdict  PASS | FAIL

Exit: 0 valid (over-broad warns); 1 at least one invalid; 2 usage error.
EOF
}

die() {
  printf 'ERROR: %s\n' "$1" >&2
  exit 2
}

# ---------------------------------------------------------------------------
# Brace expansion — iterative, budget-capped, no eval.
#
# Expands the leftmost top-level {a,b} group and re-queues each result, so
# nested and sequential groups both resolve. Returns non-zero the moment the
# budget is exceeded, because past that point Claude Code stops expanding too
# and the honest answer is "over budget", not a truncated list.
# ---------------------------------------------------------------------------
expand_braces() {
  local pattern="$1"
  local -a queue=("$pattern")
  local -a done_list=()
  local bytes=0

  while ((${#queue[@]} > 0)); do
    local current="${queue[0]}"
    queue=("${queue[@]:1}")

    # Locate the first unescaped `{` and its matching `}` at the same depth.
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
      # No expandable group left. A stray `}` or an unclosed `{` is not an
      # error here: Claude Code treats it as a literal, and so do we.
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

    # Split the body on top-level commas only — a nested group's commas belong
    # to that group, not to this split.
    local -a parts=()
    local part="" d=0 j c
    for ((j = 0; j < ${#body}; j++)); do
      c="${body:j:1}"
      if [[ "$c" == "\\" ]]; then
        part+="$c${body:j+1:1}"
        ((j++))
        continue
      fi
      if [[ "$c" == "{" ]]; then ((d++)); fi
      if [[ "$c" == "}" ]]; then ((d--)); fi
      if [[ "$c" == "," && $d -eq 0 ]]; then
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

# ---------------------------------------------------------------------------
# Bracket-expression validation.
#
# A `[` that cannot be read as a bracket expression makes the pattern match
# nothing. Mirrors glob rules: `]` immediately after `[` (or after `[!`/`[^`) is
# a literal `]`, and a backslash escapes the next character.
# ---------------------------------------------------------------------------
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
    # Optional negation, then an optional literal `]` in first position.
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

# ---------------------------------------------------------------------------
# Glob -> ERE, path-aware.
#
#   **/   ->  (.*/)?     so `**/*.ts` matches a root-level `a.ts` too
#   **    ->  .*         crosses directory separators
#   *     ->  [^/]*      does NOT cross a separator
#   ?     ->  [^/]
#   [...] ->  preserved as a bracket expression
#
# Everything else is escaped, so a `.` in a pattern is a literal dot.
# ---------------------------------------------------------------------------
glob_to_ere() {
  local pattern="$1"
  local out="" i=0 len="${#pattern}" char next
  while ((i < len)); do
    char="${pattern:i:1}"
    case "$char" in
    "\\")
      next="${pattern:i+1:1}"
      out+="\\$next"
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
      # Copy the bracket expression through verbatim; validity was checked first.
      local j=$((i + 1)) body="["
      # `!` and `^` both negate, and ERE spells both `^`. brackets_valid() reads
      # the same pair, so the two must agree on where the expression starts.
      if [[ "${pattern:j:1}" == "!" || "${pattern:j:1}" == "^" ]]; then
        body+="^"
        ((j++))
      fi
      if [[ "${pattern:j:1}" == "]" ]]; then
        body+="]"
        ((j++))
      fi
      # A backslash escapes the next character, including a `]` that would
      # otherwise close the expression. brackets_valid() honors that escape, so
      # this copy must honor it too or the two disagree on where the bracket ends.
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
    ".") out+="\\." ;;
    "^") out+="\\^" ;;
    "$") out+="\\$" ;;
    "+") out+="\\+" ;;
    "(") out+="\\(" ;;
    ")") out+="\\)" ;;
    "|") out+="\\|" ;;
    "{") out+="\\{" ;;
    "}") out+="\\}" ;;
    *) out+="$char" ;;
    esac
    ((i++))
  done
  printf '%s' "$out"
}

# `paths:` extraction is `ip_parse_paths` in lib/discover.sh — one parser, three
# consumers. This file used to carry its own copy; all three copies shared a bug
# that split `["src/*.{ts,tsx}"]` on the brace comma.

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
[[ $# -eq 0 ]] && {
  usage >&2
  exit 2
}

SUBCOMMAND=""
case "${1:-}" in
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
# Declared userConfig reaches a script process as the native
# $CLAUDE_PLUGIN_OPTION_<KEY> mirror. Without reading it, a consumer can set the
# advertised option and silently keep the default — an option that does nothing
# is worse than one that does not exist, because it is documented.
# An explicit --breadth-max still wins over the configured value.
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

# Tracked files are the match universe. Untracked and ignored files are not
# shared repository content, so a glob that only matches those matches nothing
# that a teammate would see.
TRACKED_FILE="$(mktemp)"
trap 'rm -f "$TRACKED_FILE"' EXIT
if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  git ls-files -z 2>/dev/null | tr '\0' '\n' | LC_ALL=C sort >"$TRACKED_FILE"
else
  # Not a git repository: fall back to a plain file walk so the tool still
  # answers rather than reporting every glob as a zero-match.
  find . -type f -not -path './.git/*' 2>/dev/null |
    sed 's|^\./||' | LC_ALL=C sort >"$TRACKED_FILE"
fi
TRACKED_TOTAL=$(wc -l <"$TRACKED_FILE" | tr -d ' ')

# Build the (source, budget key, pattern) work list.
#
# BUDGET_KEY is deliberately NOT the displayed source. The budget belongs to a
# rule's whole `paths:` list, and a standalone `--glob` is not part of anyone's
# list -- each is its own unit of one. Tagging every CLI glob with the same
# `<cli>` source made them share one budget, so two independently-legal
# 512-expansion globs in one invocation reported the first `over-budget`. The
# key carries the index for validate; for `rules` it is the rule path, which is
# what groups a real `paths:` list.
declare -a SOURCES=() BUDGET_KEYS=() PATTERNS=()
if [[ "$SUBCOMMAND" == "validate" ]]; then
  cli_i=0
  for g in "${CLI_GLOBS[@]}"; do
    SOURCES+=("<cli>")
    BUDGET_KEYS+=("<cli>#$cli_i")
    cli_i=$((cli_i + 1))
    PATTERNS+=("$g")
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
  done < <(ip_discover_rules .)
fi

INVALID=0
OVERBROAD=0
ROWS_FILE="$(mktemp)"
trap 'rm -f "$TRACKED_FILE" "$ROWS_FILE"' EXIT

# The brace budget belongs to a RULE'S WHOLE `paths:` LIST, not to each pattern
# in it — "a rule's whole `paths:` list shares one budget of 1,000 expanded
# patterns and 4 MiB". Charging each pattern its own budget lets a rule with two
# 512-expansion globs pass while its combined 1,024 expansions exceed what the
# loader will expand, so the gate reports green for a rule whose patterns Claude
# Code silently leaves unexpanded.
#
# Tracked with a running counter rather than an associative array: `declare -A`
# is bash 4+, and macOS still ships 3.2. The work list groups every pattern of a
# rule contiguously, so resetting on a source change is equivalent and portable.
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
  fi

  if ! brackets_valid "$pattern"; then
    status="bad-bracket"
  else
    if ! expansions_raw="$(expand_braces "$pattern")"; then
      status="over-budget"
    else
      # A read loop rather than `mapfile`: mapfile is bash 4+, and macOS still
      # ships bash 3.2 as /bin/bash, where this script must still run.
      while IFS= read -r one_expansion; do
        expansions+=("$one_expansion")
      done <<<"$expansions_raw"
      expanded_count=${#expansions[@]}

      # Charge this pattern against its rule's running total. A brace-free
      # pattern expands to one and does not count, per the same documentation.
      if ((expanded_count > 1)); then
        RUNNING_EXPANDED=$((RUNNING_EXPANDED + expanded_count))
        if ((RUNNING_EXPANDED > MAX_EXPANDED)); then
          status="over-budget"
        fi
      fi
    fi
    if [[ "$status" != "over-budget" && ${#expansions[@]} -gt 0 ]]; then

      # Union of matches across every expansion, counted once per file.
      matches_file="$(mktemp)"
      for exp in "${expansions[@]}"; do
        [[ -z "$exp" ]] && continue
        ere="$(glob_to_ere "$exp")"
        grep -E "^${ere}$" "$TRACKED_FILE" 2>/dev/null >>"$matches_file"
      done
      match_count=$(LC_ALL=C sort -u "$matches_file" | grep -c . || true)
      rm -f "$matches_file"

      if ((match_count == 0)); then
        status="zero-match"
      elif ((TRACKED_TOTAL > 0)) && ((match_count * 100 >= TRACKED_TOTAL * BREADTH_MAX)); then
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
