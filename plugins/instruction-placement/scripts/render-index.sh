#!/usr/bin/env bash
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
discover="$SCRIPT_DIR/lib/discover.sh"
[[ -f "$discover" ]] || discover="$SCRIPT_DIR/discover.sh"
# shellcheck source=./lib/discover.sh
. "$discover"

MAX_ROWS="${CLAUDE_PLUGIN_OPTION_INDEX_MAX_ROWS:-40}"
[[ "$MAX_ROWS" =~ ^[0-9]+$ ]] || MAX_ROWS=40

# Claude Code strips block-level HTML comments from CLAUDE.md before injecting it.
# https://code.claude.com/docs/en/memory
BEGIN_MARKER="<!-- BEGIN GENERATED: instruction-placement rules index -->"
END_MARKER="<!-- END GENERATED: instruction-placement rules index -->"

EMPTY_NOTE="No path-scoped rules or nested instruction files are present in this repository."

block_is_empty() { [[ "$1" == *"$EMPTY_NOTE"* ]]; }

usage() {
  cat <<'EOF'
render-index.sh — generate the always-loaded index of deferred instruction surfaces.

Usage:
  render-index.sh render [--root <dir>]
  render-index.sh check --file <path> [--root <dir>]
  render-index.sh write --file <path> [--root <dir>]
  render-index.sh reachable --file <path> [--root <dir>]
  render-index.sh wiring [--root <dir>]
  render-index.sh --help

render     print the generated block to stdout. With nothing to index it still
           prints a well-formed block saying so, which is the answer to "what
           WOULD the index hold"; `write` is the surface that decides whether
           one is worth writing, and writes none in that case
check      compare the block inside <path> against a fresh render; on drift,
           print an ADD, CHANGE or REMOVE line per differing row, then the
           FIX command that rewrites the block
write      replace the block inside <path> in place, appending it if absent
reachable  report whether anything in this repository stops Claude Code loading
           <path>: LOADED (a root memory file reaches it), UNREACHABLE (a root
           CLAUDE.md is read instead of it), or NATIVE (nothing blocks it, so
           Claude Code reads it directly where AGENTS.md support is available)
wiring     report, for every nested AGENTS.md the index would list, whether a
           CLAUDE.md on its own path blocks it and whether one imports or
           symlinks it (WIRED / NATIVE / UNWIRED rows; exit 1 on any UNWIRED).
           Prints NONE when there are no nested files, so a clean repository
           does not look like a subcommand that never ran

Indexes only surfaces that load on demand: path-scoped rules (`paths:`
frontmatter) and nested CLAUDE.md / AGENTS.md files below the repository root.
Unscoped rules and root-level instruction files already load every session and
are deliberately left out.

Exit: 0 success, in sync, or no blocked-and-unimported nested AGENTS.md; 1 drift,
write failure, an unreachable target, or a blocked unimported nested AGENTS.md;
2 usage error; 3 no block found.
EOF
}

die() {
  printf 'ERROR: %s\n' "$1" >&2
  exit 2
}

first_h1() {
  grep -m1 '^# ' "$1" 2>/dev/null | sed 's/^#[[:space:]]*//'
}

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
  [[ -n "$title" ]] || title="$(first_h1 "$file")"
  [[ -n "$title" ]] || title="$(basename "$file" .md)"
  printf '%s' "${title//|/\\|}"
}

rule_globs() {
  ip_parse_paths "$1" | awk 'NR > 1 { printf ", " } { printf "%s", $0 } END { if (NR) printf "\n" }'
}

