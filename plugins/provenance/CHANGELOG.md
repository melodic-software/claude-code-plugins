# Changelog

## [0.1.0]

### Added

- **Rubric version 2: an inverted polarity in C3 and C4, caught by blind adjudication.** The
  verdict rule says a finding STANDS only if all four criteria PASS, and it says so three times.
  But C3 and C4 were phrased as questions whose intuitive "yes" is exculpatory — is the
  attribution adequate, does the text transform — and their worked examples labelled that
  exculpatory answer PASS. Read literally, the two halves of the file contradicted each other and
  **no finding could ever stand**.

  Nothing measured was wrong: the version-1 run and the independent blind pass both graded on the
  operative verdict rule rather than the labels, and both returned the same eight positives. The
  defect was in what the file told the next judge to do. Both criteria are now phrased in the
  negative so all four point the same way, the four worked-example labels are corrected, and the
  polarity is stated once, explicitly, at the head of the criteria section. Version 2 carries the
  version-1 measurement forward and says why, which is the single exception to this catalog's own
  invalidation rule.

  Worth recording how it was found: three review passes and a self-check had read this file
  without noticing. What surfaced it was asking an agent to actually apply the rubric with the
  expectations withheld — the first reader with no way to infer the intended answer.

- **A contested class the golden set records rather than settles.** Case `c10` is a copy rotated
  until no five-word window survives. The pipeline classed it `near-verbatim` at tier
  `source-fetched-similar`, on the grounds that a source was fetched and compared; the blind
  adjudicator classed it `paraphrase` at `llm-suspected`, on the grounds that zero lexical
  evidence is available to a reader who does not already know it was rotated. Both readings are
  defensible under the current tier table, which is the finding: a rotated copy with a fetched
  source fits neither tier cleanly. The practical stakes are nil today — both tiers are
  report-only and neither is fix-eligible — so the disagreement is recorded here and carried to
  the growth round rather than resolved by picking the answer that flatters the score.

