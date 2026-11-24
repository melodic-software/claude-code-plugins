#!/usr/bin/env bash
# Parse the work-item reference from a branch name. The default convention is
# `<type>/<N>-<slug>` (or the cloud-routine variant
# `<type>/routine-issue-<N>-<slug>`), but the grammar is configurable so a
# consumer whose branches place the reference differently, e.g. a
# username-scoped scheme `alice/1234-slug`, a trailing-number scheme
# `feat/add-widget-1234`, or a tracker key `feat/SW2-1234-slug`, is not
# silently unparsable.
#
# Usage:
#   parse-branch-issue.sh [branch-name] [pattern] [--no-default] [--explain]
#
# With no branch arg, falls back to `git branch --show-current`.
# `--no-default` is for a caller bound to a work-item tracker, whose adapter
# owns the default branch grammar: when no consumer pattern (step 1 or 2 below)
# is set, the script prints nothing and exits 3 instead of applying step 3, so
# the caller asks the adapter.
# The grammar is an ERE whose LAST capture group holds the reference: an issue
# number (`1234`) or a tracker key (`SW2-1234`, `ENG-12`); the caller turns it
# into link text. A pattern with no capture group, or a capture of any other
# shape, yields no output and exit 1. It resolves, first hit wins:
#   1. The layered `branch_issue_pattern` key (reference/config-resolution.md):
#      In a markdown layer the value is the `## branch_issue_pattern` section's
#      first non-blank line, surrounding backticks
#      stripped, or, when that line opens a code fence, the first non-blank line
#      inside the fence. Headings inside fenced blocks are ignored. A leading
#      UTF-8 BOM, trailing whitespace, and a closing `#` sequence on the heading
#      are accepted. Repo root: CLAUDE_PROJECT_DIR, else
#      `git rev-parse --show-toplevel`. When that root is the home directory
#      (or an ancestor of it), team and personal override layers are not applicable. A
#      root outside any git working tree skips both layers too. A personal override
#      path that physically equals the user-global file is skipped even when
#      the root is not home.
#   2. The deprecated branch_issue_pattern userConfig: `pattern` (unless it is the
#      literal `${user_config...}` placeholder), then
#      CLAUDE_PLUGIN_OPTION_BRANCH_ISSUE_PATTERN. Using it prints a deprecation
#      note on stderr.
#   3. The built-in default (skipped with `--no-default`: exit 3).
# A layer whose section exists but yields no usable pattern stops resolution:
# the script prints nothing and exits 1, so a lower layer, the userConfig, or
# the default never supplies an issue number the author did not intend. That
# covers a near-miss H2 (one whose text contains `branch_issue_pattern` but is
# not the exact heading, e.g. `## branch_issue_pattern:`), a section with no
# value, a first value line that is a heading or an HTML comment, an empty or
# unterminated fence, and a pattern that breaks a limit (see usable_pattern).
# A higher layer that already supplied a valid pattern still wins, since the
# lower layer is never read. A userConfig value that breaks a limit is
# reported and ignored, so the default applies. Notes name the source and the
# reason, never the pattern text.
# Prints the captured reference on stdout and exits 0 on match.
# Exits 1 with no stdout if the branch does not match.
set -uo pipefail

KEY="branch_issue_pattern"

# `--explain` prints the layer that supplied the pattern on stderr; it is not a
# positional argument, so strip it wherever it appears.
EXPLAIN=0
ARGS=()
for arg in "$@"; do
  if [[ "$arg" == "--explain" ]]; then EXPLAIN=1; else ARGS+=("$arg"); fi
done
set -- ${ARGS[@]+"${ARGS[@]}"}

BRANCH="${1:-}"
[[ -n "$BRANCH" ]] || BRANCH="$(git branch --show-current 2>/dev/null || true)"
[[ -n "$BRANCH" ]] || exit 1

# Notes name the source and the reason only, never the pattern text, so a
# repo-controlled value is not echoed into the caller's context.
note() { echo "parse-branch-issue: $*" >&2; }

# shellcheck source=../../../lib/config-root.sh
source "$(dirname "${BASH_SOURCE[0]}")/../../../lib/config-root.sh" || exit 1
# shellcheck source=../../../lib/convention-key.sh
source "$(dirname "${BASH_SOURCE[0]}")/../../../lib/convention-key.sh" || exit 1

