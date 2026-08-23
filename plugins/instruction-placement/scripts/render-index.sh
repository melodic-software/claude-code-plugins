#!/usr/bin/env bash
# render-index.sh — generate the always-loaded index of deferred instruction surfaces.
#
# WHY. Every instruction surface that loads on demand — a path-scoped rule, a
# nested CLAUDE.md/AGENTS.md — is invisible inside subagents, and returns after
# compaction only when its trigger recurs (see context/verified-mechanics.md).
# An always-loaded index converts those surfaces from INVISIBLE to DISCOVERABLE:
# the agent learns the surface exists and can reach it with an ordinary Read from
# any context, including a subagent that would never have received the injection.
#
# This is the same trade Claude Code already makes for skills — the listing is
# always in context, the body loads on demand. The index is the listing for rules.
#
# WHAT IS INDEXED, AND WHAT IS NOT. Only surfaces that DEFER. An unscoped rule
# already loads in every session, so indexing it would spend always-loaded budget
# restating something already present. The index earns its own cost by covering
# exactly what would otherwise be missing.
#
# The block is delimited by HTML comments, which Claude Code strips from memory
# files before injecting them, so the markers cost no context while remaining
# visible on disk to this script.
#
# Subcommands:
#   render              print the block to stdout
#   check --file F      compare F's block against a fresh render
#   write --file F      replace F's block in place (creates it at end if absent)
#   reachable --file F  would Claude Code actually load F?
#
# `reachable` exists because Claude Code reads CLAUDE.md, not AGENTS.md. A
# repository carrying both with no import between them gets an index nothing
# ever reads, while every other gate reports green — the entire subagent-gap
# mitigation silently doing nothing.
#
# Usage:
#   render-index.sh render [--root <dir>]
#   render-index.sh check --file <path> [--root <dir>]
#   render-index.sh write --file <path> [--root <dir>]
#   render-index.sh reachable --file <path> [--root <dir>]
#   render-index.sh --help
#
# Exit: 0 success / in sync / reachable
#       1 check found drift, write failed, or target unreachable
#       2 usage error or unusable path
#       3 check found no index block in the file

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./lib/discover.sh
. "$SCRIPT_DIR/lib/discover.sh"

BEGIN_MARKER="<!-- BEGIN GENERATED: instruction-placement rules index -->"
END_MARKER="<!-- END GENERATED: instruction-placement rules index -->"

usage() {
  cat <<'EOF'
render-index.sh — generate the always-loaded index of deferred instruction surfaces.

Usage:
  render-index.sh render [--root <dir>]
  render-index.sh check --file <path> [--root <dir>]
  render-index.sh write --file <path> [--root <dir>]
  render-index.sh reachable --file <path> [--root <dir>]
  render-index.sh --help

render     print the generated block to stdout
check      compare the block inside <path> against a fresh render
write      replace the block inside <path> in place, appending it if absent
reachable  report whether Claude Code would load <path> at all (it reads
           CLAUDE.md, not AGENTS.md, so an unimported AGENTS.md is inert)

Indexes only surfaces that load on demand: path-scoped rules (`paths:`
frontmatter) and nested CLAUDE.md / AGENTS.md files below the repository root.
Unscoped rules and root-level instruction files already load every session and
are deliberately left out.

Exit: 0 success or in sync; 1 drift or write failure; 2 usage error; 3 no block found.
EOF
}

die() {
  printf 'ERROR: %s\n' "$1" >&2
  exit 2
}

# Rule title, in preference order: an explicit `description:` frontmatter value,
# then the first H1, then the basename. The frontmatter key is optional and
# ignored by Claude Code, which parses `paths:` and leaves other keys alone.
rule_title() {
  local file="$1" title
  title="$(awk '
    NR == 1 && $0 != "---" { exit }
    NR == 1 { next }
    $0 == "---" { exit }
    /^description:[[:space:]]*/ {
      v = $0
      sub(/^description:[[:space:]]*/, "", v)
      gsub(/^["'"'"']/, "", v)
      gsub(/["'"'"']$/, "", v)
      print v
      exit
    }
  ' "$file" 2>/dev/null)"
  if [[ -z "$title" ]]; then
    title="$(grep -m1 '^# ' "$file" 2>/dev/null | sed 's/^#[[:space:]]*//')"
  fi
  if [[ -z "$title" ]]; then
    title="$(basename "$file" .md)"
  fi
  # Pipes would break the markdown table row.
  printf '%s' "${title//|/\\|}"
}

