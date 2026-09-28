#!/usr/bin/env bash
# Parse the (numeric GitHub) issue number from a branch name. The default
# convention is `<type>/<N>-<slug>` (or the cloud-routine variant
# `<type>/routine-issue-<N>-<slug>`), but the grammar is configurable so a
# consumer whose branches place the number differently, e.g. a username-scoped
# scheme `alice/1234-slug` or a trailing-number scheme `feat/add-widget-1234`,
# is not silently unparsable.
#
# Usage:
#   parse-branch-issue.sh [branch-name] [pattern]
#
# With no branch arg, falls back to `git branch --show-current`.
# The grammar is an ERE whose LAST capture group holds the issue id; it must
# resolve to the numeric GitHub issue number (the caller emits `Closes #<id>`,
# which GitHub honors only for a numeric issue in this repo). A pattern with
# no capture group, or a capture that is not all digits, yields no output and
# exit 1. It resolves, first hit wins:
#   1. The `## branch_issue_pattern` section of the layered
#      `.claude/source-control.md` surface (reference/config-resolution.md):
#      `<repo>/.claude/source-control.local.md` over
#      `<repo>/.claude/source-control.md` over `$HOME/.claude/source-control.md`.
#      The value is the section's first non-blank line, surrounding backticks
#      stripped, or, when that line opens a code fence, the first non-blank line
#      inside the fence. Headings inside fenced blocks are ignored. A leading
#      UTF-8 BOM, trailing whitespace, and a closing `#` sequence on the heading
#      are accepted. Repo root: CLAUDE_PROJECT_DIR, else
#      `git rev-parse --show-toplevel`. When that root is the home directory
#      (or an ancestor of it), team and overlay layers are not applicable: the
#      team path would be the same file as user-global. Overlay is skipped the
#      same way. A team or overlay path that physically equals the user-global
#      file is skipped even when the root is not home.
#   2. The deprecated branch_issue_pattern userConfig: `pattern` (unless it is the
#      literal `${user_config...}` placeholder), then
#      CLAUDE_PLUGIN_OPTION_BRANCH_ISSUE_PATTERN. Using it prints a deprecation
#      note on stderr.
#   3. The built-in default.
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
# Prints the captured issue id on stdout and exits 0 on match.
# Exits 1 with no stdout if the branch does not match.
set -uo pipefail

KEY="branch_issue_pattern"

BRANCH="${1:-}"
if [[ -z "$BRANCH" ]]; then
  BRANCH="$(git branch --show-current 2>/dev/null || true)"
fi

if [[ -z "$BRANCH" ]]; then
  exit 1
fi

# Notes name the source and the reason only, never the pattern text, so a
# repo-controlled value is not echoed into the caller's context.
note() { echo "parse-branch-issue: $*" >&2; }

# True when two paths name the same file or directory. Existing directories
# compare via `pwd -P` (case-folded) so a native `C:/Users/<user>` and an MSYS
# `/c/Users/<user>` of the same home still match. Existing files compare by that
# physical parent plus the leaf. Missing paths compare after slash-folding,
# trailing-slash strip, and case-fold. Empty is never equal to anything.
# Never `cd` a file: that prints "Not a directory" on stderr.
paths_same() {
  local a="$1" b="$2" ap bp ad bd al bl
  [[ -n "$a" && -n "$b" ]] || return 1
  if [[ -d "$a" && -d "$b" ]]; then
    if ap=$(cd "$a" 2>/dev/null && pwd -P) && bp=$(cd "$b" 2>/dev/null && pwd -P); then
      [[ "${ap,,}" == "${bp,,}" ]] && return 0
    fi
  elif [[ -f "$a" || -f "$b" ]]; then
    ad=$(cd "$(dirname -- "$a")" 2>/dev/null && pwd -P) || ad=""
    bd=$(cd "$(dirname -- "$b")" 2>/dev/null && pwd -P) || bd=""
    al="${a##*/}"; al="${al,,}"
    bl="${b##*/}"; bl="${bl,,}"
    [[ -n "$ad" && -n "$bd" && "${ad,,}" == "${bd,,}" && "$al" == "$bl" ]] && return 0
  fi
  a="${a//\\//}"; a="${a%/}"; a="${a,,}"
  b="${b//\\//}"; b="${b%/}"; b="${b,,}"
  [[ "$a" == "$b" ]]
}

# True when ROOT is $HOME or an ancestor of $HOME. A session started in home
# (machine maintenance, user-scope config) must not read ~/.claude/<surface>
# as the team layer.
root_is_home_or_ancestor() {
  local root="$1" home="${HOME:-}" rp hp
  [[ -n "$root" && -n "$home" ]] || return 1
  paths_same "$root" "$home" && return 0
  rp=$(cd "$root" 2>/dev/null && pwd -P) || rp="$root"
  hp=$(cd "$home" 2>/dev/null && pwd -P) || hp="$home"
  rp="${rp//\\//}"; rp="${rp%/}"; rp="${rp,,}"
  hp="${hp//\\//}"; hp="${hp%/}"; hp="${hp,,}"
  [[ "$hp" == "$rp"/* ]]
}

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
  local src="$1" value="$2" outcome="$3" rc limit
  limit="$(pattern_limit "$value")"
  if [[ -n "$limit" ]]; then
    note "${src}: ${KEY} ${limit}; ${outcome}"
    return 1
  fi
  if [[ "$value" =~ \\[1-9] ]]; then
    note "${src}: ${KEY} uses a backreference, which is not allowed; ${outcome}"
    return 1
  fi
  { [[ "" =~ $value ]]; } 2>/dev/null
  rc=$?
  if [[ "$rc" -eq 2 ]]; then
    note "${src}: ${KEY} is an invalid ERE; ${outcome}"
    return 1
  fi
  return 0
}

REPO_ROOT="${CLAUDE_PROJECT_DIR:-}"
[[ -n "$REPO_ROOT" ]] || REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || true)"

LAYERS=()
USER_LAYER="${HOME:-}/.claude/source-control.md"
if [[ -n "$REPO_ROOT" ]] && ! root_is_home_or_ancestor "$REPO_ROOT"; then
  overlay="${REPO_ROOT}/.claude/source-control.local.md"
  team="${REPO_ROOT}/.claude/source-control.md"
  paths_same "$overlay" "$USER_LAYER" || LAYERS+=("$overlay")
  paths_same "$team" "$USER_LAYER" || LAYERS+=("$team")
elif [[ -n "$REPO_ROOT" ]]; then
  note "team and overlay not applicable: project root is the home directory (or an ancestor of it)"
fi
LAYERS+=("$USER_LAYER")

PATTERN="" SOURCE=""
for layer in "${LAYERS[@]}"; do
  value="$(section_value "$layer")" || exit 1
  [[ -n "$value" ]] || continue
  usable_pattern "$layer" "$value" "$STOP" || exit 1
  PATTERN="$value" SOURCE="$layer"
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
    PATTERN="$LEGACY" SOURCE="userConfig"
    note "the ${KEY} userConfig is deprecated; set a \`## ${KEY}\` section in .claude/source-control.md instead."
  fi
fi
[[ -n "$PATTERN" ]] || PATTERN='^[a-z]+/(routine-issue-)?([0-9]+)-' SOURCE="default"

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
if [[ ! "$id" =~ ^[0-9]+$ ]]; then
  note "${SOURCE}: ${KEY} captured a non-numeric id; no issue id emitted"
  exit 1
fi
echo "$id"
