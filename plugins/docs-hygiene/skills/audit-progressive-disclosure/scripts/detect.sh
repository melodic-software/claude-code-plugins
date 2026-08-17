#!/usr/bin/env bash
# Fact emitter for /docs-hygiene:audit-progressive-disclosure.
#
# Emits deterministic, mechanical facts about instruction-markdown targets —
# sizes, heading census, load-tier classification, pointer inventory, orphan
# spokes, spoke-to-spoke chains, TOC presence. It is a fact emitter, not a
# finding adjudicator: the skill's judgment layer maps these facts onto the
# seven finding shapes; nothing here is a verdict.
#
# Output records (TAB-separated, one per line, sorted per section):
#   file <path> lines=N words=N h2=N tier=<always|invocation|on-demand|unknown> toc=<yes|no>
#   pointer <path> <line> <target> resolved=<yes|no> ctx=<trimmed source line>
#   orphan <path> hub=<skill-root>
#   chain <from> <line> <target>
#   summary files=N pointers=N unresolved=N orphans=N chains=N
#
# Tier classification is a path/frontmatter heuristic; files it cannot place
# are tier=unknown and left to the in-session judgment layer. A repo with no
# Claude Code configuration degrades gracefully: everything not matching an
# instruction-surface pattern is on-demand/unknown and the size facts still
# emit.
# Exit: 0 facts emitted (including zero facts), 2 usage/environment error.
set -euo pipefail

usage() {
  cat <<'USAGE'
Usage: detect.sh <path> [<path> ...]

Emit progressive-disclosure facts for markdown files or directories.
Directories are scanned recursively for *.md (skipping node_modules, .git,
vendor, evals/fixtures). A directory containing SKILL.md is additionally
analyzed as a hub root (orphan spokes, spoke-to-spoke chains).
Exit: 0 facts emitted, 2 usage/environment error.
USAGE
}