STOP="resolution stopped, no issue id emitted"

FENCE_OPEN='^(```+|~~~+)'
FENCE_CLOSE='^(```+|~~~+)$'

# Print the value of the `## branch_issue_pattern` section of file $1: its first
# non-blank line, surrounding whitespace and backticks stripped, or, when that
# line opens a code fence, the first non-blank line inside the fence. Headings
# inside fenced blocks are ignored. Prints nothing and returns 0 when the file
# or the section is absent. Returns 1 (with a note, nothing printed) when the
# section exists but yields no value, which stops resolution: a near-miss H2
# anywhere outside a fence, a section with no value, an empty or unterminated
# fence, or a first value line that is a heading or an HTML comment.
section_value() {
  local file="$1" line state=0 fence="" value="" first=1
  # state: 0 before the section, 1 inside it awaiting the value, 2 done.
  [[ -f "$file" ]] || return 0
  while IFS= read -r line || [[ -n "$line" ]]; do
    if ((first)); then
      line="${line#$'\xef\xbb\xbf'}"
      first=0
    fi
    line="${line%$'\r'}"
    line="${line#"${line%%[![:space:]]*}"}"
    line="${line%"${line##*[![:space:]]}"}"
    if [[ -n "$fence" ]]; then
      if [[ "$line" =~ $FENCE_CLOSE && "${line:0:1}" == "${fence:0:1}" && ${#line} -ge ${#fence} ]]; then
        if [[ "$state" -eq 1 ]]; then
          if [[ -z "$value" ]]; then
            note "${file}: ## ${KEY} holds an empty code fence; ${STOP}"
            return 1
          fi
          state=2
        fi
        fence=""
      elif [[ "$state" -eq 1 && -z "$value" && -n "$line" ]]; then
        value="$line"
      fi
      continue
    fi
    if [[ "$line" =~ ^##[[:space:]] ]]; then
      if [[ "$line" =~ ^##[[:space:]]+${KEY}([[:space:]]+#+)?$ ]]; then
        [[ "$state" -eq 0 ]] && state=1
      elif [[ "${line,,}" == *"$KEY"* ]]; then
        note "${file}: near-miss heading for ## ${KEY}; ${STOP}"
        return 1
      elif [[ "$state" -eq 1 ]]; then
        note "${file}: ## ${KEY} holds no value; ${STOP}"
        return 1
      fi
      continue
    fi
    if [[ "$line" =~ $FENCE_OPEN ]]; then
      fence="${BASH_REMATCH[1]}"
      continue
    fi
    [[ "$state" -eq 1 && -n "$line" ]] || continue
    if [[ "$line" =~ ^#{1,6}([[:space:]]|$) ]]; then
      note "${file}: ## ${KEY} starts with a heading, not a pattern; ${STOP}"
      return 1
    fi
    if [[ "$line" == '<!--'* ]]; then
      note "${file}: ## ${KEY} starts with an HTML comment, not a pattern; ${STOP}"
      return 1
    fi
    while [[ "$line" == \`* ]]; do line="${line#\`}"; done
    while [[ "$line" == *\` ]]; do line="${line%\`}"; done
    if [[ -z "$line" ]]; then
      note "${file}: ## ${KEY} holds no value; ${STOP}"
      return 1
    fi
    value="$line"
    state=2
  done <"$file"
  if [[ "$state" -eq 1 ]]; then
    if [[ -n "$fence" ]]; then
      note "${file}: ## ${KEY} holds an unterminated code fence; ${STOP}"
    else
      note "${file}: ## ${KEY} holds no value; ${STOP}"
    fi
    return 1
  fi
  [[ -z "$value" ]] || printf '%s\n' "$value"
  return 0
}

# Print the first limit pattern $1 breaks, or nothing. A coarse scan that runs
# before the pattern is ever compiled, since compiling a large bounded
# repetition alone can exhaust memory: at most 200 characters, every `{m,n}`
# bound at most 16, and no quantifier applied to a group whose body already
# holds a quantifier (`(a+)+`, `(x{0,5}){0,5}`). Escaped characters and bracket
# expressions are skipped.
pattern_limit() {
  local p="$1" i j c d b depth=0 inner rest
  local n=${#p}
  local -a has=(0)
  if ((n > 200)); then
    echo "is too long (over 200 characters)"
    return
  fi
  for ((i = 0; i < n; i++)); do
    c="${p:i:1}"
    case "$c" in
      \\) i=$((i + 1)) ;;
      '[')
        j=$((i + 1))
        [[ "${p:j:1}" == "^" ]] && j=$((j + 1))
        [[ "${p:j:1}" == "]" ]] && j=$((j + 1))
        while ((j < n)); do
          c="${p:j:1}"
          d="${p:j+1:1}"
          if [[ "$c" == "[" && -n "$d" && ":.=" == *"$d"* ]]; then
            rest="${p:j+2}"
            [[ "$rest" == *"$d]"* ]] || break
            rest="${rest%%"$d]"*}"
            j=$((j + ${#rest} + 4))
            continue
          fi
          [[ "$c" == "]" ]] && break
          j=$((j + 1))
        done
        i=$j
        ;;
      '(')
        depth=$((depth + 1))
        has[depth]=0
        ;;
      ')')
        ((depth > 0)) || continue
        inner=${has[depth]}
        depth=$((depth - 1))
        if ((inner)); then
          if [[ "${p:i+1:1}" == [*+?'{'] ]]; then
            echo "applies a quantifier to a group that holds one (nested quantifier)"
            return
          fi
          has[depth]=1
        fi
        ;;
      '{')
        if [[ "${p:i}" =~ ^\{([0-9]*)(,([0-9]*))?\} ]]; then
          for b in "${BASH_REMATCH[1]}" "${BASH_REMATCH[3]}"; do
            if [[ -n "$b" ]] && ((${#b} > 2 || 10#$b > 16)); then
              echo "has a repetition bound over 16"
              return
            fi
          done
        fi
        has[depth]=1
        ;;
      '*' | '+' | '?') has[depth]=1 ;;
      *) ;;
    esac
  done
}

# True when pattern $2 from source $1 is usable: it keeps within the limits
# pattern_limit checks, holds no backreference, and compiles as an ERE (bash's
# =~ returns 2 on a bad pattern). Otherwise reports the source, the reason,
# and outcome $3.
usable_pattern() {
  local src="$1" value="$2" outcome="$3" limit reason=""
  limit="$(pattern_limit "$value")"
  if [[ -n "$limit" ]]; then
    reason="$limit"
  elif [[ "$value" =~ \\[1-9] ]]; then
    reason="uses a backreference, which is not allowed"
  else
    { [[ "" =~ $value ]]; } 2>/dev/null
    (($? != 2)) || reason="is an invalid ERE"
  fi
  [[ -z "$reason" ]] && return 0
  note "${src}: ${KEY} ${reason}; ${outcome}"
  return 1
}

REPO_ROOT="$(config_root_resolve)"

SETUP_HINT="run /source-control:setup apply to move it, which deletes the old file"
old_location() { note "old location ${1}: $2; move its keys to ${3}; ${SETUP_HINT}"; }

LAYERS=()
USER_LAYER="${HOME:-}/.claude/source-control.md"
if [[ -n "$REPO_ROOT" ]]; then
  case "$(config_root_classify "$REPO_ROOT")" in
    home) note "team and personal override not applicable: project root is the home directory (or an ancestor of it)" ;;
    non-repo) note "team and personal override not applicable: project root is not inside a git repository" ;;
    *)
      PERSONAL_YAML="${REPO_ROOT}/${CONVENTION_KEY_LOCAL_REL}"
      personal_override="${REPO_ROOT}/${CONVENTION_KEY_OLD_LOCAL_REL}"
      TEAM_YAML="${REPO_ROOT}/${CONVENTION_KEY_YAML_REL}"
      [[ -f "$PERSONAL_YAML" ]] && LAYERS+=("$PERSONAL_YAML")
      if [[ -f "$personal_override" ]] && ! config_root_paths_same "$personal_override" "$USER_LAYER"; then
        if [[ -f "$PERSONAL_YAML" ]]; then
          old_location "$personal_override" "not read, since ${CONVENTION_KEY_LOCAL_REL} supplies the personal override" "$PERSONAL_YAML"
        else
          LAYERS+=("$personal_override")
          old_location "$personal_override" "still read as the personal override" "$PERSONAL_YAML"
        fi
      fi
      if convention_key_tracked "$REPO_ROOT" "$CONVENTION_KEY_YAML_REL"; then
        LAYERS+=("$TEAM_YAML")
      elif [[ -e "$TEAM_YAML" ]]; then
        note "${CONVENTION_KEY_YAML_REL} is not tracked by git, so it is not a config layer"
      fi
      ;;
  esac
fi
if [[ -n "${HOME:-}" && -f "$USER_LAYER" ]]; then
  LAYERS+=("$USER_LAYER")
  old_location "$USER_LAYER" "still read as the lowest layer" \
    "${CONVENTION_KEY_YAML_REL} (team) or ${CONVENTION_KEY_LOCAL_REL} (personal) in each repository that needs it"
fi

# The layer a resolved pattern came from, as reported by --explain.
layer_label() {
  case "$1" in
    "${TEAM_YAML:-}") echo "$CONVENTION_KEY_YAML_REL" ;;
    "${PERSONAL_YAML:-}") echo "$CONVENTION_KEY_LOCAL_REL" ;;
    "${personal_override:-}") echo "old personal override ${CONVENTION_KEY_OLD_LOCAL_REL}" ;;
    "$USER_LAYER") echo "old user-global .claude/source-control.md in the home directory" ;;
    *) echo "$1" ;;
  esac
}

PATTERN="" SOURCE="" LABEL=""
for layer in ${LAYERS[@]+"${LAYERS[@]}"}; do
  if [[ "$layer" == "${TEAM_YAML:-}" || "$layer" == "${PERSONAL_YAML:-}" ]]; then
    rel="$CONVENTION_KEY_YAML_REL"
    [[ "$layer" == "${PERSONAL_YAML:-}" ]] && rel="$CONVENTION_KEY_LOCAL_REL"
    value="$(convention_key_yaml_value "$REPO_ROOT" "$KEY" "$rel")"
    rc=$?
    if [[ "$rc" -ne 0 ]]; then
      note "${rel} could not be parsed; ${STOP}"
      exit 1
    fi
  else
    value="$(section_value "$layer")" || exit 1
  fi
  [[ -n "$value" ]] || continue
  usable_pattern "$layer" "$value" "$STOP" || exit 1
  PATTERN="$value" SOURCE="$layer" LABEL="$(layer_label "$layer")"
  break
done

if [[ -z "$PATTERN" ]]; then
  # A surviving literal `${user_config...}` placeholder means the key is unset;
  # treat it as absent so the default applies rather than a bogus pattern.
  LEGACY="${2:-}"
  # shellcheck disable=SC2016  # matching the literal placeholder text, not expanding it
  [[ "$LEGACY" == *'${user_config'* ]] && LEGACY=""
  [[ -n "$LEGACY" ]] || LEGACY="${CLAUDE_PLUGIN_OPTION_BRANCH_ISSUE_PATTERN:-}"
  if [[ -n "$LEGACY" ]] && usable_pattern userConfig "$LEGACY" "ignored, default applies"; then
    PATTERN="$LEGACY" SOURCE="userConfig" LABEL="userConfig"
    note "the ${KEY} userConfig is deprecated; set ${KEY} in ${CONVENTION_KEY_YAML_REL} instead."
  fi
fi
if [[ -z "$PATTERN" && "${3:-}" == "--no-default" ]]; then
  exit 3
fi
[[ -n "$PATTERN" ]] || PATTERN='^[a-z]+/(routine-issue-)?([0-9]+)-' SOURCE="default" LABEL="default"
[[ "$EXPLAIN" -eq 0 ]] || note "${KEY} layer: ${LABEL}"

[[ "$BRANCH" =~ $PATTERN ]] || exit 1

# Issue id = the last (rightmost) capture group, so the default pattern's
# optional leading group still resolves to the trailing number, and a custom
# single-group pattern resolves to its one group.
n=${#BASH_REMATCH[@]}
if [[ "$n" -lt 2 ]]; then
  note "${SOURCE}: ${KEY} has no capture group; no issue id emitted"
  exit 1
fi
id="${BASH_REMATCH[n - 1]}"
if [[ ! "$id" =~ ^([0-9]+|[A-Za-z][A-Za-z0-9_]*-[0-9]+)$ ]]; then
  note "${SOURCE}: ${KEY} captured a non-numeric id that is not a tracker key either; no issue id emitted"
  exit 1
fi
echo "$id"
