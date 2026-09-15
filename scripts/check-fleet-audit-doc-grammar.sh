#!/usr/bin/env bash
# Gate: the argument grammar the audit skill DOCUMENTS must match the grammar
# audit-fleet.sh actually ACCEPTS.
#
#   scripts/check-fleet-audit-doc-grammar.sh          discover: report what the
#                                                      parser answered and what
#                                                      the skill body documents
#   scripts/check-fleet-audit-doc-grammar.sh --check  fail on a mismatch
#
# Why this exists: #2646 merged a docs-only rebase whose SKILL.md predated
# #2638. The rebase was textually clean and reverted the SKILL layer only,
# leaving audit-fleet.sh untouched — so the skill body instructed agents to
# reject the exact invocation the script accepts, and every test passed,
# because every test lives on the script side and the parser never changed
# (claude-code-plugins#2713). No test inside the plugin can catch a defect
# whose two halves are individually correct.
#
# Why this lives outside both protected files: the shape
# check-fleet-finding-test-coverage.sh established for #2656 — a stale-base
# rewrite of SKILL.md or of audit-fleet.sh cannot delete its own defender.
#
# Agreement is established by PROBING THE SCRIPT AND READING ITS ANSWERS, never
# by pattern-matching the parser source. A gate that greps the parser is a
# second, drifting copy of the parser.
#
#   1. Bare positional is in both or neither. `--apply-plan <missing> <dir>`
#      resolves immediately after the argument loop and before config
#      resolution or discovery, so three outcomes are distinguishable:
#        "unknown argument"                             -> rejected
#        "cannot be combined with audit discovery flags" -> accepted (it landed
#                                                           in the discovery
#                                                           scope arrays)
#        "apply-plan file not found"                    -> silently ignored
#      The skill's argument-hint must carry a bare positional form iff the
#      probe says accepted.
#   2. Every scope form the script NAMES is documented. The no-scope probe
#      prints the script's own remedy block; each scope token in it must have a
#      grammar bullet in the skill body. The expected set is derived from the
#      script at run time, so it updates itself when the grammar changes —
#      there is no hand-maintained list to go stale.
#   3. No-scope behaviour matches: the no-scope probe must STOP non-zero and
#      emit that remedy block rather than produce a report.
#
# NON-FLAKINESS IS THE DESIGN CONSTRAINT — a gate that cries wolf gets disabled.
#   - Probes never reach discovery or GitHub: no network, no `gh`, no `git`
#     traversal. Both resolve inside the argument/scope layer.
#   - The environment is SEALED (HOME, USERPROFILE, CLAUDE_PROJECT_DIR,
#     XDG_CONFIG_HOME redirected to a scratch dir), so a maintainer carrying
#     ~/.claude/repo-fleet-hygiene.conf gets the same verdict as CI.
#   - A probe whose output matches none of the recognized outcomes is a hard
#     exit 2 "probe inconclusive", never a pass — the analogue of the sibling
#     gate's finding-kind extraction floor. A reworded script error cannot
#     silently false-green.
#   - Doc predicates read STRUCTURED surfaces (the argument-hint frontmatter
#     field, the grammar bullet list), never free prose.
#
# NOT COVERED, deliberately: a6be07f9's third defect — SKILL.md claiming
# --project-dir is "the no-scope fallback target" when the script stops. Every
# predicate over that claim is free-prose matching, which either cries wolf or
# silently stops matching after a reword; neither is worth shipping. Assertions
# 1 and 2 already red-line that commit on structured surfaces.
#
# FLEET_DOC_GRAMMAR_SCRIPT / FLEET_DOC_GRAMMAR_SKILL override the paths (test
# injection and historical proofs).
set -uo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/.." || exit 2

SCRIPT="${FLEET_DOC_GRAMMAR_SCRIPT:-plugins/repo-fleet-hygiene/skills/audit/scripts/audit-fleet.sh}"
SKILL="${FLEET_DOC_GRAMMAR_SKILL:-plugins/repo-fleet-hygiene/skills/audit/SKILL.md}"

