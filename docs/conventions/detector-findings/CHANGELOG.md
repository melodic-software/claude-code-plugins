# Changelog — detector-findings convention

Notable changes to the detector-findings contract (SemVer). Changing a producer-owned field's rule,
the coexistence obligations, or an enforceability verdict is a major bump; additive guidance or a new
adopter row is a minor bump; docs-only clarification is a patch.

## 2.8.0 — 2026-08-28

**Minor under this contract's own rule.** A conforming producer gains its adopter row; no
producer-owned field's rule moves, no coexistence obligation changes, and no
enforceability verdict changes.

- **`docs-hygiene/audit-noise` gains its Adopters row.** The producer has carried crosswalk
  rows since 2.5.0 and conforms today, but the Adopters table never gained the row. A table
  whose own rule is that a row asserts present-tense conformance under-reported a conforming
  producer, which is the reverse of the failure the tabled-only-once-it-actually-does rule
  guards against: a reader consulting the table alone could not tell that a fifth producer
  reaches the relay. The row states what the producer does today, and adds no obligation.
- **The reachability paragraph stops saying "both".** "A habit both current adopters already
  have" and "both adopters that persist do exactly that" were written when there were two.
  There are five, and every one of them fetches this contract at run time and refuses to write
  when it is unreachable, so the claim now reads "every current adopter" and "every adopter
  that persists". The claim itself is unchanged and is still evidence about the producer's
  session rather than the consumer's.
- **The emitter section's heading stops carrying a count.** "Three emitters, one statement of
  each mechanic" was written at three and read as a standing claim; there are six counting
  `review:fanout`, and the section's own body had already been corrected away from "both" and
  "the third". A heading that names a number decays on every adopter, and this table's whole
  point is that adopters keep arriving, so the heading is now "Many emitters, one statement of
  each mechanic". The anchor moves with it; the only three references are inside this file and
  all three were updated. No obligation changes.
- **The `audit-noise` adopter row claimed a mechanical selection the producer does not have.** It
  said "selection is a mechanical per-sentence scan with no withholding verdict", which is true of
  the scanner and false of the skill: a model judgment lane sits between the scan and the writer and
  may dismiss a candidate on the grounds `SKILL.md` enumerates. Its sibling row for
  `claude-config:audit-instructions` states its model-lane carve-outs; this one did not. The row now
  scopes the mechanical claim to the scanner and names the lane, and its crosswalk row states the
  three decline classes — `frontmatter`, `quoted-trigger-phrase`, `judgment-lane-dismissal` — which
  this contract's "No evidence, no decline" rule requires a declining rule to state there. It also
  named three of the scanner's four withholding boundaries; the fourth, the clause naming an
  alternative, requires its evidence present like the other three, so the direction was right and
  the enumeration short. Found by an adversarial verifier reading the scripts, not the row.
- **`rule-negation-hard-guardrail`'s `Auto-applicable` cell led with `n/a`.** This contract states
  four permitted lead forms and `n/a` is not one; its three sibling non-emitting rows all use
  `Not applicable — no row`. Corrected, argument unchanged.
- **Two counts inside the new adopter row were wrong on the day it was written.** The row
  called `docs-hygiene/audit-noise` "the third producer to join the crosswalk" when the entry
  above it in this same file correctly says fifth, and said its detector "marks six shapes"
  with "the other five" declined. `lib/noise-shapes.sh` marks eight shapes and `detect.sh`
  classifies a ninth, `negation`, after paragraph accumulation, so eight are declined with
  `reason=no-severity-crosswalk-row`, not five. Both are corrected; the row's ordinal is
  dropped rather than renumbered, because an ordinal in a table that grows is the same decaying
  claim as the heading.

## 2.7.0 — 2026-08-27

**Minor under this contract's own rule** — one new row on an existing adopter; no
producer-owned field's rule moves, no coexistence obligation changes, and no
enforceability verdict changes.

- **`ai-slop/audit` gains `rule-model-era-phrases`**, the script rule for the
  catalog's new "Model-era additions (repo-owned)" section: distinctive
  2025-2026 model stock constructions, per occurrence, with the roster
  config-extended via `phrase_add`/`phrase_remove` (fragments validated at read
  time; invalid or empty fragments are skipped with a stderr note so the rule
  can neither flood nor silently zero out). Argued **SUGGESTION**: the same
  register-preference walk as `rule-filler-phrases` — unlike the chat-residue
  row, these constructions assert nothing false of the committed document.
  `Auto-applicable: No` (the deleted punchline sometimes carries the claim).

