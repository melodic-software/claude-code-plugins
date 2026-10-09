#!/usr/bin/env bash
# Check or write the developer-experience pointer line inside the shared
# plugin-conventions block of a repository's root AGENTS.md.
#
# The block is shared: other plugins keep their own lines in it and the user's
# text surrounds it. This helper owns exactly one line, the one that starts with
# DX_PREFIX below, and never edits any other byte. A line that merely cites a
# /developer-experience: skill belongs to another plugin. CLAUDE.md is only
# read, to report whether AGENTS.md reaches Claude Code's context; load rules:
# https://code.claude.com/docs/en/memory (as of 2026-10-08; recheck when that
# page changes its import or file-discovery rules).
#
# UNTRUSTED INPUT. AGENTS.md and CLAUDE.md are consumer prose: they are only
# compared as text, never evaluated. The conventions path is checked against the
# convention-home grammar before it is written anywhere.
set -uo pipefail
export LC_ALL=C

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RESOLVER="${POINTER_LINE_RESOLVER:-$SCRIPT_DIR/../../../lib/resolve-convention-home.sh}"

BEGIN_MARKER='<!-- BEGIN GENERATED: plugin-conventions -->'
END_MARKER='<!-- END GENERATED: plugin-conventions -->'
DRAFT_MARKER='<!-- BEGIN plugin-conventions'
DX_PREFIX='- Before creating, changing or cleaning up CLIs, scripts or other developer tools, read `'
DX_SUFFIX='` and use /developer-experience:build-cli or /developer-experience:audit-tools.'
DEFAULT_PATH='docs/conventions/developer-experience.md'

usage() {
  cat <<'EOF'
pointer-line.sh: check or write the developer-experience pointer line in AGENTS.md.

Usage:
  pointer-line.sh check [--root DIR] [--path FILE]
  pointer-line.sh apply [--root DIR] [--path FILE] [--yes] [--dry-run]
  pointer-line.sh --help

  check      report the block, the line, and whether AGENTS.md loads; writes nothing
  apply      print a diff, then write AGENTS.md atomically (asks first unless --yes)
  --root     repository root (default: CLAUDE_PROJECT_DIR, git toplevel, cwd)
  --path     conventions file, repo-relative (default: <convention home>/developer-experience.md
             when the convention-home resolver finds one, else docs/conventions/developer-experience.md)
  --yes      write without asking; without it and without a TTY, apply writes nothing
  --dry-run  print the diff apply would write and stop

Output (stdout, one "key: value" per line): file, state, path, source, then any
load: and add: lines, then result: (and a note: when a new AGENTS.md cannot load
yet) for apply.
  state   current | stale | no-line | no-block | missing-file | duplicate-line |
          unbalanced-markers | draft-marker | symlink
  source  flag | bound | default
  load    missing-import <file> | may-not-load <file>   (add: <file>: <line to add>)
  result  written | created | unchanged | would-write | declined

Environment: POINTER_LINE_RESOLVER overrides the convention-home resolver path.

Exit: 0 current or written; 1 check: change needed, apply: not confirmed (nothing
      written); 2 usage or invalid --path; 3 AGENTS.md cannot be edited safely
      (two DX lines, unbalanced markers, draft marker); 4 AGENTS.md is a symlink;
      5 the convention-home resolver reported FAIL; 6 internal or write error.
EOF
}

die_usage() {
  printf 'pointer-line: %s\n' "$1" >&2
  printf 'Run pointer-line.sh --help for usage.\n' >&2
  exit 2
}

CMD=""
ROOT=""
CONV_PATH=""
YES=0
DRY_RUN=0
case "${1:-}" in
  -h | --help)
    usage
    exit 0
    ;;
  check | apply)
    CMD="$1"
    shift
    ;;
  '') die_usage "missing command: check or apply" ;;
  *) die_usage "unknown command: $1" ;;
