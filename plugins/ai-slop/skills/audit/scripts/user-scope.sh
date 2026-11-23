#!/usr/bin/env bash
# Surfaces follow the claude-directory "File reference" table (https://code.claude.com/docs/en/claude-directory#file-reference,
# as of 2026-10-11; recheck when it adds, moves or drops a global-scope markdown file).
# Exit: 0 ok, including an empty list; 2 on a usage error or a missing root.
set -u
export LC_ALL=C
ME="user-scope.sh"

usage() {
  cat <<'EOF'
user-scope.sh: list user-level Claude Code markdown for /ai-slop:audit.

Usage:
  user-scope.sh [--memory] [--help]

Root: CLAUDE_CONFIG_DIR when set and non-empty, else $HOME/.claude.
Lists CLAUDE.md, rules/**, skills/<name>/** (where SKILL.md exists),
commands/**, agents/**, and output-styles/*.md; --memory adds
projects/*/memory/*.md and agent-memory/*/*.md.
Exit: 0 ok, 2 usage error or missing root.
EOF
}

memory=0
while [[ $# -gt 0 ]]; do
  case "$1" in
  --memory) memory=1 ;;
  --help | -h) usage; exit 0 ;;
  *) echo "$ME: unknown argument: $1" >&2; usage >&2; exit 2 ;;
  esac
  shift
done

root="${CLAUDE_CONFIG_DIR:-}"
if [[ -z "$root" ]]; then
  [[ -n "${HOME:-}" ]] || { echo "$ME: neither CLAUDE_CONFIG_DIR nor HOME is set" >&2; exit 2; }
  root="$HOME/.claude"
fi
[[ -d "$root" ]] || { echo "$ME: config root not found: $root" >&2; exit 2; }
# Windows form (C:/...) under MSYS, where `pwd -W` exists; plain pwd elsewhere.
root="$(CDPATH='' cd -- "$root" && { pwd -W 2>/dev/null || pwd; })" ||
  { echo "$ME: cannot enter config root: $root" >&2; exit 2; }
realroot=""
command -v realpath >/dev/null 2>&1 && realroot="$(realpath -- "$root" 2>/dev/null)"
if [[ "$realroot" == *[$'\n\t']* ]]; then
  echo "$ME: config root resolves to a path holding a newline or tab: $(printf '%q' "$realroot")" >&2
  exit 2
fi
warned_realpath=0

warn() { printf '%s: %s\n' "$ME" "$*" >&2; }

plain_dir() {
  if [[ -L "$1" ]]; then
    [[ -d "$1" ]] && warn "symlinked directory not followed: $1"
    return 1
  fi
  [[ -d "$1" ]]
}

consider() {
  local p="$1" t
  if [[ "$p" == *[$'\n\t']* ]]; then
    warn "skipped a path holding a newline or tab: $(printf '%q' "$p")"
    return
  fi
  if [[ -L "$p" ]]; then
    if [[ -d "$p" ]]; then
      warn "symlinked directory not followed: $p"
      return
    fi
    [[ "$p" == *.md ]] || return
    if [[ -z "$realroot" ]]; then
      [[ "$warned_realpath" == 1 ]] || warn "realpath unavailable; symlinks skipped"
      warned_realpath=1
      return
    fi
    t="$(realpath -- "$p" 2>/dev/null)"
    if [[ "$t" == *[$'\n\t']* ]]; then
      warn "skipped symlink to a path holding a newline or tab: $p"
      return
    fi
    if [[ "$t" == *.md && "$t" == "$realroot"/* && -f "$t" && -r "$t" ]]; then
      printf '%s\t1\t%s\n' "$t" "$p"
    else
      warn "skipped symlink: $p -> ${t:-(unresolvable)}"
    fi
    return
  fi
  [[ -f "$p" && -r "$p" ]] && printf '%s\t0\t%s\n' "${realroot:-$root}${p#"$root"}" "$p"
}

collect() {
  local p
  plain_dir "$1" || return 0
  while IFS= read -r -d '' p; do
    consider "$p"
  done < <(find "$1" "${@:2}" \( -type f -name '*.md' -o -type l \) -print0)
}

list() {
  local d
  [[ -e "$root/CLAUDE.md" || -L "$root/CLAUDE.md" ]] && consider "$root/CLAUDE.md"
  collect "$root/rules"
  if plain_dir "$root/skills"; then
    for d in "$root"/skills/*/; do
      d="${d%/}"
      plain_dir "$d" && [[ -f "$d/SKILL.md" ]] && collect "$d"
    done
  fi
  collect "$root/commands"
  collect "$root/agents"
  collect "$root/output-styles" -maxdepth 1
  if [[ "$memory" == 1 ]]; then
    if [[ -f "$root/settings.json" && -r "$root/settings.json" ]] &&
      grep -q '"autoMemoryDirectory"' "$root/settings.json"; then
      warn "settings.json sets autoMemoryDirectory; that directory is not listed, pass it as a path target"
    fi
    if plain_dir "$root/projects"; then
      for d in "$root"/projects/*/; do
        d="${d%/}"
        plain_dir "$d" && collect "$d/memory" -maxdepth 1
      done
    fi
    if plain_dir "$root/agent-memory"; then
      for d in "$root"/agent-memory/*/; do collect "${d%/}" -maxdepth 1; done
    fi
  fi
}

out="$(list | sort -t$'\t' -k1,1 -k2,2n | awk -F'\t' '$1 != prev { print $3; prev = $1 }' | sort)"
if [[ -z "$out" ]]; then
  echo "$ME: no user-scope markdown under $root" >&2
  exit 0
fi
printf '%s\n' "$out"
