#!/usr/bin/env bash
# instruction-load-stats.sh — how much instruction content actually loads at launch.
# Counts each root WITH its `@path` imports expanded, via the same lib/imports.sh
# parser the nested-AGENTS.md check uses, since imported files load at launch.
# A project import outside the repository is listed as `external`, never expanded:
# the loader gates it behind an approval dialog this script cannot see.
# --lines, --bytes, and --tokens print one integer and exit 0 (missing file: 0),
# because pre-compute lines inject stdout verbatim. A bad mode exits 2.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/imports.sh
source "$SCRIPT_DIR/lib/imports.sh"
# shellcheck source=lib/rule-scope.sh
source "$SCRIPT_DIR/lib/rule-scope.sh"
# shellcheck source=lib/agents-md.sh
source "$SCRIPT_DIR/lib/agents-md.sh"

usage() {
  cat <<'EOF'
instruction-load-stats.sh — size of the instruction layer as Claude Code loads it.

Usage: instruction-load-stats.sh (--lines|--bytes) [--file <path>]
       instruction-load-stats.sh (--tokens|--breakdown|--help)

  --lines       non-blank loaded lines of one root file with its @imports expanded
  --bytes       loaded bytes of that file with its @imports expanded
  --file <p>    the root file (default: CLAUDE.md, else .claude/CLAUDE.md, else the
                first AGENTS.md nothing displaces)
  --tokens      estimated tokens (bytes / 4) of the whole always-loaded set
  --breakdown   one TSV row per loaded file: status, lines, bytes, path; then TOTAL
  --help        this message

Block-level HTML comments are stripped before counting; comments inside fenced
code are kept. Imports follow the memory doc: relative to the importing file,
four hops deep, code spans and fences skipped. An import outside the repository
is listed as external and not expanded. Stat modes print one integer, exit 0.
EOF
}

mode=""
file_arg=""
while (($# > 0)); do
  case "$1" in
  --lines | --bytes | --tokens | --breakdown) mode="$1" ;;
  --file)
    shift
    file_arg="${1:-}"
    ;;
  --help | -h)
    usage
    exit 0
    ;;
  *)
    usage >&2
    exit 2
    ;;
  esac
  shift
done
[[ -n "$mode" ]] || {
  usage >&2
  exit 2
}

repo_root=$(git rev-parse --show-toplevel 2>/dev/null | tr -d '\r')
[[ -n "$repo_root" ]] || repo_root="$PWD"
cd "$repo_root" || exit 2
PROJECT_ROOT="$(il_realpath "$repo_root")"
# External-import boundary of the walk in progress: the repository, or the config
# dir for user-scope roots, whose imports load without the approval dialog.
IL_ROOT="$PROJECT_ROOT"
export IL_ROOT

