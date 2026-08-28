# Design threads — copied-external-content plugin

Cross-cutting decisions for the /planning:design stage, written 2026-08-27. Statuses:
resolved (decision made, rationale recorded), directional (direction agreed, detail deferred
with a named arbiter), deferred (needs input the design stage cannot supply). The Brief's
constraints and the interview ledger's 19 settled decisions are upstream of every thread here
and are not relitigated.

## T1 — Plugin and skill naming (Q19) — RESOLVED

User picked `provenance` from the shortlist below (2026-08-27, design acceptance gate), ahead
of the plan-gate schedule the Brief allowed. Q19 is closed; `<name>` substitution points in
the design artifacts read as `provenance`. Original pass record follows.

Ran /naming:name-it-better (default pass, three blind lenses, collision check against the
71-plugin roster). Filters removed `transclusion`, `citation`, `attribution` (they name the
remedy or the credit act, not the audited concern) and `provenance-audit` (stutters at the
call site). Ranked shortlist:

1. **`provenance` — RECOMMENDED.** The term of art for the documented origin of an artifact;
   accurately covers all three shipped surfaces (copy detection, source confirmation, stamp
   hygiene), where defect-named candidates misdescribe the stamp-expiry check.
   `/provenance:audit` reads as the question the user is asking. Known cost: a supply-chain
   (SLSA) reading is possible; the skill description, which owns model-side discovery, scopes
   it to prose.
2. `copied-content` — defect-named like ai-slop, matches the user's own phrasing and the topic
   slug; under-covers the stamp-hygiene surface.
3. `borrowed-prose` — neutral, carries the maintenance-burden frame; less established as a
   term.
4. `prose-provenance` — disambiguates SLSA at the cost of length in rule ids and config keys.

