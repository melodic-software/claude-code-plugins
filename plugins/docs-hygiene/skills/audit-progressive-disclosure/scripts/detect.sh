#!/usr/bin/env bash
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
if [[ "$1" == "--help" || "$1" == "-h" ]]; then
  usage
  exit 0
fi

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
    TROOTS+=(".")
  elif [[ -d "$arg" ]]; then
    while IFS= read -r f; do
      TARGETS+=("$f")
      TROOTS+=("$arg")
    done < <(collect "$arg" '*.md')
  else
    echo "detect.sh: no such file or directory: $arg" >&2
    exit 2
  fi
done

if [[ ${#TARGETS[@]} -eq 0 ]]; then
  printf 'summary\tfiles=0\tpointers=0\tunresolved=0\torphans=0\tchains=0\n'
  exit 0
fi

for t in "${TARGETS[@]}"; do
  if [[ "$(basename "$t")" == "SKILL.md" ]]; then
    HUB_ROOTS+=("$(dirname "$t")")
  fi
done

frontmatter() {
  awk 'NR==1 && $0!="---" {exit} NR==1 {inside=1; next}
       inside && $0=="---" {exit} inside {print}' "$1"
}

classify_tier() {
  local path="$1" rel="$2" base fm repo_root
  base="$(basename "$path")"
  case "$base" in
  CLAUDE.md | CLAUDE.local.md | AGENTS.md | MEMORY.md)
    repo_root=no
    [[ "$base" == MEMORY.md ]] || repo_root="$(at_repo_root "$path")"
    if [[ "$rel" == "$base" || "$repo_root" == yes ]]; then
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
    if grep -Eq '^[[:space:]]*paths[[:space:]]*:' <<<"$fm"; then
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

at_repo_root() {
  local dir
  dir="$(dirname "$1")"
  if [[ "$dir" == "." ]]; then
    dir="$PWD"
  fi
  if [[ -e "$dir/.git" ]]; then
    printf 'yes'
  else
    printf 'no'
  fi
}

has_toc() {
  local n
  n="$(head -40 "$1" 2>/dev/null | grep -o '](#' | wc -l | tr -d '[:space:]')"
  [[ "${n:-0}" -ge 3 ]] && printf 'yes' || printf 'no'
}

md_links() {
  { grep -n -o '\][(][^)#][^)]*[)]' "$1" 2>/dev/null || true; } |
    sed -E 's/^([0-9]+):\]\(([^)]*)\)$/\1\t\2/' |
    while IFS=$'\t' read -r ln target; do
      target="${target%%#*}"
      case "$target" in
      http://* | https://* | mailto:*) continue ;;
      *.md) ;;
      *) continue ;;
      esac
      printf '%s\t%s\t%s\n' "$ln" "$target" "$(line_ctx "$1" "$ln")"
    done
}

line_ctx() {
  sed -n "${2}p" "$1" | sed -E 's/^[[:space:]]+//; s/[[:space:]]+$//' | cut -c1-160
}

backtick_paths() {
  local hit ln span target
  # shellcheck disable=SC2016  # literal backticks are the matched delimiters
  { grep -n -oE '`[^`[:space:]]+`' "$1" 2>/dev/null || true; } |
    while IFS= read -r hit; do
      ln="${hit%%:*}"
      span="${hit#*:}"
      span="${span//\`/}"
      target="${span%%#*}"
      case "$target" in
      /* | *[!A-Za-z0-9._+/-]*) continue ;;
      */*.md) ;;
      *) continue ;;
      esac
      printf '%s\t%s\t%s\n' "$ln" "$target" "$(line_ctx "$1" "$ln")"
    done
}

FILE_RECORDS="$(mktemp)"
POINTER_RECORDS="$(mktemp)"
CHAIN_RECORDS="$(mktemp)"
ORPHAN_RECORDS="$(mktemp)"
trap 'rm -f "$FILE_RECORDS" "$POINTER_RECORDS" "$CHAIN_RECORDS" "$ORPHAN_RECORDS"' EXIT

