#!/usr/bin/env bash
# Enumerate the scan corpus: tracked markdown, minus the categorical carve-outs.
#
#   list-corpus.sh [target] [--paths-file F] [--show-config]
#
# Reasoning-free (Brief constraint C1): this script matches paths and nothing
# else. The carve-outs that need reading a file — a conforming stamped record, a
# quotation context, owned content, a distilled-product genre — are NOT
# path-expressible and are judged later in the flow, by the rubric step and by
# the fingerprint module's quote stripping. Nothing here guesses at them.
#
# The eval-fixture tree is excluded through the CONFIG layer, never
# unconditionally here. An unconditional exclusion would decline the fixtures
# under the eval harness's own config isolation, leaving the eval author reading
# prose instead of results (the ai-slop #3041 resolution). Under a consuming
# repo's `.claude/provenance.json` every normal run declines the tree and says
# so; the harness lifts the config layer and the fixtures report real findings.
#
# Two roots, resolved separately and deliberately:
#   CORPUS root — the git toplevel of the target (or the cwd). It decides which
#     files exist.
#   CONFIG root — CLAUDE_PROJECT_DIR, falling back to the corpus root. It
#     decides which files are excluded, per the config-cascade convention.
# Conflating them would make a caller unable to scan one checkout while reading
# another's exclusions, which is exactly what the eval harness does.
#
# Declined paths are counted and reported with a reason, never silently dropped
# (detector-findings declined-candidate rule).
#
# Contract: docs/specs/provenance-type-inventory.md.
# Exit: 0 on a clean run (with corpus or empty), 2 on usage or target error.
set -uo pipefail

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
                  its own fixtures this way) but the carve-outs still apply
  --show-config   print the effective config per layer, then exit

Output: JSON on stdout — {target, root, files, declined, counts}. Diagnostics
go to stderr. Exit 2 is usage or an unusable target, never "no files found".
EOF
}

