#!/usr/bin/env bash
# Effort-pin drift check for the audit skill.
#
# The repo pins effort levels in agent and skill frontmatter, lane configs,
# lane launch lines and Workflow scripts. Each pin was chosen against the
# model-config page's effort tables and per-model defaults. This script reads
# that page through the plugin's shared fetcher, hashes the three parts a pin
# rests on (the Levels column table under "Adjust effort level", the level
# rows of the "Choose an effort level" table, and item 3 of the resolution
# list, which states each model's default), and compares the hash with a
# committed baseline. It then lists every pin and flags the ones a human must
# re-decide. It never edits a pin and never rewrites the baseline.
#
# Output (stdout, one line each, in this order):
#   table status=<same|changed|unread|unparsed> levels=<csv> sha256=<hex> baseline_sha256=<hex> reason=<text>
#   pin path=<repo-relative> kind=<kind> effort=<value> status=<ok|drift> reason=<none|table-changed|level-not-in-table>
#   summary pins=<n> drift=<n> status=<ok|drift|no-claim>
# On unread or unparsed no pin line is printed: the run makes no claim.
#
# Exit codes:
#   0  the page matches the baseline and every pin's level is in the table
#   1  the page changed since the baseline, or a pin is flagged
#   2  fatal (bad arguments, baseline missing or malformed, fetcher missing or failing)
#   3  no claim: the page was unread or its headings, tables or list changed shape
#
# Env overrides (the test seam):
#   SETTINGS_AUDIT_DOCS_FIXTURE_DIR  directory of llms.txt and model-config.md; when set no fetch happens
#   CLAUDE_PLUGIN_ROOT               plugin root holding scripts/fetch-docs.sh

set -uo pipefail
export LC_ALL=C

usage() {
  cat <<'EOF'
check-effort-pins.sh: flag effort pins when model-config's effort tables or defaults change.

Usage:
  check-effort-pins.sh [--root <dir>] [--baseline <file>] [--docs-dir <dir>] [--print-baseline] [--help]

  --root <dir>       scan root (default: the git top level of the working directory, else it)
  --baseline <file>  baseline line (default: reference/effort-table.baseline beside this skill)
  --docs-dir <dir>   read model-config.md from <dir> when present instead of fetching it
  --print-baseline   print the baseline line for the page as read now, and exit; writes no file

Exit: 0 unchanged and every pin listed; 1 changed page or a flagged pin; 2 fatal;
      3 no claim (page unread or reshaped).
EOF
}

die() {
  echo "ERROR: $1" >&2
  exit 2
}

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-$(cd "$SCRIPT_DIR/../../.." && pwd)}"
FETCH_DOCS="$PLUGIN_ROOT/scripts/fetch-docs.sh"
BASELINE="$SCRIPT_DIR/../reference/effort-table.baseline"
SOURCE_URL="https://code.claude.com/docs/en/model-config"
SLUG="model-config"
ROOT=""
DOCS_DIR=""
PRINT_BASELINE=0
while [[ $# -gt 0 ]]; do
  case "$1" in
  -h | --help)
    usage
    exit 0
    ;;
  --root | --baseline | --docs-dir)
    [[ $# -ge 2 && -n "$2" ]] || die "$1 needs a value"
    [[ "$1" != --root ]] || ROOT="$2"
    [[ "$1" != --baseline ]] || BASELINE="$2"
    [[ "$1" != --docs-dir ]] || DOCS_DIR="$2"
    shift 2
    ;;
  --print-baseline)
    PRINT_BASELINE=1
    shift
    ;;
  *)
    echo "ERROR: unknown argument: $1" >&2
    usage >&2
    exit 2
    ;;
  esac
done

if [[ -z "$ROOT" ]]; then
  ROOT="$(git rev-parse --show-toplevel 2>/dev/null)" || ROOT="$PWD"
fi
[[ -d "$ROOT" ]] || die "scan root not found: $ROOT"
ROOT="$(cd "$ROOT" && pwd)"

BASE_SHA=""
if [[ $PRINT_BASELINE -eq 0 ]]; then
  [[ -f "$BASELINE" ]] || die "baseline not found: $BASELINE (write one with --print-baseline)"
  BASE_SHA="$(sed -n 's/^sha256=\([0-9a-f]\{64\}\) .*/\1/p' "$BASELINE" | head -n 1)"
  [[ -n "$BASE_SHA" ]] || die "baseline malformed, no sha256=<hex> line: $BASELINE"
fi

FIXTURE_DIR="${SETTINGS_AUDIT_DOCS_FIXTURE_DIR:-}"
[[ -z "$FIXTURE_DIR" ]] || DOCS_DIR=""

WORK="$(mktemp -d)" || die "could not create a temp directory"
trap 'rm -rf "$WORK"' EXIT