esac
while [[ $# -gt 0 ]]; do
  case "$1" in
    -h | --help)
      usage
      exit 0
      ;;
    --root | --path)
      [[ $# -ge 2 ]] || die_usage "$1 needs a value"
      if [[ "$1" == --root ]]; then ROOT="$2"; else CONV_PATH="$2"; fi
      shift 2
      ;;
    --yes)
      YES=1
      shift
      ;;
    --dry-run)
      DRY_RUN=1
      shift
      ;;
    *) die_usage "unknown argument: $1" ;;
  esac
done

if [[ -z "$ROOT" ]]; then
  ROOT="${CLAUDE_PROJECT_DIR:-}"
  [[ -n "$ROOT" ]] || ROOT="$(git rev-parse --show-toplevel 2>/dev/null)" || ROOT=""
  [[ -n "$ROOT" ]] || ROOT="$(pwd)"
fi
[[ -d "$ROOT" ]] || die_usage "--root is not a directory: $ROOT"
ROOT="$(cd "$ROOT" && pwd)" || exit 6

STAGED=""
DIR_TMP=""
RES_ERR=""
# shellcheck disable=SC2329 # invoked by the EXIT trap
cleanup() { rm -f "$STAGED" "$DIR_TMP" "$RES_ERR"; }
trap cleanup EXIT

# The convention-home path grammar: repo-relative segments of [A-Za-z0-9._-]+
# joined by "/", none equal to "." or "..".
valid_path() {
  local seg
  [[ "$1" =~ ^[A-Za-z0-9._-]+(/[A-Za-z0-9._-]+)*$ ]] || return 1
  local IFS=/
  for seg in $1; do
    [[ "$seg" == . || "$seg" == .. ]] && return 1
  done
  return 0
}

SOURCE=flag
if [[ -z "$CONV_PATH" ]]; then
  RES_ERR="$(mktemp)" || exit 6
  home="$(bash "$RESOLVER" --root "$ROOT" 2>"$RES_ERR")"
  rc=$?
  case "$rc" in
    0)
      SOURCE=bound
      CONV_PATH="${home%/}/developer-experience.md"
      ;;
    1)
      SOURCE=default
      CONV_PATH="$DEFAULT_PATH"
      ;;
    3)
      cat "$RES_ERR" >&2
      printf 'pointer-line: the convention-home pointer is broken; fix it or pass --path. Nothing written.\n' >&2
      exit 5
      ;;
    *)
      cat "$RES_ERR" >&2
      printf 'pointer-line: internal error: the convention-home resolver exited %s. Nothing written.\n' "$rc" >&2
      exit 6
      ;;
  esac
fi
valid_path "$CONV_PATH" || die_usage "invalid conventions path (want repo-relative segments of [A-Za-z0-9._-] joined by /): $CONV_PATH"
DX_LINE="$DX_PREFIX$CONV_PATH$DX_SUFFIX"

AGENTS="$ROOT/AGENTS.md"
CLAUDE="$ROOT/CLAUDE.md"
DOT_CLAUDE="$ROOT/.claude/CLAUDE.md"

# analyze <file> : prints "<state> <dx-line-no> <end-line-no> <crlf>".
analyze() {
  awk -v B="$BEGIN_MARKER" -v E="$END_MARKER" -v D="$DRAFT_MARKER" \
    -v P="$DX_PREFIX" -v W="$DX_LINE" '
    {
      line = $0
      sub(/\r$/, "", line)
      if (NR == 1) { crlf = ($0 ~ /\r$/); sub(/^\357\273\277/, "", line) }
      t = line
      sub(/^[ \t]+/, "", t)
      sub(/[ \t]+$/, "", t)
      if (t == B) { if (inb || seenb) bad = 1; inb = 1; seenb = 1; next }
      if (t == E) { if (!inb) bad = 1; inb = 0; endno = NR; next }
      if (index(t, D) == 1) draft = 1
      if (inb && index(line, P) == 1) { n++; dxno = NR; cur = (line == W) }
    }
    END {
      if (inb) bad = 1
      if (bad) s = "unbalanced-markers"
      else if (draft) s = "draft-marker"
      else if (!seenb) s = "no-block"
      else if (n > 1) s = "duplicate-line"
      else if (n == 0) s = "no-line"
      else if (cur) s = "current"
      else s = "stale"
      printf "%s %d %d %d\n", s, dxno, endno, crlf
    }' "$1"
}