if [[ $# -eq 0 ]]; then
  usage >&2
  exit 2
fi
if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
  usage
  exit 0
fi

# --- target collection -------------------------------------------------------

# Enumerate name-matching files under a root, excluding vendored/fixture trees
# by path RELATIVE to the scan root — so explicitly targeting a fixture or
# vendored directory still scans it (the exclusions guard corpus sweeps, not
# deliberate descent).
collect() {
  local root="$1" name="$2" f rel
  find "$root" -type f -name "$name" | LC_ALL=C sort | while IFS= read -r f; do
    rel="${f#"$root"/}"
    case "$rel" in
    node_modules/* | */node_modules/* | .git/* | */.git/* | \
      vendor/* | */vendor/* | evals/fixtures/* | */evals/fixtures/*) continue ;;
    *) printf '%s\n' "$f" ;;
    esac
  done
}

TARGETS=()
HUB_ROOTS=()
for arg in "$@"; do
  if [[ -f "$arg" ]]; then
    TARGETS+=("$arg")
  elif [[ -d "$arg" ]]; then
    while IFS= read -r f; do
      TARGETS+=("$f")
    done < <(collect "$arg" '*.md')
    while IFS= read -r hub; do
      HUB_ROOTS+=("$(dirname "$hub")")
    done < <(collect "$arg" 'SKILL.md')
  else
    echo "detect.sh: no such file or directory: $arg" >&2
    exit 2
  fi
done

if [[ ${#TARGETS[@]} -eq 0 ]]; then
  printf 'summary\tfiles=0\tpointers=0\tunresolved=0\torphans=0\tchains=0\n'
  exit 0
fi

# A file passed directly that IS a SKILL.md also registers its hub root.
for t in "${TARGETS[@]}"; do
  if [[ "$(basename "$t")" == "SKILL.md" ]]; then
    HUB_ROOTS+=("$(dirname "$t")")
  fi
done

# --- helpers -----------------------------------------------------------------

# Frontmatter block of a file (between leading --- fences), empty if none.
frontmatter() {
  awk 'NR==1 && $0!="---" {exit} NR==1 {inside=1; next}
       inside && $0=="---" {exit} inside {print}' "$1"
}

# Load-tier classification per the skill's tier model (path + frontmatter
# heuristic; the judgment layer owns ambiguous cases).
classify_tier() {
  local path="$1" base fm
  base="$(basename "$path")"
  case "$base" in
  CLAUDE.md | CLAUDE.local.md | AGENTS.md | MEMORY.md)
    printf 'always'
    return
    ;;
  SKILL.md)
    printf 'invocation'
    return
    ;;
  *) ;;
  esac
  case "$path" in
  */.claude/rules/*.md | .claude/rules/*.md)
    fm="$(frontmatter "$path")"
    if printf '%s\n' "$fm" | grep -Eq '^[[:space:]]*paths[[:space:]]*:'; then
      printf 'invocation'
    else
      printf 'always'
    fi
    return
    ;;
  */.claude/agents/*.md | .claude/agents/*.md | */agents/*.md | \
    */.claude/commands/*.md | .claude/commands/*.md | */commands/*.md)
    printf 'invocation'
    return
    ;;
  */context/*.md | */reference/*.md | */references/*.md | */docs/*.md | docs/*.md)
    printf 'on-demand'
    return
    ;;
  *) ;;
  esac
  printf 'unknown'
}

# TOC heuristic: >=3 in-page anchor links anywhere in the file.
has_toc() {
  local n
  n="$(grep -c '](#' "$1" 2>/dev/null || true)"
  [[ "${n:-0}" -ge 3 ]] && printf 'yes' || printf 'no'
}

# Relative markdown link targets in a file, one "line<TAB>target<TAB>ctx" per
# link. Skips absolute URLs, mailto, and pure in-page anchors; strips any
# #anchor suffix from the target. Inline-code spans are not stripped — the
# judgment layer sees ctx and can dismiss code-fenced examples.
md_links() {
  grep -n -o '\][(][^)#][^)]*[)]' "$1" 2>/dev/null |
    sed -E 's/^([0-9]+):\]\(([^)]*)\)$/\1\t\2/' |
    while IFS=$'\t' read -r ln target; do
      case "$target" in
      http://* | https://* | mailto:*) continue ;;
      *) ;;
      esac
      target="${target%%#*}"
      [[ -z "$target" ]] && continue
      case "$target" in
      *.md) ;;
      *) continue ;;
      esac
      ctx="$(sed -n "${ln}p" "$1" | sed -E 's/^[[:space:]]+//; s/[[:space:]]+$//' | cut -c1-160)"
      printf '%s\t%s\t%s\n' "$ln" "$target" "$ctx"
    done
}

# --- per-file facts + pointer inventory --------------------------------------

FILE_RECORDS="$(mktemp)"
POINTER_RECORDS="$(mktemp)"
CHAIN_RECORDS="$(mktemp)"
ORPHAN_RECORDS="$(mktemp)"
SEEN_FILES="$(mktemp)"
trap 'rm -f "$FILE_RECORDS" "$POINTER_RECORDS" "$CHAIN_RECORDS" "$ORPHAN_RECORDS" "$SEEN_FILES"' EXIT

pointers=0
unresolved=0
for f in "${TARGETS[@]}"; do
  # De-duplicate targets named more than once (file + enclosing dir).
  if grep -Fxq "$f" "$SEEN_FILES" 2>/dev/null; then
    continue
  fi
  printf '%s\n' "$f" >>"$SEEN_FILES"

  lines="$(wc -l <"$f" | tr -d '[:space:]')"
  words="$(wc -w <"$f" | tr -d '[:space:]')"
  h2="$(grep -c '^## ' "$f" 2>/dev/null || true)"
  tier="$(classify_tier "$f")"
  toc="$(has_toc "$f")"
  printf 'file\t%s\tlines=%s\twords=%s\th2=%s\ttier=%s\ttoc=%s\n' \
    "$f" "$lines" "$words" "${h2:-0}" "$tier" "$toc" >>"$FILE_RECORDS"

  dir="$(dirname "$f")"
  while IFS=$'\t' read -r ln target ctx; do
    [[ -z "${target:-}" ]] && continue
    pointers=$((pointers + 1))
    if [[ -f "$dir/$target" ]]; then
      resolved='yes'
    else
      resolved='no'
      unresolved=$((unresolved + 1))
    fi
    printf 'pointer\t%s\t%s\t%s\tresolved=%s\tctx=%s\n' \
      "$f" "$ln" "$target" "$resolved" "$ctx" >>"$POINTER_RECORDS"
  done < <(md_links "$f")
done

# --- hub-root analysis: orphan spokes + spoke-to-spoke chains ----------------

# De-duplicate hub roots.
mapfile -t HUB_ROOTS < <(printf '%s\n' "${HUB_ROOTS[@]:-}" | grep -v '^$' | LC_ALL=C sort -u)

chains=0
orphans=0
for hub in "${HUB_ROOTS[@]:-}"; do
  [[ -n "$hub" && -f "$hub/SKILL.md" ]] || continue
  # Spokes: md files under the hub's subdirectories (scripts/, vendor/, and
  # evals are not disclosure spokes — excluded relative to the hub root).
  while IFS= read -r spoke; do
    rel="${spoke#"$hub"/}"
    case "$rel" in
    scripts/* | vendor/* | evals/* | node_modules/*) continue ;;
    *) ;;
    esac
    # Referenced from any OTHER md in the hub tree?
    if ! grep -rFl --include='*.md' "$(basename "$spoke")" "$hub" \
      --exclude-dir=scripts --exclude-dir=vendor --exclude-dir=evals \
      2>/dev/null | grep -vFx "$spoke" | grep -q .; then
      printf 'orphan\t%s\thub=%s\n' "$spoke" "$hub" >>"$ORPHAN_RECORDS"
      orphans=$((orphans + 1))
    fi
    # Spoke-to-spoke chains: a spoke linking onward to another .md.
    while IFS=$'\t' read -r ln target ctx; do
      [[ -z "${target:-}" ]] && continue
      chains=$((chains + 1))
      printf 'chain\t%s\t%s\t%s\n' "$spoke" "$ln" "$target" >>"$CHAIN_RECORDS"
    done < <(md_links "$spoke")
  done < <(find "$hub" -mindepth 2 -type f -name '*.md' | LC_ALL=C sort)
done

# --- emit, deterministically ordered -----------------------------------------

LC_ALL=C sort "$FILE_RECORDS"
LC_ALL=C sort "$POINTER_RECORDS"
LC_ALL=C sort "$ORPHAN_RECORDS"
LC_ALL=C sort "$CHAIN_RECORDS"
files_n="$(wc -l <"$SEEN_FILES" | tr -d '[:space:]')"
printf 'summary\tfiles=%s\tpointers=%s\tunresolved=%s\torphans=%s\tchains=%s\n' \
  "$files_n" "$pointers" "$unresolved" "$orphans" "$chains"
exit 0