# read_page: set PAGE to the page's markdown, or PAGE="" and UNREAD to the reason.
PAGE="" UNREAD=""
read_page() {
  if [[ -n "$DOCS_DIR" && -s "$DOCS_DIR/$SLUG.md" ]]; then
    PAGE="$DOCS_DIR/$SLUG.md"
    return
  fi
  [[ -f "$FETCH_DOCS" ]] || die "shared fetcher not found: $FETCH_DOCS"
  local fetch_env=(-u FETCH_DOCS_FIXTURE_DIR FETCH_DOCS_CLAUDE_BIN='')
  [[ -z "$FIXTURE_DIR" ]] || fetch_env=(FETCH_DOCS_FIXTURE_DIR="$FIXTURE_DIR" FETCH_DOCS_CLAUDE_BIN='')
  env "${fetch_env[@]}" bash "$FETCH_DOCS" --out "$WORK/docs" --mode search "$SLUG" >/dev/null ||
    die "the shared fetcher failed"
  local state reason
  IFS=$'\t' read -r state reason < <(jq -r '.pages[0] | [.state, (.reason // "unread")] | @tsv' "$WORK/docs/manifest.json")
  if [[ "$state" == read && -s "$WORK/docs/$SLUG.md" ]]; then
    PAGE="$WORK/docs/$SLUG.md"
  else
    UNREAD="${reason:-unread}"
  fi
}

# parse_page <file>: print L<TAB>level (level set, first-seen order), A<TAB>row
# (Levels table rows), C<TAB>row (level rows of the Choose table) and
# D<TAB>line (resolution item 3), or one E<TAB>reason when a part is missing.
# Headings inside fenced code are ignored; trailing whitespace is trimmed.
parse_page() {
  awk '
    function rtrim(s) { sub(/[ \t\r]+$/, "", s); return s }
    function cell(s) { gsub(/`/, "", s); sub(/^[ \t]+/, "", s); sub(/[ \t]+$/, "", s); return s }
    { line = rtrim($0) }
    line ~ /^(```|~~~)/ { fence = !fence; next }
    fence { next }
    line ~ /^#+[ \t]/ {
      sect = ""
      if (line == "### Adjust effort level" && !seen_adjust) { sect = "adjust"; seen_adjust = 1 }
      if (line == "#### Choose an effort level" && !seen_choose) { sect = "choose"; seen_choose = 1 }
      tbl = 0; item = 0
      next
    }
    sect == "adjust" {
      if (line ~ /^\|/ && tbl < 2) {
        if (tbl == 0) {
          tbl = 1; hdr = 1
          n = split(line, c, "|")
          for (i = 2; i < n; i++) if (cell(c[i]) == "Levels") lcol = i
          next
        }
        if (hdr == 1) { hdr = 0; next }
        nA++; A[nA] = line
        if (lcol) {
          split(line, c, "|"); m = split(c[lcol], lv, ",")
          for (j = 1; j <= m; j++) { v = cell(lv[j]); if (v != "" && !(v in LV)) { LV[v] = 1; nL++; L[nL] = v } }
        }
        next
      }
      if (tbl == 1) tbl = 2
      if (line ~ /^[0-9]+\.[ \t]/) {
        if (!seen_item3 && line ~ /^3\.[ \t]/) { item = 1; seen_item3 = 1; nD++; D[nD] = line; next }
        item = 0; next
      }
      if (item && line ~ /^[ \t]+[^ \t]/) { nD++; D[nD] = line; next }
      item = 0
      next
    }
    sect == "choose" && line ~ /^\|/ && !choose_done {
      if (!ctbl) { ctbl = 1; chdr = 1; next }
      if (chdr == 1) { chdr = 0; next }
      split(line, c, "|"); nC++; C[nC] = line; CK[nC] = cell(c[2])
      next
    }
    sect == "choose" && ctbl { choose_done = 1 }
    END {
      if (!seen_adjust) { print "E\tno-adjust-heading"; exit }
      if (!lcol) { print "E\tno-levels-column"; exit }
      if (!nL) { print "E\tno-levels"; exit }
      if (!nD) { print "E\tno-defaults-item"; exit }
      if (!seen_choose) { print "E\tno-choose-heading"; exit }
      if (!ctbl) { print "E\tno-choose-table"; exit }
      k = 0
      for (i = 1; i <= nC; i++) if (CK[i] in LV) k++
      if (!k) { print "E\tno-level-rows"; exit }
      for (i = 1; i <= nL; i++) print "L\t" L[i]
      for (i = 1; i <= nC; i++) if (CK[i] in LV) print "C\t" C[i]
      for (i = 1; i <= nA; i++) print "A\t" A[i]
      for (i = 1; i <= nD; i++) print "D\t" D[i]
    }
  ' "$1"
}

sha256_text() {
  if command -v sha256sum >/dev/null 2>&1; then sha256sum | cut -d' ' -f1; else shasum -a 256 | cut -d' ' -f1; fi
}

STATUS="" REASON="" LEVELS="" SHA=""
declare -A IN_TABLE=()
read_page
if [[ -z "$PAGE" ]]; then
  STATUS=unread REASON="$UNREAD"