- **The golden set, the first measurement, and the loop that grows it.** Ten synthetic cases under
  `skills/audit/evals/fixtures/golden/`, one directory each carrying `case.md`, `expected.json`,
  and the `source.md` the case is judged against, so every case runs offline: the source is served
  to the fingerprint module directly and the fetch stage is short-circuited rather than mocked.
  Coverage is two verbatim positives, five near-verbatim, one paraphrase, and two hard negatives —
  a quoted-and-cited excerpt, and the paraphrase-styled-never-copied distractor, which is the false
  positive this detector is most likely to produce. Every fixture describes the same fictional
  build tool the earlier fixtures use. A golden set holding real copied prose would make this
  repository carry the defect the plugin exists to find, in the one tree its own scan is
  categorically forbidden to read.

  **The gate decision table**, from `score-golden.sh` over the run recorded at the same date.
  Classes are the scorer's own grouping: a case's class is its first expected finding's class, and
  a hard negative groups as `negative`.

  | Class | n | Precision | Recall | Gate outcome |
  |---|---|---|---|---|
  | `verbatim` | 2 | 1.00 | 1.00 | report-only (n=2 below `min_n_per_class` 10) |
  | `near-verbatim` | 5 | 1.00 | 1.00 | report-only (n=5 below `min_n_per_class` 10) |
  | `paraphrase` | 1 | 1.00 | 1.00 | report-only (n=1 below `min_n_per_class` 10) |
  | `negative` | 2 | n/a | n/a | report-only (n=2 below `min_n_per_class` 10) |
  | *overall* | 10 | 1.00 | 1.00 | 8 tp, 0 fp, 0 fn, 2 tn, 0 declined |

  **Every class ships report-only, and that is the gate's arithmetic rather than a shortfall.** Ten
  cases across four groupings cannot put any class at n=10, so no class is fix-eligible at v1 and
  the precision column decides nothing yet. The numbers were not tuned to change that and the gate
  was not lowered to meet them: gates bind fix eligibility and release readiness only, never what
  the report shows. `verbatim` and `near-verbatim` reaching n=10 at or above the 0.95 bar is the
  named exit condition of the first growth round. At n near 10 that bar behaves as a ratchet rather
  than as a statistic — one error demotes a class — and that is accepted.

  **What a perfect score here does and does not establish.** It does not say the detector is
  accurate on a corpus. Ten cases were authored at chosen points on the separation curve, and in
  this first round the agent that wrote the expectations is the agent that ran the pipeline, so
  recall is measured against expectations written by the same hand. What it does establish is a
  floor: the deterministic half is genuinely measured, not asserted, and the run would have failed
  the set on any contract violation — a paraphrase promoted to `fingerprint-confirmed`, a hard
  negative that fired, a span the scorer could not overlap. The adjudication loop below is what
  breaks the circularity, because a case converted from a rejected finding is a case nobody
  authored to pass. One limit of the tally is worth stating so it is not read as broader than it
  is: `score-golden.sh` matches on class equality and span overlap and never compares tiers, so
  tier fidelity is pinned by the two new eval cases rather than by this table.

  An independent blind pass was attempted and did not land. A separate agent was given the ten
  `case.md` and `source.md` pairs and the rubric, with the expectations and every lexical
  measurement withheld, so that its verdicts could stand as the run instead of the author's. It
  completed, but no channel was available to retrieve its per-case verdicts, so nothing it produced
  contributed to the table above and the figures are single-agent. Recorded as an open item rather
  than quietly dropped: the first growth round should re-run that pass and record whether a blind
  judge clears both hard negatives, since the distractor in `c07` is the case most likely to
  separate an independent judge from this one.

  **The adversarial synonym-rotation probe (design thread T15) returned a real answer.** Cases c08,
  c09 and c10 share one source page and differ only in rotation density, which makes density the
  single variable. At roughly one substitution every nineteen words the copy is untouched:
  containment 0.473 with a 22-word span, both limbs of the separation rule firing. At one every
  nine words the span limb dies and containment alone carries it: 0.413 with a longest span of 10,
  below the 15-word floor. At one every four words nothing survives: containment 0.0, no matched
  spans, against a source that was fetched and identity-checked, which lands the finding at
  `source-fetched-similar` — a human report, not fix-eligible, and deliberately not
  `llm-suspected`, because a source was in hand.

  Three consequences, recorded rather than acted on. The two-limb rule is load-bearing: dropping
  either limb loses c09. Word-shingling is evadable by an author who intends to evade it, and no
  value of `min_containment` above zero recovers a passage with zero matching shingles, so the
  answer is not a different number on this axis — which is why the constants were left at the
  bundled 0.3 and 15. And c09's containment only clears the threshold because the copy dominates a
  short file; the same rotation inside a long host file would dilute containment toward noise while
  the 10-word spans stayed under the floor, which is the dilution the span axis was added to
  survive and which rotation now defeats. A related note for fix mode: c09's eight matched spans
  are too fragmented to fence an edit against, so `fingerprint-confirmed` is not by itself evidence
  that a fix is applicable.

  **One measured behavior in the quoted-and-cited negative, found blind and then fixed.** The
  blockquote always stripped to nothing, as designed, but a 12-word residue survived at local lines
  19-20 because that fixture's inline quotation opens on one line and closes on the next, and the
  inline-quote stripper worked one line at a time: the opening mark is unpaired on its own line and
  was left in place rather than swallowing the rest of it. `c06` still cleared, the residue sitting
  far below both thresholds with carve-out 3 covering it, and this entry first recorded the gap as
  an accepted measurement. The blind adjudication pass rejected that reading, and it was right to.
  Hard-wrapped prose is ordinary markdown, so the clearance was luck rather than design: the same
  wrapped quotation carried a few words further would have cleared the 15-word span floor and
  fired, on a passage that is quoted and attributed. Inline stripping now runs over the paragraph
  rather than the line. The paragraph is also the bound, since a blank line, a fence delimiter or a
  blockquote line resets the open-quote state, so an unpaired mark or a stray apostrophe still
  cannot reach past the block it sits in, which is the conservatism the per-line behavior was
  protecting. Stripped characters are blanked in place and newlines are kept, so the line count and
  every reported line offset survive untouched and the fix step still has spans it can fence an
  edit against. Measured: `c06` moves from containment 0.100, jaccard 0.045 and a 12-word longest
  span to containment 0.031, jaccard 0.012 and a 7-word longest span, and the other nine golden
  cases do not move at all. The 7 words that remain at line 20 are not quotation residue but the
  citation URL matching the source page's own canonical-location line, and they stay in on purpose:
  a URL naming the source is evidence of attribution rather than of copying. Carve-out 3 keeps its
  reason to exist, because a stripper that follows quotation marks still cannot see a borrowing
  that carries none.

  **`.claude/provenance.json`, this repository's own config, carrying the fixture-tree exclusion.**
  `excluded_paths` lists `**/provenance/skills/audit/evals/fixtures/**`, and that is the whole of
  the file: the separation constants, budgets and gates stay at their bundled defaults because
  nothing measured here justified moving one. The exclusion lives in config and never in
  `list-corpus.sh`, which is the #3041 resolution — an unconditional exclusion would decline the
  fixtures under the eval harness's own config isolation and leave the eval author reading prose
  instead of results. Measured over `plugins/provenance` with the file in place: 33 considered, 10
  included, 23 declined against that one pattern with its reason named.

  **The adjudication-to-fixture loop, in `reference/dispositions.md`.** A finding the human rejected
  and a copy the audit walked past are both measurements the set does not yet contain, and both are
  lost unless they are converted. The section states the conversion in order — synthetic rewrite
  preserving the shape and never the text, the adjudicated verdict rather than the run's,
  registration in `evals.json` before the case counts as landed, and a re-score of the whole set —
  plus the two limits that matter as it grows: a rubric change invalidates every recorded figure
  while leaving the fixtures intact, and cases harvested from a sweep are a biased estimator
  because they are the cases this detector already got wrong.

  **This run is sidecar-only.** `emit-findings.sh` was not invoked and no relay findings file was
  written, because the crosswalk rows for `rule-verbatim-copy` and the two stamp rules land
  separately. No relay file ever carries a rule id with no row behind it.