Arbiter was the user (the naming skill's rule is the human always picks); the pick landed at
the design acceptance gate, recorded above.

## T2 — Skill surface — RESOLVED

Two skills: `audit` (actions `audit` default read-only, `fix` explicit, `sweep` explicit) and
`setup` (config management). Precedent: ai-slop's audit+setup split, named in the Brief as the
structural model. `sweep` is an action of `audit`, not a third skill, because it is the same
pipeline under the execution contract's closure discipline; a separate skill would duplicate
the flow's whole surface. Mutation rides only explicit arguments (`fix`, `sweep`), per the
marketplace's read-only-audit rule.

## T3 — Script inventory and language — RESOLVED

Six scripts, each reasoning-free (C1): `list-corpus.sh`, `extract-breadcrumbs.sh`,
`check-stamps.sh`, `emit-findings.sh`, `score-golden.sh` in bash with paired `.test.sh`
(263-test fleet precedent), and `fingerprint.mjs` in Node with `fingerprint.test.mjs`
(autonomy-plugin precedent for `.mjs` plus paired test). The fingerprint module is a text
algorithm with real data structures; bash would be the wrong tool and the spike module already
proved the shape. It is rewritten, not lifted verbatim, per prototype discipline.

## T4 — Pipeline shape and span localization — RESOLVED

nominate (LLM, fresh context, recall-biased) -> resolve source (breadcrumb-first, siblings
included, budgeted search last) -> fetch (rung ladder, identity checks, cache) -> fingerprint
verify (script) -> rubric judge (3 blind samples) -> tier map -> report + relay. The handoff's
exact-offset open question is resolved structurally: nomination supplies file plus approximate
line range only; exact spans exist exactly where fix needs them, computed deterministically by
the fingerprint module's matched-span output. No LLM offset arithmetic anywhere.

## T5 — The two S2 amendments — RESOLVED (binding)

Quotation and fence stripping, including inline quotation marks, is preprocessing INSIDE the
fingerprint module; a rubric-layer carve-out would false-positive on properly quoted excerpts.
Verdicts are matched-span reports, never whole-file containment; whole-file scores dilute real
matches to noise on real-sized files. Both are stated in the module's contract
(type-inventory.md) and its paired tests must cover both (inline-quote fixture,
real-sized-file dilution fixture).

## T6 — Relay boundary and crosswalk rows — RESOLVED

Three emitting rules (`rule-verbatim-copy`, `rule-stamp-expired`, `rule-trigger-less-stamp`),
tiers argued in type-inventory.md from the severity tests; judgment verdicts never reach the
findings file (ai-slop V1 boundary, Brief constraint). `rule-verbatim-copy` declares
producer-owned remediation (`No, remediated by /<name>:audit fix`); the stamp rules surface.
Fail-safe direction: no withholding verdicts exist; LLM uncertainty falls to report-only
tiers, visible on every emitted surface.

## T7 — Rubric catalog artifact — RESOLVED

`reference/rubric.md`, the ai-slop catalog model: versioned with the plugin (changes land in
CHANGELOG.md), carve-outs first, four binary criteria with quoted-evidence requirements and
worked pass/fail examples, the tier table, and one upstream-drift four-part record per entry
that restates an externally-owned rule (source-pinned). Carve-out definitions are carried
inline for portability, citing the owning conventions for provenance.

## T8 — Fetch discipline and untrusted framing — RESOLVED

`reference/source-fetch.md` carries the operational fetch route (raw-md channel first,
wholeness, page identity before trusting a body, no absence from truncation, mirror rung
disclosure) as a four-part record citing the upstream-drift convention; a bare pointer cannot
serve consumers who lack this repository. The untrusted-content spine is carried inline,
byte-identical, at every ingest surface: the fetch step in SKILL.md, the nomination and judge
prompt templates, and the fix flow's liveness check. Fetched-page imperatives are findings.
The one fabrication incident from research (a summarizer paraphrase recorded as page text) is
codified: no verbatim quote, no claim.

## T9 — Budgets — DIRECTIONAL

Schema resolved (per-candidate search and fetch caps, corpus fetch ceiling, convergence
early-stop, cache); numeric constants are named placeholders. Arbiter: /planning:plan with
S5-style telemetry (Q10); S5 already establishes the shape (fetches cheap, judge sampling is
the cost center, so fetch budgets start generous and `judge_samples` stays at its floor of 3).

## T10 — Evals and golden set — RESOLVED

Single-track evals.json now (runner early-access gate probed twice, trigger NOT declared
fired), golden set runner-agnostic per the case shape in type-inventory.md, synthetic-only
fixtures with the fixture tree categorically excluded from scans, hand-scored case-level P/R
with `score-golden.sh` doing the mechanical tally. Growth path 5-10 -> 20-50; the fix-mode
precision gate binds only at the stated minimum n (numbers user-reserved, Q16).

## T11 — Test-seam posture — RESOLVED

Three seams, fewest that cover the surface: (1) paired script tests, fixture-driven, one per
deterministic script; (2) `evals/evals.json` per judgment-bearing skill (house CI warrant);
(3) the golden-set harness for end-to-end judgment quality. No seam inside SKILL.md prose; the
subagent prompts are exercised through seam 3, not unit-tested. New seams were not invented
where these three suffice.

## T12 — Configurability and design defaults — RESOLVED

Config-cascade file `.claude/<name>.json` (schema in type-inventory.md), `--show-config` on
detector scripts naming the supplying layer, categorical-only exclusions (per-instance
suppression routes to the finding-suppression convention, operator-owned). Observability: the
budget log and fetch telemetry are first-class report fields, because they feed the
hash-store designed-issue trigger and the Q10 tuning. Extension axis: rubric entries and
carve-outs are catalog rows, versioned, never inline SKILL.md prose.

## T13 — Dead-pointer round-trip — RESOLVED

Edit-time liveness is the fix flow's guard; later-dead pointers demote (stamped record or
archived-snapshot citation) via `reference/dispositions.md`; the weekly link-check lane wiring
is consuming-repo integration recorded in the convention engagement, not plugin machinery.

## T14 — Convention engagement — RESOLVED

Drafted in full in `convention-engagement.md`: fires at sweep completion only, one changelog
entry, re-derivation with an honest expected outcome (at most reasoning-only ->
detect-then-judge; deterministic CI gate stays unavailable), major bump conditional on an
enforceability verdict change, trigger-less-stamp check lands built-but-off-default, plus the
hash-store trigger evaluation and #2297 closure evidence.

## T15 — Open probes carried to plan/build — DEFERRED (research-tagged)

- Adversarial fixtures (systematic synonym rotation) against the separation rule: author 2-3
  such cases in the golden set's first growth round; the module's constants may need the
  Jaccard axis if containment alone is evadable. Tag: golden-set growth, action 5 of the
  handoff.
- The neutral not-found disposition has never been exercised live (all spike sources were
  supplied); the built plugin's first no-breadcrumb case validates the searched-surfaces
  listing. Tag: build-time harness.
- Judge prompt diversity: S3 measured self-consistency (three identical prompts), not
  perspective diversity; whether distinct judge lenses change split rates is a
  golden-set-growth question, not a v1 blocker.
