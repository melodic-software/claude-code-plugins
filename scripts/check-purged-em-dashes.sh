#!/usr/bin/env bash
# Fail when an instruction surface this repository has already purged of em
# dashes grows a new one.
#
#   scripts/check-purged-em-dashes.sh            report violations, exit 1 if any
#   scripts/check-purged-em-dashes.sh --check    same (explicit form, matches sibling gates)
#   scripts/check-purged-em-dashes.sh --list     list every declared path and its verdict
#
# Exit: 0 clean, 1 a violation, a stale allowlist entry, or a declared path the
# tracked config puts out of enforcement, 2 usage or a prerequisite this gate
# cannot verify around.
#
# WHY (#2891). The de-slop campaign rewrites prose surface by surface, and each
# landed shard is paid for by hand: a mechanical em-dash split changes meaning
# often enough that every shard so far has needed a rationale-withheld reviewer
# to catch clauses the automated passes waved through. Nothing then stops the
# next contributor from reintroducing one, because no lane enforces the policy.
# A one-time purge with no gate is a purge that silently rots. This gate is the
# ratchet: what the campaign has already cleaned stays clean.
#
# ALLOWLIST, NOT A REPO-WIDE RULE, and the distinction is the whole design.
# 29,649 em-dash prose lines across 1,074 tracked markdown files remained when
# this gate was written, so a repo-wide check would fail nearly every pull
# request on contact and would have to be merged disabled, which is not a gate.
# Enforcing only DECLARED-CLEAN paths inverts that: blast radius at adoption is
# zero, because every listed path already passes. Enforcement then grows with
# the campaign instead of waiting for it. A shard that purges a surface adds
# its lines here in the same pull request, and the surface is defended from that
# moment on.
#
# This is the same shape, and the same argument, as scripts/docs-only-paths.txt:
# a positive list fails safe, because a path NOT listed is simply unenforced
# rather than wrongly declared clean. The failure mode of a blocklist here would
# be the reverse and much worse: a surface silently dropping out of enforcement
# the day someone widened an exclusion.
#
# A STALE ENTRY IS A FAILURE, not a skip. An allowlist entry matching no tracked
# file means the surface was renamed or deleted and the declaration outlived it;
# left as a no-op, the list would accumulate dead lines and quietly enforce less
# than it claims. That is the #1513 shape, a gate that enforces nothing and
# still exits 0, so a zero-match entry fails, naming itself. For the same
# reason an unreadable or entirely inactive allowlist is exit 2 rather than a
# clean run.
#
# THE TRACKED DETECTOR CONFIG IS NOT MODIFIED, and must not be. This repository's
# .claude/ai-slop.json disables rule-em-dash corpus-wide, and re-enabling it there
# is a separate decision the campaign has explicitly gated on the purge finishing
# (#2891, checkbox 4). So this gate does not touch that file, and running it
# changes nothing about what /ai-slop:audit reports. It instead builds a
# THROWAWAY config layer for its own detector invocation: the tracked config
# copied, with every switch that can quiet rule-em-dash removed and nothing else
# altered. Copying rather than synthesizing is deliberate: excluded_paths and
# every threshold stay whatever the tracked file says, so the vendor, catalog
# and eval-fixture exclusions that exist precisely because they contain em
# dashes as DATA keep applying here, and keep applying without a second copy of
# that list to drift.
#
# WHAT THE THROWAWAY LAYER DOES OVERRIDE is exactly the set of keys that would
# let a declared path pass without being judged: rule-em-dash's entry in
# disabled_rules, em_dash_allowed_paths, and rule_allowed_paths["rule-em-dash"].
# A path on the allowlist is a claim that the surface is purged; a per-rule
# exemption on the same path is the opposite claim, and honouring it would let
# the gate report the surface clean while no finding on it was ever possible,
# because such a file is still opened and still counted as scanned.
# excluded_paths is the one exclusion left standing, because its files are
# never opened at all and are therefore visible in the run as declines that the
# verdict names and fails on, rather than folded silently into the clean count.
# A file on this allowlist that genuinely carries the character as data still
# has the detector's in-file exemptions, an ignore marker or a code fence, and
# failing those it belongs off the allowlist with the reason.
#
# REUSES THE DETECTOR RATHER THAN GREPPING. A bare grep for the em-dash byte
# sequence would fire inside fenced code blocks, inline code spans, and
# ignore-marked regions, all of which legitimately carry the character. Prose
# extraction is exactly what plugins/ai-slop/skills/audit/scripts/detect.sh
# already implements and tests, so this gate drives that script and reads its
# findings instead of growing a second, less-tested notion of what prose is.
#
# LIVENESS IS ASSERTED, NOT ASSUMED. detect.sh exits 0 on every audit path by
# design (a read-only audit must never fail its caller), so an exit code proves
# nothing here. Worse, the failure this gate is most exposed to is silent: if the
# throwaway config ever stopped taking effect, rule-em-dash would be disabled,
# the detector would report no em-dash findings, and this gate would pass
# everything forever. So the run is only believed when the detector's own summary
# line for rule-em-dash is present AND reports disabled=0, and when the files it
# accounts for are exactly the files handed to it. Any other shape is exit 2.
# That second count is derived rather than added up from the two summary
# totals, which overlap; see the comment above the arithmetic.
#
# Test injection, all defaulting to this repository:
#   EM_DASH_PURGED_ROOT      repository root to scan
#   EM_DASH_PURGED_PATHS     allowlist file (relative to the root, or absolute)
#   EM_DASH_SLOP_CONFIG      tracked detector config to copy
#   EM_DASH_DETECT           detect.sh to drive
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)" || exit 2