- **Five review findings fixed, each verified by execution first.** All were real:

  - **`list-corpus.sh .` reported an empty corpus.** The repository root has several spellings and
    every one means "the whole corpus", but `.` reached the directory-prefix filter as a literal
    prefix, matched no tracked path, and returned zero files with no error. On this repository
    that was 0 instead of 1,353, and it read as a clean repository rather than a broken
    invocation. Every root spelling now normalizes to the empty prefix.
  - **An explicit `"excluded_paths": []` could not clear an inherited exclusion.** Treating "no
    elements" as "key absent" left the earlier layer's value in force, so an overlay could add
    exclusions but never remove one. Presence, not emptiness, now decides whether a layer
    overrides, which is what per-key override actually requires.
  - **`emit-findings.sh` reported success having written nothing.** With `set -e` deliberately
    off, an uncreatable directory or an unwritable path fell through to the "wrote" message and
    exit 0. That is the worst failure a persistence step can have, because nothing downstream
    contradicts it: the audit says the findings are relayed and the consumer never scans a file
    that does not exist. Both writing steps are now checked, with a new exit 5.
  - **Configured separation thresholds never reached the fingerprint module.** The module reads
    no config by design, so a repository that tuned `min_containment` or `min_span_words` silently
    got the bundled 0.3 and 15 — constants that decide which findings become fix-eligible. The
    audit flow now resolves them through the cascade and passes them explicitly, and reports the
    values it used.
  - **`--show-config` did not say which layer supplied a value.** The setup skill promises
    per-value provenance and tells the operator to read it from there rather than parsing the
    layers by hand; listing the layers and the effective values separately did not deliver that.
    Each value is now attributed to its layer, to the overriding flag, or to the bundled defaults.

