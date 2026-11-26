#!/usr/bin/env bash
set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/noise-shapes.sh
source "$SCRIPT_DIR/lib/noise-shapes.sh"
# shellcheck source=lib/opt-value.sh
source "$SCRIPT_DIR/lib/opt-value.sh"

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

while [[ $# -gt 0 ]]; do
  case "$1" in
  --paths-file)
    require_opt_value "detect.sh" "$@"
    PATHS_FILE="$2"
    shift 2
    ;;
  --offset)
    require_opt_value "detect.sh" "$@"
    OFFSET="$2"
    shift 2
    ;;
  --limit)
    require_opt_value "detect.sh" "$@"
    LIMIT="$2"
    shift 2
    ;;
  -h | --help)
    usage
    exit 0
    ;;
  --)
    shift
    TARGETS+=("$@")
    break
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

if [[ ! "$OFFSET" =~ ^[0-9]+$ || ! "$LIMIT" =~ ^[0-9]+$ ]]; then
  echo "detect.sh: --offset and --limit require non-negative integers" >&2
  exit 2
fi
OFFSET=$((10#$OFFSET))
LIMIT=$((10#$LIMIT))

repo_root="$(git rev-parse --show-toplevel 2>/dev/null | tr -d '\r')"

resolve_existing_path() {
  local raw="$1"
  [[ "$raw" == /* ]] || raw="$PWD/$raw"
  printf '%s' "$raw"
}

if [[ ${#TARGETS[@]} -eq 0 ]]; then
  if [[ -n "$PATHS_FILE" ]]; then
    while IFS= read -r line || [[ -n "$line" ]]; do
      line="${line//$'\r'/}"
      [[ -z "$line" ]] && continue
      TARGETS+=("$(resolve_existing_path "$line")")
    done <"$PATHS_FILE"
  elif [[ -n "$repo_root" ]]; then
    while IFS= read -r -d '' record; do
      [[ -z "$record" ]] && continue
      local_path="${record:3}"
      if [[ "${record:0:1}" == [RC] || "${record:1:1}" == [RC] ]]; then
        IFS= read -r -d '' _rename_origin || true
      fi
      [[ "$local_path" == *.md ]] || continue
      TARGETS+=("$local_path")
    # With -z, git status prints pathnames as is, without quoting.
    # https://git-scm.com/docs/git-status
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

no_targets() {
  echo "status: no-targets"
  echo "Summary total: files=0 T1=0 T2=0 T3=0"
  echo "Note: $1"
  exit 0
}

if [[ ${#TARGETS[@]} -eq 0 ]]; then
  no_targets "no markdown targets — pass file paths or edit some .md files"
fi

mapfile -d '' -t SORTED < <(printf '%s\0' "${TARGETS[@]}" | LC_ALL=C sort -uz)

if [[ "$LIMIT" -gt 0 ]]; then
  SORTED=("${SORTED[@]:OFFSET:LIMIT}")
elif [[ "$OFFSET" -gt 0 ]]; then
  SORTED=("${SORTED[@]:OFFSET}")
fi

if [[ ${#SORTED[@]} -eq 0 ]]; then
  no_targets "chunk offset/limit selected no targets"
fi

total_t1=0 total_t2=0 total_t3=0 files_audited=0

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
  # _rows is a nameref to the caller's array; assigning it is not a scalar overwrite.
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
  [[ "${file##*/}" == "CHANGELOG.md" ]] && return 0
  files_audited=$((files_audited + 1))

  local owner_routed=0 file_dir="/."
  [[ "$file" == */* ]] && file_dir="/${file%/*}"
  if [[ "${file##*/}" == "SKILL.md" || "$file_dir" == */agents ]]; then
    owner_routed=1
  fi

  local t1=0 t2=0 t3=0
  local in_exempt=0 line_num=0
  local in_ignored_para=0 skip_next=0
  local in_frontmatter=0 in_fence=0
  local fence_char="" fence_len=0
  # finding_rows is written via nameref in audit_noise_record_finding.
  # shellcheck disable=SC2034
  local -a shapes=() finding_rows=()
  local shape excerpt line heading_text trimmed uwrapped
  local fence_delim fence_dchar fence_dlen
  local is_heading=0
  local list_item_re='^[[:space:]]*([-*+]|[0-9]+[.)])[[:space:]]'
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

    if [[ "$line" =~ ^(\`{3,}|~{3,}) ]]; then
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

    if [[ "$line" =~ ^(#{1,6})[[:space:]]+(.*)$ ]]; then
      heading_text="${BASH_REMATCH[2]}"
      flush_negation
      is_heading=1
      heading_text="${heading_text%%$'\r'*}"
      if audit_noise_section_exempt "$heading_text"; then
        in_exempt=1
      else
        in_exempt=0
      fi
      in_ignored_para=0
    fi
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
    if audit_noise_detect_shapes_into shapes "$line" "skip-negation"; then
      audit_noise_trim_excerpt "$line" excerpt
      for shape in "${shapes[@]}"; do
        [[ -z "$shape" ]] && continue
        [[ $owner_routed -eq 1 && "$shape" == 'ticket-pr-residue' ]] && continue
        audit_noise_record_finding "$line_num" "$shape" "$excerpt" "" \
          finding_rows t1 t2 t3
      done
    fi

    if [[ -z "${line//[[:space:]]/}" ]]; then
      continue
    fi
    if [[ "$line" =~ $list_item_re ]] && [[ ${#neg_line_nums[@]} -gt 0 ]]; then
      flush_negation
    fi
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
