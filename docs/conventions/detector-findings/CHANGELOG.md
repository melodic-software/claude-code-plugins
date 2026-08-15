# Changelog — detector-findings convention

Notable changes to the detector-findings contract (SemVer). Changing a producer-owned field's rule,
the coexistence obligations, or an enforceability verdict is a major bump; additive guidance or a new
adopter row is a minor bump; docs-only clarification is a patch.

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
