#!/usr/bin/env bash
# finding-ids.sh -- derive the audit-pass finding identity of audit-instructions
# findings from scan-shaped rows.
#
#   finding-ids.sh [--records] [--root <dir>] [FILE]
#
# Reads rows from FILE, or stdin when FILE is absent:
#
#   <path>:<line>:<check-id>                      one site
#   <pathA>:<lineA>|<pathB>:<lineB>|I15           the one pairwise claim
#
# and prints, per row, tab-separated:
#
#   <row>  <finding_id/v1>  <group/v1>  <surface>=<anchor>  [<surface>=<anchor>]
#
# With --records, prints a JSON finding record instead, in the shape
# `finding-identity.sh validate-record` accepts.
#
# The identity rules are audit-pass's (reference/finding-identity.md there) and
# the hashing is its finding-identity.sh; this script only fills the tuple the
# way reference/finding-identity.md in this skill states: check is
# claude-config/audit-instructions/<id>, claim is the id's template from the
# table below, and every anchor is an excerpt anchor over the flagged line,
# discriminated by its enclosing ATX heading path. Frontmatter and fenced code
# never contribute a heading; a line inside a fence is anchored --in-fence.
#
# A row it cannot identify prints `#REFUSED<TAB><row><TAB><reason>` and gets no
# id: an id with no claim template, a pairwise row for any check but I15, a
# surface outside both the repository and the home directory, a file under the
# home directory that is not an instruction file (see instruction_shape), a line
# past EOF or blank. Refusals never change the exit code, so a caller counts them.
#
# The claim table MIRRORS reference/finding-identity.md "Claim templates";
# finding-ids.test.sh fails when the two, or the catalog's check headings,
# disagree.
#
# Exit: 0 when every row was processed (refused rows included), 2 on a usage
# error or a missing prerequisite.
set -uo pipefail

PROG="finding-ids.sh"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FI="$SCRIPT_DIR/../../audit-pass/scripts/finding-identity.sh"
CHECK_PREFIX="claude-config/audit-instructions/"

die() {
  printf '%s: %s\n' "$PROG" "$1" >&2
  exit 2
}

usage() {
  cat <<'EOF'
finding-ids.sh -- audit-pass finding identity for audit-instructions rows.

Usage:
  finding-ids.sh [--records] [--root <dir>] [FILE]

Rows (FILE, or stdin):
  <path>:<line>:<check-id>
  <pathA>:<lineA>|<pathB>:<lineB>|I15

Output, per row, tab-separated:
  <row> <finding_id/v1> <group/v1> <surface>=<anchor> [<surface>=<anchor>]
--records prints a JSON finding record per row instead.
A row that cannot be identified prints `#REFUSED<TAB><row><TAB><reason>`.

--root names the repository root surfaces are relative to; it defaults to the
git toplevel of the current directory. Under the home directory only an
instruction file is a surface: a *.md file, or a settings.json,
settings.local.json or hooks.json inside a .claude tree or the resolved
${CLAUDE_CONFIG_DIR:-~/.claude}.
EOF
}