- **Design artifacts graduated to `docs/specs/`, contract slice pruned.** The
  `copied-external-content` contract slice was pruned before merge per the topic-docs
  contract-slice lifecycle. Its durable half graduated with history preserved:
  `provenance-type-inventory.md` (script contracts, finding record, tier enum, config schema,
  golden-set case shape, draft crosswalk rows), `provenance-capability-matrix.md`,
  `provenance-design-threads.md`, `provenance-plugin-topology.md`, and
  `provenance-convention-engagement.md`. Remaining phases 6 to 8 graduated to the work-item
  tracker. Every in-plugin pointer to the old `docs/topics/` paths was rewritten, so a script
  header names a contract that still resolves.

- **The two skills, their evals, and the leaf-name registration.** `/provenance:audit` (default
  read-only, plus explicit `fix` and `sweep`) and `/provenance:setup` (`check` by default,
  `apply` on request), with 8 and 6 eval cases and a `context/gotchas.md` recording the build's
  real failure history.

  The audit's action router keeps mutation behind an explicit argument, so a bare invocation
  scopes, judges and reports and touches nothing. The untrusted-content spine is carried in the
  fetch step, and the fix flow's pointer-liveness check cites that statement rather than
  restating it, which keeps one contract in the file instead of two wordings of it.

  The setup skill is human-invoked under the setup contract, and the reason is specific rather
  than ceremonial: config decides what the audit is allowed to ignore, so a model proposing its
  own exclusions could quiet its own findings. Its eval set pins the refusals that matter, among
  them declining to hardcode the fixture exclusion into `list-corpus.sh` and correcting the
  premise that raising a gate shortens a report.

  Eval fixtures describe a fictional build tool. A fixture that planted real copied text would
  make the plugin's own repository carry the defect it exists to find.

- **The reference artifacts, the audit's judgment half.** `rubric.md` (shipped at version 1 here,
  corrected to version 2 above before this release closed),
  `dispositions.md`, `source-fetch.md`, `nomination.md`, and `context/persist-findings.md`. Each
  is read at the step that needs it rather than preloaded, so a read-only audit never pays for
  the fix discipline and a run with no fetch never reads the fetch route.

  The rubric states its own boundary first, because the four criterion names resemble fair-use
  factors and the resemblance is misleading: the verdicts are editorial, the remedies are
  maintenance remedies, and a finding says a passage should point at its source rather than
  restate it. It never says a passage is unlawful. Carve-outs are evaluated before any criterion,
  since several of them make the criteria meaningless rather than merely satisfied, and each
  criterion requires a quoted span, with UNKNOWN available when the material needed to quote is
  not in front of the judge.

  Two shapes exist to stop a measurement from lying. Judges are blind to the fingerprint numbers
  and to each other, because a judge told the containment score turns three samples into one
  sample repeated; and the semantic-diff guard reads the before and after without the rewrite
  rationale, because an agent told why an edit was made reliably finds that the edit achieved it.
  Nomination passes union rather than intersect, since intersecting two recall-biased passes
  converts them into a precision filter and discards the recall they were spawned to buy.

  `persist-findings.md` resolves the detector-findings contract through three rungs: the `review`
  plugin's bundled copy when that plugin is installed, the publisher's raw URL otherwise, and a
  refusal to write when neither is reachable. The first rung is new against the ai-slop precedent
  and closes a real gap — fetching a contract from one organization's URL made every offline run
  report-only and pointed a portable plugin at a single publisher.

  The untrusted-content framing spine is carried inline byte-identical at both Phase 4 ingest
  surfaces, with the site tails naming what these surfaces actually attract: fetched
  documentation pages that instruct the reader to copy them, which is the case under audit rather
  than a settlement of it.