# Comma-joined `paths:` values, or empty when the rule is unscoped.
rule_globs() {
  local file="$1"
  awk '
    NR == 1 && $0 != "---" { exit }
    NR == 1 { infm = 1; next }
    infm && $0 == "---" { exit }
    !infm { exit }
    /^paths:[[:space:]]*\[/ {
      line = $0
      sub(/^paths:[[:space:]]*\[/, "", line)
      sub(/\].*$/, "", line)
      n = split(line, parts, ",")
      for (k = 1; k <= n; k++) {
        v = parts[k]
        gsub(/^[[:space:]]*["'"'"']?/, "", v)
        gsub(/["'"'"']?[[:space:]]*$/, "", v)
        if (v != "") print v
      }
      next
    }
    /^paths:[[:space:]]*$/ { inpaths = 1; next }
    inpaths && /^[[:space:]]+-[[:space:]]*/ {
      v = $0
      sub(/^[[:space:]]+-[[:space:]]*/, "", v)
      gsub(/^["'"'"']/, "", v)
      gsub(/["'"'"']$/, "", v)
      if (v != "") print v
      next
    }
    inpaths && /^[^[:space:]]/ { inpaths = 0 }
  ' "$file" 2>/dev/null | paste -sd, - | sed 's/,/, /g'
}

# True when every non-blank, non-comment line is an `@import`. Such a file is a
# shim: it exists only so Claude Code loads the AGENTS.md beside it.
is_pure_shim() {
  local file="$1" line trimmed seen=0
  while IFS= read -r line || [[ -n "$line" ]]; do
    # Trim leading and trailing whitespace with parameter expansion only —
    # glob matching below stays portable where a regex would not.
    trimmed="${line#"${line%%[![:space:]]*}"}"
    trimmed="${trimmed%"${trimmed##*[![:space:]]}"}"
    [[ -z "$trimmed" ]] && continue
    [[ "$trimmed" == "<!--"* ]] && continue
    # An import is a single `@token` with no embedded whitespace.
    if [[ "$trimmed" == "@"?* && "$trimmed" != *[[:space:]]* ]]; then
      seen=1
      continue
    fi
    return 1
  done <"$file"
  ((seen == 1))
}

render_block() {
  local -a rows=()

  # Path-scoped rules.
  local rule globs title
  while IFS= read -r rule; do
    [[ -z "$rule" ]] && continue
    globs="$(rule_globs "$rule")"
    [[ -z "$globs" ]] && continue # unscoped: already always-loaded
    title="$(rule_title "$rule")"
    # shellcheck disable=SC2016 # backticks here are markdown code spans, not command substitution
    rows+=("$(printf '| `%s` | `%s` | %s |' "$rule" "$globs" "$title")")
  done < <(ip_discover_rules .)

  # Nested instruction files. Discovery owns the root-level, tracked-status, and
  # vendored-tree filters — an untracked or vendored file must never reach the
  # consuming repository's always-loaded surface.
  local nested dir label
  while IFS= read -r nested; do
    [[ -z "$nested" ]] && continue
    dir="$(dirname "$nested")"
    # Skip a pure shim — a CLAUDE.md whose whole body is `@import` lines carries
    # no content of its own, and the file it imports is indexed on its own row.
    # The index is always-loaded, so a row that says nothing is a real cost.
    if [[ "$(basename "$nested")" == "CLAUDE.md" ]] && is_pure_shim "$nested"; then
      continue
    fi
    label="$(grep -m1 '^# ' "$nested" 2>/dev/null | sed 's/^#[[:space:]]*//')"
    [[ -z "$label" ]] && label="Conventions for this subtree"
    # shellcheck disable=SC2016 # backticks here are markdown code spans, not command substitution
    rows+=("$(printf '| `%s` | `%s/**` | %s |' "$nested" "$dir" "${label//|/\\|}")")
  done < <(ip_discover_nested_instructions .)

  printf '%s\n' "$BEGIN_MARKER"
  if ((${#rows[@]} == 0)); then
    printf '\n%s\n\n' "No path-scoped rules or nested instruction files are present in this repository."
  else
    cat <<'PREAMBLE'

## Conventions that load on demand

Each surface below enters context automatically when Claude reads a file it covers. That trigger
does **not** fire inside subagents, and after a compaction it fires again only when a covered file
is read again. When you are working on something an entry covers and its content is not already in
context, read the file directly.

| Surface | Covers | Topic |
|---|---|---|
PREAMBLE
    printf '%s\n' "${rows[@]}" | LC_ALL=C sort
    printf '\n'
  fi
  printf '%s\n' "$END_MARKER"
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
[[ $# -eq 0 ]] && {
  usage >&2
  exit 2
}

SUBCOMMAND=""
case "${1:-}" in
-h | --help)
  usage
  exit 0
  ;;
render | check | write | reachable)
  SUBCOMMAND="$1"
  shift
  ;;
*) die "unknown subcommand: $1 (expected render, check, write, or reachable)" ;;
esac

ROOT="$PWD"
TARGET=""
while [[ $# -gt 0 ]]; do
  case "$1" in
  -h | --help)
    usage
    exit 0
    ;;
  --root)
    [[ $# -lt 2 ]] && die "--root needs a path"
    ROOT="$2"
    shift 2
    ;;
  --file)
    [[ $# -lt 2 ]] && die "--file needs a path"
    TARGET="$2"
    shift 2
    ;;
  *) die "unknown argument: $1" ;;
  esac
done

[[ -d "$ROOT" ]] || die "--root is not a directory: $ROOT"

if [[ "$SUBCOMMAND" != "render" && -z "$TARGET" ]]; then
  die "$SUBCOMMAND needs --file"
fi

# Resolve the target before entering --root, so a relative --file is read
# relative to the caller's cwd rather than silently re-anchored.
if [[ -n "$TARGET" && "$TARGET" != /* ]]; then
  TARGET="$PWD/$TARGET"
fi

cd "$ROOT" || die "cannot enter --root: $ROOT"

# `reachable` answers a question about wiring, not about content, so it runs
# before the (comparatively expensive) block render.
if [[ "$SUBCOMMAND" == "reachable" ]]; then
  rel_target="${TARGET#"$PWD"/}"
  ip_index_target_loaded "." "$rel_target"
  exit $?
fi

BLOCK="$(render_block)"

case "$SUBCOMMAND" in
render)
  printf '%s\n' "$BLOCK"
  ;;

check)
  [[ -f "$TARGET" ]] || die "--file is not a readable file: $TARGET"
  begin_count="$(grep -cF "$BEGIN_MARKER" "$TARGET")"
  if [[ "$begin_count" -gt 1 ]]; then
    printf 'NO-BLOCK\t%s\t%s begin markers; the block extent is ambiguous\n' \
      "$TARGET" "$begin_count"
    exit 3
  fi
  if ! grep -qF "$BEGIN_MARKER" "$TARGET"; then
    printf 'NO-BLOCK\t%s\n' "$TARGET"
    exit 3
  fi
  if ! grep -qF "$END_MARKER" "$TARGET"; then
    printf 'NO-BLOCK\t%s\tbegin marker present, end marker missing\n' "$TARGET"
    exit 3
  fi
  current="$(awk -v b="$BEGIN_MARKER" -v e="$END_MARKER" '
    $0 == b { inblock = 1 }
    inblock { print }
    $0 == e { inblock = 0 }
  ' "$TARGET")"
  if [[ "$current" == "$BLOCK" ]]; then
    printf 'IN-SYNC\t%s\n' "$TARGET"
    exit 0
  fi
  printf 'DRIFTED\t%s\n' "$TARGET"
  exit 1
  ;;

write)
  [[ -f "$TARGET" ]] || die "--file is not a readable file: $TARGET"
  tmp="$(mktemp)" || die "cannot create a temporary file"
  begin_count="$(grep -cF "$BEGIN_MARKER" "$TARGET")"
  if [[ "$begin_count" -gt 1 ]]; then
    rm -f "$tmp"
    printf 'ERROR: %s has %s begin markers; refusing to guess which block to replace\n' \
      "$TARGET" "$begin_count" >&2
    exit 1
  fi
  if grep -qF "$BEGIN_MARKER" "$TARGET"; then
    if ! grep -qF "$END_MARKER" "$TARGET"; then
      rm -f "$tmp"
      printf 'ERROR: %s has a begin marker with no end marker; refusing to guess its extent\n' \
        "$TARGET" >&2
      exit 1
    fi
    awk -v b="$BEGIN_MARKER" -v e="$END_MARKER" -v repl="$BLOCK" '
      $0 == b { print repl; skipping = 1; next }
      $0 == e { skipping = 0; next }
      !skipping { print }
    ' "$TARGET" >"$tmp"
  else
    cat "$TARGET" >"$tmp"
    # Separate the appended block from whatever precedes it.
    [[ -s "$tmp" ]] && printf '\n' >>"$tmp"
    printf '%s\n' "$BLOCK" >>"$tmp"
  fi
  if cat "$tmp" >"$TARGET"; then
    rm -f "$tmp"
    printf 'WROTE\t%s\n' "$TARGET"
    # An index Claude Code never loads is the whole point silently not working,
    # so say so at the moment of writing rather than leaving it for a later gate.
    rel_written="${TARGET#"$PWD"/}"
    if ! reach="$(ip_index_target_loaded "." "$rel_written")"; then
      printf 'WARNING\t%s\n' "${reach#*$'\t'}" >&2
    fi
    exit 0
  fi
  rm -f "$tmp"
  printf 'ERROR: failed writing %s\n' "$TARGET" >&2
  exit 1
  ;;
*) die "unreachable subcommand: $SUBCOMMAND" ;;
esac