mode="${1:-discover}"
case "$mode" in
discover | --check) ;;
*)
  echo "usage: $(basename "$0") [--check]" >&2
  exit 2
  ;;
esac

if [[ ! -f "$SCRIPT" ]]; then
  echo "check-fleet-audit-doc-grammar: collector not found: $SCRIPT" >&2
  exit 2
fi
if [[ ! -f "$SKILL" ]]; then
  echo "check-fleet-audit-doc-grammar: skill body not found: $SKILL" >&2
  exit 2
fi

inconclusive() {
  echo "check-fleet-audit-doc-grammar: probe inconclusive — $1" >&2
  echo "The probe, not the skill body, is what broke. Re-read the collector's" >&2
  echo "argument/scope layer and update this gate's recognized outcomes." >&2
  exit 2
}

SEAL="$(mktemp -d)"
trap 'rm -rf "$SEAL"' EXIT
mkdir -p "$SEAL/home" "$SEAL/xdg" "$SEAL/positional"

# Sealed probe. Never pipe this: $? through a pipeline reports the LAST command,
# which false-greens every probe.
probe() {
  HOME="$SEAL/home" \
    USERPROFILE="$SEAL/home" \
    XDG_CONFIG_HOME="$SEAL/xdg" \
    CLAUDE_PROJECT_DIR="" \
    bash "$SCRIPT" "$@" 2>&1
}

# --- Probe 1: is a bare positional path accepted? ----------------------------
positional_out="$(probe --apply-plan "$SEAL/no-such-plan.json" "$SEAL/positional")"
positional_rc=$?

case "$positional_out" in
*"cannot be combined with audit discovery flags"*) POSITIONAL="accepted" ;;
*"unknown argument"*) POSITIONAL="rejected" ;;
*"apply-plan file not found"*) POSITIONAL="ignored" ;;
*) inconclusive "the bare-positional probe returned an unrecognized outcome (rc=$positional_rc): $positional_out" ;;
esac

# --- Probe 2: what does the script do, and say, with no scope at all? --------
noscope_out="$(probe)"
noscope_rc=$?

# Scope forms named by the script's OWN remedy block: an indented token followed
# by its description. Derived per run, so a grammar change updates the expected
# set without touching this file.
scope_forms="$(printf '%s\n' "$noscope_out" |
  grep -oE '^[[:space:]]{2,}(<[a-z]+>|--[a-z][a-z-]*)[[:space:]]' |
  awk '{print $1}' | sort -u)"
scope_form_count="$(printf '%s\n' "$scope_forms" | grep -c . || true)"

if [[ "$noscope_rc" -eq 0 ]]; then
  NOSCOPE="report"
elif [[ "$scope_form_count" -ge 2 ]]; then
  NOSCOPE="stopped"
else
  inconclusive "the no-scope probe stopped (rc=$noscope_rc) without a parseable remedy block; extracted $scope_form_count scope form(s): $noscope_out"
fi

# --- Doc side: argument-hint --------------------------------------------------
# Frontmatter field, not prose. Absence is a structural break, not a pass.
arg_hint="$(sed -n 's/^argument-hint:[[:space:]]*"\(.*\)"[[:space:]]*$/\1/p' "$SKILL" | head -n 1)"
if [[ -z "$arg_hint" ]]; then
  inconclusive "no quoted argument-hint frontmatter field in $SKILL"
fi

# A bracket group whose first character is not '-' is a positional form.
# "[<dir>]... [--root <dir>]..." -> [<dir>] qualifies; "[--root <dir>]" does not.
doc_bare_positional=false
while IFS= read -r group; do
  [[ -n "$group" ]] || continue
  inner="${group#[}"
  inner="${inner%]}"
  inner="${inner#"${inner%%[![:space:]]*}"}"
  [[ -n "$inner" ]] || continue
  if [[ "${inner:0:1}" != "-" ]]; then
    doc_bare_positional=true
    break
  fi
done < <(printf '%s\n' "$arg_hint" | grep -oE '\[[^]]*\]')

