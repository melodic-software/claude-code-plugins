#!/usr/bin/env bash
# Gate: a skill's eval suite and its detector must agree on the check-id set,
# in BOTH directions.
#
#   scripts/check-detector-eval-coverage.sh          discover: per registered
#                                                     pair, print the emitted
#                                                     ids, the eval-named ids,
#                                                     and each id's status
#   scripts/check-detector-eval-coverage.sh --check  fail if an emitted id is
#                                                     covered by no eval case, or
#                                                     an eval case names an id
#                                                     the detector cannot emit
#
# Output follows the check-script contract (README.md, "The check-script
# contract"): 0 clean, 1 findings, 2 environment or usage, findings on stderr.
#
# WHY. claude-code-plugins#4149 found claude-config:audit-permission-grants
# emitting five check ids while its eval suite exercised three, and one case
# (`scope-boundary-routes-out`) asserting in prose that the owned scope IS the
# stale three. So the suite did not merely under-cover the detector: it graded a
# model for ignoring a check that fires. Backfilling the missing cases closes
# that instance; nothing stopped the NEXT added check from reopening it, which
# is what this gate is.
#
# The reverse direction is the half that would have caught the stale case, and
# it is the half a coverage-only check omits. An eval naming an id the detector
# cannot emit is either a check that was renamed out from under its suite or a
# scope claim that was never true. Both read as coverage until something asks
# the detector.
#
# WHAT COUNTS AS COVERAGE, and why it is not "the string appears in the file".
# An earlier revision read every string anywhere in evals.json through
# `.. | strings`. That verifies MENTION, not coverage, and four shapes passed it
# while covering nothing: an id named only inside a NEGATIVE assertion ("does
# NOT exercise P4"), an id that is only an incidental path token in `files`
# (`~/w/P4/settings.json`), a suite with ZERO cases whose id appears only in
# top-level `skill_name`, and a file that is a bare JSON string -- `jq -e .`
# accepts one, so parseability was the only shape check there was.
#
# So the shape is asserted first: the suite must be a JSON OBJECT carrying a
# NON-EMPTY `evals` ARRAY whose every entry is an OBJECT. Anything else is exit
# 2 (a suite this gate cannot read), never a pass. A mention outside `evals[]`
# -- `skill_name` included -- counts for nothing.
#
# Within an entry, the coverage-bearing fields are `expected_output` and
# `expectations`, and only those. Read the real suite
# (plugins/claude-config/skills/audit-permission-grants/evals/evals.json): an
# entry carries `id`, `name`, `prompt`, `files`, `expected_output`,
# `expectations`. Of those, `expected_output` and `expectations` are the two the
# runner GRADES a response against, so naming a check id there is the suite
# asserting that check is exercised. The rest cannot carry that force: `prompt`
# is the operator's INPUT (naming an id there feeds it to the model, it does not
# grade it), `name` is a label, `files` is fixture paths (the incidental-token
# shape above), and `id` is an ordinal.
#
# NEGATIVE ASSERTIONS: an ADVISORY, never a failure. A graded expectation can
# name an id in order to assert it is NOT exercised, and that is the opposite of
# coverage. An earlier revision screened for that automatically and let the
# screen FAIL the gate: an id stopped counting as covered whenever a negation
# cue appeared anywhere in the 80 characters before it, back to the previous
# `.`, `;` or `:`. Ordinary covering prose carries those cues -- "Reports P1. A
# rule without a scope suffix must be flagged as P4.", "a rule that does not
# name an interpreter is reported as P4" -- so a genuinely covering expectation
# was read as a disclaimer and the gate exited 1 on a correct suite. That is the
# worst failure available to a gate: a false FAILURE with no remedy except
# editing this script.
#
# So the screen no longer decides pass or fail. Two changes:
#
#   1. The cue must attach to the ID'S OWN PREDICATE. The window is the two
#      words immediately before the id, back to the previous clause break, and
#      `,` is a break now alongside `.`, `;` and `:`. "does not exercise P4"
#      still reads as a disclaimer; "flagged as P4" and "reported as P4" do not,
#      whatever some earlier clause said.
#   2. A disclaimed-only id is reported as a DISCLAIMED advisory (stdout, exit
#      0), not as a finding. Only an id named in NO graded field at all is an
#      UNCOVERED finding.
#
# Why that trade rather than a tighter screen alone. Deciding merge/no-merge
# from a heuristic reading of English is what produced the false failure, and
# narrowing does not remove that class -- it only makes the next sentence that
# trips it rarer and more surprising. Meanwhile the half of this gate that
# caught claude-code-plugins#4149, the REVERSE direction, is untouched: a
# disclaimed id is still NAMED, so it must still be emittable, and a case
# asserting "P4 is out of scope" beside a detector that cannot emit P4 still
# fails. The screen stays purely one-directional and is now purely advisory.
#
# RESIDUE, in BOTH directions, because the revision before this one enumerated
# only the first:
#   - FALSE PASS (widened by this trade): a suite whose only mention of an
#     emitted id is a blunt disclaimer ("deliberately does NOT exercise P4") now
#     PASSES, with a DISCLAIMED advisory beside it. Nothing exercises P4 and
#     this gate will not stop that; the advisories are the thing to read.
#   - FALSE PASS (unchanged): a negation phrased outside the cue set, placed
#     after the id ("P4 is never exercised"), or more than two words before it
#     ("does not cover the P4 check") reads as ordinary coverage and prints no
#     advisory at all.
#   - FALSE FAILURE: not reachable THROUGH THE SCREEN any more, because the
#     screen cannot fail the gate. What remains is the plainer kind: a case that
#     exercises a check without naming its id in a graded field -- describing it
#     in prose, or naming it only in `prompt`, `name` or `files` -- is an
#     UNCOVERED finding, correct by this gate's definition of coverage and wrong
#     by a human's. Its remedy is cheap (name the id in `expected_output` or
#     `expectations`); the screen-driven false failure had none, which is why
#     the screen no longer fails anything.
#   - FALSE ADVISORY: a covering sentence that does put a cue in the two words
#     before the id ("flags a grant with no P4 suffix") prints a DISCLAIMED
#     advisory it does not deserve. That costs one line of stdout and no exit
#     code, which is the whole point of moving the screen off the exit path.
#
# ACCOUNTING FOR EVERY EMIT CALL SITE, and why a partial loss is exit 2. The
# emitted-id set comes from `emit <severity> <id>` call sites. An earlier
# revision extracted them with one greedy sed and guarded only the case where
# extraction yielded exactly ZERO, so every PARTIAL loss passed silently:
# `emit "$sev" P4` (variable severity), `emit error "$id"` (variable id), two
# emits on one line (the greedy `.*` kept only the last), a partially renamed
# emitter, and an id outside the row's pattern (`P2ab` under `P[0-9]+[a-z]?`)
# each dropped an id while the rest of the file kept the count non-zero.
#
# So the scanner COUNTS candidate call sites and compares that count against the
# ids it actually resolved. Any mismatch is exit 2 -- cannot determine -- and
# names the unparsed sites. A gate that cannot see its inputs must never pass,
# and an emitter shape this scanner cannot read is exactly that.
#
# The scanner reads shell rather than grepping it: heredoc bodies and quoted
# string contents are removed before any call site is looked for, so an
# `emit error P9` inside the detector's own help text or prose is not a call
# site (which the greedy sed counted, yielding a permanent false failure), and a
# `#` comment after real code is dropped once quoting is resolved.
#
# ORDINARY SHELL IS NOT A PARTIAL LOSS. The first version of that scanner was
# too literal and too loose at once, and exit 2 means "cannot determine", so
# every shape it misread failed CLOSED on a detector that was perfectly well
# formed. Five reproduced shapes, and what reads them now:
#   - `emit "error" P1` and `emit error "P1"`. A quoted run whose whole content
#     is one bare literal word is now that word, tagged as having been quoted;
#     only a multi-word or expanding run stays the opaque `@Q@`. The tag is what
#     keeps prose safe: an emitter NAME must be unquoted, so `echo "emit"` is
#     still not a call site while `emit "error" P1` resolves.
#   - `emit \` + newline + `warning P4`. Backslash-newline is joined first, so a
#     continued call is ONE logical site rather than a truncated one plus an
#     orphan fragment.
#   - `emit_x() { emit error "$@"; }`. The definition header was already
#     removed; what tripped it was the forwarding body. A call whose severity or
#     id is `"$@"`/`$@`/`$*` carries no literal id to lose -- the ids enter at
#     the WRAPPER's own call sites, which are counted like any other -- so a
#     forwarder is not a call site.
#   - `local emit_count`. An emitter token now has to stand in COMMAND POSITION
#     (first word of a command, after `;`/`&&`/`|`/`(`/`{`, after a keyword such
#     as `if`/`then`/`do`, or after a `VAR=value` prefix) and have at least one
#     argument. A bare identifier that merely begins with `emit` is a variable,
#     not a call.
#
# The property the accounting exists for is unchanged: a call site that DOES
# carry a literal id this scanner cannot read is still exit 2. `emit "$sev" P4`,
# `emit error "$id"`, `emit error P2ab` under /P[0-9]+[a-z]?/ and a half-renamed
# `emitx` with unreadable arguments all still refuse to produce a verdict.
#
# RESIDUE of the scanner, both directions:
#   - MISSED (false pass): an emitter renamed to something that does not begin
#     with `emit` is invisible to both the count and the extraction -- a total
#     rename still trips the zero-ids guard, a partial one to such a name does
#     not. An emit reached only through a variable or an alias
#     (`$emitter error P1`) is likewise invisible. A forwarder that rewrites its
#     id rather than passing it through (`emit error "P${n}"`) is skipped as a
#     forwarder only if its id token is literally `"$@"`/`$*`; otherwise it is
#     unresolved and exits 2, which is the safe side.
#   - SPURIOUS (false failure, exit 2): a call site whose severity or id is
#     computed rather than written -- a lookup table of ids, a loop over a list
#     -- cannot be read and stops the gate. That is deliberate (the gate must
#     not pass on inputs it cannot see) but it IS a false failure for a detector
#     written that way, and the remedy is a registry-row conversation, not a
#     silent pass. A quoted literal carrying a space or an expansion
#     (`emit "$sev" P4`) is the same answer.
#
# Adjacent and DIFFERENT: scripts/check-detector-findings-crosswalk.sh checks
# that each severity-crosswalk row in docs/conventions/detector-findings/ argues
# its disposition from a stated test. That is a judgment about a markdown table
# and says nothing about eval coverage.
# scripts/check-fleet-finding-test-coverage.sh is the same SHAPE one surface
# over (emitted kinds vs unit-test assertions) for one named collector; it does
# not read any evals.json.
#
# WHY A REGISTRY RATHER THAN DISCOVERY, AND WHY DISCOVERY ANYWAY. Globbing
# plugins/*/skills/*/ for a detector plus an evals.json finds the pair, but not
# the third fact the comparison needs: the shape of that detector's check ids.
# They are a per-skill vocabulary (`P1`/`P2b` here, something else next time),
# and a gate that guessed the shape would go quietly empty on the first detector
# that spelled them differently. A registry row carries the id pattern
# explicitly.
#
# But a registry with no stopping rule leaves the first NEW detector-plus-evals
# skill silently unenforced, which is the same false-green one level up.
# scripts/check-script-contract.test.sh already answers this for its own family
# ("THE REGISTRY IS THE STOPPING RULE": a new member fails as UNREGISTERED
# rather than being quietly uncovered), so this follows that precedent. Every
# run walks plugins/*/skills/*/ for a QUALIFYING pair -- a skill with an
# evals/evals.json and a non-test script carrying at least two distinct
# `emit <word> <ID>` call sites whose ID is check-id shaped
# (/[A-Z][A-Za-z]*[0-9]+[A-Za-z0-9]*/) -- and an unregistered one is a FINDING
# (exit 1), not an environment answer: the tree is in a real state with a real
# remedy, which is to add the row. Two distinct ids is what separates a check-id
# vocabulary from an `emit <scope> <kind>` printer; the other emitters in this
# repo (permission-state.sh, discover-instruction-surfaces.sh,
# file-provenance.sh) pass none and are correctly not candidates.
#
# Discovery finds those call sites with THE SAME scanner the verdict path uses,
# widened only in the id pattern. It used to have a greedy sed of its own, which
# kept one id per line and so missed a detector spelling two emits as
# `emit warning Q1 ...; emit error Q2 ...` -- the stopping rule defeated by
# ordinary shell that the verdict scanner beside it read correctly. A fix
# applied at one call site and missed at its sibling is the defect class this
# whole gate is about, so the two extractors are now one.
#
# RESIDUE of the stopping rule, both directions:
#   - MISSED (false pass): the shapes the scanner reports UNRESOLVED contribute
#     no id here. A candidate whose ids are computed or quoted-with-expansion
#     (`emit "$sev" Q1`, a lookup table) can sit below the two-distinct-ids bar
#     and never be reported as unregistered. The verdict path answers that shape
#     with exit 2; discovery cannot, because a stranger's unreadable shell is
#     not this run's environment, so it under-counts instead. The same is true
#     of the scanner's own misses: an emitter renamed to something not beginning
#     with `emit`, or reached through a variable, is invisible to both halves.
#   - MISSED (narrowed by this change, deliberately): a candidate whose only
#     check-id-shaped tokens sit inside a quoted string or a heredoc -- help
#     text, a usage block -- used to qualify, because the old sed grepped prose.
#     It no longer does. That is the verdict scanner's reading, and a pair whose
#     detector emits nothing real is not a pair worth a registry row.
#   - SPURIOUS (false failure, exit 1): a script that really does pass two
#     distinct check-id-shaped tokens through an `emit`-prefixed command while
#     being something other than a detector is reported as unregistered. The
#     remedy is the registry-row conversation the rule exists to force.
#
# Registry row: <detector script>|<evals.json>|<check-id ERE>
#
# The ERE matches WHOLE word tokens on both sides: the detector's resolved
# `emit <severity> <id>` call sites, and the coverage-bearing strings of each
# eval entry. So `P1` in `PLAN1` and `P4` in `xP4` name nothing, while `P2` in
# `(P1/P2/P3)` names P2. The row's pattern must therefore describe an id made of
# [A-Za-z0-9_]; an id family spelled with punctuation needs this splitting rule
# revisited rather than a wider pattern.
#
# The boundaries are spelled out rather than written as \b, which is a GNU
# extension scripts/check-shell-portability.sh rejects.
#
# DETECTOR_EVAL_COVERAGE_PAIRS overrides the rows (newline-separated), for the
# self-test and for historical proofs.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)" || exit 2
cd "$SCRIPT_DIR/.." || exit 2

