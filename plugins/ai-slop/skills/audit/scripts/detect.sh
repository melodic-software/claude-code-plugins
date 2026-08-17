#!/usr/bin/env bash
# AI-slop findings for /ai-slop:audit. Read-only.
#
# Rules (plan phase 2 seed set; the full roster lands in phase 3):
#   ai-slop/audit/rule-em-dash        zero-tolerance: any em dash in prose flags
#   ai-slop/audit/rule-ai-vocabulary  AI-vocabulary density per 1000 words
#
# Output: Finding rows (rule/file/line/fired/excerpt), then Summary rows with
# per-rule finding and declined counts. All key=value, line-oriented.
# Exit: always 0 on audit paths (a read-only audit must never fail the caller);
# 2 on unknown arguments or unreadable --paths-file.
#
# Prose extraction: fenced code blocks, inline code spans, and ignore-marked
# lines and blocks are removed before any rule runs; exempted candidates are
# counted as declined per rule, never silently dropped.
#
# Unicode: matching uses LC_ALL=C byte sequences (em dash = \xE2\x80\x94) and
# POSIX ERE only, so behavior is identical across GNU and BSD grep and does
# not depend on the host locale.
set -u

EM_DASH=$'\xe2\x80\x94'

# Distinctive AI-vocabulary defaults (catalog rule-ai-vocabulary; config-tunable).
DEFAULT_VOCAB="delve tapestry testament pivotal crucial underscore underscores boasts intricate intricacies meticulous meticulously garner bolstered fostering showcasing vibrant nestled groundbreaking renowned interplay enduring"
DEFAULT_THRESHOLD_VOCAB="3.0"

PATHS_FILE=""
TARGETS=()
OFFSET=0
LIMIT=0
SHOW_CONFIG=0

usage() {
  cat <<'EOF'
detect.sh: emit AI-slop findings for /ai-slop:audit.

Usage:
  detect.sh [file.md ...]
  detect.sh --paths-file <file>
  detect.sh --offset N --limit N   # chunk the sorted target list
  detect.sh --show-config          # print effective config per layer, then exit
  detect.sh --help

With no paths, scans the repository's tracked markdown (git ls-files '*.md').
Exit: 0 on audit, 2 on unknown arguments or unreadable --paths-file.
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
  --show-config)
    SHOW_CONFIG=1
    shift
    ;;
  --help | -h)
    usage
    exit 0
    ;;
  -*)
    echo "detect.sh: unknown option: $1" >&2
    exit 2
    ;;
  *)
    TARGETS+=("$1")
    shift
    ;;
  esac
done

# --- Config cascade (.claude/ai-slop.json; user-global -> team -> overlay) ------

REPO_ROOT="${CLAUDE_PROJECT_DIR:-}"
if [[ -z "$REPO_ROOT" ]]; then
  REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
fi

CFG_LAYERS=()
[[ -f "${HOME:-/nonexistent}/.claude/ai-slop.json" ]] && CFG_LAYERS+=("$HOME/.claude/ai-slop.json")
[[ -f "$REPO_ROOT/.claude/ai-slop.json" ]] && CFG_LAYERS+=("$REPO_ROOT/.claude/ai-slop.json")
[[ -f "$REPO_ROOT/.claude/ai-slop.local.json" ]] && CFG_LAYERS+=("$REPO_ROOT/.claude/ai-slop.local.json")

HAVE_JQ=1
command -v jq >/dev/null 2>&1 || HAVE_JQ=0

VOCAB="$DEFAULT_VOCAB"
THRESHOLD_VOCAB="$DEFAULT_THRESHOLD_VOCAB"
EXCLUDED_GLOBS=()
EM_DASH_ALLOWED_GLOBS=()

# cfg_scalar <jq-path>: last layer that defines the key wins (per-key override).
cfg_scalar() {
  local path="$1" layer v out=""
  for layer in ${CFG_LAYERS[@]+"${CFG_LAYERS[@]}"}; do
    v="$(jq -r "$path // empty" "$layer" 2>/dev/null)" && [[ -n "$v" ]] && out="$v"
  done
  printf '%s' "$out"
}

