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
  echo "Summary total: files=0 T1=0 T2=0 T3=0"
  echo "Note: no markdown targets — pass file paths or edit some .md files"
  exit 0
fi

mapfile -t SORTED < <(printf '%s\n' "${TARGETS[@]}" | LC_ALL=C sort -u)

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
  echo "Summary total: files=0 T1=0 T2=0 T3=0"
  echo "Note: chunk offset/limit selected no targets"
  exit 0
fi

# Hoist convention-root resolution once per run (also repairs F6: contract
# root must survive into the ghost-ref exemption check).
AUDIT_NOISE_REPO_ROOT="${AUDIT_NOISE_REPO_ROOT:-${repo_root:-.}}"
audit_noise_resolve_convention_roots

total_t1=0 total_t2=0 total_t3=0 files_audited=0

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
  local -a shapes=()
  local shape tier excerpt line heading_text
  local fence_delim fence_dchar fence_dlen

  while IFS= read -r line || [[ -n "$line" ]]; do
    line_num=$((line_num + 1))

    # YAML frontmatter: opening --- on line 1 (or immediately after a BOM-less
    # blank? — SKILL exempts frontmatter; require the conventional start).
    if [[ $line_num -eq 1 && "$line" == '---' ]]; then
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
      fence_delim="${BASH_REMATCH[1]}"
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
      heading_text="${BASH_REMATCH[2]}"
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
      skip_next=1
      continue
    fi
    if audit_noise_is_ignore_para_marker "$line"; then
      in_ignored_para=1
      continue
    fi
    if [[ -z "${line//[[:space:]]/}" ]]; then
      in_ignored_para=0
    fi
    if [[ $in_exempt -eq 1 || $in_ignored_para -eq 1 || $skip_next -eq 1 ]]; then
      skip_next=0
      continue
    fi
    # Hot path: nameref APIs only — no per-line command substitutions.
    # Shape helpers unwrap/strip inline code internally (ghost-ref vs others).
    if audit_noise_detect_shapes_into shapes "$line"; then
      audit_noise_trim_excerpt "$line" excerpt
      for shape in "${shapes[@]}"; do
        [[ -z "$shape" ]] && continue
        audit_noise_shape_tier_into "$shape" tier
        printf 'File: %s\n' "$file"
        printf 'Finding tier: %s\n' "$tier"
        printf 'Finding shape: %s\n' "$shape"
        printf 'Finding line: %s\n' "$line_num"
        printf 'Finding excerpt: %s\n' "$excerpt"
        # The fired prohibition travels with the finding so the relay writer
        # reports the marker from the sentence that actually triggered. Keeping
        # it here leaves ONE implementation of the sentence walk; re-deriving it
        # in the writer would be a second copy free to drift from this one.
        if [[ "$shape" == 'negation' && -n "${AUDIT_NOISE_FIRED_MARKER:-}" ]]; then
          printf 'Finding marker: %s\n' "$AUDIT_NOISE_FIRED_MARKER"
        fi
        printf '%s\n' '---'
        case "$tier" in
        1) t1=$((t1 + 1)) total_t1=$((total_t1 + 1)) ;;
        2) t2=$((t2 + 1)) total_t2=$((total_t2 + 1)) ;;
        *) t3=$((t3 + 1)) total_t3=$((total_t3 + 1)) ;;
        esac
      done
    fi
  done <"$file"

  printf 'Summary file: %s | T1=%s T2=%s T3=%s\n' "$file" "$t1" "$t2" "$t3"
}

for file in "${SORTED[@]}"; do
  audit_file "$file"
done

printf 'Summary total: files=%s T1=%s T2=%s T3=%s\n' "$files_audited" "$total_t1" "$total_t2" "$total_t3"
exit 0