declare -A seen_files=() seen_ptr=() reached=()
pointers=0
unresolved=0
for i in "${!TARGETS[@]}"; do
  f="${TARGETS[$i]}"
  root="${TROOTS[$i]}"
  [[ -n "${seen_files[$f]:-}" ]] && continue
  seen_files[$f]=1

  rel="${f#"$root"/}"
  lines="$(wc -l <"$f" | tr -d '[:space:]')"
  words="$(wc -w <"$f" | tr -d '[:space:]')"
  h2="$(grep -c '^## ' "$f" 2>/dev/null || true)"
  tier="$(classify_tier "$f" "$rel")"
  toc="$(has_toc "$f")"
  printf 'file\t%s\tlines=%s\twords=%s\th2=%s\ttier=%s\ttoc=%s\n' \
    "$f" "$lines" "$words" "${h2:-0}" "$tier" "$toc" >>"$FILE_RECORDS"

  dir="$(dirname "$f")"
  seen_ptr=()
  while IFS=$'\t' read -r ln target ctx; do
    [[ -z "${target:-}" ]] && continue
    key="$ln"$'\t'"$target"
    [[ -n "${seen_ptr[$key]:-}" ]] && continue
    seen_ptr[$key]=1
    pointers=$((pointers + 1))
    if [[ -f "$dir/$target" ]]; then
      resolved='yes'
    else
      resolved='no'
      unresolved=$((unresolved + 1))
    fi
    printf 'pointer\t%s\t%s\t%s\tresolved=%s\tctx=%s\n' \
      "$f" "$ln" "$target" "$resolved" "$ctx" >>"$POINTER_RECORDS"
  done < <(
    md_links "$f"
    backtick_paths "$f"
  )
done

mapfile -t HUB_ROOTS < <(printf '%s\n' "${HUB_ROOTS[@]:-}" | grep -v '^$' | LC_ALL=C sort -u)

chains=0
orphans=0
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

ref_candidates() {
  {
    md_links "$1" | cut -f2
    # shellcheck disable=SC2016  # literal backticks are the matched delimiters
    { grep -oE '`[^` ]+\.md`' "$1" 2>/dev/null || true; } | tr -d '`'
    backtick_paths "$1" | cut -f2
  } | LC_ALL=C sort -u
}

for hub in "${HUB_ROOTS[@]:-}"; do
  [[ -n "$hub" && -f "$hub/SKILL.md" ]] || continue
  reached=(["$hub/SKILL.md"]=1)
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
        if [[ -z "${reached[$t]:-}" ]]; then
          reached[$t]=1
          queue+=("$t")
        fi
      done
    done < <(ref_candidates "$cur")
  done
  while IFS= read -r spoke; do
    rel="${spoke#"$hub"/}"
    case "$rel" in
    scripts/* | vendor/* | evals/* | node_modules/*) continue ;;
    *) ;;
    esac
    if [[ -z "${reached[$spoke]:-}" ]]; then
      printf 'orphan\t%s\thub=%s\n' "$spoke" "$hub" >>"$ORPHAN_RECORDS"
      orphans=$((orphans + 1))
    fi
    while IFS=$'\t' read -r ln target ctx; do
      [[ -z "${target:-}" ]] && continue
      chains=$((chains + 1))
      printf 'chain\t%s\t%s\t%s\n' "$spoke" "$ln" "$target" >>"$CHAIN_RECORDS"
    done < <(md_links "$spoke")
  done < <(find "$hub" -mindepth 2 -type f -name '*.md' | LC_ALL=C sort)
done

LC_ALL=C sort "$FILE_RECORDS"
LC_ALL=C sort "$POINTER_RECORDS"
LC_ALL=C sort "$ORPHAN_RECORDS"
LC_ALL=C sort "$CHAIN_RECORDS"
printf 'summary\tfiles=%s\tpointers=%s\tunresolved=%s\torphans=%s\tchains=%s\n' \
  "${#seen_files[@]}" "$pointers" "$unresolved" "$orphans" "$chains"
exit 0
