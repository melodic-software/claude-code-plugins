#!/usr/bin/env bash
# Noise findings for /audit-noise. Read-only.
#
# Output: File, Finding tier/shape/line/excerpt; Summary lines.
# Exit: always 0 on audit paths — a read-only audit must never fail the caller,
# so -e is omitted; 2 on unknown arguments.
set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/noise-shapes.sh
source "$SCRIPT_DIR/lib/noise-shapes.sh"

PATHS_FILE=""
TARGETS=()
OFFSET=0
LIMIT=0

usage() {
  cat <<'EOF'
detect.sh — emit markdown noise findings for /audit-noise.

Usage:
  detect.sh <file.md>...
  detect.sh --paths-file <file>
  detect.sh --offset N --limit N   # chunk affordance over the sorted target list
  detect.sh --help

When no paths are given, audits the uncommitted .md files of the repository
it runs in (from git status). Exit: 0 on audit, 2 on unknown arguments.

--offset / --limit slice the sorted unique target list after directory
expansion (0-based offset; limit 0 means no cap). Repo-wide orchestration can
invoke one detect.sh process per chunk without a per-file shell loop.
EOF
}

require_opt_value() {
  local opt="$1"
  if [[ $# -lt 2 || -z "${2:-}" || "$2" == -* ]]; then
    echo "detect.sh: $opt requires a value" >&2
    exit 2
  fi
}

while [[ $# -gt 0 ]]; do
  case "$1" in
  --paths-file)
    require_opt_value "$@"
    PATHS_FILE="$2"
    shift 2
    ;;
  --offset)
    require_opt_value "$@"
    OFFSET="$2"
    shift 2
    ;;
  --limit)
    require_opt_value "$@"
    LIMIT="$2"
    shift 2
    ;;
  -h | --help)
    usage
    exit 0
    ;;
  --)
    shift
    while [[ $# -gt 0 ]]; do
      TARGETS+=("$1")
      shift
    done
    ;;
  -*)
    echo "detect.sh: unknown arg '$1'" >&2
    exit 2
    ;;
  *)
    TARGETS+=("$1")
    shift
    ;;
  esac
done

# Reject non-integer offset/limit early (unknown-arg class → exit 2).
if [[ ! "$OFFSET" =~ ^[0-9]+$ || ! "$LIMIT" =~ ^[0-9]+$ ]]; then
  echo "detect.sh: --offset and --limit require non-negative integers" >&2
  exit 2