claim_template() {
  case "$1" in
  I6) echo "I6.bare-prohibition" ;;
  I7) echo "I7.request-without-reason" ;;
  I8) echo "I8.model-era-reaudit" ;;
  I8-a) echo "I8-a.instructed-self-check" ;;
  I8-b) echo "I8-b.conservative-reporting" ;;
  I8-c) echo "I8-c.dont-think-directive" ;;
  I8-d) echo "I8-d.short-turn-assumption" ;;
  I8-e) echo "I8-e.forced-interim-status" ;;
  I8-f) echo "I8-f.think-carefully-steer" ;;
  I9) echo "I9.example-hygiene" ;;
  I10) echo "I10.reasoning-echo-directive" ;;
  I11) echo "I11.mcp-where-cli-equivalent" ;;
  I12) echo "I12.stale-harness-claim" ;;
  I13) echo "I13.non-loading-citation" ;;
  I14) echo "I14.already-loaded-retrieval" ;;
  I15) echo "I15.cross-surface-conflict" ;;
  I16) echo "I16.definition-site-locality" ;;
  I17) echo "I17.thinking-disabled-where-forbidden" ;;
  I17-a) echo "I17-a.universal-thinking-off-switch" ;;
  I17-b) echo "I17-b.mid-session-change-without-cost" ;;
  I17-c) echo "I17-c.fixed-thinking-budget" ;;
  I17-d) echo "I17-d.tool-reliance-without-nudge" ;;
  I18) echo "I18.thinking-blocks-altered" ;;
  I18-a) echo "I18-a.leading-thinking-block-required" ;;
  I19) echo "I19.benchmark-figure-without-trigger" ;;
  I20) echo "I20.prefilled-response" ;;
  I21) echo "I21.effort-pinned-across-model-change" ;;
  I22) echo "I22.routing-without-baseline" ;;
  I23) echo "I23.self-estimated-budget-trigger" ;;
  I24) echo "I24.silent-generalization" ;;
  I25) echo "I25.rejected-sampling-parameter" ;;
  I26) echo "I26.generic-negative-steering" ;;
  I27) echo "I27.effort-lowered-for-brevity" ;;
  I28) echo "I28.trigger-emphasis" ;;
  I28-a) echo "I28-a.forced-compliance-emphasis" ;;
  I28-b) echo "I28-b.blanket-tool-default" ;;
  I29) echo "I29.body-restatement" ;;
  I29-a) echo "I29-a.description-restatement" ;;
  I29-b) echo "I29-b.sibling-restatement" ;;
  I30) echo "I30.stamp-without-recheck-trigger" ;;
  I31) echo "I31.migration-relative-phrasing" ;;
  I32) echo "I32.route-to-absent-skill" ;;
  I33) echo "I33.spoke-self-description" ;;
  I34) echo "I34.maintainer-rationale-in-yaml" ;;
  I35) echo "I35.settled-answers-instruction" ;;
  *) return 1 ;;
  esac
}

RECORDS=0
ROOT=""
INPUT=""
while [[ $# -gt 0 ]]; do
  case "$1" in
  --records)
    RECORDS=1
    shift
    ;;
  --root)
    [[ $# -ge 2 && -n "$2" ]] || die "--root requires a value"
    ROOT="$2"
    shift 2
    ;;
  --help | -h)
    usage
    exit 0
    ;;
  -*) die "unknown argument: $1" ;;
  *)
    [[ -z "$INPUT" ]] || die "at most one FILE"
    INPUT="$1"
    shift
    ;;
  esac
done

[[ -f "$FI" ]] || die "audit-pass finding-identity.sh not found at $FI"
if [[ -n "$INPUT" && ! -f "$INPUT" ]]; then
  die "input file not found: $INPUT"
fi

[[ -n "$ROOT" ]] || ROOT="$(git rev-parse --show-toplevel 2>/dev/null || true)"
# Physical spellings on both sides, so a symlinked or Git Bash-spelled root and
# the file path it contains compare equal.
if [[ -n "$ROOT" ]]; then
  ROOT="$(cd "$ROOT" 2>/dev/null && pwd -P)" || ROOT=""
fi
HOME_P=""
if [[ -n "${HOME:-}" ]]; then
  HOME_P="$(cd "$HOME" 2>/dev/null && pwd -P)" || HOME_P=""
fi
CONFIG_P=""
if [[ -n "${CLAUDE_CONFIG_DIR:-${HOME:+$HOME/.claude}}" ]]; then
  CONFIG_P="$(cd "${CLAUDE_CONFIG_DIR:-$HOME/.claude}" 2>/dev/null && pwd -P)" || CONFIG_P=""
fi