require_opt_value() {
  local opt="$1"
  if [[ $# -lt 2 || -z "${2:-}" || "$2" == -* ]]; then
    echo "list-corpus.sh: $opt requires a value" >&2
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

# --- Roots -----------------------------------------------------------------------

anchor_dir() {
  # The directory the corpus root is resolved from: the target itself when it is
  # a directory, its parent when it is a file, the cwd otherwise.
  if [[ -d "${TARGET:-}" ]]; then
    printf '%s' "$TARGET"
  elif [[ -n "${TARGET:-}" && -f "$TARGET" ]]; then
    printf '%s' "$(dirname "$TARGET")"
  else
    printf '%s' "$PWD"
  fi
}

ROOT="$(git -C "$(anchor_dir)" rev-parse --show-toplevel 2>/dev/null || true)"
[[ -n "$ROOT" ]] || ROOT="$PWD"

CONFIG_ROOT="${CLAUDE_PROJECT_DIR:-$ROOT}"

# --- Config cascade (.claude/provenance.json; user-global -> team -> overlay) -----

CFG_LAYERS=()
[[ -f "${HOME:-/nonexistent}/.claude/provenance.json" ]] && CFG_LAYERS+=("$HOME/.claude/provenance.json")
[[ -f "$CONFIG_ROOT/.claude/provenance.json" ]] && CFG_LAYERS+=("$CONFIG_ROOT/.claude/provenance.json")
[[ -f "$CONFIG_ROOT/.claude/provenance.local.json" ]] && CFG_LAYERS+=("$CONFIG_ROOT/.claude/provenance.local.json")

HAVE_JQ=1
command -v jq >/dev/null 2>&1 || HAVE_JQ=0

EXCLUDED_GLOBS=()

# cfg_array <jq-path>: last layer that defines the key wins (per-key override,
# the config-cascade contract's sanctioned form for a closed list).
#
# Carriage returns are stripped because the Windows build of jq terminates its
# lines with CRLF: without this every configured glob arrives as `docs/**<CR>`
# and matches nothing, so `excluded_paths` silently stops applying on a Windows
# workstation while CI, which sees LF, agrees with the config (the ai-slop
# #3343 finding, same jq, same exposure).
cfg_array() {
  local path="$1" layer v out=""
  for layer in ${CFG_LAYERS[@]+"${CFG_LAYERS[@]}"}; do
    v="$(jq -r "($path // empty) | .[]" "$layer" 2>/dev/null | tr -d '\r' | tr '\n' ' ')"
    [[ -n "${v// /}" ]] && out="$v"
  done
  printf '%s' "$out"
}

if [[ "$HAVE_JQ" -eq 1 && "${#CFG_LAYERS[@]}" -gt 0 ]]; then
  read -r -a EXCLUDED_GLOBS <<<"$(cfg_array '.excluded_paths')"
elif [[ "$HAVE_JQ" -eq 0 && "${#CFG_LAYERS[@]}" -gt 0 ]]; then
  echo "list-corpus.sh: jq not found; config layers present but unread, using defaults" >&2
fi

VENDOR_GLOB='**/vendor/**'
VENDOR_REASON='vendored tree (built-in carve-out; upstream owns this text)'
ATTR_PATTERN='linguist-vendored'
ATTR_REASON='marked linguist-vendored in gitattributes (built-in carve-out)'

if [[ "$SHOW_CONFIG" -eq 1 ]]; then
  echo "Config layers (later refines earlier):"
  if [[ "${#CFG_LAYERS[@]}" -eq 0 ]]; then
    echo "  (none; bundled defaults)"
  else
    for layer in "${CFG_LAYERS[@]}"; do echo "  $layer"; done
  fi
  echo "Corpus root: $ROOT"
  echo "Config root: $CONFIG_ROOT"
  echo "Built-in carve-out: $VENDOR_GLOB"
  echo "Built-in carve-out: $ATTR_PATTERN (gitattributes)"
  echo "Effective: excluded_paths=${EXCLUDED_GLOBS[*]:-}"
  exit 0
fi

# --- Candidate enumeration -------------------------------------------------------

CANDIDATES=()

rel_to_root() {
  # Repo-relative spelling of a path given relative to the cwd or absolute.
  local p="$1" abs
  if [[ "$p" == /* ]]; then
    abs="$p"
  else
    abs="$PWD/$p"
  fi
  abs="${abs//\/.\//\/}"
  printf '%s' "${abs#"$ROOT"/}"
}

tracked_markdown() {
  # Repo-relative tracked markdown. core.quotePath=false keeps a non-ASCII
  # filename from arriving as a C-quoted escape that matches nothing downstream.
  git -C "$ROOT" -c core.quotePath=false ls-files -- '*.md' 2>/dev/null
}

if [[ -n "$PATHS_FILE" ]]; then
  if [[ ! -r "$PATHS_FILE" ]]; then
    echo "list-corpus.sh: cannot read --paths-file: $PATHS_FILE" >&2
    exit 2
  fi
  while IFS= read -r line; do
    [[ -n "$line" ]] || continue
    CANDIDATES+=("$(rel_to_root "$line")")
  done <"$PATHS_FILE"
elif [[ -z "$TARGET" ]]; then
  while IFS= read -r line; do
    [[ -n "$line" ]] && CANDIDATES+=("$line")
  done < <(tracked_markdown)
elif [[ -d "$TARGET" ]]; then
  prefix="$(rel_to_root "$TARGET")"
  prefix="${prefix%/}"
  while IFS= read -r line; do
    [[ -n "$line" ]] || continue
    if [[ -z "$prefix" || "$line" == "$prefix"/* ]]; then
      CANDIDATES+=("$line")
    fi
  done < <(tracked_markdown)
elif [[ -f "$TARGET" ]]; then
  CANDIDATES+=("$(rel_to_root "$TARGET")")
else
  echo "list-corpus.sh: target does not exist: $TARGET" >&2
  exit 2
fi

# --- Carve-out matching ----------------------------------------------------------

glob_match() {
  # glob_match <repo-relative path> <glob>. A leading `**/` also matches the
  # repository root, so `**/vendor/**` covers a top-level `vendor/` tree; bash
  # case globbing alone would require a directory above it.
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
  # One batched check-attr rather than one process per file. -z makes both the
  # input and the NUL-separated (path, attr, value) output unambiguous for paths
  # holding a colon or a newline.
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
  for g in ${EXCLUDED_GLOBS[@]+"${EXCLUDED_GLOBS[@]}"}; do
    [[ -n "$g" ]] || continue
    if glob_match "$candidate" "$g"; then
      matched="$g"
      break
    fi
  done
  if [[ -n "$matched" ]]; then
    decline "$matched" "excluded_paths (config cascade)"
    continue
  fi
  FILES+=("$candidate")
done

# --- JSON product ----------------------------------------------------------------

json_str() {
  # Escape for a JSON string: backslash and quote first, then the control
  # characters a path or a reason can legally carry.
  local s="$1"
  s="${s//\\/\\\\}"
  s="${s//\"/\\\"}"
  s="${s//$'\t'/\\t}"
  s="${s//$'\r'/\\r}"
  s="${s//$'\n'/\\n}"
  printf '"%s"' "$s"
}

declined_total=0
for pattern in ${DECLINED_PATTERNS[@]+"${DECLINED_PATTERNS[@]}"}; do
  declined_total=$((declined_total + DECLINED_COUNT[$pattern]))
done

printf '{\n'
printf '  "target": %s,\n' "$(json_str "${TARGET:-${PATHS_FILE:-$ROOT}}")"
printf '  "root": %s,\n' "$(json_str "$ROOT")"
printf '  "files": ['
first=1
for f in ${FILES[@]+"${FILES[@]}"}; do
  [[ "$first" -eq 1 ]] && printf '\n' || printf ',\n'
  first=0
  printf '    %s' "$(json_str "$f")"
done
[[ "$first" -eq 1 ]] || printf '\n  '
printf '],\n'
printf '  "declined": ['
first=1
for pattern in ${DECLINED_PATTERNS[@]+"${DECLINED_PATTERNS[@]}"}; do
  [[ "$first" -eq 1 ]] && printf '\n' || printf ',\n'
  first=0
  printf '    {"path_pattern": %s, "count": %s, "reason": %s}' \
    "$(json_str "$pattern")" "${DECLINED_COUNT[$pattern]}" "$(json_str "${DECLINED_REASON[$pattern]}")"
done
[[ "$first" -eq 1 ]] || printf '\n  '
printf '],\n'
printf '  "counts": {"considered": %s, "included": %s, "declined": %s}\n' \
  "$((${#FILES[@]} + declined_total))" "${#FILES[@]}" "$declined_total"
printf '}\n'