ROOT="${EM_DASH_PURGED_ROOT:-$SCRIPT_DIR/..}"
cd "$ROOT" || {
  echo "check-purged-em-dashes: cannot enter root: $ROOT" >&2
  exit 2
}
ROOT="$(pwd)"

# shellcheck source=lib/read-list.sh
. "$SCRIPT_DIR/lib/read-list.sh" || exit 2

ALLOWLIST="${EM_DASH_PURGED_PATHS:-scripts/em-dash-purged-paths.txt}"
SLOP_CONFIG="${EM_DASH_SLOP_CONFIG:-.claude/ai-slop.json}"
DETECT="${EM_DASH_DETECT:-plugins/ai-slop/skills/audit/scripts/detect.sh}"

MODE=check
case "${1-}" in
"" | --check) ;;
--list) MODE=list ;;
*)
  echo "usage: check-purged-em-dashes.sh [--check|--list]" >&2
  exit 2
  ;;
esac

# --- Prerequisites ----------------------------------------------------------
# Each is fail-closed at exit 2: this gate cannot report a trustworthy "clean"
# without all four, and reporting an untrustworthy one is the failure mode the
# whole design is arranged against.

if ! command -v jq >/dev/null 2>&1; then
  echo "check-purged-em-dashes: jq not found; cannot build the detector config layer" >&2
  exit 2
fi
if [[ ! -r "$SLOP_CONFIG" ]]; then
  echo "check-purged-em-dashes: detector config not readable: $SLOP_CONFIG" >&2
  exit 2
fi
if [[ ! -r "$DETECT" ]]; then
  echo "check-purged-em-dashes: detector not readable: $DETECT" >&2
  exit 2
fi

