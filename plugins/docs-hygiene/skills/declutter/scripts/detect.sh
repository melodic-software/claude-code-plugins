#!/usr/bin/env bash
# Noise findings for /declutter. Read-only.
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

usage() {
  cat <<'EOF'
detect.sh — emit markdown noise findings for /declutter.

Usage:
  detect.sh <file.md>...
  detect.sh --paths-file <file>
  detect.sh --help

When no paths are given, audits the uncommitted .md files of the repository
it runs in (from git status). Exit: 0 on audit, 2 on unknown arguments.
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
  --paths-file)
    PATHS_FILE="${2:-}"
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

repo_root="$(git rev-parse --show-toplevel 2>/dev/null | tr -d '\r')"
if [[ -n "$repo_root" ]]; then
  cd "$repo_root" 2>/dev/null || true
fi

if [[ ${#TARGETS[@]} -eq 0 ]]; then
  if [[ -n "$PATHS_FILE" ]]; then
    while IFS= read -r line || [[ -n "$line" ]]; do
      line="${line//$'\r'/}"
      [[ -z "$line" ]] && continue
      TARGETS+=("$line")
    done <"$PATHS_FILE"
  elif [[ -n "$repo_root" ]]; then
    # Uncommitted .md files: modified/added/renamed/untracked, per git status.
    while IFS= read -r line; do
      line="${line//$'\r'/}"
      [[ -z "$line" ]] && continue
      TARGETS+=("$line")
    done < <(git status --porcelain 2>/dev/null | awk '/\.md$/ {print $NF}')
  fi
fi

if [[ ${#TARGETS[@]} -eq 0 ]]; then
  echo "Summary total: files=0 T1=0 T2=0 T3=0"
  echo "Note: no markdown targets — pass file paths or edit some .md files"
  exit 0
fi

mapfile -t SORTED < <(printf '%s\n' "${TARGETS[@]}" | LC_ALL=C sort -u)

total_t1=0 total_t2=0 total_t3=0 files_audited=0

audit_file() {
  local file="$1"
  [[ -f "$file" ]] || return 0
  files_audited=$((files_audited + 1))

  local t1=0 t2=0 t3=0
  local in_exempt=0 current_section="" prev_line="" line_num=0 shapes shape tier excerpt

  while IFS= read -r line || [[ -n "$line" ]]; do
    line_num=$((line_num + 1))
    if [[ "$line" =~ ^##[[:space:]]+ ]]; then
      current_section="${line#'## '}"
      current_section="${current_section%%$'\r'*}"
      if declutter_section_exempt "$current_section"; then
        in_exempt=1
      else
        in_exempt=0
      fi
    fi
    if [[ $in_exempt -eq 1 ]] || declutter_line_skipped "$prev_line" "$line"; then
      prev_line="$line"
      continue
    fi
    shapes="$(declutter_detect_shapes "$line" || true)"
    if [[ -n "$shapes" ]]; then
      excerpt="$(declutter_trim_excerpt "$line")"
      while IFS= read -r shape; do
        [[ -z "$shape" ]] && continue
        tier="$(declutter_shape_tier "$shape")"
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
