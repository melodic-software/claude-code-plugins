#!/usr/bin/env bash
# Comment-residue findings for /audit-comment-residue. Read-only.
#
# Output: File, Finding tier/shape/line/excerpt; Summary lines.
# Exit: always 0 on audit paths — a read-only audit must never fail the caller,
# so -e is omitted; 2 on unknown arguments.
set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/comment-shapes.sh
source "$SCRIPT_DIR/lib/comment-shapes.sh"

# Where the caller invoked us. Explicit targets and --paths-file are relative to THIS, not to
# the repo root we cd into below, so they must be anchored here before the cd.
INVOCATION_CWD="$PWD"

# Anchor a caller-supplied path to the invocation cwd unless it is already absolute (POSIX or
# Windows drive-letter form), so relative targets survive the cd to the repo root.
cr_anchor_path() {
  case "$1" in
  /* | ?:[\\/]*) printf '%s' "$1" ;;
  *) printf '%s/%s' "$INVOCATION_CWD" "$1" ;;
  esac
}

PATHS_FILE=""
EXCLUDE_FILE=""
ADDED_SINCE=""
TARGETS=()

usage() {
  cat <<'EOF'
detect.sh — emit comment-residue findings for /audit-comment-residue.

Usage:
  detect.sh <file>...
  detect.sh --paths-file <file>
  detect.sh [--exclude-from <file>] [<file>...]
  detect.sh --added-since <base> [<file>...]
  detect.sh --help

Audits code files only (markdown is /audit-noise's territory and is skipped).
When no paths are given, audits the uncommitted code files of the repository
it runs in (from git status).

--exclude-from <file> skips targets matching a root-relative glob, one per line
(blank lines and lines starting with '#' are ignored) and reports how many.

--added-since <base> reports only comments on lines the branch adds against
the merge base of <base> and HEAD (added-lines.sh). With no paths it audits the
files that gained lines; with paths, only those of them that gained lines.

A file whose first 10 lines carry sync-managed, do not edit or @generated gets
a "Note: upstream" line before its summary. Exit: 0 on audit, 2 on unknown
arguments, a missing --exclude-from file, or a base added-lines.sh refuses.
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
  --paths-file)
    if [[ $# -lt 2 ]]; then
      echo "detect.sh: --paths-file requires a value" >&2
      exit 2
    fi
    PATHS_FILE="$2"
    shift 2
    ;;
  --exclude-from)
    if [[ $# -lt 2 ]]; then
      echo "detect.sh: --exclude-from requires a value" >&2
      exit 2
    fi
    EXCLUDE_FILE="$2"
    shift 2
    ;;
  --added-since)
    if [[ $# -lt 2 ]]; then
      echo "detect.sh: --added-since requires a value" >&2
      exit 2
    fi
    ADDED_SINCE="$2"
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

# Anchor caller-supplied paths to the invocation cwd BEFORE the cd, or they resolve against the
# repo root instead and silently miss (git-status discovery below stays repo-relative by design).
if [[ ${#TARGETS[@]} -gt 0 ]]; then
  ANCHORED=()
  for target in "${TARGETS[@]}"; do
    ANCHORED+=("$(cr_anchor_path "$target")")
  done
  TARGETS=("${ANCHORED[@]}")
fi
[[ -n "$PATHS_FILE" ]] && PATHS_FILE="$(cr_anchor_path "$PATHS_FILE")"
if [[ -n "$EXCLUDE_FILE" ]]; then
  EXCLUDE_FILE="$(cr_anchor_path "$EXCLUDE_FILE")"
  if [[ ! -f "$EXCLUDE_FILE" ]]; then
    echo "detect.sh: --exclude-from file not found: $EXCLUDE_FILE" >&2
    exit 2
  fi
fi

repo_root="$(git rev-parse --show-toplevel 2>/dev/null | tr -d '\r')"
if [[ -n "$repo_root" ]]; then
  cd "$repo_root" 2>/dev/null || true
fi

# --added-since: the added lines, keyed "<repo-relative path><TAB><line>", and the files
# that gained any. added-lines.sh prints `<start><TAB><count><TAB><path>`, path last.
declare -A ADDED_LINES=() ADDED_FILES=()
if [[ -n "$ADDED_SINCE" ]]; then
  if [[ -z "$repo_root" ]]; then
    echo "detect.sh: --added-since needs a git repository" >&2
    exit 2
  fi
  added_rows="$("$SCRIPT_DIR/added-lines.sh" "$ADDED_SINCE")" || exit 2
  while IFS=$'\t' read -r a_start a_count a_path; do
    [[ -z "$a_path" ]] && continue
    # Digits only before arithmetic: (( )) evaluates array subscripts, which run commands.
    if [[ ! "$a_start" =~ ^[0-9]+$ || ! "$a_count" =~ ^[0-9]+$ ]]; then
      echo "detect.sh: added-lines.sh printed a row that is not digits, tab, digits, tab, path" >&2
      exit 2
    fi
    ADDED_FILES["$a_path"]=1
    for ((a_line = a_start; a_line < a_start + a_count; a_line++)); do
      ADDED_LINES["$a_path"$'\t'"$a_line"]=1
    done
  done <<<"$added_rows"
  if [[ ${#TARGETS[@]} -eq 0 && -z "$PATHS_FILE" ]]; then
    for a_path in "${!ADDED_FILES[@]}"; do TARGETS+=("$a_path"); done
  fi
fi

# A target's path relative to the repository root, resolving symlinked directories so an
# anchored absolute path still matches added-lines.sh's repository-relative one.
cr_repo_rel() {
  local file="$1" dir
  case "$file" in
  /* | ?:[\\/]*)
    dir="$(cd "$(dirname "$file")" 2>/dev/null && pwd -P)" || dir="$(dirname "$file")"
    file="$dir/$(basename "$file")"
    printf '%s' "${file#"$repo_root"/}"
    ;;
  *) printf '%s' "${file#./}" ;;
  esac
}

if [[ ${#TARGETS[@]} -eq 0 ]]; then
  if [[ -n "$PATHS_FILE" ]]; then
    while IFS= read -r line || [[ -n "$line" ]]; do
      line="${line//$'\r'/}"
      [[ -z "$line" ]] && continue
      TARGETS+=("$(cr_anchor_path "$line")")
    done <"$PATHS_FILE"
  elif [[ -n "$repo_root" && -z "$ADDED_SINCE" ]]; then
    # Read the -z form, which git documents as unquoted and unescaped; the default output
    # C-escapes unusual paths beyond reliable splitting. Paths are already repo-relative.
    while IFS= read -r -d '' record; do
      [[ -z "$record" ]] && continue
      # A rename/copy emits the NEW path here and the ORIGINAL as the next record, so consume
      # and drop that second record rather than audit a path that no longer exists.
      case "${record:0:2}" in
      [RC]? | ?[RC]) IFS= read -r -d '' _ || true ;;
      *) ;;
      esac
      local_path="${record:3}"
      [[ -n "$local_path" ]] && TARGETS+=("$local_path")
    done < <(git status --porcelain -z 2>/dev/null)
  fi
fi

EXCLUDE_GLOBS=()
if [[ -n "$EXCLUDE_FILE" ]]; then
  while IFS= read -r line || [[ -n "$line" ]]; do
    line="${line//$'\r'/}"
    [[ -z "$line" || "$line" == '#'* ]] && continue
    EXCLUDE_GLOBS+=("$line")
  done <"$EXCLUDE_FILE"
fi
excluded=0

# True when the target, made root-relative, matches an --exclude-from glob.
cr_is_excluded() {
  local rel="$1" glob
  rel="${rel#"$repo_root"/}"
  rel="${rel#"$INVOCATION_CWD"/}"
  rel="${rel#./}"
  for glob in ${EXCLUDE_GLOBS[@]+"${EXCLUDE_GLOBS[@]}"}; do
    # shellcheck disable=SC2053
    [[ "$rel" == $glob ]] && return 0
  done
  return 1
}

cr_excluded_note() {
  [[ -n "$EXCLUDE_FILE" ]] && printf 'Note: excluded %s file(s) by --exclude-from\n' "$excluded"
  return 0
}

# Expand directory targets to the files inside them (recursive); filter every target down to
# code files (markdown is /audit-noise's job, so a .md target is silently skipped).
EXPANDED=()
for target in ${TARGETS[@]+"${TARGETS[@]}"}; do
  if [[ -d "$target" ]]; then
    while IFS= read -r f; do
      cr_is_code_file "$f" || continue
      if cr_is_excluded "$f"; then excluded=$((excluded + 1)); else EXPANDED+=("$f"); fi
    done < <(find "$target" -type f 2>/dev/null)
  elif cr_is_code_file "$target"; then
    if cr_is_excluded "$target"; then excluded=$((excluded + 1)); else EXPANDED+=("$target"); fi
  fi
done

# Under --added-since, a target that gained no lines has nothing in scope.
if [[ -n "$ADDED_SINCE" && ${#EXPANDED[@]} -gt 0 ]]; then
  IN_SCOPE=()
  for target in "${EXPANDED[@]}"; do
    [[ -n "${ADDED_FILES["$(cr_repo_rel "$target")"]:-}" ]] && IN_SCOPE+=("$target")
  done
  EXPANDED=(${IN_SCOPE[@]+"${IN_SCOPE[@]}"})
fi

if [[ ${#EXPANDED[@]} -eq 0 ]]; then
  echo "Summary total: files=0 T1=0 T2=0 T3=0"
  if [[ -n "$ADDED_SINCE" ]]; then
    echo "Note: no code file gained lines since the base"
  else
    echo "Note: no code targets — pass code file paths or edit some tracked code files"
  fi
  cr_excluded_note
  exit 0
fi

mapfile -t SORTED < <(printf '%s\n' "${EXPANDED[@]}" | LC_ALL=C sort -u)

total_t1=0 total_t2=0 total_t3=0 files_audited=0

# Print one finding and count it. Reads t1/t2/t3 from audit_file's frame (dynamic scope).
emit_finding() {
  local file="$1" shape="$2" line_num="$3" excerpt="$4" tier
  tier="$(cr_shape_tier "$shape")"
  printf 'File: %s\n' "$file"
  printf 'Finding tier: %s\n' "$tier"
  printf 'Finding shape: %s\n' "$shape"
  printf 'Finding line: %s\n' "$line_num"
  printf 'Finding excerpt: %s\n' "$excerpt"
  printf '%s\n' '---'
  case "$tier" in
  1) t1=$((t1 + 1)) total_t1=$((total_t1 + 1)) ;;
  2) t2=$((t2 + 1)) total_t2=$((total_t2 + 1)) ;;
  *) t3=$((t3 + 1)) total_t3=$((total_t3 + 1)) ;;
  esac
}

# Under --added-since, true when any named line of the file is an added line. Reads rel
# from audit_file's frame (dynamic scope). Always true without --added-since.
in_scope() {
  [[ -z "$ADDED_SINCE" ]] && return 0
  local l
  for l in "$@"; do
    [[ -n "${ADDED_LINES["$rel"$'\t'"$l"]:-}" ]] && return 0
  done
  return 1
}

audit_file() {
  local file="$1"
  [[ -f "$file" ]] || return 0
  files_audited=$((files_audited + 1))

  local t1=0 t2=0 t3=0
  local prev_line="" line_num=0 shapes shape excerpt
  local prev_ct="" prev_shapes="" ct joined

  # Pre-pass: every line of a comment run carrying a license cue is exempt from origin-note,
  # even when the cue sits on another line of the same NOTICE block.
  local -A license_block=() justified_run=()
  local n
  while IFS= read -r n; do
    [[ -n "$n" ]] && license_block["$n"]=1
  done < <(cr_license_block_lines "$file")
  # Likewise a workaround comment run is justified whole by a link or removal condition on
  # any of its lines.
  while IFS= read -r n; do
    [[ -n "$n" ]] && justified_run["$n"]=1
  done < <(cr_justified_run_lines "$file")

  local rel=""
  [[ -n "$ADDED_SINCE" ]] && rel="$(cr_repo_rel "$file")"

  # shellcheck disable=SC2094 # emit_finding only prints the file name; it never writes the file
  while IFS= read -r line || [[ -n "$line" ]]; do
    line_num=$((line_num + 1))
    if cr_line_skipped "$prev_line" "$line"; then
      prev_line="$line"
      prev_ct=""
      continue
    fi
    shapes="$(cr_detect_shapes "$line" "${license_block[$line_num]:-0}" "${justified_run[$line_num]:-0}" || true)"

    # A comment line that continues a comment on the line before it is also read joined to
    # that line, so a phrase wrapped across the break is found. Only a shape neither line
    # yields alone is new, and it is reported once, at the first line's number.
    ct=""
    if cr_is_comment_line "$line"; then
      ct="$(cr_comment_text "$line")"
      ct="${ct#"${ct%%[![:space:]]*}"}"
      ct="${ct%"${ct##*[![:space:]]}"}"
    fi
    if [[ -n "$ct" && -n "$prev_ct" ]] && in_scope $((line_num - 1)) "$line_num"; then
      joined="$(cr_trim_excerpt "$prev_ct $ct")"
      while IFS= read -r shape; do
        [[ -z "$shape" ]] && continue
        case $'\n'"$shapes"$'\n'"$prev_shapes"$'\n' in
        *$'\n'"$shape"$'\n'*) continue ;;
        *) ;;
        esac
        emit_finding "$file" "$shape" $((line_num - 1)) "$joined"
      done < <(cr_detect_shapes_text "$prev_ct $ct" "${license_block[$line_num]:-0}" "${justified_run[$line_num]:-0}" || true)
    fi

    if [[ -n "$shapes" ]] && in_scope "$line_num"; then
      excerpt="$(cr_trim_excerpt "$line")"
      while IFS= read -r shape; do
        [[ -z "$shape" ]] && continue
        emit_finding "$file" "$shape" "$line_num" "$excerpt"
      done <<<"$shapes"
    fi
    prev_line="$line"
    prev_ct="$ct"
    prev_shapes="$shapes"
  done <"$file"

  if ((t1 + t2 + t3 > 0)) && head -n 10 "$file" | grep -qiE 'sync-managed|do not edit|@generated'; then
    printf 'Note: upstream (sync-managed or generated file) %s\n' "$file"
  fi
  printf 'Summary file: %s | T1=%s T2=%s T3=%s\n' "$file" "$t1" "$t2" "$t3"
}

for file in "${SORTED[@]}"; do
  audit_file "$file"
done

cr_excluded_note
printf 'Summary total: files=%s T1=%s T2=%s T3=%s\n' "$files_audited" "$total_t1" "$total_t2" "$total_t3"
exit 0