# --- Doc side: the grammar bullet list ---------------------------------------
# Scoped to the Input resolution section so unrelated backticked bullets
# elsewhere in the body cannot stand in for a grammar entry.
doc_grammar="$(awk '
  /^## Input resolution[[:space:]]*$/ { inside = 1; next }
  /^## / { inside = 0 }
  inside && /^- `[^`]+`:/ {
    line = $0
    sub(/^- `/, "", line)
    sub(/`.*$/, "", line)
    split(line, parts, " ")
    if (parts[1] ~ /^(-|<)/) print parts[1]
  }
' "$SKILL" | sort -u)"
doc_grammar_count="$(printf '%s\n' "$doc_grammar" | grep -c . || true)"
if [[ "$doc_grammar_count" -lt 3 ]]; then
  inconclusive "the Input resolution grammar list in $SKILL yielded $doc_grammar_count bullet(s); the extraction, not the skill body, is broken"
fi

doc_documents() {
  printf '%s\n' "$doc_grammar" | grep -Fxq -- "$1"
}

if [[ "$mode" == "discover" ]]; then
  echo "Collector: $SCRIPT"
  echo "Skill body: $SKILL"
  echo
  echo "Parser probes:"
  echo "  bare positional path   $POSITIONAL"
  echo "  no-scope run           $NOSCOPE (rc=$noscope_rc)"
  echo "  scope forms named      $(printf '%s' "$scope_forms" | tr '\n' ' ')"
  echo
  echo "Skill body:"
  echo "  argument-hint bare positional form   $doc_bare_positional"
  echo "  grammar bullets ($doc_grammar_count)"
  while IFS= read -r entry; do
    [[ -n "$entry" ]] || continue
    printf '    %s\n' "$entry"
  done <<<"$doc_grammar"
  exit 0
fi

errors=0

# Assertion 1 — bare positional is in both or neither.
if [[ "$POSITIONAL" == "accepted" && "$doc_bare_positional" != "true" ]]; then
  echo "DOC GRAMMAR: parser accepts a bare positional path but argument-hint documents no bare positional form" >&2
  echo "  $SCRIPT accepts a bare <dir> as a discovery scope (probe: --apply-plan <missing> <dir> reported the discovery-flag conflict)." >&2
  echo "  $SKILL argument-hint: $arg_hint" >&2
  echo "  Agents told to reject arguments outside the documented grammar will refuse a valid invocation (#2646)." >&2
  errors=$((errors + 1))
elif [[ "$POSITIONAL" != "accepted" && "$doc_bare_positional" == "true" ]]; then
  echo "DOC GRAMMAR: argument-hint documents a bare positional form but the parser does not accept one (probe: $POSITIONAL)" >&2
  echo "  $SKILL argument-hint: $arg_hint" >&2
  errors=$((errors + 1))
fi

# Assertion 2 — every scope form the script names has a grammar bullet.
if [[ "$NOSCOPE" == "stopped" ]]; then
  while IFS= read -r form; do
    [[ -n "$form" ]] || continue
    if ! doc_documents "$form"; then
      echo "DOC GRAMMAR: the collector names '$form' as a way to supply scope, but $SKILL has no grammar bullet for it" >&2
      errors=$((errors + 1))
    fi
  done <<<"$scope_forms"
fi

# Assertion 3 — a no-scope run stops rather than reporting.
if [[ "$NOSCOPE" != "stopped" ]]; then
  echo "DOC GRAMMAR: a no-scope run produced a report (rc=$noscope_rc) instead of stopping with the scope remedy block" >&2
  echo "  The skill body documents the stop-and-name-the-remedies behaviour; the collector no longer does it." >&2
  errors=$((errors + 1))
fi

if [[ "$errors" -gt 0 ]]; then
  echo "check-fleet-audit-doc-grammar: FAILED — $errors mismatch(es)" >&2
  exit 1
fi

echo "check-fleet-audit-doc-grammar: passed — the documented grammar matches the parser (bare positional: $POSITIONAL; scope forms: $(printf '%s' "$scope_forms" | tr '\n' ' '))"
exit 0