PAIRS_DEFAULT=(
  "plugins/claude-config/skills/audit-permission-grants/scripts/permission-rule-check.sh|plugins/claude-config/skills/audit-permission-grants/evals/evals.json|P[0-9]+[a-z]?"
)

# The check-id SHAPE the stopping rule recognizes across skills it has never
# seen. Deliberately wider than any row's own pattern: this one only has to
# decide "is this a check-id vocabulary at all", and the row that follows states
# the real spelling.
QUALIFYING_ID_ERE='[A-Z][A-Za-z]*[0-9]+[A-Za-z0-9]*'

# Argv is exact. `--check extra` used to ignore its trailing words, which reads
# as a mode the gate accepted and did not run.
if [[ "$#" -gt 1 ]]; then
  echo "usage: $(basename "$0") [--check]" >&2
  exit 2
fi
mode="${1:-discover}"
case "$mode" in
discover | --check) ;;
*)
  echo "usage: $(basename "$0") [--check]" >&2
  exit 2
  ;;
esac

# Read the eval suite through a JSON parser, not a grep: a suite that no longer
# parses must be an environment answer, never a pass. jq is the prerequisite and
# its absence is exit 2 before anything reaches stdout.
if ! command -v jq >/dev/null 2>&1; then
  echo "check-detector-eval-coverage: jq not found; cannot read any eval suite" >&2
  exit 2
