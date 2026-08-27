# Capability matrix — copied-external-content plugin

Design-stage decomposition per /planning:design, written 2026-08-27 against the Brief in
`../PLAN.md`. Working plugin name: `provenance` (recommended by the naming pass; final pick is
the user's at the plan approval gate, thread T1). `<name>` below reads as that working name.

Every capability row states what it does, whether it is deterministic-script or LLM work (the
Brief's C1 split: scripts do only reasoning-free operations), and where it lives in the plugin.

| # | Capability | Kind | Home |
|---|---|---|---|
| 1 | Corpus enumeration and exclusion filtering | Script | `skills/audit/scripts/list-corpus.sh` |
| 2 | Breadcrumb inventory (links, fences, stamps) | Script | `skills/audit/scripts/extract-breadcrumbs.sh` |
| 3 | Stamp expiry check (portable baseline) | Script | `skills/audit/scripts/check-stamps.sh` |
| 4 | Trigger-less-stamp check (repo override only) | Script | same script, off-by-default flag |
| 5 | Nomination of suspect passages | LLM (fresh context) | audit flow + `reference/nomination.md` |
| 6 | Source resolution (breadcrumb-first, budgeted search) | LLM + budgets | audit flow |
| 7 | Source fetch (rung ladder, identity checks, cache) | Mechanical fetch, LLM-orchestrated | audit flow + `reference/source-fetch.md` |
| 8 | Fingerprint verify (quote-strip, shingle, matched spans) | Script | `skills/audit/scripts/fingerprint.mjs` |
| 9 | Rubric judgment (4 binary criteria, 3 blind judges) | LLM (fresh contexts) | `reference/rubric.md` + audit flow |
| 10 | Tier mapping and dispositions | Fixed mapping, applied by the flow | `reference/rubric.md` tier table |
| 11 | Human report | LLM | audit flow |
| 12 | Relay persistence (findings file) | Script | `skills/audit/scripts/emit-findings.sh` + `context/persist-findings.md` |
| 13 | Fix (three dispositions, guarded) | LLM behind explicit `fix` | audit skill `fix` action + `reference/dispositions.md` |
| 14 | Sweep (execution-contract mode) | LLM behind explicit `sweep` | audit skill `sweep` action |
| 15 | Configuration and carve-out management | LLM + config-cascade | `setup` skill, `.claude/<name>.json` |
| 16 | Evals and golden set | Fixtures + scorer script | `skills/audit/evals/` |
| 17 | Convention engagement at sweep completion | One-time repo work, not plugin machinery | `design/convention-engagement.md` |

## 1. Corpus enumeration and exclusion filtering

Enumerates tracked markdown for a target (file, directory, or repo-wide) and removes the
categorical carve-outs before anything reads a byte. Reasoning-free: path matching only.

- Built-in categorical exclusions (the Brief's carve-out constraint): vendored trees
  (`**/vendor/**` and linguist-vendored path attributes), the plugin's own eval-fixture tree,
  and consumer `excluded_paths` from config.
- Carve-outs that need reading (conforming stamped records, quotation contexts, owned content,
  distilled-product genre) are NOT path-expressible; they are evaluated by capability 9 before
  criteria, and by capability 8's preprocessing for quotations. The script never guesses at
  them.
- Declined paths are counted and reported per the detector-findings declined-candidate rule,
  never silently dropped.
- Invariant: the fixture tree is always excluded, even when a target argument points inside it;
  the script says so rather than scanning.

Cross-app reuse: none. This is plugin-specific plumbing.

## 2. Breadcrumb inventory

Extracts, per corpus file, the provenance signals already present: URLs with line numbers,
HTML-comment fence pairs (source URL + date), stamp lines, and blockquote/citation markers.
Reasoning-free extraction; no judgment about which breadcrumb explains which passage.

- Scope includes SIBLING files: S1 resolved a cross-file breadcrumb (a neighbor's citation
  identified an unfenced copy's source), so the inventory is emitted per directory, and the
  audit flow hands the nominating and resolving steps the whole directory's inventory, not just
  the flagged file's.
- Output is JSON to stdout so the LLM layers consume it without re-reading files.

## 3. Stamp expiry check (portable baseline)

The one deterministic stamp check the portable baseline ships (Brief constraint, Q13): a
four-part record whose as-of date is older than the configured expiry window is flagged with
the run's own values (stamp date, window, days over). Parsing tolerates the fleet's known
stamp forms but claims only what it parses; unparsed candidate stamps are counted as declined
with the reason, because the live corpus carries stamp dates in at least four prose forms and a
guessing parser would manufacture findings.

## 4. Trigger-less-stamp check (repo override only)

The upstream-drift convention's named-not-built check (flag a dated stamp whose surface states
no recheck trigger). Ships built but OFF by default; a consuming repo that standardizes
greppable stamp forms enables it via config. It lands through the convention engagement
(capability 17), which is where its build trigger is formally answered.

## 5. Nomination

A fresh-context subagent reads a chunk of corpus files plus their breadcrumb inventories and
nominates suspect passages: file, approximate line range, suspected class (verbatim,
near-verbatim, paraphrase, summary), candidate source URLs (breadcrumbs first, sibling
breadcrumbs included), and the provenance signals that raised suspicion. Nomination is
recall-biased; precision comes from verification and judgment downstream.

- Nomination needs only file plus approximate line range. Exact spans for fix-eligible findings
  come deterministically from capability 8's matched-span output, which resolves the handoff's
  exact-offset open question without asking the nomination prompt to do offset arithmetic.
- The nomination prompt carries the untrusted-content spine for the file contents it reads
  (repository files under exploration are an ingest surface).

## 6. Source resolution

Per nomination, in order: (a) breadcrumbs in or near the passage, (b) sibling-file breadcrumbs,
(c) budgeted WebSearch enrichment, only when no breadcrumb exists and only inside the Q10
budgets (per-candidate caps, convergence early-stop: same top source twice with no new
evidence, corpus-level fetch ceiling). Exhaustion produces the neutral disposition "source not
identified (budget exhausted; searched: ...)" naming every surface checked.

## 7. Source fetch

Fetches candidate sources for verification, under the upstream-drift fetch discipline carried
operationally in `reference/source-fetch.md` (raw-markdown channel first where one exists,
wholeness check, page-identity check before trusting a body, no absence claim from a truncated
read). Responses are cached for the run (lychee `--cache` is the in-repo model) and fetch
counts land in the budget log. Every fetch surface carries the untrusted-content framing spine
inline, byte-identical, per that convention's inline form.

## 8. Fingerprint verify

The liftable pure module from S2, rewritten for the plugin per prototype discipline: word
5-shingles, Jaccard plus containment plus longest matched span, comparing a local passage
against a fetched source text. Two spike-earned amendments are part of the module's contract,
not the rubric's:

- Quotation and fence stripping, including INLINE quotation marks and not only blockquotes, is
  a PREPROCESSING step inside the module. A properly quoted excerpt never reaches shingling.
- Verdicts are reported per matched SPAN, never as whole-file containment: on real-sized files
  whole-file scores dilute genuine matches to noise (a 27-word match scored 0.019 whole-file in
  S2).

Output: matched spans with local line offsets, per-span word counts, and the separation-rule
inputs (containment, longest span). The working separation rule, containment >= 0.3 OR span >=
15 words after quote-stripping, ships as a named placeholder constant pair tuned at plan time
from golden-set telemetry (Q10/Q16 arbiters).

## 9. Rubric judgment

The versioned rubric catalog (`reference/rubric.md`) applied by three blind fresh-context
judges per candidate. Carve-outs are evaluated BEFORE criteria; then four binary criteria (span
correspondence to a named source, beyond common idiom, attribution adequacy, transformative
use), each graded with quoted evidence. Unanimity renders the verdict; any split routes to the
human. Judge sampling is the cost center (S5), so `judge_samples` is config with default 3 and
a floor of 3 for fix-eligible findings.

## 10. Tier mapping and dispositions

Evidence-gated tiers, fixed mapping (S4-adopted):

- fingerprint-confirmed: a matched span above the separation rule against an identity-checked
  fetched source. Fix-eligible; the only tier that reaches the relay for copy findings.
- source-fetched-similar: source fetched, similarity below the deterministic rule, judges say
  copy. Human flag, report-only.
- llm-suspected: no lexical evidence possible (paraphrase, summary). Report-only, permanently.
- Neutral: "source not identified (budget exhausted; searched: ...)". First-class outcome, not
  a failure.

Dispositions (applied only by `fix`): convert-to-pointer, trim-to-citation,
condense-to-stamped-record. Offline-load-bearing surfaces are never bare-removed; they condense
to conforming stamped records. Read-frequency and fetch cost weigh on the disposition choice,
never as an allowance category.

## 11. Human report

All tiers, rubric grades with quoted evidence, carve-out declines with counts, budget
telemetry, and what the rubric pass did not cover. Also emitted as a machine-parseable JSON
sidecar in the memory tier (S2's design nudge), so golden-set scoring never parses prose.

## 12. Relay persistence

Script findings only, per the detector-findings convention: fingerprint-confirmed copy findings
and the deterministic stamp findings, with argued crosswalk rows, Confidence high or omitted,
rule ids leading every Finding cell. Judgment verdicts never enter the findings file (ai-slop's
V1 relay boundary, kept deliberately). The emitter fetches the producer contract at run time
and refuses to write when it is unreachable, reporting report-only as the outcome.

## 13. Fix

Explicit argument only. Applies the three dispositions to fix-eligible findings, then per file:
verify every pointer target live at edit time (fetch with identity check), run a fresh-context
semantic-diff verifier blind to the rewrite rationale (flags semantic loss, ambiguity, quote
corruption), revert flagged hunks, and close with fixed / suppressed-with-reason /
reverted-with-reason accounting. A later-dead pointer demotes back to a stamped record or an
archived-snapshot citation; the wiring to the weekly link-check lane is repo-side integration
recorded in the convention engagement, not plugin machinery.

## 14. Sweep

The Brief's execution contract as an explicit action: one tracked file at a time, apply the
verdict, verify (semantic diff plus pointer liveness), close. A file is closed when every
finding in it carries a disposition or an explicit neutral outcome. Sweep state (per-file
closure ledger) lives in the memory tier so an interrupted sweep resumes instead of
restarting. Sweep completion, never spike results, fires the convention engagement.

## 15. Configuration

`.claude/<name>.json` per the config-cascade convention, managed by the `setup` skill:
`excluded_paths`, budget constants, `stamp_expiry_days`, `trigger_less_stamp_check` (default
false), `judge_samples`, fetch-cache location. The detector scripts expose `--show-config`
naming the layer supplying each effective value (ai-slop model).

## 16. Evals and golden set

Per-skill `evals/evals.json` (house CI warrant) plus the golden set: synthetic fixtures
(shape-preserving rewrites of history cases; hard negatives including
paraphrase-styled-never-copied distractors), authored runner-agnostic so cases wrap as
case.yaml when `claude plugin eval` leaves early access. Case-level precision/recall is
hand-scored; a scorer script does the mechanical tally once verdicts exist. The fixture tree
carries the named categorical exclusion from every scan corpus.

## 17. Convention engagement

One combined engagement at sweep completion, drafted in `convention-engagement.md` beside this
file: reopen the upstream-drift recorded decision, conditional major bump, land the
trigger-less-stamp check behind the repo override, one changelog entry.