cfg_array() {
  local path="$1" layer v out=""
  for layer in ${CFG_LAYERS[@]+"${CFG_LAYERS[@]}"}; do
    v="$(jq -r "($path // empty) | .[]" "$layer" 2>/dev/null | tr '\n' ' ')"
    [[ -n "${v// /}" ]] && out="$v"
  done
  printf '%s' "$out"
}

if [[ "$HAVE_JQ" -eq 1 && "${#CFG_LAYERS[@]}" -gt 0 ]]; then
  v="$(cfg_scalar '.threshold_ai_vocabulary')" && [[ -n "$v" ]] && THRESHOLD_VOCAB="$v"
  read -r -a EXCLUDED_GLOBS <<<"$(cfg_array '.excluded_paths')"
  read -r -a EM_DASH_ALLOWED_GLOBS <<<"$(cfg_array '.em_dash_allowed_paths')"
  add="$(cfg_array '.vocab_add')"
  remove="$(cfg_array '.vocab_remove')"
  [[ -n "${add// /}" ]] && VOCAB="$VOCAB $add"
  if [[ -n "${remove// /}" ]]; then
    filtered=""
    for w in $VOCAB; do
      case " $remove " in
      *" $w "*) ;;
      *) filtered="$filtered $w" ;;
      esac
    done
    VOCAB="${filtered# }"
  fi
elif [[ "$HAVE_JQ" -eq 0 && "${#CFG_LAYERS[@]}" -gt 0 ]]; then
  echo "Note: jq not found; config layers present but unread, using defaults" >&2
fi

if [[ "$SHOW_CONFIG" -eq 1 ]]; then
  echo "Config layers (later refines earlier):"
  if [[ "${#CFG_LAYERS[@]}" -eq 0 ]]; then
    echo "  (none; bundled defaults)"
  else
    for layer in "${CFG_LAYERS[@]}"; do echo "  $layer"; done
  fi
  echo "Effective: threshold_ai_vocabulary=$THRESHOLD_VOCAB"
  echo "Effective: vocab=$VOCAB"
  echo "Effective: excluded_paths=${EXCLUDED_GLOBS[*]:-}"
  echo "Effective: em_dash_allowed_paths=${EM_DASH_ALLOWED_GLOBS[*]:-}"
  exit 0
fi

# --- Target list -----------------------------------------------------------------

if [[ -n "$PATHS_FILE" ]]; then
  if [[ ! -r "$PATHS_FILE" ]]; then
    echo "detect.sh: cannot read --paths-file: $PATHS_FILE" >&2
    exit 2
  fi
  while IFS= read -r line; do
    [[ -n "$line" ]] && TARGETS+=("$line")
  done <"$PATHS_FILE"
fi

if [[ "${#TARGETS[@]}" -eq 0 ]]; then
  while IFS= read -r line; do
    TARGETS+=("$REPO_ROOT/$line")
  done < <(git -C "$REPO_ROOT" ls-files '*.md' 2>/dev/null)
fi

# Sort unique, then apply --offset/--limit over the sorted list.
mapfile -t TARGETS < <(printf '%s\n' ${TARGETS[@]+"${TARGETS[@]}"} | sort -u)
if [[ "$OFFSET" -gt 0 || "$LIMIT" -gt 0 ]]; then
  end="${#TARGETS[@]}"
  [[ "$LIMIT" -gt 0 ]] && end=$((OFFSET + LIMIT))
  mapfile -t TARGETS < <(printf '%s\n' ${TARGETS[@]+"${TARGETS[@]}"} | awk -v s="$OFFSET" -v e="$end" 'NR > s && NR <= e')
fi

matches_glob() {
  # matches_glob <path> <glob>...: any glob matches the path (or its repo-relative form).
  local path="$1" rel="${1#"$REPO_ROOT"/}" g
  shift
  for g in "$@"; do
    # shellcheck disable=SC2254
    case "$path" in $g) return 0 ;; *) ;; esac
    # shellcheck disable=SC2254
    case "$rel" in $g) return 0 ;; *) ;; esac
  done
  return 1
}

# --- Prose extraction ------------------------------------------------------------
# Emits "lineno<TAB>text" for prose lines; strips fenced code blocks, inline code
# spans, and honors the ignore markers. Prints decline events to a side stream:
#   DECLINE<TAB>line|block|file
extract_prose() {
  awk '
    BEGIN { fence = 0; ignored = 0 }
    /ai-slop-ignore-file/ { print "DECLINE\tfile"; exit }
    /^(```|~~~)/ { fence = !fence; next }
    fence { next }
    /ai-slop-ignore-start/ { ignored = 1; next }
    /ai-slop-ignore-end/ { ignored = 0; next }
    ignored { print "DECLINE\tblock"; next }
    /ai-slop-ignore/ { print "DECLINE\tline"; next }
    {
      line = $0
      gsub(/`[^`]*`/, "", line)   # inline code spans
      printf "%d\t%s\n", NR, line
    }
  ' "$1"
}

# --- Scan ------------------------------------------------------------------------