# render <file> <state> <dx-line-no> <end-line-no> <crlf> <final-newline> :
# the new file on stdout. Every line not replaced or added is printed as read.
render() {
  awk -v B="$BEGIN_MARKER" -v E="$END_MARKER" -v W="$DX_LINE" -v s="$2" \
    -v dxno="$3" -v endno="$4" -v crlf="$5" -v finalnl="$6" '
    { line[NR] = $0 }
    END {
      cr = crlf ? "\r" : ""
      n = 0
      for (i = 1; i <= NR; i++) {
        if (s == "no-line" && i == endno) out[++n] = W cr
        if (s == "stale" && i == dxno) {
          out[++n] = W ((line[i] ~ /\r$/) ? "\r" : "")
          continue
        }
        out[++n] = line[i]
      }
      if (s == "no-block") {
        last = line[NR]
        sub(/\r$/, "", last)
        if (NR > 0 && last != "") out[++n] = cr
        out[++n] = B cr
        out[++n] = W cr
        out[++n] = E cr
        finalnl = 1
      }
      for (i = 1; i <= n; i++) printf "%s%s", out[i], (i < n || finalnl) ? "\n" : ""
    }' "$1"
}

# has_import <file> <token> : the file holds an @-import of AGENTS.md.
has_import() {
  grep -Eq "(^|[[:space:]])$2([[:space:]]|\$)" "$1" 2>/dev/null
}

# load_report : print load:/add: lines for files that keep AGENTS.md out of
# context. Sets LOAD_FINDINGS.
LOAD_FINDINGS=0
load_report() {
  if [[ -L "$CLAUDE" && "$CLAUDE" -ef "$AGENTS" ]]; then return; fi
  if [[ -f "$CLAUDE" ]] && has_import "$CLAUDE" '@(\./)?AGENTS\.md'; then return; fi
  if [[ -f "$DOT_CLAUDE" ]] && has_import "$DOT_CLAUDE" '@\.\./AGENTS\.md'; then return; fi
  local root_add=0 need_root_add=0 d f
  if [[ -e "$CLAUDE" ]]; then
    printf 'load: missing-import CLAUDE.md\nadd: CLAUDE.md: @AGENTS.md\n'
    root_add=1
    LOAD_FINDINGS=$((LOAD_FINDINGS + 1))
  fi
  if [[ -e "$DOT_CLAUDE" ]]; then
    printf 'load: missing-import .claude/CLAUDE.md\nadd: .claude/CLAUDE.md: @../AGENTS.md\n'
    LOAD_FINDINGS=$((LOAD_FINDINGS + 1))
  fi
  if [[ -e "$ROOT/CLAUDE.local.md" ]]; then
    printf 'load: may-not-load CLAUDE.local.md\n'
    need_root_add=1
    LOAD_FINDINGS=$((LOAD_FINDINGS + 1))
  fi
  d="$ROOT"
  while [[ "$d" != / && -n "$d" ]]; do
    d="${d%/*}"
    [[ -n "$d" ]] || d=/
    for f in "${d%/}/CLAUDE.md" "${d%/}/.claude/CLAUDE.md" "${d%/}/CLAUDE.local.md"; do
      [[ -n "${HOME:-}" && "$f" == "${HOME%/}/.claude/CLAUDE.md" ]] && continue
      if [[ -e "$f" ]]; then
        printf 'load: may-not-load %s\n' "$f"
        need_root_add=1
        LOAD_FINDINGS=$((LOAD_FINDINGS + 1))
      fi
    done
  done
  if [[ "$need_root_add" -eq 1 && "$root_add" -eq 0 ]]; then
    printf 'add: CLAUDE.md: @AGENTS.md\n'
  fi
}

