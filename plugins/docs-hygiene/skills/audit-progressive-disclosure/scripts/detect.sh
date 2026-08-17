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
TROOTS=()
HUB_ROOTS=()
for arg in "$@"; do
  if [[ -f "$arg" ]]; then
    TARGETS+=("$arg")
    TROOTS+=("$(dirname "$arg")")
  elif [[ -d "$arg" ]]; then
    while IFS= read -r f; do
      TARGETS+=("$f")
      TROOTS+=("$arg")
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
# heuristic; the judgment layer owns ambiguous cases). $2 is the path relative
# to its scan root: a root-level CLAUDE.md/AGENTS.md is always-loaded, but the
# same basename nested deeper is a SUBTREE file — loaded when Claude reads
# that directory, i.e. invocation tier (per context/tier-model.md).
classify_tier() {
  local path="$1" rel="$2" base fm
  base="$(basename "$path")"
  case "$base" in
  CLAUDE.md | CLAUDE.local.md | AGENTS.md | MEMORY.md)
    if [[ "$rel" == "$base" ]]; then
      printf 'always'
    else
      printf 'invocation'
    fi
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

# TOC heuristic: >=3 in-page anchor LINKS (grep -o counts occurrences, so a
# compact one-line TOC counts every link) within the first 40 lines — a TOC
# lives at the top; scattered anchor links deep in the body are not one.
has_toc() {
  local n
  n="$(head -40 "$1" 2>/dev/null | grep -o '](#' | wc -l | tr -d '[:space:]')"
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
for i in "${!TARGETS[@]}"; do
  f="${TARGETS[$i]}"
  root="${TROOTS[$i]}"
  # De-duplicate targets named more than once (file + enclosing dir).
  if grep -Fxq "$f" "$SEEN_FILES" 2>/dev/null; then
    continue
  fi
  printf '%s\n' "$f" >>"$SEEN_FILES"

  rel="${f#"$root"/}"
  lines="$(wc -l <"$f" | tr -d '[:space:]')"
  words="$(wc -w <"$f" | tr -d '[:space:]')"
  h2="$(grep -c '^## ' "$f" 2>/dev/null || true)"
  tier="$(classify_tier "$f" "$rel")"
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
# Lexically normalize a path: drop '.' segments, resolve '..'. Returns 1 when
# '..' escapes the path root (mirrors the sibling audit-encapsulation
# resolver; realpath is avoided for Git Bash parity).
normalize() {
  local raw="$1" seg prefix=""
  [[ "$raw" == /* ]] && prefix="/"
  local -a out=()
  while IFS= read -r seg; do
    case "$seg" in
    '' | '.') continue ;;
    '..')
      ((${#out[@]})) || return 1
      out=("${out[@]:0:${#out[@]}-1}")
      ;;
    *) out+=("$seg") ;;
    esac
  done < <(printf '%s\n' "${raw//\//$'\n'}")
  (
    IFS=/
    printf '%s%s' "$prefix" "${out[*]}"
  )
}

# Candidate spoke references in a file: markdown-link targets plus
# backtick-quoted .md path mentions (hubs legitimately cite spokes either
# way; reachability honors both, but only ROOTED at the hub).
ref_candidates() {
  {
    md_links "$1" | cut -f2
    # shellcheck disable=SC2016  # literal backticks are the matched delimiters
    grep -oE '`[^` ]+\.md`' "$1" 2>/dev/null | tr -d '`'
  } | LC_ALL=C sort -u
}

for hub in "${HUB_ROOTS[@]:-}"; do
  [[ -n "$hub" && -f "$hub/SKILL.md" ]] || continue
  # Reachability BFS from the hub: a spoke counts as referenced only when a
  # chain of links/mentions leads to it FROM SKILL.md — an arbitrary inbound
  # mention (e.g. two unreferenced spokes citing each other in a cycle) does
  # not make a file reachable.
  REACHED="$(mktemp)"
  printf '%s\n' "$hub/SKILL.md" >"$REACHED"
  queue=("$hub/SKILL.md")
  while ((${#queue[@]})); do
    cur="${queue[0]}"
    queue=("${queue[@]:1}")
    curdir="$(dirname "$cur")"
    while IFS= read -r cand; do
      [[ -z "$cand" ]] && continue
      for base_dir in "$curdir" "$hub"; do
        # shellcheck disable=SC2310  # normalize failure = unresolvable ref; skip is the handling
        t="$(normalize "$base_dir/$cand")" || continue
        [[ -f "$t" ]] || continue
        case "$t" in
        "$hub"/*) ;;
        *) continue ;;
        esac
        if ! grep -Fxq "$t" "$REACHED"; then
          printf '%s\n' "$t" >>"$REACHED"
          queue+=("$t")
        fi
      done
    done < <(ref_candidates "$cur")
  done
  # Spokes: md files under the hub's subdirectories (scripts/, vendor/, and
  # evals are not disclosure spokes — excluded relative to the hub root).
  while IFS= read -r spoke; do
    rel="${spoke#"$hub"/}"
    case "$rel" in
    scripts/* | vendor/* | evals/* | node_modules/*) continue ;;
    *) ;;
    esac
    if ! grep -Fxq "$spoke" "$REACHED"; then
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
  rm -f "$REACHED"
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
