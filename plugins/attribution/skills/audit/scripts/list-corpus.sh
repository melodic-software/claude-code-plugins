#!/usr/bin/env bash
# Exit: 0 on a clean run (with corpus or empty), 2 on usage or target error.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [[ ! -r "$SCRIPT_DIR/lib.sh" ]]; then
  echo "list-corpus.sh: cannot read $SCRIPT_DIR/lib.sh" >&2
  for arg in "$@"; do
    if [[ "$arg" == "--show-config" ]]; then
      echo "detector unavailable"
      exit 0
    fi
  done
  exit 2
fi
# shellcheck source=lib.sh
source "$SCRIPT_DIR/lib.sh"

TARGET=""
PATHS_FILE=""
SHOW_CONFIG=0

usage() {
  cat <<'EOF'
list-corpus.sh — enumerate tracked markdown minus the categorical carve-outs.

Usage:
  list-corpus.sh [target] [--paths-file F] [--show-config]

  target          file or directory to scan (default: the whole repository)
  --paths-file F  read candidate paths from F, one per line, instead of a
                  target; entries need not be tracked (the eval harness feeds
                  its own fixtures this way); the built-in and configured
                  carve-outs still apply, the bundled fixture default does not
  --show-config   print the effective config per layer, then exit

Output: JSON on stdout — {target, root, files, declined, counts}. Diagnostics
go to stderr. Exit 2 is usage or an unusable target, never "no files found".
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
  --paths-file)
    require_opt_value "list-corpus.sh" "$@"
    PATHS_FILE="$2"
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
    echo "list-corpus.sh: unknown argument: $1" >&2
    usage >&2
    exit 2
    ;;
  *)
    if [[ -n "$TARGET" ]]; then
      echo "list-corpus.sh: only one target is accepted (got '$TARGET' and '$1')" >&2
      exit 2
    fi
    TARGET="$1"
    shift
    ;;
  esac
done

if [[ -n "$PATHS_FILE" && -n "$TARGET" ]]; then
  echo "list-corpus.sh: --paths-file replaces the target; pass one or the other" >&2
  exit 2
fi

anchor_dir() {
  if [[ -d "$TARGET" ]]; then
    printf '%s' "$TARGET"
  elif [[ -f "$TARGET" ]]; then
    dirname "$TARGET"
  else
    printf '%s' "$PWD"
  fi
}

ROOT="$(git -C "$(anchor_dir)" rev-parse --show-toplevel 2>/dev/null || true)"
[[ -n "$ROOT" ]] || ROOT="$PWD"

CONFIG_ROOT="${CLAUDE_PROJECT_DIR:-$ROOT}"

cfg_layers_init "$CONFIG_ROOT"

if cfg_have_unread_layer; then
  echo "list-corpus.sh: jq not found; JSON config layers present but unread, using defaults" >&2
fi

DEFAULT_EXCLUDED=('**/fixtures/**' '**/__fixtures__/**' '**/testdata/**')
EXCLUDED_GLOBS=("${DEFAULT_EXCLUDED[@]}")
cfg_list EXCLUDED_GLOBS excluded_paths
EXCLUDED_FROM="$CFG_SOURCE"

VENDOR_GLOB='**/vendor/**'
VENDOR_REASON='vendored tree (built-in carve-out; upstream owns this text)'
ATTR_PATTERN='linguist-vendored'
ATTR_REASON='marked linguist-vendored in gitattributes (built-in carve-out)'

if [[ "$SHOW_CONFIG" -eq 1 ]]; then
  cfg_layers_print
  echo "Corpus root: $ROOT"
  echo "Config root: $CONFIG_ROOT"
  echo "Built-in carve-out: $VENDOR_GLOB"
  echo "Built-in carve-out: $ATTR_PATTERN (gitattributes)"
  echo "Effective: excluded_paths=${EXCLUDED_GLOBS[*]:-} $(cfg_from_label "$EXCLUDED_FROM")"
  exit 0
fi

CANDIDATES=()
DEFAULT_BASE=""
DEFAULT_OFF=0

rel_to_root() {
  local p="$1" dir base placed pfx top
  if [[ -d "$p" ]]; then
    dir="$p"
    base=""
  else
    dir="$(dirname -- "$p")"
    base="$(basename -- "$p")"
  fi
  if ! placed="$(git -C "$dir" rev-parse --show-prefix --show-toplevel 2>/dev/null)"; then
    printf '%s' "$p"
    return 0
  fi
  pfx="${placed%%$'\n'*}"
  top="${placed#*$'\n'}"
  if [[ "$top" != "$ROOT" ]]; then
    printf '%s' "$p"
    return 0
  fi
  printf '%s' "$pfx$base"
}

tracked_markdown() {
  git -C "$ROOT" -c core.quotePath=false ls-files -- '*.md' 2>/dev/null
}

if [[ -n "$PATHS_FILE" ]]; then
  if [[ ! -r "$PATHS_FILE" ]]; then
    echo "list-corpus.sh: cannot read --paths-file: $PATHS_FILE" >&2
    exit 2
  fi
  DEFAULT_OFF=1
  while IFS= read -r line; do
    [[ -n "$line" ]] || continue
    CANDIDATES+=("$(rel_to_root "$line")")
  done <"$PATHS_FILE"