fi

# --- the emit-call-site scanner ----------------------------------------------
# Removes heredoc bodies and quoted contents, then resolves each candidate call
# site to an id or reports it unresolved. Emits `ID <id>` lines, `UNRESOLVED
# <site>` lines, and a final `CANDIDATES <n>`.
EMIT_SCAN_AWK=""
read -r -d '' EMIT_SCAN_AWK <<'AWK'
function cmd_position(p) {
  # The first word of a command, or the first word after something that ends
  # one. Everything else that merely BEGINS with `emit` -- `local emit_count`,
  # `declare -i emit_total` -- is an identifier, not a call.
  if (p == "" || p == "@SEP@") return 1
  if (p ~ /^(if|then|else|elif|do|while|until|!|time|exec|command|builtin|eval|nohup)$/) return 1
  if (p ~ /^[A-Za-z_][A-Za-z0-9_]*=/) return 1
  return 0
}
function forwarded(t) { return (t == "@FWD@" || t == "$@" || t == "$*") }
function unquoted_value(t) { return (substr(t, 1, 3) == "@L@") ? substr(t, 4) : t }
BEGIN { hd = ""; candidates = 0; anchored = "^(" idre ")$"; pending = ""; startfnr = 0 }
{
  line = $0

  # Inside a heredoc body: prose, usage text, or a template. Never a call site.
  if (hd != "") {
    t = line
    sub(/^[[:space:]]*/, "", t)
    sub(/[[:space:]]*$/, "", t)
    if (t == hd) hd = ""
    next
  }

  if (pending == "" && line ~ /^[[:space:]]*#/) next

  # BACKSLASH-NEWLINE is joined before anything else looks at the line, so a
  # continued call (`emit \` / `warning P4`) is one logical site rather than a
  # truncated site plus an orphan fragment. An odd number of trailing
  # backslashes continues; an even number is an escaped backslash.
  tb = 0
  j = length(line)
  while (j >= 1 && substr(line, j, 1) == "\\") { tb++; j-- }
  if (tb % 2 == 1) {
    if (startfnr == 0) startfnr = FNR
    pending = pending substr(line, 1, length(line) - 1)
    next
  }
  line = pending line
  pending = ""
  if (startfnr == 0) startfnr = FNR

  # A heredoc OPENING on this line arms the skip for the lines after it. `<<<`
  # is a here-string and opens no body.
  s2 = line
  while ((r = index(s2, "<<")) > 0) {
    tail = substr(s2, r + 2)
    if (substr(tail, 1, 1) == "<") { s2 = substr(s2, r + 3); continue }
    if (substr(tail, 1, 1) == "-") tail = substr(tail, 2)
    sub(/^[[:space:]]*/, "", tail)
    if (match(tail, /^("[A-Za-z_][A-Za-z0-9_]*"|'[A-Za-z_][A-Za-z0-9_]*'|\\?[A-Za-z_][A-Za-z0-9_]*)/)) {
      d = substr(tail, RSTART, RLENGTH)
      gsub(/["'\\]/, "", d)
      hd = d
    }
    break
  }

  # Each quoted run collapses to ONE token, which preserves every call site's
  # ARITY (so `emit "$sev" P4` stays three words and is seen as unresolved)
  # while making prose inside a string unreadable as code. Three outcomes:
  # `@FWD@` for pure argument forwarding, `@L@<word>` for a run that is one
  # bare literal word (so `emit "error" "P1"` resolves), and the opaque `@Q@`
  # for everything else -- multi-word prose, and any run carrying an expansion.
  # The `@L@` tag survives into the token, so a quoted word can be a VALUE but
  # never an emitter NAME: `echo "emit"` stays prose. A `#` that survives the
  # walk is a real comment: drop the rest of the line.
  out = ""
  n = length(line)
  i = 1
  q = ""
  qbuf = ""
  while (i <= n) {
    c = substr(line, i, 1)
    if (q == "") {
      if (c == "\\") { i += 2; continue }
      if (c == "\"" || c == "'") { q = c; qbuf = ""; i++; continue }
      if (c == "#") {
        p = (out == "") ? "" : substr(out, length(out), 1)
        if (p == "" || p ~ /[[:space:]]/) break
      }
      out = out c
      i++
    } else {
      if (q == "\"" && c == "\\") { qbuf = qbuf substr(line, i + 1, 1); i += 2; continue }
      if (c == q) {
        q = ""
        if (qbuf ~ /^\$[@*]$/) out = out "@FWD@"
        else if (qbuf ~ /^[A-Za-z0-9_][A-Za-z0-9_.:\/+-]*$/) out = out "@L@" qbuf
        else out = out "@Q@"
        i++
        continue
      }
      qbuf = qbuf c
      i++
    }
  }
  if (q != "") out = out "@Q@"

  # A definition (`emit() {`) is not a call. Separators become an explicit
  # @SEP@ so that two call sites on one line are two sites, not one, AND so
  # that command position is still readable after tokenizing.
  gsub(/[A-Za-z_][A-Za-z0-9_]*[[:space:]]*\(\)/, " @SEP@ ", out)
  gsub(/[;&|(){}`<>]/, " @SEP@ ", out)

  nt = split(out, tok, /[[:space:]]+/)
  for (k = 1; k <= nt; k++) {
    if (tok[k] !~ /^emit[A-Za-z0-9_]*$/) continue
    if (!cmd_position((k > 1) ? tok[k - 1] : "")) continue

    na = 0
    a1 = ""
    a2 = ""
    for (m = k + 1; m <= nt; m++) {
      if (tok[m] == "@SEP@") break
      if (tok[m] == "") continue
      na++
      if (na == 1) a1 = tok[m]
      else if (na == 2) a2 = tok[m]
    }

    # No arguments at all: a bare word, so there is no literal id to lose.
    if (na == 0) continue
    # A FORWARDER (`emit error "$@"`) passes its caller's arguments through. The
    # ids enter at the wrapper's own call sites, which are counted like any
    # other, so nothing is lost here.
    if (forwarded(a1) || forwarded(a2)) continue

    candidates++
    sev = unquoted_value(a1)
    id = unquoted_value(a2)
    if (sev ~ /^[A-Za-z][A-Za-z0-9_]*$/ && id ~ anchored) {
      print "ID " id
    } else {
      site = line
      sub(/^[[:space:]]*/, "", site)
      print "UNRESOLVED line " startfnr ": " site
    }
  }
  startfnr = 0
}
END { print "CANDIDATES " candidates }
AWK

# --- the coverage-bearing-string reader --------------------------------------
# Reads one JSON-encoded string per line and prints, per whole-token id
# occurrence, `NAMED <id>` always, then either `COVERING <id>` or -- when a
# negation cue sits in the id's own predicate -- `DISCLAIMED <id>`. DISCLAIMED
# is an advisory the caller reports and never fails on; see the header.
COVERAGE_AWK=""
read -r -d '' COVERAGE_AWK <<'AWK'
BEGIN {
  apos = sprintf("%c", 39)
  cue = "(^|[^a-z0-9])(not|never|without|excludes?|omits?|ignores?|neither|nor|no)([^a-z0-9]|$)"
  ncue = "[a-z]n" apos "t([^a-z0-9]|$)"
}
{
  rest = $0
  done = ""
  while (match(rest, idre)) {
    s = RSTART
    l = RLENGTH
    before = (s > 1) ? substr(rest, s - 1, 1) : substr(done, length(done), 1)
    after = substr(rest, s + l, 1)
    id = substr(rest, s, l)
    if ((before == "" || before !~ /[A-Za-z0-9_]/) && (after == "" || after !~ /[A-Za-z0-9_]/)) {
      print "NAMED " id
      clause = done substr(rest, 1, s - 1)
      # The id's OWN predicate: back to the previous clause break (`,` included,
      # which `must be flagged as P4` needs), then the two words immediately
      # before the id. A cue anywhere else in the sentence -- "A rule without a
      # scope suffix must be flagged as P4" -- disclaims nothing.
      if (match(clause, /^.*[.;:,]/)) clause = substr(clause, RSTART + RLENGTH)
      w = clause
      sub(/[[:space:]]+$/, "", w)
      win = ""
      cnt = 0
      while (cnt < 2 && match(w, /[^[:space:]]+$/)) {
        win = substr(w, RSTART) " " win
        w = substr(w, 1, RSTART - 1)
        sub(/[[:space:]]+$/, "", w)
        cnt++
      }
      win = tolower(win)
      if (win ~ cue || win ~ ncue) print "DISCLAIMED " id
      else print "COVERING " id
    }
    done = done substr(rest, 1, s + l - 1)
    rest = substr(rest, s + l)
  }
}
AWK

pairs=()
if [[ -n "${DETECTOR_EVAL_COVERAGE_PAIRS:-}" ]]; then
  while IFS= read -r line; do
    [[ -n "${line//[[:space:]]/}" ]] && pairs+=("$line")
  done <<<"$DETECTOR_EVAL_COVERAGE_PAIRS"
else
  pairs=("${PAIRS_DEFAULT[@]}")
fi

if [[ "${#pairs[@]}" -eq 0 ]]; then
  echo "check-detector-eval-coverage: no registered pairs; there is nothing this run could have inspected" >&2
  exit 2
fi

emitted_tmp="$(mktemp)" || exit 2
named_tmp="$(mktemp)" || exit 2
covering_tmp="$(mktemp)" || exit 2
disclaimed_tmp="$(mktemp)" || exit 2
scan_tmp="$(mktemp)" || exit 2
strings_tmp="$(mktemp)" || exit 2
# Discover-mode stdout is BUFFERED, not streamed: a per-row exit 2 used to leave
# a partial report on stdout with no denominator trailer under it, and the
# check-script contract says a run that inspected nothing says nothing there.
report_tmp="$(mktemp)" || exit 2
# Advisories are BUFFERED for the same reason the discover report is: a per-row
# exit 2 must leave nothing on stdout.
advisory_tmp="$(mktemp)" || exit 2
trap 'rm -f "$emitted_tmp" "$named_tmp" "$covering_tmp" "$disclaimed_tmp" "$scan_tmp" "$strings_tmp" "$report_tmp" "$advisory_tmp"' EXIT

errors=0
total_emitted=0
total_named=0
advisories=0

# qualifying_detectors -- every non-test skill script that carries a check-id
# vocabulary next to an eval suite. It runs THE SAME scanner the verdict path
# runs (EMIT_SCAN_AWK, under the wider QUALIFYING_ID_ERE rather than a row's
# own pattern), so a spelling one half of this gate can read is a spelling the
# other half can read.
#
# It did not always. An earlier revision kept a second extractor here, one
# greedy sed whose `.*` retained only the LAST call site on a line. A new
# detector spelling two emits as `emit warning Q1 ...; emit error Q2 ...`
# resolved to ONE id, fell short of the two-distinct-ids bar, and was never
# reported as unregistered -- the stopping rule that exists so the next
# detector cannot be silently unenforced, silently defeated by ordinary shell,
# while the verdict scanner beside it read that same line as two call sites
# correctly. Two extractors that must agree is how that happened; one
# extractor with one behavior is why it cannot happen again.
#
# Discovery reads the scanner's `ID` lines and NOTHING else. Its UNRESOLVED
# lines and its candidate count belong to the verdict path: an unreadable call
# site in a script nobody registered is not this run's environment answer, so
# discovery under-counts (see the stopping rule's residue in the header) rather
# than exiting 2 over a stranger's shell. An awk that cannot run at all is the
# same answer -- no ids, no candidate, no exit code of its own.
qualifying_detectors() {
  local evals_path skill script count
  for evals_path in plugins/*/skills/*/evals/evals.json; do
    [[ -f "$evals_path" ]] || continue
    skill="${evals_path%/evals/evals.json}"
    [[ -d "$skill/scripts" ]] || continue
    for script in "$skill"/scripts/*.sh; do
      [[ -f "$script" ]] || continue
      case "$script" in
      *.test.sh) continue ;;
      *) ;;
      esac
      count="$(awk -v idre="$QUALIFYING_ID_ERE" "$EMIT_SCAN_AWK" "$script" 2>/dev/null |
        sed -n 's/^ID //p' | sort -u | grep -c .)" || count=0
      [[ "$count" -ge 2 ]] && printf '%s\n' "$script"
    done
  done
}

for row in "${pairs[@]}"; do
  detector="${row%%|*}"
  rest="${row#*|}"
  evals="${rest%%|*}"
  id_re="${rest#*|}"

  if [[ -z "$detector" || -z "$evals" || -z "$id_re" || "$evals" == "$rest" ]]; then
    echo "check-detector-eval-coverage: malformed registry row: $row" >&2
    exit 2
  fi
  if [[ ! -r "$detector" ]]; then
    echo "check-detector-eval-coverage: detector not readable: $detector" >&2
    exit 2
  fi
  if [[ ! -r "$evals" ]]; then
    echo "check-detector-eval-coverage: eval suite not readable: $evals" >&2
    exit 2
  fi

  # A suite that covers no id is a real answer (every emitted id is then
  # uncovered, which is a finding). A suite that does not PARSE, or that is not
  # the SHAPE coverage can be read out of, is not an answer at all.
  if ! jq -e . "$evals" >/dev/null 2>&1; then
    echo "check-detector-eval-coverage: $evals is not valid JSON; the eval-named id set cannot be read" >&2
    exit 2
  fi
  if ! jq -e 'type == "object" and (.evals | type) == "array" and (.evals | length) > 0 and ([.evals[] | type] | all(. == "object"))' \
    "$evals" >/dev/null 2>&1; then
    echo "check-detector-eval-coverage: $evals is not a suite this gate can read coverage out of; it must be a JSON object whose 'evals' is a non-empty array of objects" >&2
    exit 2
  fi

  # Emitted ids, with every candidate call site accounted for.
  if ! awk -v idre="$id_re" "$EMIT_SCAN_AWK" "$detector" >"$scan_tmp" 2>/dev/null; then
    echo "check-detector-eval-coverage: the emit-call-site scan of $detector failed; the emitted id set cannot be read" >&2
    exit 2
  fi
  sed -n 's/^ID //p' "$scan_tmp" | sort -u >"$emitted_tmp"
  candidate_count="$(sed -n 's/^CANDIDATES //p' "$scan_tmp" | tail -n 1)"
  resolved_count="$(grep -c '^ID ' "$scan_tmp")"

  if [[ "$candidate_count" != "$resolved_count" ]]; then
    {
      echo "check-detector-eval-coverage: $detector has $candidate_count emit call site(s) but only $resolved_count resolved to a check id under /${id_re}/; the emitted id set is incomplete, so no verdict is available"
      sed -n 's/^UNRESOLVED /  unparsed: /p' "$scan_tmp"
    } >&2
    exit 2
  fi

  # Eval-named and eval-COVERING ids, read only out of entries of `evals` and
  # only out of the two fields the runner grades against.
  jq -r '.evals[] | (.expected_output, .expectations) | .. | strings | @json' "$evals" >"$strings_tmp"
  awk -v idre="$id_re" "$COVERAGE_AWK" "$strings_tmp" >"$scan_tmp"
  sed -n 's/^NAMED //p' "$scan_tmp" | sort -u >"$named_tmp"
  sed -n 's/^COVERING //p' "$scan_tmp" | sort -u >"$covering_tmp"
  sed -n 's/^DISCLAIMED //p' "$scan_tmp" | sort -u >"$disclaimed_tmp"

  emitted_count="$(grep -c . "$emitted_tmp")"
  named_count="$(grep -c . "$named_tmp")"

  # A detector that emits nothing under the row's pattern means the extraction
  # broke (an emitter renamed, an id shape changed), not that the suite is
  # complete. Passing here would be the false-green this gate exists to stop.
  if [[ "$emitted_count" -eq 0 ]]; then
    echo "check-detector-eval-coverage: no check ids extracted from $detector with /${id_re}/; the extraction, not the eval suite, is broken" >&2
    exit 2
  fi

  total_emitted=$((total_emitted + emitted_count))
  total_named=$((total_named + named_count))

  if [[ "$mode" == "discover" ]]; then
    {
      echo "$detector"
      echo "  evals:          $evals"
      echo "  id pattern:     $id_re"
      echo "  emitted ids:    $emitted_count"
      echo "  eval-named ids: $named_count"
      while IFS= read -r id; do
        if grep -Fxq -- "$id" "$covering_tmp"; then
          printf '    COVERED    %s\n' "$id"
        elif grep -Fxq -- "$id" "$disclaimed_tmp"; then
          advisories=$((advisories + 1))
          printf '    DISCLAIMED %s\n' "$id"
        else
          printf '    UNCOVERED  %s\n' "$id"
        fi
      done <"$emitted_tmp"
      while IFS= read -r id; do
        grep -Fxq -- "$id" "$emitted_tmp" || printf '    UNEMITTABLE %s\n' "$id"
      done <"$named_tmp"
    } >>"$report_tmp"
  else
    while IFS= read -r id; do
      if grep -Fxq -- "$id" "$covering_tmp"; then
        continue
      fi
      # An id named ONLY inside a negated clause is an advisory, never a
      # finding: see NEGATIVE ASSERTIONS in the header for why this direction
      # gave up failing, and what it costs.
      if grep -Fxq -- "$id" "$disclaimed_tmp"; then
        printf 'DISCLAIMED CHECK ID: %s is emitted by %s and named in %s only inside a negated clause, so nothing there exercises it (advisory, not a finding)\n' \
          "$id" "$detector" "$evals" >>"$advisory_tmp"
        advisories=$((advisories + 1))
        continue
      fi
      echo "UNCOVERED CHECK ID: $id is emitted by $detector and covered by no case in $evals" >&2
      errors=$((errors + 1))
    done <"$emitted_tmp"

    # The direction that catches a suite asserting a scope the detector outgrew.
    while IFS= read -r id; do
      if ! grep -Fxq -- "$id" "$emitted_tmp"; then
        echo "UNEMITTABLE CHECK ID: $id is named in $evals and $detector cannot emit it" >&2
        errors=$((errors + 1))
      fi
    done <"$named_tmp"
  fi
done

# The stopping rule. Runs after the rows so an unregistered pair is reported
# alongside them rather than instead of them.
registered_detectors=""
for row in "${pairs[@]}"; do
  registered_detectors+="${row%%|*}"$'\n'
done
while IFS= read -r candidate; do
  [[ -n "$candidate" ]] || continue
  if ! printf '%s' "$registered_detectors" | grep -Fxq -- "$candidate"; then
    if [[ "$mode" == "discover" ]]; then
      printf 'UNREGISTERED PAIR: %s emits check ids beside an eval suite and has no registry row\n' \
        "$candidate" >>"$report_tmp"
    else
      echo "UNREGISTERED PAIR: $candidate emits check ids beside an eval suite and has no registry row, so nothing compares them; add a row" >&2
      errors=$((errors + 1))
    fi
  fi
done < <(qualifying_detectors)

denominator="${#pairs[@]} pair(s), $total_emitted emitted id(s), $total_named eval-named id(s)"
if [[ "$advisories" -gt 0 ]]; then
  denominator+=", $advisories disclaimed-only id(s)"
fi

if [[ "$mode" == "discover" ]]; then
  cat "$report_tmp"
  echo "check-detector-eval-coverage: $denominator"
  exit 0
fi

cat "$advisory_tmp"

if [[ "$errors" -gt 0 ]]; then
  echo "check-detector-eval-coverage: FAILED — $errors gap(s) across $denominator" >&2
  exit 1
fi

if [[ "$advisories" -gt 0 ]]; then
  echo "check-detector-eval-coverage: passed with advisories — every emitted check id is named by an eval case ($advisories only inside a negated clause, which exercises nothing) and every eval-named id is emittable ($denominator)"
  exit 0
fi

echo "check-detector-eval-coverage: passed — every emitted check id is covered by an eval case and every eval-named id is emittable ($denominator)"
exit 0