else
  parse_page "$PAGE" >"$WORK/parsed"
  if grep -q '^E' "$WORK/parsed"; then
    STATUS=unparsed REASON="$(cut -f2 "$WORK/parsed" | head -n 1)"
  else
    while IFS=$'\t' read -r _ level; do
      IN_TABLE[$level]=1
      LEVELS="${LEVELS:+$LEVELS,}$level"
    done < <(grep '^L' "$WORK/parsed")
    # Hash order: task rows, then the Levels table rows, then the defaults item.
    SHA="$(grep -E '^[CAD]' "$WORK/parsed" | cut -f2- | sha256_text)"
    if [[ $PRINT_BASELINE -eq 1 ]]; then
      STATUS=parsed
    elif [[ "$SHA" == "$BASE_SHA" ]]; then
      STATUS=same REASON=none
    else
      STATUS=changed REASON=sha256-differs
    fi
  fi
fi

if [[ $PRINT_BASELINE -eq 1 ]]; then
  if [[ "$STATUS" != parsed ]]; then
    printf 'ERROR: no baseline: page %s (%s)\n' "$STATUS" "$REASON" >&2
    exit 3
  fi
  printf 'sha256=%s levels=%s as_of=%s source=%s\n' "$SHA" "$LEVELS" "$(date -u +%Y-%m-%d)" "$SOURCE_URL"
  exit 0
fi

# scan_pins: print kind<TAB>repo-relative path<TAB>value for every pin under ROOT.
scan_pins() {
  local f
  shopt -s nullglob
  for f in "$ROOT"/plugins/*/agents/*.md "$ROOT"/plugins/*/skills/*/SKILL.md \
    "$ROOT"/.claude/agents/*.md "$ROOT"/.claude/skills/*/SKILL.md; do
    awk -v p="${f#"$ROOT"/}" '
      NR == 1 { if ($0 !~ /^---[ \t\r]*$/) exit; next }
      /^---[ \t\r]*$/ { exit }
      /^effort:/ {
        v = $0; sub(/^effort:[ \t]*/, "", v); sub(/[ \t]+#.*$/, "", v); sub(/[ \t\r]+$/, "", v)
        gsub(/^["\047]|["\047]$/, "", v)
        print "frontmatter\t" p "\t" v
      }
    ' "$f"
  done
  f="$ROOT/plugins/harness-ops/skills/lanes/context/config.md"
  [[ -f "$f" ]] && grep -oE '"effort"[[:space:]]*:[[:space:]]*"[^"]*"' "$f" |
    sed -E 's/.*:[[:space:]]*"([^"]*)"$/\1/' | while IFS= read -r v; do printf 'lane-config\t%s\t%s\n' "${f#"$ROOT"/}" "$v"; done
  f="$ROOT/prompts/loops/loop-lane-prompts.md"
  [[ -f "$f" ]] && grep -oE -- '--effort[ =][A-Za-z0-9_-]+' "$f" |
    sed -E 's/^--effort[ =]//' | while IFS= read -r v; do printf 'lane-launch\t%s\t%s\n' "${f#"$ROOT"/}" "$v"; done
  for f in "$ROOT"/plugins/*/skills/*/context/*.md "$ROOT"/plugins/*/workflows/*.js "$ROOT"/plugins/*/workflows/*.mjs; do
    grep -oE "effort:[[:space:]]*('[^']*'|\"[^\"]*\")" "$f" |
      sed -E "s/^effort:[[:space:]]*['\"]//; s/['\"]$//" | while IFS= read -r v; do printf 'workflow-literal\t%s\t%s\n' "${f#"$ROOT"/}" "$v"; done
  done
  shopt -u nullglob
}

scan_pins >"$WORK/pins"
PINS="$(grep -c . "$WORK/pins")"

if [[ "$STATUS" == unread || "$STATUS" == unparsed ]]; then
  printf 'table status=%s levels= sha256= baseline_sha256=%s reason=%s\n' "$STATUS" "$BASE_SHA" "$REASON"
  printf 'summary pins=%d drift=0 status=no-claim\n' "$PINS"
  exit 3
fi

printf 'table status=%s levels=%s sha256=%s baseline_sha256=%s reason=%s\n' "$STATUS" "$LEVELS" "$SHA" "$BASE_SHA" "$REASON"
DRIFT=0
while IFS=$'\t' read -r kind path value; do
  if [[ -z "$value" || -z "${IN_TABLE[$value]:-}" ]]; then
    pin_status=drift pin_reason=level-not-in-table
  elif [[ "$STATUS" == changed ]]; then
    pin_status=drift pin_reason=table-changed
  else
    pin_status=ok pin_reason=none
  fi
  [[ "$pin_status" == ok ]] || DRIFT=$((DRIFT + 1))
  printf 'pin path=%s kind=%s effort=%s status=%s reason=%s\n' "$path" "$kind" "$value" "$pin_status" "$pin_reason"
done <"$WORK/pins"

if [[ $DRIFT -eq 0 && "$STATUS" == same ]]; then
  printf 'summary pins=%d drift=0 status=ok\n' "$PINS"
  exit 0
fi
printf 'summary pins=%d drift=%d status=drift\n' "$PINS" "$DRIFT"
exit 1