elif [[ -z "$TARGET" || -d "$TARGET" ]]; then
  prefix=""
  [[ -z "$TARGET" ]] || prefix="$(rel_to_root "$TARGET")"
  prefix="${prefix%/}"
  DEFAULT_BASE="$prefix"
  while IFS= read -r line; do
    [[ -n "$line" ]] || continue
    if [[ -z "$prefix" || "$line" == "$prefix"/* ]]; then
      CANDIDATES+=("$line")
    fi
  done < <(tracked_markdown)
elif [[ -f "$TARGET" ]]; then
  DEFAULT_OFF=1
  CANDIDATES+=("$(rel_to_root "$TARGET")")
else
  echo "list-corpus.sh: target does not exist: $TARGET" >&2
  exit 2
fi

glob_match() {
  local path="$1" g="$2"
  # shellcheck disable=SC2254
  case "$path" in "$g" | $g) return 0 ;; *) ;; esac
  if [[ "$g" == '**/'* ]]; then
    local bare="${g#'**/'}"
    # shellcheck disable=SC2254
    case "$path" in $bare) return 0 ;; *) ;; esac
  fi
  return 1
}

declare -A VENDORED_BY_ATTR=()
if [[ "${#CANDIDATES[@]}" -gt 0 ]] && command -v git >/dev/null 2>&1; then
  while IFS= read -r -d '' attr_path && IFS= read -r -d '' _attr_name && IFS= read -r -d '' attr_value; do
    case "$attr_value" in
    set | true) VENDORED_BY_ATTR["$attr_path"]=1 ;;
    *) ;;
    esac
  done < <(printf '%s\0' "${CANDIDATES[@]}" | git -C "$ROOT" check-attr -z --stdin linguist-vendored 2>/dev/null)
fi

FILES=()
DECLINED_PATTERNS=()
declare -A DECLINED_COUNT=()
declare -A DECLINED_REASON=()

decline() {
  local pattern="$1" reason="$2"
  if [[ -z "${DECLINED_COUNT[$pattern]:-}" ]]; then
    DECLINED_PATTERNS+=("$pattern")
    DECLINED_COUNT["$pattern"]=0
    DECLINED_REASON["$pattern"]="$reason"
  fi
  DECLINED_COUNT["$pattern"]=$((DECLINED_COUNT[$pattern] + 1))
}

for candidate in ${CANDIDATES[@]+"${CANDIDATES[@]}"}; do
  if [[ "$candidate" != *.md ]]; then
    decline "$candidate" "not markdown"
    continue
  fi
  if [[ ! -f "$ROOT/$candidate" ]]; then
    decline "$candidate" "path does not exist"
    continue
  fi
  if glob_match "$candidate" "$VENDOR_GLOB"; then
    decline "$VENDOR_GLOB" "$VENDOR_REASON"
    continue
  fi
  if [[ -n "${VENDORED_BY_ATTR[$candidate]:-}" ]]; then
    decline "$ATTR_PATTERN" "$ATTR_REASON"
    continue
  fi
  matched=""
  subject="$candidate"
  reason="excluded_paths (config cascade)"
  if [[ -z "$EXCLUDED_FROM" ]]; then
    reason="excluded_paths (bundled default: test-fixture tree)"
    if [[ "$DEFAULT_OFF" -eq 1 ]]; then
      subject=""
    elif [[ -n "$DEFAULT_BASE" ]]; then
      subject="${candidate#"$DEFAULT_BASE"/}"
    fi
  fi
  for g in ${EXCLUDED_GLOBS[@]+"${EXCLUDED_GLOBS[@]}"}; do
    [[ -n "$g" && -n "$subject" ]] || continue
    if glob_match "$subject" "$g"; then
      matched="$g"
      break
    fi
  done
  if [[ -n "$matched" ]]; then
    decline "$matched" "$reason"
    continue
  fi
  FILES+=("$candidate")
done

json_array() {
  local first=1 item
  printf '['
  for item in "$@"; do
    [[ "$first" -eq 1 ]] && printf '\n' || printf ',\n'
    first=0
    printf '    %s' "$item"
  done
  [[ "$first" -eq 1 ]] || printf '\n  '
  printf ']'
}

FILE_ITEMS=()
for f in ${FILES[@]+"${FILES[@]}"}; do
  FILE_ITEMS+=("$(json_str "$f")")
done

declined_total=0
DECLINED_ITEMS=()
for pattern in ${DECLINED_PATTERNS[@]+"${DECLINED_PATTERNS[@]}"}; do
  declined_total=$((declined_total + DECLINED_COUNT[$pattern]))
  DECLINED_ITEMS+=("{\"path_pattern\": $(json_str "$pattern"), \"count\": ${DECLINED_COUNT[$pattern]}, \"reason\": $(json_str "${DECLINED_REASON[$pattern]}")}")
done

printf '{\n'
printf '  "target": %s,\n' "$(json_str "${TARGET:-${PATHS_FILE:-$ROOT}}")"
printf '  "root": %s,\n' "$(json_str "$ROOT")"
printf '  "files": %s,\n' "$(json_array ${FILE_ITEMS[@]+"${FILE_ITEMS[@]}"})"
printf '  "declined": %s,\n' "$(json_array ${DECLINED_ITEMS[@]+"${DECLINED_ITEMS[@]}"})"
printf '  "counts": {"considered": %s, "included": %s, "declined": %s}\n' \
  "$((${#FILES[@]} + declined_total))" "${#FILES[@]}" "$declined_total"
printf '}\n'
