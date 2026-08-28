# Changelog

## [0.1.0]

### Added

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
  contract they build against is `docs/topics/copied-external-content/PLAN.md` and its `design/`
  artifacts.

  The rubric catalog is versioned with this plugin, so a criterion or carve-out change lands here
  and invalidates any golden-set measurement pinned to the prior version.