# Whether a physical path under $HOME is an instruction file: a markdown file
# (CLAUDE.md, CLAUDE.local.md, AGENTS.md, rules, skills, agents, output styles,
# and the files they import or a symlink points at), or the JSON that carries
# hook instruction text (settings.json, settings.local.json, a plugin's
# hooks.json) inside a .claude tree or the resolved config directory. Anything
# else under $HOME, such as .ssh/config, .claude/.credentials.json or a shell rc
# file, is not a surface, so its lines are never hashed into an anchor.
#
# Home-directory scope. The user surface is $HOME-wide, not
# ${CLAUDE_CONFIG_DIR:-~/.claude} alone, because Claude Code reads instruction
# files that sit outside the config directory and under $HOME.
#   Claim:   "Claude Code loads `CLAUDE.md` and `CLAUDE.local.md` from your
#            current working directory and every directory above it", and reads
#            "every `AGENTS.md` and `.claude/AGENTS.md` in your working directory
#            and the directories above it" where no CLAUDE.md counts; imports
#            accept "Both relative and absolute paths", and a user-scope file's
#            imports load without the approval dialog.
#   Basis:   https://code.claude.com/docs/en/memory ("How CLAUDE.md files load",
#            "When Claude Code reads AGENTS.md", "Import additional files").
#   As of:   2026-09-29.
#   Recheck: the ancestor-loading or import-path sentences change, or a release
#            note adds an instruction file type that is neither *.md nor the
#            settings and hooks JSON above.
instruction_shape() {
  case "$1" in
  *.md) return 0 ;;
  */settings.json | */settings.local.json | */hooks.json) ;;
  *) return 1 ;;
  esac
  [[ "$1" == */.claude/* || (-n "$CONFIG_P" && "$1" == "$CONFIG_P"/*) ]]
}

surface_of() {
  local p="$1" dir base dir_abs abs target hops=0
  # Follow a symlink chain by hand (plain readlink is portable; -f is GNU-only),
  # bounded so a cycle cannot spin forever.
  while [[ -L "$p" ]] && ((hops < 32)); do
    target="$(readlink "$p" 2>/dev/null)" || break
    [[ -n "$target" ]] || break
    [[ "$target" == /* ]] || target="$(dirname -- "$p")/$target"
    p="$target"
    hops=$((hops + 1))
  done
  dir="$(dirname -- "$p")"
  base="$(basename -- "$p")"
  dir_abs="$(cd -- "$dir" 2>/dev/null && pwd -P)" || return 1
  abs="$dir_abs/$base"
  if [[ -n "$ROOT" && "$abs" == "$ROOT"/* ]]; then
    printf '%s' "${abs#"$ROOT"/}"
    return 0
  fi
  if [[ -n "$HOME_P" && "$abs" == "$HOME_P"/* ]]; then
    instruction_shape "$abs" || return 2
    printf 'user:%s' "${abs#"$HOME_P"/}"
    return 0
  fi
  return 1
}

# Three lines for line <n> of <file>: its text, 1 when it sits inside a fenced
# block (else 0), and its enclosing ATX heading path joined by 0x1F. Prints
# nothing when the line is past EOF. A heading line's own text is its excerpt,
# never part of its own path.
line_context() {
  LC_ALL=C awk -v want="$2" '
    { sub(/\r$/, "") }
    NR == want {
      path = ""
      for (i = 1; i <= 6; i++) if (i in stack) path = path (path == "" ? "" : "\037") stack[i]
      print $0
      print (infence ? 1 : 0)
      print path
      found = 1
      exit
    }
    NR == 1 && /^---[[:space:]]*$/ { infm = 1; next }
    infm { if (/^---[[:space:]]*$/) infm = 0; next }
    # Block HTML comments outside a fence do not affect anchors, so a
    # heading-shaped line inside one never enters the path.
    incomment { if (/-->/) incomment = 0; next }
    !infence && /^[ \t]*<!--/ && !/-->/ { incomment = 1; next }
    /^[ \t]*(```|~~~)/ { infence = !infence; next }
    !infence && /^#{1,6}[ \t]/ {
      level = match($0, /[^#]/) - 1
      for (i = level; i <= 6; i++) delete stack[i]
      h = $0
      sub(/[ \t]+$/, "", h)
      stack[level] = h
    }
  ' "$1"
}

json_str() {
  local s="$1"
  s="${s//\\/\\\\}"
  s="${s//\"/\\\"}"
  printf '"%s"' "$s"
}

refuse() {
  printf '#REFUSED\t%s\t%s\n' "$1" "$2"
}

# site_of <path> <line> -> prints `<surface>=<anchor>`, or a refusal reason on
# stderr-free stdout prefixed with `!`.
site_of() {
  local path="$1" lno="$2" surface ctx text infence hpath anchor
  local -a args
  if [[ ! -f "$path" ]]; then
    printf '!file-unreadable'
    return
  fi
  surface="$(surface_of "$path")"
  case $? in
  0) ;;
  2)
    printf '!surface-not-an-instruction-file'
    return
    ;;
  *)
    printf '!surface-outside-repository-and-home'
    return
    ;;
  esac
  if [[ "$surface" == *"="* ]]; then
    printf '!surface-contains-equals-sign'
    return
  fi
  ctx="$(line_context "$path" "$lno")"
  if [[ -z "$ctx" ]]; then
    printf '!line-past-eof'
    return
  fi
  {
    IFS= read -r text
    IFS= read -r infence
    IFS= read -r hpath
  } <<<"$ctx"
  if [[ -z "${text//[[:space:]]/}" ]]; then
    printf '!blank-line'
    return
  fi
  args=(anchor --excerpt "$text")
  [[ -n "$hpath" ]] && args+=(--heading-path "$hpath")
  [[ "$infence" == "1" ]] && args+=(--in-fence)
  anchor="$(bash "$FI" "${args[@]}")" || {
    printf '!anchor-derivation-failed'
    return
  }
  printf '%s=%s' "$surface" "$anchor"
}

process_row() {
  local row="$1" id pa la pb lb claim s1 s2 fid gid pairwise=0
  if [[ "$row" =~ ^(.+):([0-9]+)\|(.+):([0-9]+)\|(I[0-9]+(-[a-f])?)$ ]]; then
    pa="${BASH_REMATCH[1]}"
    la="${BASH_REMATCH[2]}"
    pb="${BASH_REMATCH[3]}"
    lb="${BASH_REMATCH[4]}"
    id="${BASH_REMATCH[5]}"
    pairwise=1
  elif [[ "$row" =~ ^(.+):([0-9]+):(I[0-9]+(-[a-f])?)$ ]]; then
    pa="${BASH_REMATCH[1]}"
    la="${BASH_REMATCH[2]}"
    id="${BASH_REMATCH[3]}"
  else
    refuse "$row" "unparsable-row"
    return
  fi
  claim="$(claim_template "$id")" || {
    refuse "$row" "no-claim-template"
    return
  }
  if [[ "$pairwise" -eq 1 && "$id" != "I15" ]]; then
    refuse "$row" "pairwise-row-for-a-single-site-claim"
    return
  fi
  if [[ "$pairwise" -eq 0 && "$id" == "I15" ]]; then
    refuse "$row" "I15-requires-two-sites"
    return
  fi

  s1="$(site_of "$pa" "$la")"
  if [[ "$s1" == !* ]]; then
    refuse "$row" "${s1#!}"
    return
  fi
  local -a site_args=(--site "$s1")
  s2=""
  if [[ "$pairwise" -eq 1 ]]; then
    s2="$(site_of "$pb" "$lb")"
    if [[ "$s2" == !* ]]; then
      refuse "$row" "${s2#!}"
      return
    fi
    if [[ "$s2" == "$s1" ]]; then
      refuse "$row" "pairwise-sites-identical"
      return
    fi
    site_args+=(--site "$s2")
  fi

  fid="$(bash "$FI" finding-id --check "$CHECK_PREFIX$id" --claim "$claim" "${site_args[@]}")" || {
    refuse "$row" "finding-id-derivation-failed"
    return
  }
  gid="$(bash "$FI" group-id --check "$CHECK_PREFIX$id" --claim "$claim")" || {
    refuse "$row" "group-derivation-failed"
    return
  }

  if [[ "$RECORDS" -eq 0 ]]; then
    if [[ -n "$s2" ]]; then
      printf '%s\t%s\t%s\t%s\t%s\n' "$row" "$fid" "$gid" "$s1" "$s2"
    else
      printf '%s\t%s\t%s\t%s\n' "$row" "$fid" "$gid" "$s1"
    fi
    return
  fi

  local sites_json site
  sites_json=""
  for site in "$s1" ${s2:+"$s2"}; do
    [[ -n "$sites_json" ]] && sites_json+=","
    sites_json+="{\"surface\":$(json_str "${site%%=*}"),\"anchor\":$(json_str "${site#*=}")}"
  done
  printf '{"record":"finding","identity":{"check":%s,"claim":%s,"sites":[%s]%s},"finding_id/v1":%s,"group":%s}\n' \
    "$(json_str "$CHECK_PREFIX$id")" "$(json_str "$claim")" "$sites_json" \
    "$([[ "$pairwise" -eq 1 ]] && printf ',"pairwise":true')" \
    "$(json_str "$fid")" "$(json_str "$gid")"
}

while IFS= read -r row || [[ -n "$row" ]]; do
  row="${row%$'\r'}"
  [[ -n "$row" ]] || continue
  process_row "$row"
done < <(if [[ -n "$INPUT" ]]; then cat -- "$INPUT"; else cat; fi)