declare -a GLOBS=()
read_list::into GLOBS "$ALLOWLIST" --comments inline || exit 2
if ((${#GLOBS[@]} == 0)); then
  echo "check-purged-em-dashes: no active entries in $ALLOWLIST; a gate with an empty allowlist enforces nothing" >&2
  exit 2
fi

# --- Expand the allowlist ---------------------------------------------------
# `:(glob)` pathspec magic, not git's default wildmatch: without it `*` matches
# across directory separators, so `plugins/*/README.md` would silently pull in
# `plugins/a/b/README.md`. An allowlist whose entries claim more surface than
# they name is a declaration nobody can audit by reading it.

TMP="$(mktemp -d)" || exit 2
trap 'rm -rf "$TMP"' EXIT

FILES="$TMP/files.txt"
: >"$FILES"
stale=0
# Initialized here rather than only where it is computed: the verdict section
# reads it, this script runs under `set -u`, and a future early return between
# the two would turn a clean run into an unbound-variable crash.
excluded=0
for glob in "${GLOBS[@]}"; do
  matched="$(git ls-files -z -- ":(glob)$glob" | tr '\0' '\n' | sed '/^$/d')"
  count=0
  [[ -n "$matched" ]] && count="$(printf '%s\n' "$matched" | wc -l | tr -d ' ')"
  if ((count == 0)); then
    echo "check-purged-em-dashes: stale allowlist entry matches no tracked file: $glob" >&2
    stale=1
    [[ "$MODE" == list ]] && printf 'STALE  %s\n' "$glob"
    continue
  fi
  [[ "$MODE" == list ]] && printf 'ok     %s (%s files)\n' "$glob" "$count"
  printf '%s\n' "$matched" >>"$FILES"
done

sort -u -o "$FILES" "$FILES"
EXPECTED="$(wc -l <"$FILES" | tr -d ' ')"

if ((stale == 1)); then
  echo "check-purged-em-dashes: remove or repoint the stale entries above" >&2
  exit 1
fi
if ((EXPECTED == 0)); then
  echo "check-purged-em-dashes: allowlist expanded to zero files" >&2
  exit 2
fi

# --list stops here, and stopping here is the point. The allowlist header tells
# a reader to audit the declaration by expanding it with --list and grepping the
# named files, WITHOUT running the detector. Falling through to the detector run
# would make that audit cost the same minutes as a full check and would report a
# check verdict under a listing flag.
if [[ "$MODE" == list ]]; then
  printf 'check-purged-em-dashes: %s declared paths, %s files.\n' "${#GLOBS[@]}" "$EXPECTED"
  exit 0
fi

# --- Throwaway detector config ----------------------------------------------
# The tracked config with every switch that can quiet rule-em-dash removed. An
# empty HOME keeps the user-global layer out: detect.sh cascades
# $HOME/.claude/ai-slop.json under the repo layer, and a contributor who happens
# to carry one must not be able to change this gate's verdict.
#
# Three keys can silence this rule and all three are stripped, because a path on
# the allowlist declares the surface purged and a per-rule exemption claims it
# need not be. `disabled_rules` turns the rule off outright.
# `em_dash_allowed_paths` and `rule_allowed_paths["rule-em-dash"]` turn it off
# per file, and those two are the quieter hazard: detect.sh still OPENS such a
# file, so it lands in the scanned count, the coverage assertion below still
# balances, and the rule summary still reports `disabled=0`. Nothing in the run
# says why no finding was possible, and the gate would call the surface checked
# and clean.
#
# `excluded_paths` is deliberately NOT stripped. Those files are never opened,
# so they surface as excluded-glob declines that the verdict below names and
# fails on, which is the report this gate wants rather than a silent override.

mkdir -p "$TMP/root/.claude" "$TMP/home" || exit 2
if ! jq '.disabled_rules |= ((. // []) | map(select(. != "rule-em-dash")))
  | del(.em_dash_allowed_paths)
  | .rule_allowed_paths |= ((. // {}) | del(."rule-em-dash"))' \
  "$SLOP_CONFIG" >"$TMP/root/.claude/ai-slop.json"; then
  echo "check-purged-em-dashes: could not derive the detector config from $SLOP_CONFIG" >&2
  exit 2
fi

OUT="$TMP/findings.txt"
if ! HOME="$TMP/home" CLAUDE_PROJECT_DIR="$TMP/root" \
  bash "$DETECT" --paths-file "$FILES" >"$OUT" 2>"$TMP/detect.err"; then
  echo "check-purged-em-dashes: detector failed" >&2
  cat "$TMP/detect.err" >&2
  exit 2
fi

# --- Believe the run only if it proves it happened --------------------------

summary="$(grep -m1 '^Summary rule=ai-slop/audit/rule-em-dash ' "$OUT")"
if [[ -z "$summary" ]]; then
  echo "check-purged-em-dashes: detector emitted no rule-em-dash summary; cannot confirm the rule ran" >&2
  exit 2
fi
if [[ "$summary" != *" disabled=0"* ]]; then
  echo "check-purged-em-dashes: rule-em-dash was disabled for this run ($summary); the config layer did not take effect" >&2
  exit 2
fi

# The detector's two counters OVERLAP, and reading them as disjoint is how this
# assertion misfires. "files scanned" counts every file the detector opened,
# which includes one it opened and then declined on an in-file marker; that file
# is counted a second time under "files declined". Only a file excluded by a
# config glob is never opened, so only that cause is missing from the scanned
# count. Unique files handled is therefore the scanned count plus the
# excluded-glob declines alone, and the detector names the cause on every
# decline row, so the gate reads those rather than inferring them.
scanned="$(sed -n 's/^Summary total: [0-9]* findings across \([0-9]*\) files scanned ([0-9]* files declined)$/\1/p' "$OUT")"
if [[ -z "$scanned" ]]; then
  echo "check-purged-em-dashes: detector emitted no total summary; cannot confirm coverage" >&2
  exit 2
fi
excluded="$(grep -c '^Declined: file=.* cause=excluded-glob$' "$OUT" || true)"
handled=$((scanned + excluded))
if ((handled != EXPECTED)); then
  echo "check-purged-em-dashes: detector handled $handled files but $EXPECTED were declared; coverage is not what the allowlist claims" >&2
  exit 2
fi

# --- Verdict ----------------------------------------------------------------

# A declared path that the tracked config excludes FAILS the gate rather than
# folding into the clean count. Such a path is inside the allowlist and outside
# enforcement at the same time, which is the one way this gate can be green over
# a surface it is checking nothing on. Reporting it is not enough: an unenforced
# declaration reads as coverage to every consumer of this exit code, so only a
# nonzero verdict keeps it from shipping as one.
verdict=0
if ((excluded > 0)); then
  echo "check-purged-em-dashes: $excluded declared file(s) are excluded by $SLOP_CONFIG and were NOT checked:" >&2
  sed -n 's/^Declined: file=\([^ ]*\) cause=excluded-glob$/  \1/p' "$OUT" >&2
  echo "check-purged-em-dashes: remove them from $ALLOWLIST or from the config's excluded_paths; declaring a path the detector never reads enforces nothing" >&2
  verdict=1
fi

findings="$(grep '^Finding: rule=ai-slop/audit/rule-em-dash ' "$OUT")"
if [[ -z "$findings" ]]; then
  if ((verdict == 0)); then
    printf 'check-purged-em-dashes: %s declared paths, %s files scanned, no em dashes.\n' "${#GLOBS[@]}" "$scanned"
  else
    echo "check-purged-em-dashes: the $scanned file(s) that were checked carry no em dashes, but the excluded file(s) above were not checked at all" >&2
  fi
  exit "$verdict"
fi

count="$(printf '%s\n' "$findings" | wc -l | tr -d ' ')"
echo "check-purged-em-dashes: $count em-dash line(s) on surfaces declared purged in $ALLOWLIST" >&2
printf '%s\n' "$findings" |
  sed -n 's|^Finding: rule=ai-slop/audit/rule-em-dash file=\([^ ]*\) line=\([0-9]*\) .*excerpt=\(.*\)$|  \1:\2: \3|p' >&2
cat >&2 <<'EOF'

These paths are declared already purged, so an em dash here is a regression.
Rewrite the line: a period, a comma, or a restructured sentence. Do not
substitute parentheses, en dashes, or spaced hyphens, and do not "fix" an em
dash that is quoted data, a fixture, or third-party text. Take that path off
the allowlist instead, with the reason.
EOF
exit 1