printf 'file: AGENTS.md\n'
if [[ -L "$AGENTS" ]]; then
  printf 'state: symlink\npath: %s\nsource: %s\n' "$CONV_PATH" "$SOURCE"
  printf 'pointer-line: AGENTS.md is a symlink to %s; refusing to write through it. Edit the target or replace the link with a file.\n' \
    "$(readlink "$AGENTS")" >&2
  exit 4
fi

if [[ -e "$AGENTS" ]]; then
  read -r STATE DX_NO END_NO CRLF <<<"$(analyze "$AGENTS")" || exit 6
else
  STATE=missing-file DX_NO=0 END_NO=0 CRLF=0
fi
printf 'state: %s\npath: %s\nsource: %s\n' "$STATE" "$CONV_PATH" "$SOURCE"
load_report

case "$STATE" in
  duplicate-line)
    printf 'pointer-line: the plugin-conventions block holds more than one developer-experience line; remove all but one by hand. Nothing written.\n' >&2
    exit 3
    ;;
  unbalanced-markers)
    printf 'pointer-line: the plugin-conventions markers are unbalanced (a BEGIN without END, an END without BEGIN, or two blocks); fix them by hand. Nothing written.\n' >&2
    exit 3
    ;;
  draft-marker)
    printf 'pointer-line: AGENTS.md has a draft "%s" block; migrate it to %s ... %s, then rerun. Nothing written.\n' \
      "$DRAFT_MARKER" "$BEGIN_MARKER" "$END_MARKER" >&2
    exit 3
    ;;
  *) ;;
esac

if [[ "$CMD" == check ]]; then
  [[ "$STATE" == current && "$LOAD_FINDINGS" -eq 0 ]] && exit 0
  exit 1
fi

if [[ "$STATE" == current ]]; then
  printf 'result: unchanged\n'
  exit 0
fi

FINAL_NL=1
if [[ -e "$AGENTS" ]]; then
  [[ -z "$(tail -c 1 "$AGENTS")" ]] || FINAL_NL=0
fi
STAGED="$(mktemp)" || exit 6
if [[ -e "$AGENTS" ]]; then
  render "$AGENTS" "$STATE" "$DX_NO" "$END_NO" "$CRLF" "$FINAL_NL" >"$STAGED" || exit 6
  diff -u -L a/AGENTS.md -L b/AGENTS.md "$AGENTS" "$STAGED"
else
  render /dev/null no-block 0 0 0 1 >"$STAGED" || exit 6
  diff -u -L /dev/null -L b/AGENTS.md /dev/null "$STAGED"
fi

if [[ "$DRY_RUN" -eq 1 ]]; then
  printf 'result: would-write\n'
  exit 0
fi
if [[ "$YES" -ne 1 ]]; then
  answer=""
  if [[ -t 0 ]]; then
    printf 'Write AGENTS.md? [y/N] ' >&2
    read -r answer || answer=""
  else
    printf 'pointer-line: not confirmed and no terminal to ask on; rerun with --yes to write. Nothing written.\n' >&2
  fi
  case "$answer" in
    y | Y | yes | YES) ;;
    *)
      printf 'result: declined\n'
      exit 1
      ;;
  esac
fi

DIR_TMP="$(mktemp "$ROOT/.AGENTS.md.XXXXXX")" || exit 6
if [[ -e "$AGENTS" ]]; then
  cp -p "$AGENTS" "$DIR_TMP" || exit 6
else
  chmod "$(printf '%o' $((0666 & ~$(umask))))" "$DIR_TMP" || exit 6
fi
cat "$STAGED" >"$DIR_TMP" || exit 6
mv -f "$DIR_TMP" "$AGENTS" || {
  printf 'pointer-line: could not replace AGENTS.md. Nothing written.\n' >&2
  exit 6
}
DIR_TMP=""

if [[ "$STATE" == missing-file ]]; then
  printf 'result: created\n'
  if [[ -e "$CLAUDE" && "$LOAD_FINDINGS" -gt 0 ]]; then
    printf 'note: AGENTS.md has no effect until CLAUDE.md imports @AGENTS.md\n'
  fi
else
  printf 'result: written\n'
fi
exit 0
