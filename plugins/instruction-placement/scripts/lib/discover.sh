#!/usr/bin/env bash
# discover.sh — the shared discovery layer for this plugin's engines.
#
# WHY THIS EXISTS AS ITS OWN FILE. Version 0.1.0 open-coded discovery inside
# each engine as a single `find .claude/rules`, and every one of the four bugs
# found after release lived in that one line: nested rules trees were invisible,
# symlinked rules were invisible, untracked and vendored files were indexed, and
# the index could be written somewhere Claude Code never reads. Discovery is the
# layer the rest of the plugin trusts, so it is defined once, tested on its own,
# and reused by glob-tools.sh, render-index.sh, and detect.sh.
#
# Source it; it defines functions and runs nothing on its own.
#
#   ip_discover_rules <root>
#       Every rule file Claude Code would load, at any depth, following symlinks.
#
#   ip_discover_nested_instructions <root>
#       Tracked CLAUDE.md / AGENTS.md files BELOW the root, which load on demand.
#
#   ip_index_target_loaded <root> <target>
#       Whether Claude Code would actually load <target>. Exit 0 reachable,
#       1 unreachable; prints "<VERDICT>\t<reason>".

# ---------------------------------------------------------------------------
# Portable canonicalization.
#
# `readlink -f` is GNU-only; BSD readlink (macOS) has no -f, and a `|| echo $1`
# fallback would silently return the UNRESOLVED path — which would break the
# symlink dedupe and the import-chain comparison on exactly the platform the
# fallback was meant to protect. Plain `readlink <file>` is portable, and
# `cd -P` + `pwd -P` resolves directory symlinks anywhere, so the resolution is
# done by hand instead.
# ---------------------------------------------------------------------------
ip_realpath() {
  local p="${1:-}" dir base target hops=0
  [[ -n "$p" ]] || return 0
  if [[ ! -e "$p" ]]; then
    printf '%s' "$p"
    return 0
  fi
  if [[ -d "$p" ]]; then
    (cd -P "$p" 2>/dev/null && pwd -P) || printf '%s' "$p"
    return 0
  fi

  dir="$(cd -P "$(dirname "$p")" 2>/dev/null && pwd -P)" || {
    printf '%s' "$p"
    return 0
  }
  base="$(basename "$p")"

  # Follow a symlink chain by hand, bounded so a cycle cannot spin forever.
  while [[ -L "$dir/$base" ]] && ((hops < 32)); do
    target="$(readlink "$dir/$base" 2>/dev/null)" || break
    [[ -n "$target" ]] || break
    case "$target" in
    /*)
      dir="$(cd -P "$(dirname "$target")" 2>/dev/null && pwd -P)" || break
      ;;
    *)
      dir="$(cd -P "$dir/$(dirname "$target")" 2>/dev/null && pwd -P)" || break
      ;;
    esac
    base="$(basename "$target")"
    hops=$((hops + 1))
  done

  printf '%s/%s' "$dir" "$base"
}

# ---------------------------------------------------------------------------
# Rules discovery
#
# Two deliberate asymmetries against the nested-instruction discovery below:
#
#   * Symlinks are FOLLOWED. Upstream documents `.claude/rules/` symlinks as the
#     supported way to share one rule set across projects, so a symlinked file
#     or directory is a first-class rule, not an edge case.
#   * Tracked status is NOT required. A symlinked rule points outside the
#     repository by design and is therefore never tracked; gating on git here
#     would delete the very feature the previous point supports.
# ---------------------------------------------------------------------------
ip_discover_rules() {
  local root="${1:-.}"
  [[ -d "$root" ]] || return 0

  local rules_dir found_file real seen_file emitted
  seen_file="$(mktemp)" || return 1
  emitted="$(mktemp)" || {
    rm -f "$seen_file"
    return 1
  }

  # Every `.claude/rules` directory at any depth, not just the root one.
  while IFS= read -r rules_dir; do
    [[ -z "$rules_dir" ]] && continue
    # -L follows symlinked entries and symlinked directories. GNU find detects
    # symlink loops itself and reports them on stderr, which is discarded; the
    # realpath dedupe below is what keeps a loop from producing repeats.
    while IFS= read -r found_file; do
      [[ -z "$found_file" ]] && continue
      real="$(ip_realpath "$found_file")"
      printf '%s\t%s\n' "$real" "${found_file#"$root"/}" >>"$seen_file"
    done < <(find -L "$rules_dir" -type f -name '*.md' 2>/dev/null)
  done < <(find "$root" -type d -name rules -path '*/.claude/rules' \
    -not -path '*/.git/*' -not -path '*/node_modules/*' 2>/dev/null)

  # One entry per REAL file. When a symlink loop or a duplicate link exposes the
  # same file under several paths, keep the shallowest, then the lexically first
  # — so a loop reports `.claude/rules/ok.md`, never `.claude/rules/loop/ok.md`.
  LC_ALL=C sort "$seen_file" | awk -F'\t' '
    {
      depth = gsub(/\//, "/", $2)
      if (!($1 in best) || depth < bestdepth[$1] ||
          (depth == bestdepth[$1] && $2 < best[$1])) {
        best[$1] = $2
        bestdepth[$1] = depth
      }
    }
    END { for (k in best) print best[k] }
  ' | LC_ALL=C sort >"$emitted"

  cat "$emitted"
  rm -f "$seen_file" "$emitted"
}

# ---------------------------------------------------------------------------
# Nested instruction-file discovery
#
# Tracked-only, and excluding vendored trees. Both are corpus rules rather than
# performance shortcuts: what is not tracked is not a shared convention, and
# vendored third-party instructions must never be pulled into the consuming
# repository's own always-loaded surface.
#
# Root-level files are excluded because they already load at session start;
# this function answers "what loads on demand", which is what the index covers.
# ---------------------------------------------------------------------------
ip_discover_nested_instructions() {
  local root="${1:-.}"
  [[ -d "$root" ]] || return 0

  local listing
  if git -C "$root" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    listing="$(git -C "$root" ls-files -z 2>/dev/null | tr '\0' '\n')"
  else
    # Not a repository: fall back to a plain walk. Tracked status is unknowable
    # here, so the vendor exclusions below carry the whole filter.
    listing="$(cd "$root" && find . -type f \
      \( -name 'CLAUDE.md' -o -name 'AGENTS.md' \) 2>/dev/null | sed 's|^\./||')"
  fi

  printf '%s\n' "$listing" | awk '
    $0 == "" { next }
    {
      n = split($0, seg, "/")
      if (n < 2) next                                   # root-level: loads at start
      base = seg[n]
      if (base != "CLAUDE.md" && base != "AGENTS.md") next
      for (i = 1; i < n; i++) {
        if (seg[i] == ".claude" || seg[i] == "node_modules" ||
            seg[i] == "vendor" || seg[i] == ".git") next
      }
      print
    }
  ' | LC_ALL=C sort
}

# ---------------------------------------------------------------------------
# Import-chain reachability
#
# Writing the index into a root AGENTS.md is only useful if Claude Code loads
# that file, and it loads CLAUDE.md — not AGENTS.md. A repository carrying both
# with no import between them gets an index nothing ever reads, while every
# other gate reports green. This function is what stops that.
# ---------------------------------------------------------------------------

# Emit the @import targets of one markdown file, resolved to absolute paths.
# Fenced code blocks and inline code spans are skipped: upstream documents that
# import parsing ignores both, so a `@AGENTS.md` shown inside an example fence
# is documentation, not wiring.
_ip_imports_of() {
  local file="$1" dir
  dir="$(cd "$(dirname "$file")" && pwd)"
  awk '
    /^[[:space:]]*```/ { fence = !fence; next }
    fence { next }
    {
      line = $0
      gsub(/`[^`]*`/, "", line)          # drop inline code spans
      n = split(line, tok, /[[:space:]]+/)
      for (i = 1; i <= n; i++) {
        if (substr(tok[i], 1, 1) == "@" && length(tok[i]) > 1) {
          t = substr(tok[i], 2)
          sub(/[.,;:)]+$/, "", t)
          if (t != "") print t
        }
      }
    }
  ' "$file" 2>/dev/null | while IFS= read -r target; do
    case "$target" in
    /*) printf '%s\n' "$target" ;;
    "~"/*) printf '%s\n' "${HOME}/${target#\~/}" ;;
    *) printf '%s\n' "$dir/$target" ;;
    esac
  done
}

# Depth-bounded walk of the import graph. Upstream caps imports at four hops, so
# a file reachable only past that depth is genuinely not loaded.
_ip_reaches() {
  local from="$1" want="$2" depth="${3:-0}"
  ((depth > 4)) && return 1
  [[ -f "$from" ]] || return 1

  local resolved import_real
  resolved="$(ip_realpath "$from")"
  [[ "$resolved" == "$want" ]] && return 0

  local imported
  while IFS= read -r imported; do
    [[ -z "$imported" ]] && continue
    import_real="$(ip_realpath "$imported")"
    [[ "$import_real" == "$want" ]] && return 0
    if [[ -f "$import_real" ]] && _ip_reaches "$import_real" "$want" $((depth + 1)); then
      return 0
    fi
  done < <(_ip_imports_of "$from")
  return 1
}

ip_index_target_loaded() {
  local root="${1:-.}" target="${2:-}"
  [[ -n "$target" ]] || {
    printf 'UNREACHABLE\tno target given\n'
    return 1
  }

  local abs_target
  abs_target="$(ip_realpath "$root/$target")"
  if [[ ! -f "$abs_target" ]]; then
    printf 'UNREACHABLE\t%s does not exist\n' "$target"
    return 1
  fi

  # A root memory file is loaded by Claude Code directly, with no import needed.
  case "$target" in
  CLAUDE.md | CLAUDE.local.md | .claude/CLAUDE.md)
    printf 'LOADED\t%s is a root memory file, loaded at session start\n' "$target"
    return 0
    ;;
  *) ;;
  esac

  # Otherwise it must be reachable from one, by import or by symlink.
  local entry
  for entry in "$root/CLAUDE.md" "$root/.claude/CLAUDE.md" "$root/CLAUDE.local.md"; do
    [[ -f "$entry" ]] || continue
    if _ip_reaches "$entry" "$abs_target" 0; then
      printf 'LOADED\t%s reaches %s\n' "${entry#"$root"/}" "$target"
      return 0
    fi
  done

  printf 'UNREACHABLE\t%s is not imported by any root memory file; Claude Code reads CLAUDE.md, not %s\n' \
    "$target" "$target"
  return 1
}