TOTAL_FINDINGS=0
TOTAL_FILES=0
DECLINED_FILES=0
DECL_EM_DASH=0
DECL_VOCAB=0
FIND_EM_DASH=0
FIND_VOCAB=0

VOCAB_ERE="($(printf '%s' "$VOCAB" | tr ' ' '|'))"

for file in ${TARGETS[@]+"${TARGETS[@]}"}; do
  [[ -f "$file" ]] || continue
  rel="${file#"$REPO_ROOT"/}"

  if [[ "${#EXCLUDED_GLOBS[@]}" -gt 0 ]] && matches_glob "$file" "${EXCLUDED_GLOBS[@]}"; then
    DECLINED_FILES=$((DECLINED_FILES + 1))
    DECL_EM_DASH=$((DECL_EM_DASH + 1))
    DECL_VOCAB=$((DECL_VOCAB + 1))
    continue
  fi

  TOTAL_FILES=$((TOTAL_FILES + 1))
  prose="$(extract_prose "$file")"

  case "$prose" in
  DECLINE$'\t'file*)
    DECLINED_FILES=$((DECLINED_FILES + 1))
    DECL_EM_DASH=$((DECL_EM_DASH + 1))
    DECL_VOCAB=$((DECL_VOCAB + 1))
    continue
    ;;
  *) ;;
  esac

  declines="$(printf '%s\n' "$prose" | LC_ALL=C grep -c '^DECLINE' || true)"
  prose="$(printf '%s\n' "$prose" | LC_ALL=C grep -v '^DECLINE' || true)"

  # rule-em-dash: zero tolerance unless the document is allow-listed.
  if [[ "${#EM_DASH_ALLOWED_GLOBS[@]}" -gt 0 ]] && matches_glob "$file" "${EM_DASH_ALLOWED_GLOBS[@]}"; then
    DECL_EM_DASH=$((DECL_EM_DASH + 1))
  else
    while IFS=$'\t' read -r lineno text; do
      [[ -z "$lineno" ]] && continue
      excerpt="$(printf '%s' "$text" | cut -c1-80 | tr '|' '/')"
      printf 'Finding: rule=ai-slop/audit/rule-em-dash file=%s line=%s fired=zero-tolerance excerpt=%s\n' \
        "$rel" "$lineno" "$excerpt"
      FIND_EM_DASH=$((FIND_EM_DASH + 1))
    done < <(printf '%s\n' "$prose" | LC_ALL=C grep -- "$EM_DASH" || true)
  fi

  # rule-ai-vocabulary: density per 1000 words against the effective threshold.
  words="$(printf '%s\n' "$prose" | cut -f2- | wc -w | tr -d ' ')"
  if [[ "$words" -gt 0 ]]; then
    hits="$(printf '%s\n' "$prose" | cut -f2- | LC_ALL=C grep -E -o -i -w "$VOCAB_ERE" | wc -l | tr -d ' ')"
    density="$(awk -v h="$hits" -v w="$words" 'BEGIN { printf "%.1f", (h * 1000) / w }')"
    over="$(awk -v d="$density" -v t="$THRESHOLD_VOCAB" 'BEGIN { print (d >= t) ? 1 : 0 }')"
    if [[ "$hits" -gt 0 && "$over" -eq 1 ]]; then
      first_line="$(printf '%s\n' "$prose" | LC_ALL=C grep -E -i -w -m1 "$VOCAB_ERE" | cut -f1)"
      printf 'Finding: rule=ai-slop/audit/rule-ai-vocabulary file=%s line=%s fired=density %s/1000 words, threshold %s (%s hits in %s words) excerpt=vocabulary density\n' \
        "$rel" "${first_line:-1}" "$density" "$THRESHOLD_VOCAB" "$hits" "$words"
      FIND_VOCAB=$((FIND_VOCAB + 1))
    fi
  fi

  if [[ "$declines" -gt 0 ]]; then
    DECL_EM_DASH=$((DECL_EM_DASH + declines))
    DECL_VOCAB=$((DECL_VOCAB + declines))
  fi
done

TOTAL_FINDINGS=$((FIND_EM_DASH + FIND_VOCAB))

echo "Summary rule=ai-slop/audit/rule-em-dash findings=$FIND_EM_DASH declined=$DECL_EM_DASH"
echo "Summary rule=ai-slop/audit/rule-ai-vocabulary findings=$FIND_VOCAB declined=$DECL_VOCAB"
echo "Summary total: $TOTAL_FINDINGS findings across $TOTAL_FILES files scanned ($DECLINED_FILES files declined)"
exit 0