# A comment ends at the first `-->` after its own opener; an opener that never
# closes is content, so it is flushed at EOF rather than eaten.
loaded_content() {
  tr -d '\r' <"$1" | LC_ALL=C awk '
    function uncomment(s,   p, q, out) {
      while ((p = index(s, "<!--")) > 0) {
        out = out substr(s, 1, p - 1)
        q = index(substr(s, p + 4), "-->")
        if (q == 0) { incomment = 1; pending = substr(s, p) "\n"; return out }
        s = substr(s, p + q + 6)
      }
      return out s
    }
    incomment {
      pending = pending $0 "\n"
      close_at = index($0, "-->")
      if (close_at == 0) next
      incomment = 0; pending = ""
      print uncomment(substr($0, close_at + 3))
      next
    }
    /^[[:space:]]*```/ { fence = !fence; print; next }
    fence { print; next }
    /<!--/ { print uncomment($0); next }
    { print }
    END { printf "%s", pending }
  '
}

count_lines() { loaded_content "$1" | grep -c '[^[:space:]]'; }
count_bytes() { loaded_content "$1" | wc -c; }

# One `<scope>\t<path>` per always-loaded root. The user scope loads in every
# session of every project; a file both scopes reach is counted once, below.
scope_roots() {
  local scope="$1" base="$2" f
  if [[ "$scope" == "project" ]]; then
    for f in CLAUDE.md .claude/CLAUDE.md CLAUDE.local.md; do
      [[ -f "$f" ]] && printf '%s\t%s\n' "$scope" "$f"
    done
    # Only natively loaded AGENTS.md files: a shim already reaches one as an import,
    # and a displacing CLAUDE.md that does not import it means it never loads.
    while IFS= read -r agents_file; do
      [[ -n "$agents_file" ]] && printf '%s\t%s\n' "$scope" "$agents_file"
    done < <(agents_md_native_files)
  else
    [[ -f "$base/CLAUDE.md" ]] && printf '%s\t%s\n' "$scope" "$base/CLAUDE.md"
  fi
  [[ -d "$base/rules" ]] || return 0
  while IFS= read -r f; do
    [[ -n "$f" ]] || continue
    is_unscoped_rule "$f" && printf '%s\t%s\n' "$scope" "$f"
  done < <(find "$base/rules" -name '*.md' -type f 2>/dev/null | LC_ALL=C sort)
}

always_loaded_roots() {
  scope_roots project .claude
  local user_dir="${CLAUDE_CONFIG_DIR:-${HOME:-}/.claude}"
  [[ -n "${CLAUDE_CONFIG_DIR:-}${HOME:-}" && -d "$user_dir" ]] || return 0
  scope_roots user "$user_dir"
}

is_unscoped_rule() {
  ! rule_frontmatter_declares "$1" paths
}

relpath() {
  local p="$1"
  [[ "$p" == "$PROJECT_ROOT"/* ]] && p="${p#"$PROJECT_ROOT"/}"
  printf '%s' "$p"
}

if [[ "$mode" == "--lines" || "$mode" == "--bytes" ]]; then
  target="$file_arg"
  if [[ -z "$target" ]]; then
    for f in CLAUDE.md .claude/CLAUDE.md; do
      [[ -f "$f" ]] && {
        target="$f"
        break
      }
    done
    [[ -z "$target" ]] && target="$(agents_md_native_files | head -1)"
  fi
  if [[ -z "$target" || ! -f "$target" ]]; then
    echo 0
    exit 0
  fi
  total=0
  while IFS=$'\t' read -r status path; do
    case "$status" in
    root | import)
      if [[ "$mode" == "--lines" ]]; then n=$(count_lines "$path"); else n=$(count_bytes "$path"); fi
      total=$((total + n))
      ;;
    *) ;;
    esac
  done < <(il_walk "$target")
  printf '%s\n' "$total"
  exit 0
fi

declare -A counted=()
rows=()
lines_total=0
bytes_total=0
while IFS=$'\t' read -r scope root; do
  [[ -n "$root" ]] || continue
  if [[ "$scope" == "user" ]]; then
    IL_ROOT="$(il_realpath "${CLAUDE_CONFIG_DIR:-${HOME:-}/.claude}")"
  else
    IL_ROOT="$PROJECT_ROOT"
  fi
  while IFS=$'\t' read -r status path; do
    [[ -n "$path" ]] || continue
    case "$status" in
    root | import)
      [[ -n "${counted[$path]:-}" ]] && continue
      counted[$path]=1
      l=$(count_lines "$path")
      b=$(count_bytes "$path")
      lines_total=$((lines_total + l))
      bytes_total=$((bytes_total + b))
      rows+=("$(printf '%s\t%s\t%s\t%s\t%s' "$scope" "$status" "$l" "$b" "$(relpath "$path")")")
      ;;
    *)
      key="$status $path"
      [[ -n "${counted[$key]:-}" ]] && continue
      counted[$key]=1
      rows+=("$(printf '%s\t%s\t0\t0\t%s' "$scope" "$status" "$(relpath "$path")")")
      ;;
    esac
  done < <(il_walk "$root")
done < <(always_loaded_roots)

tokens=$((bytes_total / 4))
if [[ "$mode" == "--tokens" ]]; then
  printf '%s\n' "$tokens"
  exit 0
fi

printf 'scope\tstatus\tlines\tbytes\tpath\n'
for row in ${rows[@]+"${rows[@]}"}; do printf '%s\n' "$row"; done
printf 'TOTAL\t%s\t%s\t~%s tokens (bytes/4, estimate)\n' "$lines_total" "$bytes_total" "$tokens"
exit 0