## 2.6.0 — 2026-08-23

**Minor under this contract's own rule** — two new rows on an existing adopter; no
producer-owned field's rule moves, no coexistence obligation changes, and no
enforceability verdict changes.

- **`claude-config/audit-instructions` gains I29 (#3186)**, the D4 restatement
  shape. Two rows, both **IMPORTANT**, argued from `severity.md`'s
  degradation-with-a-named-trigger limb (the next session that pays the listing
  `description` *and* the body copy for the same fact):
  - `rule-description-restatement` — an H2 section wholly recoverable from the
    file's own `description`.
  - `rule-sibling-restatement` — an H2 section wholly recoverable from a sibling
    H2 section. Footer headings are sources, never findings.
  Both are body-scoped: the remediation is a cut of the body restatement, never
  an edit to `description`, `when_to_use`, or a quoted trigger phrase.
  `Auto-applicable: No`.

## 2.5.1 — 2026-08-23

**Patch** — docs-only clarification of one adopter row's selection text. No producer-owned field's
rule moves, no coexistence obligation changes, and no enforceability verdict changes.

- **`rule-negation-without-positive` now describes paragraph-scoped accumulation (#3195).** The
  row had inherited 0.21.1's "the line must close its own sentence" gate, which withheld every
  hard-wrapped prohibition. The detector now accumulates a soft-wrapped sentence before classifying
  it; the crosswalk row states that, and that a finding is attributed to the first physical line of
  the triggering sentence. The other eight shapes stay line-scoped.

## 2.5.0 — 2026-08-23

**Minor under this contract's own rule** — a new adopter's rows are added; no producer-owned field's
rule moves, no coexistence obligation changes, and no enforceability verdict changes.

- **`docs-hygiene/audit-noise` joins the crosswalk (#3123)**, the third producer and the second to
  reach the relay from a read-only audit skill. Two rows:
  - `rule-negation-without-positive` — **IMPORTANT**, argued from `severity.md`'s **stated-rule**
    limb rather than the degradation limb both `audit-instructions` rows walk. The fleet's own
    `docs-hygiene:write-for-agents` "Prompt the positive" is the stated rule a bare prohibition
    violates, so the argument does not have to reach for a nameable degradation trigger.
    `Auto-applicable: No` — contained to `Location`, but recovering the positive target is a rewrite
    judgment.
  - `rule-negation-hard-guardrail` — **non-emitting**, and its row states which ground it uses, as
    the admission test requires: the **Boundary**'s "findings that never reach a relay", never a
    tier test. The claim is that the candidate is not a defect at all — the write-side rule itself
    preserves a negation "when the positive form genuinely loses the constraint" — and a tier test
    can only ever return a tier.
- **The adopter is a worked instance of admission test 2 checked on EVERY withholding boundary.**
  This producer has three (paired positive, hard guardrail, worked example) and each requires its
  evidence PRESENT on the sentence, so absence of that evidence selects the emitting rule. That is
  the failure 2.4.0's own pilot recorded — a criterion satisfied on the boundary easiest to argue
  while the second stayed open — met here by construction rather than by re-argument.
- **It is also the first adopter whose fall-through placement is forced by having two output
  surfaces.** The carve-out sits in the shared scanner, before either the human report or the
  findings file is composed, so one candidate carries one disposition on both. The contract binds
  the outcome and not a structure, and this is a second shape that satisfies it — the pilot placed
  its bar at classification for the same reason, from a different starting point.

## 2.4.1 — 2026-08-21

Two clarifications to prose this contract already had. **Patch under its own rule**: no
producer-owned field's rule moves, no coexistence obligation changes, no enforceability verdict
changes, no adopter row is added, and nothing a producer emits or a consumer parses is different.
Both passages are corrected to say what the consumer already does.

- **"Auto-applicability is settled per rule, at contract time" stated its criterion unqualified.**
  The opening sentence read as a fence over every finding — "a fix is auto-applied only when it is
  contained to its `Location`, high-confidence, and not a call for architectural judgment" — while
  the section directly above it, and the Declared-dispositions table, both turn on the fact that
  `fix-pass-mode.md` "Step 4" states that fence under its **correctness-class** heading and a
  cleanup-class row never passes through it. Read literally the sentence contradicted its own
  neighbours. It is now scoped to the correctness class, with the consequence this contract owns
  (settle it once per rule, in the crosswalk) marked as the class-independent half. **This wording
  predates the 2.4.0 release**: it entered with the crosswalk in #2737 on 2026-08-15, and 2.4.0 only
  put a second passage beside it that made the tension legible.
- **The `Auto-applicable: No` bullet described the cleanup route as `/simplify`-only.** It said the
  route "hands that class wholesale to `/simplify`". Step 4 has two branches — `/simplify` when it
  is available in the session, otherwise the cleanup findings applied directly, one file at a time —
  and the bullet named one. Its conclusion is unaffected and was never at risk: a `No` cell cannot
  restrain the route under *either* branch, which is why the bullet was written. The correction
  states both branches and why the cell reaches neither: on the first no consumer reads it, and on
  the second the reader is the cleanup route, whose fence is the file rather than auto-applicability.

The same `/simplify`-only description appears in 2.4.0's own entry below and in
`plugins/review/CHANGELOG.md`. Those are published entries recording what was written at the time
and are deliberately left as they stand; this note is the correction's home.

## 2.4.0 — 2026-08-21

A producer can now name the skill that owns its findings' remediation (#3033). New section, "When
the remediation is owned by the producer's own skill": a rule whose repair is contained to
`Location` but safe only under discipline the producer owns leads its crosswalk `Auto-applicable`
cell with ``No, remediated by `<invocation>` `` (a code span; a consumer strips the delimiters before matching). The consumer resolves that declaration through the
qualified rule id every conforming row already leads its `Finding` cell with, and routes those rows
to that surface instead of the cleanup route's `/simplify`.

Minor under this contract's own rule: the disposition is **opt-in and additive**. No existing
obligation changes, no producer-owned field's rule moves, nothing about what a producer emits
changes, and a row that declares nothing behaves exactly as it did.

**The declaration is per RULE and lives only in the crosswalk**, which is this contract's own
settle-once rule applied rather than restated — "Auto-applicability is settled per rule, at contract
time" already says a rule's remediation shape does not vary run to run, and who owns the repair is
exactly such a fact. Requiring every emitted row to carry a copy would be the per-finding
restatement that section forbids, and would make conformance a property of a producer's emitter
rather than of its rule set. A producer MAY additionally lead an `Action` cell with
``Remediate with `<invocation>` `` (same code-span convention), which **corroborates** the crosswalk
declaration and never substitutes for it: the crosswalk row is NECESSARY, and a rule with no
crosswalk declaration is not producer-owned however its `Action` reads. Where both are present and
name different invocations the crosswalk wins and the row is the defect.

**That asymmetry is a trust boundary rather than a preference**, and the section says so in terms a
later reader cannot relax by accident. The crosswalk lives in the consuming repo's own docs, outside
the artifact being consumed; the `Action` cell is inside it. Nothing authenticates the writer of a
findings file — this contract's own opening premise — and this is the disposition that hands rows to
a skill the consumer does not then re-fence, so an `Action`-alone route would let any component that
can write a conforming file name any already-installed skill and hand it arbitrary rows, bounded by
neither `Location` nor the consumer's own step. Availability is not authentication. An unreachable
crosswalk is therefore the no-declaration case, never a fallback to the `Action` cell.

The section opens by ruling out the two cheaper answers, because both were checked first and the
reasoning is what makes the third disposition defensible rather than accreted:

- **Off-site does not reach it.** Its producer obligation binds a remediation "outside `Location`'s
  file" and both of the consumer's limbs are site limbs, so a rule whose repair is *at* `Location`
  would have to assert something false to reach the disposition — and would then be routed to
  surface-only, which is the wrong destination when the producer ships a surface that can apply the
  fix.
- **`Auto-applicable: No` does not reach it either.** `fix-pass-mode.md` Step 4's
  surface-instead-of-applying fence sits under its correctness-class heading; a prose-style row
  classifies as cleanup by content and the cleanup route hands the class wholesale to `/simplify`,
  which reads no findings file. A cell no consumer reads on that path cannot restrain it.

**No column was added**, for the three reasons the off-site remediation-target column was rejected
plus one that is new: `scripts/check-detector-findings-crosswalk.sh` locates the crosswalk by its
exact five-column header and fails any row splitting into a different field count. The leading-token
device is this contract's own precedent — it is how the rule id rides in `Finding` without a column.

Also here: `Auto-applicable`'s cell grammar is stated (four leading forms, argument after);
producer-owned joins cross-file and architectural judgment as a third shape that is never
auto-applicable *by the consumer*; the fourteen non-`rule-utm-params` `ai-slop:audit` rows carry the
new lead; two Enforceability rows are added, one deterministic (the leading form is a literal-prefix
read of a cell the crosswalk gate already parses) and one reasoning-only (nothing outside the
session can see which skill the fixer invoked, so the declaration is checkable and the honoring is
not). All three adopter rows now state their disposition explicitly — `ai-slop:audit` declares an
owner, `mutation-testing:audit` is off-site and decided first, `testing:audit` declares none because
no skill owns choosing an oracle.

The consumer half lands in `review` 0.26.0.

## 2.3.0 — 2026-08-19

Three `ai-slop:audit` rows join the crosswalk (`rule-chatbot-artifacts`, `rule-filler-phrases`,
`rule-stacked-hedging`), from the plugin's integration of Cursor's `unslop` pattern set (ai-slop
0.2.0). Minor under this contract's own rule: additive crosswalk rows, no obligation changed.
`rule-chatbot-artifacts` argues IMPORTANT on the same degradation walk as the
knowledge-cutoff-disclaimer row (chat-turn residue asserts a conversational exchange false of the
committed document); the other two argue SUGGESTION. The adopter row's tier-spread counts update
to twelve SUGGESTION and three IMPORTANT.

## 2.2.0 — 2026-08-17

Third adopter tabled (`ai-slop:audit`), with its twelve rules admitted to the crosswalk. Minor
under this contract's own rule: a new adopter row and additive crosswalk rows, no obligation
changed. One additive clarification rides along: the flat-map paragraph now says explicitly that
a tier spread sourced from the RULES (each row arguing which claim its rule makes) is admitted —
what stays forbidden is a spread sourced from a finding's prose. `ai-slop:audit` is the first
producer to use it (ten SUGGESTION style rules, two IMPORTANT generation-residue rules) and the
first whose persist is default-on for repo-examining runs rather than opt-in.

## 2.1.0 — 2026-08-15

Second adopter tabled, with its rules admitted to the crosswalk (#2684). Minor under this
contract's own rule: a new adopter row and additive crosswalk rows, no obligation changed.

- **Three `testing:audit` rows join the severity crosswalk** — `rule-zero-assertion`,
  `rule-recomputed-expectation`, `rule-mock-only-oracle` — each arguing IMPORTANT through
  `severity.md`'s first-match walk (CRITICAL fails every limb because a can't-fail test is evidence
  about the suite's oracle, never a source defect; IMPORTANT's degradation-with-a-named-trigger limb
  matches, the trigger being a regression that ships under a green run). All three are contained to
  `Location` yet none is auto-applicable: the repair encodes the intended oracle, which is judgment
  Step 4 surfaces. The set is the crosswalk's first **fully mechanical** selection — no withholding
  verdict exists, so the fail-safe criterion is met by construction, and the one uncertainty
  (deliberate interaction-style tests) resolves toward emitting with `Confidence` omitted rather
  than toward silence. Its decline evidence is stated in the rows: an in-file
  `cant-fail-ok: <reason>` annotation, counted in `## Surfaces`.
- **`testing:audit` tabled as the second adopter**, added by the change that makes it true. The
  flat-map sentence under the crosswalk is rescoped from "the two emitting rules" to per-producer
  flatness, which its argument already meant.

## 2.0.2 — 2026-08-15

Docs-only: the self-ignore-guard bullet's consequence sentence was universally
true only where a checkout governs the destination. Where none is detected, the
[topic-docs convention](../topic-docs/README.md) "Runtime guards" now says the
guard does not run, and a producer bound to leave tracked content unmodified
withholds the findings file there too — that destination may be an index-tracked
deletion in the checkout the detection missed, where writing modifies tracked
content instead of creating an untracked path (measured). No producer-owned field
rule, coexistence obligation, or enforceability verdict changes, so this is a
patch. (#2680, #2756 follow-through on #2715)

## 2.0.1 — 2026-08-15

Patch: no rule changes, one statement corrected to match the rule it was already describing.

- **The producer-registry row stated the aridity bar without its node-kind half**, in the same file
  as the crosswalk row that states it fully — so one document described one bar two ways, with
  nothing to catch the divergence: `scripts/check-detector-findings-crosswalk.sh` validates the
  crosswalk table and does not read the Adopters table. The row now matches the rule.

## 2.0.0 — 2026-08-15

The crosswalk phase, written from what the pilot ran into. **Major** under this contract's own rule:
three producer-owned obligations are added, and an existing producer that ignores any of them stops
conforming — a row that does not name its rule id, an off-site rule that does not name its
remediation target, and a declined candidate reported as prose rather than a count are each
non-conforming under 2.0.0 and were each conforming under 1.1.0.

- **Rule-id-to-severity crosswalk, with the test each mapping is argued from.** `severity.md` decides
  a tier by test, so a threshold-to-tier table with no argument in it is nominal closure. The
  argument is now the row, and a rule whose tier cannot be argued from the test is **not admitted** —
  its detector reports to a human, outside this contract. Seeded with the four rules the first
  adopter evaluates.
- **Rule and threshold vocabulary.** Every emitted row leads its `Finding` cell with the rule that
  fired and the threshold it crossed in the run's own values. A rule id is
  `<plugin>/<skill>/rule-<slug>` — **one form, no short form**, because the crosswalk is a
  cross-producer registry and an emitted id is resolved against a row by exact match; an unqualified
  id would collide on the second detector, and the gate below would then resolve it to the wrong row.
  The id shares its shape with
  `finding-suppression`'s `check:` constituent but is **not** identical to it: a consumer may qualify
  checks more finely, and the first adopter keys a suppression `check:` to the mutation operator
  because a suppression retires per mutant while a rule classifies a disposition.
- **The determinism claim is corrected at its premise, and a new admission criterion replaces it.**
  The first draft's admission test opened "the rule is deterministic — the same tree fires it the
  same way", which is false for every rule in the seeded set: `mutation-testing:audit` classifies
  survivors through a fresh-context reviewer and its `SKILL.md` "Phase 4" calls that difference a
  judgment outright. What the crosswalk actually fixes is the **mapping** — given a rule id, the
  tier, disposition and auto-applicability are published and never re-derived per finding — not the
  **selection** of which rule a candidate fires. Rather than soften the criterion, the real bound is
  admitted in its place: **a rule set whose selection involves judgment must be fail-safe toward
  emitting.** Every non-emitting rule states the positive evidence its selection requires, and
  absence of that evidence selects an emitting rule, so a wavering judgment can add a row or make a
  run noisier but can never silently withhold a finding. The pilot already satisfies it — an
  equivalence verdict that cannot cite its demonstration is `rule-survivor-unclassified`, which
  emits at IMPORTANT — and a rule set whose unresolved judgments fall toward silence is not admitted.
- **The new criterion immediately caught a row in its own seeded set, and the row changed rather than
  the criterion.** The pilot has **two** withholding boundaries, and the bar was stated only on the
  first. `rule-survivor-equivalent` named positive evidence and a fall-through; `rule-survivor-arid`
  named only a definition of its class, with no fall-through anywhere — so a survivor misjudged as
  arid was silently withheld, which is the exact failure the criterion forbids, sitting next to the
  row it was demonstrated on. Aridity now requires a **complete** proposed suppression entry whose
  reason names the behavior the suite deliberately leaves unasserted, and an arid call that cannot
  show it falls through to `rule-survivor-unclassified` — symmetric with equivalence. That rule's own
  cell broadened accordingly: it is the fall-through for **any** unevidenced withholding verdict, not
  an equivalence-specific one. The criterion itself now says to check every withholding boundary
  rather than the one easiest to argue, because passing on a worked example while leaving the second
  boundary open is precisely how it would have shipped.
- **The bar's strength is named: instruction, not mechanism.** The fall-through is stated
  imperatively and nothing computes whether a cited demonstration is real. A criterion claiming more
  than the mechanism delivers would be the failure this contract is about.
- **The fall-through must take effect before a producer's FIRST output** — added to criterion 2 as an
  **outcome**, not a structure: one candidate gets one disposition on every surface the producer
  emits to. A single-surface producer satisfies it by construction and owes no classification step of
  any named shape; what fails it is a multi-surface producer applying the fall-through on the path to
  only some of them. The adopter surfaced it by first placing aridity's bar at persist time, which
  split one run's answer in two — its report is written before its findings file, so the same
  survivor read "arid" in one and "unclassified" in the other. Its bar now sits at classification,
  but **that placement is the adopter's answer, not the rule** — stating it as the rule would make a
  mechanism binding on producers whose shape makes it meaningless.
- **A non-emitting rule argues from the Boundary, never from a tier test.** The two grounds are not
  interchangeable and a row must say which it uses — a tier test can only return a tier, so reaching
  for one to justify a non-emission makes a row look argued while arguing nothing. Both non-emitting
  rows now say plainly that a tier test would match and is not what decides them.
- **The crosswalk bar is enforced, not asserted.**
  `scripts/check-detector-findings-crosswalk.sh --check` runs in CI behind its own discriminating
  self-test, failing an empty or prose-free test cell, an unqualified or duplicated rule id, a row an
  unescaped pipe has shifted, and a restatement of the findings-file table. It locates the table by
  its exact header, so a neighbouring table can neither satisfy it nor be dragged into it, and it
  accepts a **correctly escaped** `\|` inside a cell — this table is prose about rules, which is
  exactly the content that carries pipes, so a gate that rejected the escape the shape requires
  would dead-end an author who did the right thing. Each self-test asserts the failure MESSAGE as
  well as the exit status, so a case cannot start passing for a different reason than it was written
  for.
- **A disposition for a finding whose remediation is not at its `Location`.** `Location` still names
  the detection site and is never retargeted. The producer names the remediation target in `Action`
  and declares the rule off-site in its crosswalk row; the consumer surfaces such a row rather than
  auto-applying it, via a new named trigger in `fix-pass-mode.md` "Step 4" (`review` 0.21.0). A
  remediation-target column is recorded as considered and rejected: what it would enable is an
  unattended two-file apply, which is what the fence exists to forbid.
- **A home for the examined-but-not-reportable candidate.** Three outcomes, three homes: a declined
  candidate is coverage and is reported as a count per rule id in `## Surfaces`; a real finding an
  operator accepted is `finding-suppression`'s, proposed by the producer and never written by it; a
  not-a-defect claim without the rule's stated evidence emits a row. The disposition belongs to the
  **rule** and is declared once in the crosswalk, so no field is added to the findings shape.
- **Auto-applicability is settled per rule at contract time**, not per finding at apply time.
  Cross-file and architectural-judgment rules are never auto-applicable — layering, abstraction, and
  coupling detectors are designed to inform a human, which is the intent of the route rather than a
  limitation in it. Shaping a rule to look auto-applicable, by narrowing `Location` or lowering
  `Confidence`, is named as the failure it is.
- **The shared-emitter question is decided: three implementations are accepted, and no shared-source
  cluster is declared.** The registry cannot hold it mechanically — `check-cross-plugin-source-drift.sh`
  clusters files by path-within-plugin under `plugins/*/`, so a `docs/` convention can never be a
  cluster, and registering a path that is not a live byte-identical cluster fails as `REGISTRY STALE`
  (verified). There is also no emitter code to share: both emitters are prose a model executes. What
  prevents drift is that each mechanic has exactly one owner reached by pointer. The revisit trigger
  fires itself — the first emitter code copied across two plugins is reported `UNREGISTERED` by that
  same script.
- **`REVIEW.md` cited as the consumer-precedence override**, with the reason it is not decorative:
  this repository's own vocabulary folds Critical and Important onto one marker, so the tier name
  does not survive the fold and the row's argued test is what lets a reader re-derive which side of
  it a finding sat on.
- **Enforceability re-rated.** `Tier` is machine-computed moves from reasoning-only to
  detect-then-judge, because a rule id in every row gives a gate something to check. Three rows are
  added — one of them **built rather than deferred** (the crosswalk gate above), and one recording
  honestly that a declined-candidate count is greppable but that no gate can know what a run
  examined.
- **The shared-emitter revisit trigger's limit is stated.** It fires on a **byte-identical** second
  copy; a copy edited before it ever landed clusters as `DIFFERS` and never trips it. Duplication
  born already-drifted is outside what any part of that decision detects, and the answer is review
  rather than a script.
- **The depth recheck trigger is recorded as MET** and the doc no longer describes itself as a stub.

## 1.1.0 — 2026-08-15

First adopter tabled. The row is added by the commit that makes it true, per the Adopters rule
("tabled only once it actually does" conform) — tabling it in the stub itself would have asserted
what a reader could not yet rely on.

- **`mutation-testing:audit` tabled as the first adopter**, with what it computes, what it omits and
  why, and the one gap the pilot surfaced.
- **Conformance-gate recheck trigger recorded as FIRED.** The two enforceability rows that read
  "**Not built**: no producer exists yet" now read as buildable: a real emitter exists to check. No
  gate is written here; naming the trigger as fired is what stops the deferral from reading as
  permanent.
- **Depth trigger recorded as partially met** — the pilot's first evidence includes a case the
  contract does not address: a producer whose remediation site is not its `Location`
  ([#2681](https://github.com/melodic-software/claude-code-plugins/issues/2681)).

## 1.0.0 — 2026-08-15

Initial published contract — a deliberate stub, per
[#2679](https://github.com/melodic-software/claude-code-plugins/issues/2679). It lands before the
first detector pilot because `PLUGIN-PHILOSOPHY.md`'s registry rule sets a deadline ("before a second
plugin adopts it"), and the pilot is that second adopter. Depth trails the pilot, which is what
produces the evidence to harden against.

- Contract stated as **format-only**: a producer reaches the apply relay by writing a conforming
  file into the current branch's findings directory, with no fanout edit, registration, or dispatch
  wiring. Nothing authenticates the writer.
- Every rule another doc owns is **cited, never copied** — the findings-file schema and the
  cell-escaping and path-relativization rules to
  `plugins/review/skills/fanout/context/default-mode.md`; the severity-tier and confidence
  vocabularies (and the consumer-precedence rule that overrides the baseline) to
  `plugins/review/context/severity.md`; the merge-set, admission-test, and consumption-ledger
  mechanics to `context/fix-pass-mode.md`.
- **Destination bound to the consumer's own binding**: a producer resolves through
  `plugins/review/reference/topic-docs.md` "Resolution" — what `SKILL.md` "Shared inputs" names as
  what `review:fanout` resolves through — named by its repo path because that plugin reaches it
  through a `${CLAUDE_PLUGIN_ROOT}`-relative pointer no other plugin can expand. The binding's rules
  are cited rather than restated; what the doc states is only what the binding leaves to a producer —
  run the whole rung order rather than its default, take the contract's "Non-interactive / forked
  mode" rule rather than inventing an answer to a rung that asks, match on `branch:` frontmatter
  rather than the directory, and owe the self-ignore guard.
- Four producer-owned fields fixed: machine-computed `Tier` in the owner's vocabulary; `Confidence`
  `high`-or-omitted and **never `low`**, which ranks below absent; repo-relative `file:line`
  `Location`; producer-side cell escaping. `Confidence` is confidence-of-realness, never confidence
  in the fix.
- Coexistence obligations stated: write your own file rather than appending into another producer's,
  name yourself in `Surface(s)`, and do not pre-deduplicate against another producer's output.
- Re-emission rule stated: a detector re-runs and writes what it currently finds; it never replays.
- Minimal conformance defined by pointer to the admission test; omit an absent coverage field rather
  than fabricating it, and always emit `date:`.
- Liveness relationship recorded: persisting a conforming file satisfies the
  `liveness-assertion` agent-readable-channel limb.
- Enforceability classified; all mechanical enforcement deferred with event triggers (first detector
  on `main`; pilot completion or a second adopter). Adopters table ships **empty** — `review:fanout`
  is the reference writer, not an adopter, and sits on the other side of this doc's boundary.
- Convention registry row added in `PLUGIN-PHILOSOPHY.md`; `review:fanout`'s writer contract gains a
  pointer to this doc.
