#!/usr/bin/env bash
# Comment-residue findings for /comment-residue. Read-only.
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
TARGETS=()

usage() {
  cat <<'EOF'
detect.sh — emit comment-residue findings for /comment-residue.

Usage:
  detect.sh <file>...
  detect.sh --paths-file <file>
  detect.sh --help

Audits code files only (markdown is /audit-noise's territory and is skipped).
When no paths are given, audits the uncommitted code files of the repository
it runs in (from git status). Exit: 0 on audit, 2 on unknown arguments.
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

repo_root="$(git rev-parse --show-toplevel 2>/dev/null | tr -d '\r')"
if [[ -n "$repo_root" ]]; then
  cd "$repo_root" 2>/dev/null || true
fi

if [[ ${#TARGETS[@]} -eq 0 ]]; then
  if [[ -n "$PATHS_FILE" ]]; then
    while IFS= read -r line || [[ -n "$line" ]]; do
      line="${line//$'\r'/}"
      [[ -z "$line" ]] && continue
      TARGETS+=("$(cr_anchor_path "$line")")
    done <"$PATHS_FILE"
  elif [[ -n "$repo_root" ]]; then
    # Uncommitted files: modified/added/renamed/untracked, per git status.
    while IFS= read -r line; do
      line="${line//$'\r'/}"
      [[ -z "$line" ]] && continue
      TARGETS+=("$line")
    done < <(git status --porcelain 2>/dev/null | awk '{print $NF}')
  fi
fi

# Expand directory targets to the files inside them (recursive); filter every target down to
# code files (markdown is /audit-noise's job, so a .md target is silently skipped).
EXPANDED=()
for target in ${TARGETS[@]+"${TARGETS[@]}"}; do
  if [[ -d "$target" ]]; then
    while IFS= read -r f; do
      cr_is_code_file "$f" && EXPANDED+=("$f")
    done < <(find "$target" -type f 2>/dev/null)
  elif cr_is_code_file "$target"; then
    EXPANDED+=("$target")
  fi
done
TARGETS=(${EXPANDED[@]+"${EXPANDED[@]}"})

if [[ ${#TARGETS[@]} -eq 0 ]]; then
  echo "Summary total: files=0 T1=0 T2=0 T3=0"
  echo "Note: no code targets — pass code file paths or edit some tracked code files"
  exit 0
fi

mapfile -t SORTED < <(printf '%s\n' "${TARGETS[@]}" | LC_ALL=C sort -u)

total_t1=0 total_t2=0 total_t3=0 files_audited=0

audit_file() {
  local file="$1"
  [[ -f "$file" ]] || return 0
  files_audited=$((files_audited + 1))

  local t1=0 t2=0 t3=0
  local prev_line="" line_num=0 shapes shape tier excerpt

  while IFS= read -r line || [[ -n "$line" ]]; do
    line_num=$((line_num + 1))
    if cr_line_skipped "$prev_line" "$line"; then
      prev_line="$line"
      continue
    fi
    shapes="$(cr_detect_shapes "$line" || true)"
    if [[ -n "$shapes" ]]; then
      excerpt="$(cr_trim_excerpt "$line")"
      while IFS= read -r shape; do
        [[ -z "$shape" ]] && continue
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
      done <<<"$shapes"
    fi
    prev_line="$line"
  done <"$file"

  printf 'Summary file: %s | T1=%s T2=%s T3=%s\n' "$file" "$t1" "$t2" "$t3"
}

for file in "${SORTED[@]}"; do
  audit_file "$file"
done

printf 'Summary total: files=%s T1=%s T2=%s T3=%s\n' "$files_audited" "$total_t1" "$total_t2" "$total_t3"
exit 0