fi
# Strip leading zeros so values like 08 are decimal, not octal, under arithmetic.
OFFSET=$((10#$OFFSET))
LIMIT=$((10#$LIMIT))

repo_root="$(git rev-parse --show-toplevel 2>/dev/null | tr -d '\r')"

# Resolve relative CLI / paths-file targets against the caller's cwd BEFORE any
# cd into the repo root (F10: cd-before-target-resolution used to silently skip
# relative paths given from another working directory).
resolve_existing_path() {
  local raw="$1"
  if [[ "$raw" == /* ]]; then
    printf '%s' "$raw"
    return 0
  fi
  local abs
  abs="$(pwd)/$raw"
  printf '%s' "$abs"
}

if [[ ${#TARGETS[@]} -eq 0 ]]; then
  if [[ -n "$PATHS_FILE" ]]; then
    while IFS= read -r line || [[ -n "$line" ]]; do
      line="${line//$'\r'/}"
      [[ -z "$line" ]] && continue
      TARGETS+=("$(resolve_existing_path "$line")")
    done <"$PATHS_FILE"
  elif [[ -n "$repo_root" ]]; then
    # Uncommitted .md files: modified/added/renamed/untracked. Read the
    # NUL-delimited `-z` form, which git documents as performing no quoting and
    # no backslash-escaping: every byte of the path arrives verbatim, so there
    # is nothing left to unquote or decode. The v1 form C-quotes any path
    # holding a space, a quote, a backslash, or a non-ASCII/control byte, and a
    # parse that misses one of those escapes drops the file from the target list
    # silently — a clean run over a dirty tree.
    while IFS= read -r -d '' record; do
      [[ -z "$record" ]] && continue
      # XY + space + path. Under -z a rename/copy puts the NEW path in this
      # record and the ORIGINAL in a following record — the reverse of v1's
      # `old -> new` display order. Consume that second record and discard it,
      # or the audit targets a path that no longer exists. The rename is decided
      # by the status letter alone; no arrow ever appears under -z, so an
      # ordinary path containing " -> " cannot be mistaken for one.
      local_path="${record:3}"
      if [[ "${record:0:1}" == [RC] || "${record:1:1}" == [RC] ]]; then
        IFS= read -r -d '' _rename_origin || true
      fi
      [[ "$local_path" == *.md ]] || continue
      TARGETS+=("$local_path")
    done < <(git status --porcelain -z 2>/dev/null)
  fi
else
  RESOLVED=()
  for target in "${TARGETS[@]}"; do
    RESOLVED+=("$(resolve_existing_path "$target")")
  done
  TARGETS=("${RESOLVED[@]}")
fi

if [[ -n "$repo_root" ]]; then
  cd "$repo_root" 2>/dev/null || true
fi

# Expand directory targets to the .md files inside them (recursive), so
# `detect.sh <dir>` batch-audits instead of silently skipping non-files.
EXPANDED=()
for target in ${TARGETS[@]+"${TARGETS[@]}"}; do
  if [[ -d "$target" ]]; then
    while IFS= read -r md; do
      EXPANDED+=("$md")
    done < <(find "$target" -type f -name '*.md' 2>/dev/null)
  else
    EXPANDED+=("$target")
  fi
done
TARGETS=(${EXPANDED[@]+"${EXPANDED[@]}"})

if [[ ${#TARGETS[@]} -eq 0 ]]; then
  echo "status: no-targets"
  echo "Summary total: files=0 T1=0 T2=0 T3=0"
  echo "Note: no markdown targets — pass file paths or edit some .md files"
  exit 0
fi

# Keep NUL delimiters through sort/dedup so a path that itself contains a
# newline (a control byte the -z read just recovered) is not split into two
# nonexistent targets.
mapfile -d '' -t SORTED < <(printf '%s\0' "${TARGETS[@]}" | LC_ALL=C sort -uz)

# Chunk affordance: slice the sorted list so a parent can fan out without a
# per-file shell loop (hook-bypass-safe single process per chunk).
if [[ "$OFFSET" -gt 0 || "$LIMIT" -gt 0 ]]; then
  CHUNKED=()
  idx=0
  for file in "${SORTED[@]}"; do
    if [[ "$idx" -ge "$OFFSET" ]]; then
      if [[ "$LIMIT" -eq 0 || ${#CHUNKED[@]} -lt "$LIMIT" ]]; then
        CHUNKED+=("$file")
      else
        break
      fi
    fi
    idx=$((idx + 1))
  done
  SORTED=(${CHUNKED[@]+"${CHUNKED[@]}"})
fi

if [[ ${#SORTED[@]} -eq 0 ]]; then
  echo "status: no-targets"
  echo "Summary total: files=0 T1=0 T2=0 T3=0"
  echo "Note: chunk offset/limit selected no targets"
  exit 0
fi

# Hoist convention-root resolution once per run (also repairs F6: contract
# root must survive into the ghost-ref exemption check).
AUDIT_NOISE_REPO_ROOT="${AUDIT_NOISE_REPO_ROOT:-${repo_root:-.}}"
audit_noise_resolve_convention_roots

total_t1=0 total_t2=0 total_t3=0 files_audited=0

# Record one finding into a nameref array as a US-delimited row so the file
# can emit in line-number order after paragraph-scoped negation is flushed.
audit_noise_record_finding() {
  local at_line="$1" shape="$2" excerpt="$3" marker="${4:-}"
  local -n _rows="$5"
  local -n _t1="$6" _t2="$7" _t3="$8"
  local tier=""
  audit_noise_shape_tier_into "$shape" tier
  _rows+=("${at_line}"$'\x1f'"${tier}"$'\x1f'"${shape}"$'\x1f'"${excerpt}"$'\x1f'"${marker}")
  case "$tier" in
  1) _t1=$((_t1 + 1)) total_t1=$((total_t1 + 1)) ;;
  2) _t2=$((_t2 + 1)) total_t2=$((total_t2 + 1)) ;;
  *) _t3=$((_t3 + 1)) total_t3=$((total_t3 + 1)) ;;
  esac
}

audit_noise_print_findings() {
  local file="$1"
  # nameref to the caller's finding_rows; the string assignment is the name,
  # not a scalar overwrite of the array.
  # shellcheck disable=SC2178
  local -n _rows="$2"
  local at_line tier shape excerpt marker
  ((${#_rows[@]})) || return 0
  while IFS=$'\x1f' read -r at_line tier shape excerpt marker; do
    printf 'File: %s\n' "$file"
    printf 'Finding tier: %s\n' "$tier"
    printf 'Finding shape: %s\n' "$shape"
    printf 'Finding line: %s\n' "$at_line"
    printf 'Finding excerpt: %s\n' "$excerpt"
    if [[ "$shape" == 'negation' && -n "$marker" ]]; then
      printf 'Finding marker: %s\n' "$marker"
    fi
    printf '%s\n' '---'
  done < <(printf '%s\n' "${_rows[@]}" | LC_ALL=C sort -t$'\x1f' -k1,1n)
}

audit_file() {
  local file="$1"
  [[ -f "$file" ]] || return 0
  # CHANGELOG.md entries are exempt per SKILL.md hard rules — skip by basename
  # so a changelog in a target list never emits findings.
  [[ "${file##*/}" == "CHANGELOG.md" ]] && return 0
  files_audited=$((files_audited + 1))

  local t1=0 t2=0 t3=0
  local in_exempt=0 line_num=0
  local in_ignored_para=0 skip_next=0
  local in_frontmatter=0 in_fence=0
  local fence_char="" fence_len=0
  # finding_rows is written via nameref in audit_noise_record_finding.
  # shellcheck disable=SC2034
  local -a shapes=() finding_rows=()
  local shape tier excerpt line heading_text
  local fence_delim fence_dchar fence_dlen
  local is_heading=0
  # Negation is paragraph-scoped: accumulate soft-wrapped lines, then classify.
  # Other shapes stay line-scoped. Attribution is the first physical line of
  # the triggering sentence — that is where the cue opens, so the fix action
  # lands on the instruction's start rather than its wrap continuation.
  # Offsets are tracked on the UNWRAPPED join so inline backticks cannot shift
  # attribution onto an earlier line.
  local neg_unwrapped=""
  local -a neg_line_nums=() neg_line_texts=() neg_offsets=()

  reset_negation() {
    neg_unwrapped=""
    neg_line_nums=()
    neg_line_texts=()
    neg_offsets=()
  }

  flush_negation() {
    local sentences=() s idx offset attr_line attr_excerpt sentence_off
    local cursor=0 rest prefix_in_rest
    [[ -n "${neg_unwrapped//[[:space:]]/}" ]] || {
      reset_negation
      return 0
    }
    # Every qualifying sentence in the paragraph is a finding. Returning after
    # the first would drop a later imperative on its own physical line.
    # Walk a cursor so two identical sentences attribute to their own lines:
    # `${var%%"$s"*}` always anchors at the earliest match.
    audit_noise_split_sentences_into sentences "$neg_unwrapped"
    for s in "${sentences[@]}"; do
      rest="${neg_unwrapped:cursor}"
      prefix_in_rest="${rest%%"${s}"*}"
      sentence_off=$cursor
      if [[ "$prefix_in_rest" != "$rest" ]]; then
        sentence_off=$((cursor + ${#prefix_in_rest}))
        cursor=$((sentence_off + ${#s}))
      fi
      audit_noise_line_has_negation_without_positive "$s" "paragraph" || continue
      attr_line="${neg_line_nums[0]}"
      attr_excerpt=""
      idx=0
      for offset in "${neg_offsets[@]}"; do
        if [[ $offset -le $sentence_off ]]; then
          attr_line="${neg_line_nums[idx]}"
          audit_noise_trim_excerpt "${neg_line_texts[idx]}" attr_excerpt
        fi
        idx=$((idx + 1))
      done
      [[ -n "$attr_excerpt" ]] || audit_noise_trim_excerpt "${neg_line_texts[0]}" attr_excerpt
      audit_noise_record_finding "$attr_line" "negation" "$attr_excerpt" \
        "${AUDIT_NOISE_FIRED_MARKER:-}" finding_rows t1 t2 t3
    done
    reset_negation
  }

  while IFS= read -r line || [[ -n "$line" ]]; do
    line_num=$((line_num + 1))
    is_heading=0

    # YAML frontmatter: opening --- on line 1 (or immediately after a BOM-less
    # blank? — SKILL exempts frontmatter; require the conventional start).
    if [[ $line_num -eq 1 && "$line" == '---' ]]; then
      flush_negation
      in_frontmatter=1
      continue
    fi
    if [[ $in_frontmatter -eq 1 ]]; then
      if [[ "$line" == '---' ]]; then
        in_frontmatter=0
      fi
      continue
    fi

    # Fenced code blocks (``` or ~~~): never scan fence lines or their body.
    # CommonMark closes a fence only with the same character at a run length
    # greater than or equal to the opener, so a four-backtick outer fence
    # wrapping a three-backtick example stays open through the inner close.
    # A bare toggle keyed on "line starts with 3+" treats the inner fence as
    # the outer close and then scans the remaining example as prose.
    if [[ "$line" =~ ^(\`{3,}|~{3,}) ]]; then
      # Capture before flushing: flush_negation runs its own [[ =~ ]] matches,
      # which overwrite BASH_REMATCH. Reading it afterwards aborts under set -u
      # whenever a fence closes a paragraph that had pending negation text.
      fence_delim="${BASH_REMATCH[1]}"
      flush_negation
      fence_dchar="${fence_delim:0:1}"
      fence_dlen=${#fence_delim}
      if [[ $in_fence -eq 0 ]]; then
        in_fence=1
        fence_char="$fence_dchar"
        fence_len=$fence_dlen
      elif [[ "$fence_dchar" == "$fence_char" && $fence_dlen -ge $fence_len ]]; then
        in_fence=0
        fence_char=""
        fence_len=0
      fi
      in_ignored_para=0
      continue
    fi
    if [[ $in_fence -eq 1 ]]; then
      continue
    fi

    # Any ATX heading level toggles section exemption (F7: ##-only toggles let
    # an exempt ## Sources followed by an H1 stay exempt to EOF, and ### Sources
    # was never recognized).
    if [[ "$line" =~ ^(#{1,6})[[:space:]]+(.*)$ ]]; then
      # Capture before flushing, for the same reason as the fence branch above.
      heading_text="${BASH_REMATCH[2]}"
      flush_negation
      is_heading=1
      heading_text="${heading_text%%$'\r'*}"
      if audit_noise_section_exempt "$heading_text"; then
        in_exempt=1
      else
        in_exempt=0
      fi
      # A heading ends any marker-ignored paragraph even without a preceding
      # blank line (unreachable in MD022-clean markdown; robustness only).
      in_ignored_para=0
    fi
    # Opt-out markers: require a well-formed HTML comment line (F4). Prose that
    # merely mentions the marker name must not act as a live marker. Order
    # matters: -line first.
    if audit_noise_is_ignore_line_marker "$line"; then
      flush_negation
      skip_next=1
      continue
    fi
    if audit_noise_is_ignore_para_marker "$line"; then
      flush_negation
      in_ignored_para=1
      continue
    fi
    if [[ -z "${line//[[:space:]]/}" ]]; then
      flush_negation
      in_ignored_para=0
    fi
    if [[ $in_exempt -eq 1 || $in_ignored_para -eq 1 || $skip_next -eq 1 ]]; then
      flush_negation
      skip_next=0
      continue
    fi
    # Hot path: nameref APIs only — no per-line command substitutions.
    # Shape helpers unwrap/strip inline code internally (ghost-ref vs others).
    # Negation is classified after paragraph accumulation, not here.
    if audit_noise_detect_shapes_into shapes "$line" "skip-negation"; then
      audit_noise_trim_excerpt "$line" excerpt
      for shape in "${shapes[@]}"; do
        [[ -z "$shape" ]] && continue
        audit_noise_record_finding "$line_num" "$shape" "$excerpt" "" \
          finding_rows t1 t2 t3
      done
    fi

    if [[ -z "${line//[[:space:]]/}" ]]; then
      continue
    fi
    # A new list item is its own block, not a soft-wrap continuation of the
    # previous item. Flush first so `- Do not use markdown` / `- Prefer HTML.`
    # cannot pair across items. Hold the regex in a variable so the unquoted
    # `)` in `[.)]` is not parsed as bash syntax.
    local list_item_re='^[[:space:]]*([-*+]|[0-9]+[.)])[[:space:]]'
    if [[ "$line" =~ $list_item_re ]] && [[ ${#neg_line_nums[@]} -gt 0 ]]; then
      flush_negation
    fi
    # Accumulate this physical line into the negation paragraph. Offsets are
    # taken on the unwrapped join so a backticked earlier line cannot pull
    # attribution forward. A heading is its own paragraph.
    local trimmed uwrapped=""
    trimmed="${line#"${line%%[![:space:]]*}"}"
    audit_noise_unwrap_backticks "$trimmed" uwrapped
    if [[ -n "$neg_unwrapped" ]]; then
      neg_unwrapped+=" "
    fi
    neg_offsets+=(${#neg_unwrapped})
    neg_unwrapped+="$uwrapped"
    neg_line_nums+=("$line_num")
    neg_line_texts+=("$line")
    if [[ $is_heading -eq 1 ]]; then
      flush_negation
    fi
  done <"$file"
  flush_negation
  audit_noise_print_findings "$file" finding_rows

  printf 'Summary file: %s | T1=%s T2=%s T3=%s\n' "$file" "$t1" "$t2" "$t3"
}

for file in "${SORTED[@]}"; do
  audit_file "$file"
done

if [[ "$files_audited" -eq 0 ]]; then
  echo "status: no-targets"
fi
printf 'Summary total: files=%s T1=%s T2=%s T3=%s\n' "$files_audited" "$total_t1" "$total_t2" "$total_t3"
exit 0