- **The five deterministic scripts, the audit's reasoning-free half.** `list-corpus.sh`
  enumerates tracked markdown minus the categorical carve-outs; `extract-breadcrumbs.sh`
  inventories the provenance signals already in a directory; `check-stamps.sh` flags expired
  verification stamps; `emit-findings.sh` projects relay-eligible findings into a conforming
  findings file; `score-golden.sh` tallies case-level precision and recall. Each was written
  test-first and observed red: 223 cases across the five, all passing.

  Three shapes are contract rather than implementation detail. The eval-fixture exclusion reaches
  `list-corpus.sh` through the config layer and never unconditionally, so the eval harness's own
  config isolation lifts it and the fixtures report real findings; making that expressible is why
  the corpus root and the config root resolve separately. Breadcrumbs are emitted per directory
  rather than per file, because a neighbor's citation is what identifies an unfenced copy's
  source. And `emit-findings.sh` enforces the relay boundary: only fingerprint-confirmed copies
  and the two stamp rules may reach a findings file, judgment verdicts are counted in `Surfaces`
  rather than dropped, and their tier names are deliberately absent from the file, since a tier
  name in the apply relay's input invites a consumer to act on a verdict this producer withheld
  on purpose.

  Two findings cost real measurement. **mawk panics at compile time on interval expressions**
  (`{0,4}`), and the panic is quiet enough that the scan simply returns nothing and the script
  still exits 0 — a whole rule silently stopped firing until the corpus run showed zero
  candidates where hundreds were expected. Every regex in these scripts uses explicit repetition
  instead. Second, **"read" is an ordinary English verb**, so at the same keyword window the
  explicit stamp verbs use, prose like "an unconfirmed read of a shipped build" became a stamp
  candidate, and `context-management-2025-06-27` — an API beta identifier, not a date — became an
  expired-stamp finding. Narrowing the window for that one keyword dropped every such case while
  keeping the real `read <date>` forms: declined candidates fell 54 to 43 and the false finding
  went with them.

  Measured over this repository, 1,347 tracked files after carve-outs: 525 stamp candidates, 482
  parsed, 43 declined, 0 expired at the 180-day default (the oldest parsed stamp is 2026-04-08).
  The declined count is the honest report the design asks for and not a defect to tune away — the
  corpus genuinely carries month-name and bare-year stamp forms, and a parser that guessed at
  them would manufacture findings against dates nobody wrote down.

- **The fingerprint module, the plugin's one pure library.** Word 5-shingles,
  containment, Jaccard, and contiguous matched spans between a local passage and an
  already-fetched source, behind a thin CLI. It decides nothing: it reports lexical overlap and
  the audit flow maps that evidence to a tier.

  Two behaviors are contract rather than implementation detail, both earned in the spike phase.
  Quotation stripping runs inside the module over the local text before shingling and covers
  inline quotation marks (straight and curly) as well as blockquotes and code fences, because a
  properly quoted and cited excerpt must not read as a copy and a rubric-layer carve-out arrives
  too late. Verdicts are matched spans carrying local line offsets, because whole-file
  containment diluted a real 27-word match to 0.019 on a 2,912-shingle file; the separation rule
  fires on either measure, and the spans are what a fix edits against.

  Written test-first: 21 cases, red before the module existed, with the two amendment fixtures
  named in the output (an inline-quoted excerpt that must strip to zero matched spans, and a
  real-sized file whose planted span must surface while its ratio goes to noise). An unpaired
  quotation mark is left in place rather than swallowing the rest of the line, and a
  word-internal apostrophe is not treated as a quote. The `.test.sh` wrapper exists because CI
  discovers only `*.test.sh`; without it the module would ship with no CI coverage.

- **Plugin scaffold and registration.** Manifest, README, and marketplace entry for the
  documentation-provenance audit: prose in tracked markdown that restates an externally-owned
  fact without a pointer or a conforming stamped record.

  The README carries the boundary against every adjacent owner, the config schema, the fence and
  stamped-record marker forms, and the prerequisites, including what the audit still does when web
  search is unavailable (breadcrumb-only resolution, with the rest landing on the neutral
  `not-found` disposition). The skills, scripts, rubric, and evals land in later phases; the
  contract they build against is the graduated specs under `docs/specs/provenance-*.md`, chiefly
  `provenance-type-inventory.md` and `provenance-capability-matrix.md`.

  The rubric catalog is versioned with this plugin, so a criterion or carve-out change lands here
  and invalidates any golden-set measurement pinned to the prior version.
