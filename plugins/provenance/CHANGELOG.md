# Changelog

## [0.1.0]

### Added

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

- **The reference artifacts, the audit's judgment half.** `rubric.md` (rubric version 1),
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