is_pure_shim() {
  local file="$1" line trimmed seen=0
  while IFS= read -r line || [[ -n "$line" ]]; do
    trimmed="${line#"${line%%[![:space:]]*}"}"
    trimmed="${trimmed%"${trimmed##*[![:space:]]}"}"
    [[ -z "$trimmed" ]] && continue
    [[ "$trimmed" == "<!--"* ]] && continue
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

  local rule globs title
  while IFS= read -r rule; do
    [[ -z "$rule" ]] && continue
    globs="$(rule_globs "$rule")"
    [[ -z "$globs" ]] && continue
    title="$(rule_title "$rule")"
    # shellcheck disable=SC2016 # backticks here are markdown code spans, not command substitution
    rows+=("$(printf '| `%s` | `%s` | %s |' "$rule" "$globs" "$title")")
  done < <(ip_discover_rules .)

  local nested dir label
  while IFS= read -r nested; do
    [[ -z "$nested" ]] && continue
    dir="$(dirname "$nested")"
    if [[ "$(basename "$nested")" == "CLAUDE.md" ]] && is_pure_shim "$nested"; then
      continue
    fi
    label="$(first_h1 "$nested")"
    [[ -z "$label" ]] && label="Conventions for this subtree"
    # shellcheck disable=SC2016 # backticks here are markdown code spans, not command substitution
    rows+=("$(printf '| `%s` | `%s/**` | %s |' "$nested" "$dir" "${label//|/\\|}")")
  done < <(ip_discover_nested_instructions .)

  printf '%s\n' "$BEGIN_MARKER"
  if ((${#rows[@]} == 0)); then
    printf '\n%s\n\n' "$EMPTY_NOTE"
  else
    cat <<'PREAMBLE'

## Conventions that load on demand

Each surface below enters context automatically, in subagents as well as in the main session,
once a file it covers triggers it. The triggers differ by surface type: see
<https://code.claude.com/docs/en/memory#path-specific-rules> for rules,
<https://code.claude.com/docs/en/memory#how-claude-md-files-load> for nested `CLAUDE.md`, and
<https://code.claude.com/docs/en/memory#when-claude-code-reads-agents-md> for `AGENTS.md`. The
match is on the requested path, so even a Read tool call that finds no file fires it. A surface
whose trigger has not fired is simply absent, and after a compaction it returns only when its
trigger fires again. When you are working on something an entry covers and its content is not
already in context, read the file directly.

| Surface | Covers | Topic |
|---|---|---|
PREAMBLE
    local sorted
    sorted="$(printf '%s\n' "${rows[@]}" | LC_ALL=C sort)"
    if ((${#rows[@]} <= MAX_ROWS)); then
      printf '%s\n\n' "$sorted"
    else
      printf '%s\n' "$sorted" | head -n "$MAX_ROWS"
      printf '\n'
      printf 'Plus %d further surface(s), grouped by location:\n\n' \
        $((${#rows[@]} - MAX_ROWS))
      # shellcheck disable=SC2016 # strips the markdown code span, not an expansion
      printf '%s\n' "$sorted" | tail -n +$((MAX_ROWS + 1)) |
        sed 's/^| `//; s/`.*$//; s|/[^/]*$||' |
        LC_ALL=C sort | uniq -c |
        awk '{ printf "- `%s/` — %d surface(s)\n", $2, $1 }'
      printf '\n%s\n\n' \
        "Read a directory's instruction files directly when working inside it."
    fi
  fi
  printf '%s\n' "$END_MARKER"
}

print_row_diff() {
  IP_CUR="$1" IP_NEW="$2" awk '
    function key(r) { sub(/^([|]|-) `/, "", r); sub(/`.*$/, "", r); return r }
    function row(l) { return l ~ /^([|]|-) `/ }
    BEGIN {
      n = split(ENVIRON["IP_CUR"], a, "\n")
      for (i = 1; i <= n; i++) if (row(a[i])) cur[key(a[i])] = a[i]
      m = split(ENVIRON["IP_NEW"], b, "\n")
      for (i = 1; i <= m; i++) {
        if (!row(b[i])) continue
        k = key(b[i]); seen[k] = 1
        if (!(k in cur)) { printf "ADD\t%s\n", b[i]; out++ }
        else if (cur[k] != b[i]) { printf "CHANGE\t%s\n", b[i]; out++ }
      }
      for (i = 1; i <= n; i++)
        if (row(a[i]) && !(key(a[i]) in seen)) { printf "REMOVE\t%s\n", a[i]; out++ }
      if (!out) print "NOTE\tevery row matches; the text around the table differs"
    }'
}

print_fix() {
  printf 'FIX\tbash "%s/render-index.sh" write --file "%s" --root "%s"\n' "$SCRIPT_DIR" "$TARGET" "$PWD"
}

normalize_drive_path() {
  local p="$1"
  if [[ "$p" =~ ^[A-Za-z]:[\\/] ]]; then
    p="${p//\\//}"
  fi
  printf '%s' "$p"
}

is_abs_path() { [[ "$1" == /* || "$1" =~ ^[A-Za-z]:[\\/] ]]; }

[[ $# -eq 0 ]] && {
  usage >&2
  exit 2
}

case "${1:-}" in
-h | --help)
  usage
  exit 0
  ;;
render | check | write | reachable | wiring)
  SUBCOMMAND="$1"
  shift
  ;;
*) die "unknown subcommand: $1 (expected render, check, write, reachable, or wiring)" ;;
esac

ROOT="$PWD"
ROOT_GIVEN=0
TARGET=""
while [[ $# -gt 0 ]]; do
  case "$1" in
  -h | --help)
    usage
    exit 0
    ;;
  --root)
    [[ $# -lt 2 ]] && die "--root needs a path"
    ROOT="$(normalize_drive_path "$2")"
    ROOT_GIVEN=1
    shift 2
    ;;
  --file)
    [[ $# -lt 2 ]] && die "--file needs a path"
    TARGET="$(normalize_drive_path "$2")"
    shift 2
    ;;
  --max-rows)
    [[ $# -lt 2 ]] && die "--max-rows needs an integer"
    [[ "$2" =~ ^[0-9]+$ ]] || die "--max-rows must be an integer"
    MAX_ROWS="$2"
    shift 2
    ;;
  *) die "unknown argument: $1" ;;
  esac
done

[[ -d "$ROOT" ]] || die "--root is not a directory: $ROOT"

if [[ "$SUBCOMMAND" != "render" && "$SUBCOMMAND" != "wiring" && -z "$TARGET" ]]; then
  die "$SUBCOMMAND needs --file"
fi

if [[ -n "$TARGET" ]] && ! is_abs_path "$TARGET"; then
  anchor="$PWD"
  if ((ROOT_GIVEN)); then
    if is_abs_path "$ROOT"; then anchor="${ROOT%/}"; else anchor="$PWD/${ROOT%/}"; fi
  fi
  TARGET="$anchor/$TARGET"
fi

cd "$ROOT" || die "cannot enter --root: $ROOT"

TARGET_NORM="$TARGET"
if [[ -n "$TARGET" ]]; then
  target_dir="$(dirname -- "$TARGET")"
  target_base="$(basename -- "$TARGET")"
  if target_dir_norm="$(cd "$target_dir" 2>/dev/null && pwd)"; then
    TARGET_NORM="${target_dir_norm%/}/$target_base"
  fi
fi

REL_TARGET="${TARGET_NORM#"$PWD"/}"

if [[ "$SUBCOMMAND" == "reachable" ]]; then
  ip_index_target_loaded "." "$REL_TARGET"
  exit $?
fi

nested_agents_wiring() {
  local nested dir want entry wired blocker unwired=0
  while IFS= read -r nested; do
    [[ -n "$nested" ]] || continue
    [[ "$(basename "$nested")" == "AGENTS.md" ]] || continue
    dir="$(dirname "$nested")"
    want="$(ip_realpath "$nested")"
    wired=""
    blocker=""
    while IFS= read -r entry; do
      [[ -n "$entry" ]] || continue
      [[ -n "$blocker" ]] || blocker="${entry#./}"
      if _ip_reaches "$entry" "$want" 0; then
        wired="${entry#./}"
        break
      fi
    done < <(ip_entry_points_on_path "." "$dir")
    if [[ -n "$wired" ]]; then
      printf 'WIRED\t%s\t%s reaches it\n' "$nested" "$wired"
    elif [[ -z "$blocker" ]]; then
      printf 'NATIVE\t%s\tno CLAUDE.md on its path, so Claude Code reads it on a Read in that directory where AGENTS.md support is available\n' "$nested"
    else
      printf 'UNWIRED\t%s\t%s is read instead of it and does not import it, so it never loads\n' "$nested" "$blocker"
      unwired=1
    fi
  done < <(ip_discover_nested_instructions .)
  return "$unwired"
}

if [[ "$SUBCOMMAND" == "wiring" ]]; then
  wiring_out="$(nested_agents_wiring)"
  wiring_rc=$?
  if [[ -z "$wiring_out" ]]; then
    printf 'NONE\n'
    exit 0
  fi
  printf '%s\n' "$wiring_out"
  exit "$wiring_rc"
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
  if [[ "$begin_count" -eq 0 ]]; then
    if block_is_empty "$BLOCK"; then
      printf 'IN-SYNC\t%s\tnothing to index, and no block to keep in sync\n' "$TARGET"
      exit 0
    fi
    printf 'NO-BLOCK\t%s\n' "$TARGET"
    exit 3
  fi
  if ! grep -qF "$END_MARKER" "$TARGET"; then
    printf 'NO-BLOCK\t%s\tbegin marker present, end marker missing\n' "$TARGET"
    exit 3
  fi
  if block_is_empty "$BLOCK"; then
    printf 'DRIFTED\t%s\tnothing to index; the block should be removed\n' "$TARGET"
    print_fix
    exit 1
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
  print_row_diff "$current" "$BLOCK"
  print_fix
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
  if [[ "$begin_count" -eq 1 ]] && ! grep -qF "$END_MARKER" "$TARGET"; then
    rm -f "$tmp"
    printf 'ERROR: %s has a begin marker with no end marker; refusing to guess its extent\n' \
      "$TARGET" >&2
    exit 1
  fi
  if [[ "$begin_count" -eq 0 ]] && block_is_empty "$BLOCK"; then
    rm -f "$tmp"
    printf 'NO-INDEX-NEEDED\t%s\tno path-scoped rules and no nested instruction files; an always-loaded block saying so is pure cost\n' \
      "$TARGET"
    exit 0
  fi
  if [[ "$begin_count" -eq 1 ]]; then
    if block_is_empty "$BLOCK"; then
      awk -v b="$BEGIN_MARKER" -v e="$END_MARKER" '
        $0 == b { skipping = 1; if (blankheld) blankheld = 0; next }
        $0 == e { skipping = 0; next }
        skipping { next }
        /^$/ { blankheld = 1; next }
        { if (blankheld) { print ""; blankheld = 0 } print }
      ' "$TARGET" >"$tmp"
    else
      IP_INDEX_BLOCK="$BLOCK" awk -v b="$BEGIN_MARKER" -v e="$END_MARKER" '
        $0 == b { print ENVIRON["IP_INDEX_BLOCK"]; skipping = 1; next }
        $0 == e { skipping = 0; next }
        !skipping { print }
      ' "$TARGET" >"$tmp"
    fi
  else
    cat "$TARGET" >"$tmp"
    [[ -s "$tmp" ]] && printf '\n' >>"$tmp"
    printf '%s\n' "$BLOCK" >>"$tmp"
  fi
  if cat "$tmp" >"$TARGET"; then
    rm -f "$tmp"
    printf 'WROTE\t%s\n' "$TARGET"
    if ! reach="$(ip_index_target_loaded "." "$REL_TARGET")"; then
      printf 'WARNING\t%s\n' "${reach#*$'\t'}" >&2
    fi
    while IFS=$'\t' read -r state nested detail; do
      [[ "$state" == "UNWIRED" ]] || continue
      printf 'WARNING\t%s is indexed but %s\n' "$nested" "$detail" >&2
    done < <(nested_agents_wiring || true)
    exit 0
  fi
  rm -f "$tmp"
  printf 'ERROR: failed writing %s\n' "$TARGET" >&2
  exit 1
  ;;
*) die "unreachable subcommand: $SUBCOMMAND" ;;
esac
