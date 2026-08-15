# Changelog

All notable changes to the `knowledge` plugin are recorded here. The `version` in
`.claude-plugin/plugin.json` is the delivery vehicle — a consumer receives a change
only after that version increases.

## [0.12.3]

### Added

- **`youtube-digest` and `course-digest` gain public test entry surfaces (#2701).** Each skill's
  new `scripts/run-tests.sh` facade (`install`/`build`/`test`/`all`) delegates into the private
  `extraction/` npm package; CI and repo docs now invoke the facades instead of running npm
  directly inside the private subdirectory. The extraction packages themselves are unchanged.

## [0.12.2]

### Changed

- **`map-corpus` states its own deferred decisions instead of pointing outside itself.** The skill
  cited an authoring-time planning document by label, which no consumer ever receives — an
  unresolvable reference on a shipped surface. Each site is now self-contained: the deferred rung-3
  decision states its own fork (a presence-gated `/firecrawl:firecrawl map` seam versus a recorded
  reimplementation), its user-reserved arbiter, and its trigger; the deferred repo-tree enumeration
  rung states its trigger; the opaque `Q19` label is dropped from `SKILL.md`,
  `discovery/link-map-format.md`, `discovery/check_linkmap.py`, and the eval set; and the
  whole-snapshot hash in `extraction/node-manifest-format.md` now points at
  `reference/citation-shape.md`, its actual owner. No behavior, schema, gate, exit code, or
  argument changes.
>>>>>>> origin/main

## [0.12.1]

### Added

- **Owner doc for the tracked citation shape** (`reference/citation-shape.md`): URL + retrieval
  date (ISO 8601, UTC) + `sha256:<hex64>` over raw snapshot bytes, with inline and structured
  forms, an optional node-id sub-resource anchor, and a drift rule (new fetch = new citation;
  never edit a hash in place). Pays down the debt `map-corpus` recorded ("that citation shape still
  needs an owner doc before a second skill emits it") — the skill's cite-never-copy gotcha now
  points at the owner doc instead of naming the debt.

## [0.12.0]

### Added

- **New skill `map-corpus`** (`/knowledge:map-corpus`): map a multi-resource documentation corpus
  into a verified slice before any digesting — bounded discovery (llms.txt + sitemap, rungs 1–2
  only; in-page extraction deferred), a user-approved link map classifying every discovered URL
  with rung provenance, deterministic per-resource node manifests emitted by a script over
  immutable snapshots, and a per-node relevance inventory whose evidence tokens a script gate
  byte-verifies. Hands an approved queue to N runs of the unrenamed `docpage-digest` and its
  handoff to `/planning:interview`. Coverage denominators (URL set, node set) are
  script-produced, never agent-produced; all three bundled gates fail loudly on unparsable
  input and report exactly what they exercised. Requires `python3` (3.9+), declared at point of
  use.

## [0.11.2]

### Changed

- **Docs:** actionable `/plugin configure` guidance now uses the marketplace-qualified form
  (`<plugin>@<marketplace>`; generated option blocks use `@<marketplace>`) per
  [`docs/extensibility-contract-smoke-tests.md`](../../docs/extensibility-contract-smoke-tests.md)
  Test E (#1360). Targetless references to the flow stay unqualified.

## [0.11.1]

### Fixed

- **`docpage-digest`: the Anthropic profile cited a live docs page by line number, and the line had
  moved.** The `api-only` near-miss sub-shape (3) recorded its sole attested instance as
  `env-vars.md:394`. On a full verbatim read of that page on 2026-08-10 it runs 458 lines with 315
  variable rows, line 394 is `DISABLE_UPGRADE_COMMAND`, and the retry/fallback row the instance
  actually describes is `FALLBACK_FOR_ALL_PRIMARY_MODELS` — the only row on the page that both
  describes Claude Code's own retry behavior and names a model subject, the sibling
  `CLAUDE_CODE_DISABLE_NONSTREAMING_FALLBACK` naming none. The attestation is intact; its address
  was not, so the citation now names the variable. A standing rule goes with it: cite a live docs
  page by anchor, heading, or row key — never by line number, which the `.md` channel renumbers
  whenever the page gains a row. Line numbers into an archived snapshot stay citable, because that
  file is immutable.
- **`docpage-digest`: the profile's absence-fetch rule is now identified as the fleet rung it always
  was.** The rule itself is unchanged and was already right — `curl` the raw `.md` channel, record
  the retrieved length, because "a truncated fetch cannot fabricate a PRESENCE, only an ABSENCE".
  That asymmetry is this pipeline's own and stays here. What is added is one sentence naming it as
  rung 1 of the
  [fetch route](https://github.com/melodic-software/claude-code-plugins/blob/main/docs/conventions/upstream-drift/README.md#reading-the-basis--the-fetch-route),
  which the `upstream-drift` convention now owns fleet-wide — this profile's practice was one of two
  surfaces that route was generalized from, so the pointer records provenance rather than importing
  anything. Nothing is duplicated into or out of the profile. Its recorded "451-line, 316-row page"
  is qualified in place: the count has no stated counting rule and this page admits two differing by
  three, so it supports nothing by subtraction — the rule rests on the unambiguous 277-of-451
  position and the first-fifth cutoff. Qualified, not deleted, per the profile's own rule that a
  source artifact is noted at the row and never silently repaired.

## [0.11.0]

### Removed

- **The bare `/<skill>` alias for this plugin's skills.** Their `SKILL.md` files no longer
  declare a frontmatter `name`. The field is optional and defaults to the directory name, so
  declaring it only restated the path while registering a second, unnamespaced command — which
  the slash-command picker then echoed back as `/plugin:skill (skill)`. Invoke a skill by its
  namespaced command; the command itself is unchanged.

## [0.10.24]

### Changed

- **`course-digest` no longer mandates a progress report every fixed number of lessons.** The
  fixed-interval status cadence appeared in both the SKILL.md pacing list and the `context/workflow.md`
  Phase 2 pacing list the phase table routes execution at. Per-lesson crash-safe saving, the
  per-module save, and the context-pressure checkpoint are unchanged, so extraction durability and
  the resume path are untouched — only the forced interim status is gone.
- **`course-digest` keys session handoff to observable signals instead of a self-estimated context
  percentage.** The handoff protocol and the pacing checkpoint carried inconsistent `>40%` and
  `>50%` thresholds, and a model cannot measure its own context occupancy. Both now trigger on a
  long or quality-degraded session, a compaction, or a session ending mid-pipeline. The
  continuation-prompt contents, the phase markers, and both resume paths are unchanged.

## [0.10.23]

### Added

- **Anthropic profile's applicability filter gains the `tag-exempt (<sub-shape>)` class.** The
  vocabulary (`cc-applicable` / `mixed` / `api-only`) adjudicates API-vs-harness guidance, but some
  rows carry no guidance for any surface it adjudicates — consumer-surface material, an archive's
  own apparatus, metadata, or a navigation pointer — and the closest negative tag misdescribes what
  such material is. The new class is one disposition with those four documented sub-shapes, the
  sub-shape named at the row. It describes the material's genre and asserts nothing about harness
  applicability — not a positive tag, not a negative claim — so it owes no live-doc citation and no
  absence basis, and the near-miss disclosure burden never attaches; `api-only` remains reserved
  for rows that DO assert a harness absence for their own specific assertion. Consistent with the
  co-decided positive-tag rule (a positive tag asserts harness applicability and requires a
  live-doc citation): the class carries neither assertion, so neither evidence obligation.

## [0.10.22]

### Changed

- **Anthropic profile's model-matching table catches up with the dateless model-ID scheme.** The
  table's model-pin cell warned "never a bare family alias, which resolves to the current family
  model" and demanded "a full model ID" — vocabulary from the dated-snapshot era. The live
  model-IDs-and-versioning page now states that since the 4.6 generation the canonical model ID is
  dateless (`claude-{name}-{major}[-{minor}]`) and "is not an alias. It is the snapshot", so the
  old wording would misclassify exactly the correct pin for a current-generation model guide as a
  forbidden alias and fall through to the session default. The cell now pins "its pinned model ID
  — never an alias that can move to a newer snapshot", and a sentence under the table routes the
  generation-dependent pinned-vs-alias resolution to the live page at spawn time
  (pointer-not-copy; verified against the live page 2026-08-04, raw `.md` channel, 3836 bytes).

## [0.10.21]

### Changed

- **`whats-new-opus-5` moves from deferred to the Anthropic profile's Models queue, on grounds its
  own trigger never supplied.** The deferral read "release notes for a model the models `overview`
  page already covers canonically; enqueue when Opus 5 enters or materially changes a fleet lane",
  and that trigger has not fired. What moved the entry is custody: the `playbooks` Opus 5
  model-adaptation chapter already cites this page as **sole authority** for three shipped claims —
  thinking on by default, the 400 the API returns when thinking is disabled above effort `high`, and
  the live effort-level enumeration that establishes the upstream Opus 5 prompting guide's own ladder
  statement as truncated (all three re-verified live 2026-08-03) — and the `overview` page carries
  none of them. The deferral's premise is therefore
  false for exactly the facts already in use: doctrine ships on a page with no digest slice and no
  custody record. Scope is this one page, not a reopened release-notes lane — `whats-new-sonnet-5`
  carries no such citations and keeps its identical trigger.

## [0.10.20]

### Added

- **Anthropic profile gains archive-reading conventions.** Some pages this publisher maintains are
  archives — dated entries accumulated over time rather than a current statement, the [published
  system prompts](https://platform.claude.com/docs/en/release-notes/system-prompts) being the
  standing case — and three of their properties are invisible from inside any single entry, so a
  digest that does not know them reads the archive wrong in a way its own verification cannot catch.
  Each was found independently by multiple digest units before it became a convention. **(1) A dated
  entry is not a content-change signal:** two entries five days apart are byte-identical, differing
  on zero lines across 100-line bodies, with no annotation explaining why the second exists — so a
  new dated heading licenses no inference of revision, intent, or policy movement. The rule is
  stated in the narrower **content-change** form, which is what the finding supports: it bars
  inferring change from sameness, and leaves a reader free to read an actual textual narrowing
  between two entries as the change it is. **(2)
  Absence of bold does not prove absence of change:** the page states that updates between versions
  are bolded and the convention does not hold — one span carries zero bold markup across three dated
  entries differing in three sentences plus a twelve-paragraph addition, another marks one
  transition of three, and silent unbolded typo fixes and a silent removal were found the same way,
  so deltas come from diffing entries and never from reading the markup. **(3) Note a source
  artifact at the row; never silently repair it:** typos, escaped markup and malformed auto-links
  are reproduced byte-exact so a verifier can tell faithful reproduction from digest transcription
  error, with the blog channel's two known extraction artifacts named as the standing instance
  rather than restated. Its one exception runs the other way — a downstream artifact reproducing a
  known-corrupt entry *for a reader* rather than for verification repairs the corruption and says
  that it did. The property all three refine — that everything inside a dated entry is scoped to that
  entry's date — opens the section as its premise rather than as a fourth rule.

- **Anthropic profile gains hedge preservation and the residual-risk footer.** A source's own hedge
  now travels with the content it qualifies: an artifact graduated from this publisher preserves the
  hedge as the source states it, neither dropped as throat-clearing nor widened past what the source
  claims. Two instances graduate under the one convention rather than each inventing its own — the
  residual-risk footer below, and the harness best-practices material's "starting points, not set in
  stone" relativization. The **footer** is quoted rather than paraphrased from [Reduce
  hallucinations](https://platform.claude.com/docs/en/test-and-evaluate/strengthen-guardrails/reduce-hallucinations)
  (re-fetched 2026-08-03, HTTP 200; the sentence is byte-identical to the snapshot the corpus
  froze): *"Remember, while these techniques significantly reduce hallucinations, they don't
  eliminate them entirely. Always validate critical information, especially for high-stakes
  decisions."* **Its scope is the source's own and is deliberately not broadened** — it is about
  hallucinations, not errors or guardrail failures in general, and it names **no validator**, since
  who or what validates critical information is unstated in the source. That exact scoping is the
  part most likely to be lost in transit: it survived two correction rounds during the slice's
  verification, both of which caught a widening. It attaches **at the profile rather than per
  artifact**, because the profile is the seam every guardrail slice of this publisher flows through,
  so a graduated chapter or template cites the footer and never restates it.

## [0.10.19]

### Changed

- **Anthropic profile — the doc queue is repopulated from the Sitting-5 doc-queue dispositions.**
  The queue had been emptied as its slices completed, so twelve adopted rows had nowhere to land and
  the pipeline had no stated next page. Counted at the bytes, one bullet per page: **14 pages
  queued** across seven groups, and **5 pages deferred with triggers** — the deferred section now
  holds six bullets, the sixth being `task-budgets`, which predates this batch. Each entry carries
  the reason it is where it is rather than a bare URL.
- **`thinking-troubleshooting` is queued first, on a corrected rationale.** DQ-2's original ground —
  that the page backs the thinking doc set's *weakest* absence check — is not what the corpus says.
  The check is **falsified, not weak**: the harness carries a parallel troubleshooting surface
  (`errors.md`, `prompt-caching.md`), which is why the page's transfer is demonstrated rather than
  conjectured and why digesting it lets the corpus state the mapping instead of guessing at it.
  Carrying the old wording forward would have re-inherited a premise the evidence disproves. Rider
  R1 — the `api-only` → `mixed` retag the falsification compels on the affected claim — was
  discharged separately on 2026-08-03 and does not close silently with this enqueue.
- **Companion-doc order amended: `memory` moves to second.** DQ-9's source ranked
  `how-claude-code-works` ahead of it and held `memory` entirely. Two things have moved since:
  `memory.md` carries four to five times the corpus citation load of either page ranked ahead of it
  (47 line-anchored citations across 22 distinct sites in 18 files, against 11/6/9 and 9/5/6), and
  `claude-memory:audit` became a live adopted routing destination for memory-layer findings.
  `features-overview` keeps first place on its own reasoning; `common-workflows` stays held as
  recipe-level content whose citations are concentrated rather than distributed.
- **The Agent SDK entry queues one page, not the SDK doc set.** All thirty snapshotted `agent-sdk_*`
  pages sit inside the harness boundary, so a loosely phrased entry would take a scope decision
  nobody has made. The heading states the boundary instead of leaving it to inference.
- **Two pages fold into existing entries rather than gaining their own (DQ-15).**
  `whats-new-sonnet-5` is already a subject of the models deferral with a trigger, and a second
  differently-triggered standalone entry is how one page acquires two custody records that drift
  apart; `prompting-best-practices` is API-side content this corpus points at rather than digests.
  The source's premise that best-practices was "already in the profile doc queue" is false at the
  bytes — it never has been — but the disposition is unaffected, because folding resolves to no
  standalone entry either way.
- **Retention and ZDR are queued as one slice, and the slice remains owner-vetoable.** A corpus that
  will be pointed at repositories we do not control is precisely the one that should not be silent
  on retention: it is the one queued topic carrying compliance weight, and both properties are
  already in scope. The slice drains as three page runs per the engine's one-page-per-run rule;
  the API lane is the only page not already held in the harness snapshot. The org-policy posture
  is the argument for it rather than against, but the posture is real
  and cuts against the standing self-alignment-before-packaging ordering, so the enqueue is recorded
  as still open to an owner veto. A queue entry is trivially reversible if that veto fires.
- **The engineering-post entry's contingency is discharged.** Its enqueue was sequenced behind the
  engineering-property profile edit, which landed in 0.10.18 — the same merge that closed that
  property decision's veto window — so the entry ships unconditionally; the deferred-with-trigger
  fallback written for a fired veto never engaged.

## [0.10.18]

### Changed

- **Anthropic profile — `anthropic.com/engineering` is now an in-scope property.** The profile
  scoped this publisher to `platform.claude.com`, `code.claude.com`, and `claude.com/blog`, which
  put Anthropic's own engineering posts outside the pipeline even though they are first-party and
  are the stated best-practices channel for several topics the corpus already wants. Engineering
  pages are in scope by default now, rather than admitted one at a time by exception — the same
  coverage either way, with an honest boundary instead of a growing list of one-off exemptions.
  Two standing costs come with it and are not yet written into any rule: the vendor-blog
  attestation bullet below still names `claude.com/blog` literally and does not reach the new
  property, and unlike the two docs properties, `anthropic.com/engineering` publishes no
  machine-readable page index, so page selection and absence checks against it have no instrument.
- **Anthropic profile — a fourth artifact target: cross-slice synthesis.** The taxonomy named three
  targets, all of which describe a shape a cross-model synthesis artifact is not — it is not
  per-model, not an audit rule row, and not graduation of one slice. Content deferred to such a pass
  therefore had nowhere to route: the digest fan-out is barred from reaching across units by design,
  and no later pipeline stage exists to pick it up. Four units in one slice deferred content into
  that gap. The target is named without a host — which repository or seam it lands in is a separate
  decision no run has taken — so the taxonomy stops silently converting cross-unit findings into
  out-of-scope ones.

## [0.10.17]

### Changed

- **Anthropic profile — "harness surface" now has a written definition, and three shapes that come
  close without falsifying `api-only`.** J-12 was one of the five items 0.10.16 deliberately held
  for the dispositions interview; it is answered here. A harness surface is a surface a user can
  reach. Two of the three non-falsifying shapes — a **counterpart artifact** and a
  **same-workload mention** — carry an identical adjudication from two independent verification
  arms. The third, **harness-internal recognition or support** (a harness doc naming the subject in
  describing the harness's own behavior toward it, with no user-reachable path), is new: it rests on
  one attested instance, and the amendment is labelled as the campaign's own choice rather than an
  inherited adjudication, because nothing in the corpus ever defined the term. Every such hit is
  still disclosed as a near-miss under 0.10.16's rule, which this appends to rather than replaces.
  Without the definition, an `api-only` tag turned on whether the reader read "harness surface" as
  user-reachable selection or as any harness mention at all — and the two readings disagree on real
  rows.
- **Anthropic profile — bare names are not API surfaces.** The `cc-applicable`/`mixed` boundary now
  says what an API surface is not: a product name, display name, or docs-path slug never by itself
  triggers `mixed`, and the enumeration gains the fourth surface it had been missing (model ID)
  alongside parameter, endpoint, and SDK call. This ratifies a standard 15+ rows in the
  models-explained slice already stood on and a cross-vendor retag already applied in-slice — it is
  written down, not invented. It also gives the tier-name line `changelog.md:961` a destination: the
  harness-surface definition above excludes it from sub-shape (3), and this rule is what it routes
  to instead — a bare-name near-miss, disclosed under 0.10.16's rule, neither an API surface nor a
  harness surface.

## [0.10.16]

### Changed

- **`docpage-digest` — a second batch of the campaign's evidence-forced amendments.** Same standard
  as 0.10.15: each rule below was forced by a defect the pipeline's own runs produced, and each
  states its evidence inline. Not the last batch — the two classes held below say why.
- **Anthropic profile — what falsifies `api-only`, written down once.** Only the corpus documenting
  the claim's *own specific assertion* falsifies the tag; topical overlap never does. Below that
  line sits the **near-miss** — a harness page covering the row's subject without stating its
  specific rule: the tag survives, and the row must name the near-miss by page and line, so an
  affirmative "no surface" or "undisclosed" phrasing in such a row is simply false. Undisclosed
  near-misses were the largest MINOR class in the slice that measured them — one unit disclosed 24
  on its own — and the rule had been re-derived per unit rather than written down.
- **Anthropic profile — the two reproducible `claude.com/blog` extraction artifacts are recorded**
  (H1 word-spacing collapse; reading-time value and unit split across lines) with reconstruction
  from the canonical URL slug, labelled reconstructed because a slug recovers word boundaries only.
  Both reproduced exactly across two blog runs, which is what the earlier deferral was waiting for.

Two classes of item are deliberately **not** applied here, for two different reasons.

Three change instruments that live in the campaign's untracked work root, not in the shipped plugin
— making the quote checker a required artifact (whose own precondition, unrecognized-row detection
erroring loudly, cannot be demonstrated as shipped), the command-replay gate reading only the first
number of a `→ N lines, M files` pair, and the absence-measurement script skipping positive rows.
Whether any of those graduates into the skill is a scope decision, not a forced one.

Five more are held for the dispositions interview, having been reclassified out of this batch. The
campaign's triage marks each `evidence-forced`, but the judgment-amendments file writes all five up
as judgment calls with two named readings apiece — vendor-voice attestation for blog material
embedded in a non-blog page (J-6), splitting the two questions a positive tag's row collapses (J-7),
naming the publisher's `llms.txt` index as the page-selection instrument (J-8), the scope of
"harness surface" for counterpart artifacts and same-workload mentions (J-12), and the standing
convention for site-injected matter in a snapshot (J-14). That file's own reasoning governs: J-14
says outright it is held "only because no defect was demonstrated, so the bar for the applied subset
is not met", and J-7 says it should be decided *after* the Decision-A ordering question already
escalated to the maintainer. All five now carry recommendations in the interview's decision block.
The contested tag-vocabulary questions therefore remain where 0.10.15 left them, and these five join
them: with the dispositions interview.

## [0.10.15]

### Changed

- **`docpage-digest` now carries the evidence-forced rules the eleven-run digest campaign proved on
  itself.** Every rule below was demonstrated as a defect by the pipeline's own runs, not proposed
  abstractly, and each states its evidence inline so a later maintainer can see why it exists.
- **Anthropic profile — absence and citation evidence.** An `api-only` basis now records the exact
  command and its raw result count rather than a prose summary of what was checked; every non-zero
  result names its match site(s), with a sampled hit set stating that scope at the row; and a cited
  `file.md:NN` counts as disclosed only when a command recorded in that same row produces it.
  Absence-establishing fetches must use the raw `.md` channel with `curl` and record the retrieved
  length — a rendered fetch of a long page returns a silent prefix, and truncation can fabricate an
  absence but never a presence.
- **`SKILL.md` Phase 4 — verification-record discipline.** No tree moves until every dispatched arm
  has reported; every correction round leaves a dated applied record whose "New findings" section is
  a required input to the next round's brief; verdicts land in `verification/` or they did not
  happen; a mechanical gate errors loudly on input it cannot parse and is fixed *before* it is made
  required; commands are replayable in every pipeline artifact, not just digest rows, and each is
  replayed where it is authored — the Phase 5 handoff included, which no Phase 4 pass can reach; and
  the digest set is reconciled against itself before Phase 5, since every other check is scoped
  within a row.

Contested amendments the campaign also surfaced are deliberately **not** applied here — the tag
vocabulary questions (metadata and consumer-surface classes, pointer/navigation claims, archive-page
representation, the form `api-only` corroboration should take) have two defensible readings each and
belong to the dispositions interview, alongside the already-escalated Decision-A ordering question.

## [0.10.14]

### Changed

- **`docpage-digest` Anthropic profile: system-prompts release-notes entry removed, and the doc
  queue is now empty.** The `platform.claude.com/docs/en/release-notes/system-prompts` slice
  completed — 18 digests over a 2,548-line source, 659 claim rows, 561 `api-only`. It is the
  largest slice the pipeline has run and the last entry in the queue; only the deferred
  task-budgets trigger entry remains, which was never queued.
- **The "Supplementary references" heading is removed with it**, since the entry was the last one
  under it.

Verification reached `VERDICT: PASS` on both arms across the run's rounds, on SHA-256-pinned bytes,
with a final confirming round after the last corrections. Residual MINOR findings are disclosed in
the slice's `interview-handoff.md` as Open questions for the batched dispositions interview, per the
run's stopping rule; one contested tag-ordering question is escalated there as a candidate profile
amendment rather than decided in-run.

## [0.10.13]

### Changed

- **`docpage-digest` Anthropic profile: verification-loops blog entry removed, and the "Blog posts"
  heading with it.** The `claude.com/blog/building-verification-loops-in-claude-code-with-skills`
  slice completed — raw-md fetch through interview handoff, with dual verification reached on
  identical SHA-256-pinned bytes (both arms PASS, no MAJOR findings) — so its entry leaves the doc
  queue per the queue's remove-on-completion rule, and the heading is removed because it emptied.
  The slice exercised the vendor-blog attestation rule (profile 0.10.9) at scale: all 44
  `vendor-claimed` rows carry a targeted row-local `platform.claude.com` check, because the rule's
  predicate — "no harness **or platform** doc states the same assertion" — names both properties and
  a harness-only search never establishes it.

## [0.10.12]

### Changed

- **`docpage-digest` Anthropic profile: resources-overview queue entry removed.** The
  `platform.claude.com/docs/en/resources/overview` slice completed — raw-md fetch through interview
  handoff, with dual verification reached on identical SHA-256-pinned bytes (both arms PASS, no
  MAJOR findings) — so its entry leaves the doc queue per the queue's remove-on-completion rule. The
  "Supplementary references" heading remains: the system-prompts release-notes page is a separate
  concurrent run under the same heading, and its own queue PR removes the heading when it empties.

## [0.10.11]

### Changed

- **`docpage-digest` Anthropic profile: thinking-steering-and-cost queue entry removed, emptying
  the "Thinking" category.** The thinking-steering-and-cost platform doc slice completed — raw-md
  fetch through interview handoff, dual verification (three correction rounds, re-verified PASS by
  both arms on identical frozen bytes, no degraded fallback) — so its entry leaves the doc queue
  per the queue's remove-on-completion rule, and the now-empty "Thinking" category heading goes
  with it, as its paired run-9 entry's PR anticipated. Both overlapping thinking docs are now
  digested, one page per run under the category's contract.

## [0.10.10]

### Changed

- **`docpage-digest` Anthropic profile: thinking queue entry removed.** The extended-thinking
  platform doc slice completed — raw-md fetch through interview handoff, dual verification (one
  correction round of ten items, re-verified PASS by both verifiers, no degraded fallback) — so
  its entry leaves the doc queue per the queue's remove-on-completion rule. The paired
  thinking-steering-and-cost entry and the "Thinking" category heading remain: that page is a
  separate concurrent run under the category's one-page-per-run contract, and its own queue PR
  removes both.

## [0.10.9]

### Fixed

- **Vendored `video-digestion` frame counting no longer stops at 500 frames.**
  `countFrameFiles` carried a `max = 500` default bound, so a video with 500 or more
  contiguous extracted frames silently lost everything past frame 500 — about 4h10m at the
  interval fallback's 1 frame / 30 s, truncating long conference recordings with no warning.
  Counting is now unbounded and ends only at the first gap in the sequence, for both scene
  and interval frames. Mirrored from the medley SSOT
  (`melodic-software/medley#1687`), where the authored fix and its regression test live.

### Changed

- **`docpage-digest` Anthropic profile: models-explained blog queue entry removed.** The
  claude-models-explained blog slice completed — rendered-channel fetch (raw-md confirmed
  absent, matching the profile's blog-post channel note) with firecrawl extraction, through
  interview handoff, dual verification (two correction rounds, re-verified REVERIFY2: PASS by
  both verifiers, no degraded fallback) — so its entry leaves the doc queue per the queue's
  remove-on-completion rule, taking its inlined seven-item pairing cross-link contract with it
  (the contract was executed by the slice; its results live in the slice's handoff).
- **`docpage-digest` Anthropic profile: vendor-blog attestation rule.** Blog-only assertions
  (behavioral, performance, figure/percentage, comparative, positioning — an illustrative, not
  exhaustive, list) carry an assertion-specific `vendor-claimed (blog, <fetch date> fetch)`
  marker beside their vocabulary tag — never satisfied by related-property citations, never
  co-occurring with a same-assertion live-doc citation, never deferred to the interview. Closes
  the rule gap the context-engineering blog slice's handoff flagged (its OQ-3), with the shape
  enforced end-to-end by both verifiers on this slice.

## [0.10.8]

### Changed

- **`docpage-digest` Anthropic profile: choosing-a-model queue entry removed.** The
  choosing-a-model digest slice completed — raw-md fetch through interview handoff, dual
  verification (two correction rounds, re-verified REVERIFY2: PASS by both verifiers, no
  degraded fallback) — closing the entry's second half; its routing-vet half was already
  executed 2026-07-29 (#1697). The emptied "Model selection" special-handling category goes
  with it. The paired models-explained blog entry now points at the completed slice's handoff
  for its pairing observations.

## [0.10.7]

### Changed

- **`docpage-digest` Anthropic profile: increase-consistency queue entry removed.** The
  increase-consistency guardrail slice completed — raw-md fetch through interview handoff,
  dual verification (one correction round, re-verified REVERIFY: PASS by both verifiers, no
  degraded fallback) — so its entry leaves the doc queue per the queue's remove-on-completion
  rule. It was the last remaining guardrail guide, so the emptied category heading goes with it.

## [0.10.6]

### Changed

- **`docpage-digest` Anthropic profile: reduce-hallucinations queue entry removed.** The
  reduce-hallucinations guardrail slice completed — raw-md fetch through interview handoff,
  dual verification (two correction rounds, re-verified REVERIFY2: PASS by both verifiers, no
  degraded fallback) — so its entry leaves the doc queue per the queue's remove-on-completion
  rule. The increase-consistency guardrail entry remains queued.

## [0.10.5]

### Changed

- **`docpage-digest` Anthropic profile: best-practices queue entry removed.** The
  code.claude.com best-practices slice completed — raw-md fetch through interview handoff,
  dual verification (one correction round, re-verified REVERIFY: PASS by both verifiers, no
  degraded fallback) — so its entry leaves the doc queue per the queue's remove-on-completion
  rule. It was the sole "Applies across all of the above" entry, so the emptied category
  heading goes with it.
- **`docpage-digest` Anthropic profile: applicability-filter clarification from that slice's
  verification.** A digested page that is itself a live code.claude.com harness doc serves as
  its own row-local basis for intrinsic harness-guidance claims; the boundary rule still routes
  API-surface-naming claims to `mixed`, with third-party APIs counting as API surfaces.

## [0.10.4]

### Changed

- **`docpage-digest` Anthropic profile: sonnet-5 prompting-guide queue entry removed.** The
  prompting-claude-sonnet-5 slice completed — raw-md fetch through interview handoff, dual
  verification with corrections applied and cross-vendor re-verified — so its entry leaves the
  doc queue per the queue's remove-on-completion rule. It was the last remaining per-model
  guide, so the emptied category heading goes with it.
- **`docpage-digest` Anthropic profile: applicability-filter clarifications from that slice's
  verification.** Evidence is row-local ("same basis as claim N" never satisfies the contract),
  and `unverified-inference` is an additional uncertainty marker, never a substitute for the
  `cc-applicable`/`api-only`/`mixed` tag itself.

## [0.10.3]

### Changed

- **`docpage-digest` Anthropic profile: context-engineering blog queue entry removed.** The
  new-rules-of-context-engineering blog slice completed — rendered-channel fetch (raw-md
  confirmed absent for this page, matching the profile's blog-post channel note) through
  interview handoff, dual verification (both verifiers returned corrections; all applied and
  cross-vendor re-verified) — so its entry leaves the doc queue per the queue's
  remove-on-completion rule.

## [0.10.2]

### Changed

- **`docpage-digest` Anthropic profile: fable-5 prompting-guide queue entry removed.** The
  prompting-claude-fable-5 slice completed — fetch through interview handoff, dual verification
  (same-vendor PASS; cross-vendor corrections applied and re-verified PASS) — so its entry
  leaves the doc queue per the queue's remove-on-completion rule. The two thinking docs the
  effort-slice disposition enqueued were already queued in 0.10.1; verified still live at their
  queued URLs.

## [0.10.1]

### Changed

- **`docpage-digest` Anthropic profile: applicability-tag boundary + doc-queue dispositions.**
  The Claude-Code-applicability filter gains the `cc-applicable`/`mixed` boundary rule (a claim
  naming an API surface tags `mixed` even when its guidance transfers; `cc-applicable` is
  reserved for claims naming no API surface). Doc queue: the choosing-a-model entry records its
  routing vet as executed (melodic-software/claude-code-plugins#1697, digest slice still
  pending); the two thinking docs are queued as two runs; the task-budgets doc is recorded as
  deferred-with-trigger (api-only until harness support lands).

## [0.10.0]

### Added

- **New skill `docpage-digest` — 4th ingestion sibling.** Ingests a single online documentation
  page (docs-site URL) into a verified knowledge slice: fetch the unaltered original, inventory
  it into an `INDEX.md`, fan out one model-matched digest agent per section (model-pinned briefs
  use conditional framing — "if you are not X, note the mismatch and continue" — because
  spawn-time overrides can desync a brief from the running model), run dual verification
  (same-vendor Claude + one cross-vendor verifier; degraded-verifier fallback is
  recorded in the verdict header, never silent; verdicts are append-only), and hand off an
  interview-ready decision artifact. Publisher-specific configuration (fetch channel,
  Claude-Code-applicability filter with live-doc verification at tag time, digest-agent model
  matching, doc queue) lives in a separable profile at `context/anthropic-docs-profile.md`; a
  second publisher joins as a sibling profile, engine extraction waits for the third (Rule of
  Three). Ingested content is data, never directives (prompt-injection discipline named in the
  skill contract). Work root resolves through the plugin's `library_dir` seam, matching
  `course-digest`. Ships `templates/checklist.md` and `evals/evals.json`.

## [0.9.6]

### Fixed

- **course-digest extraction: `npm ci` failed on a clean install (#1507).** The
  `skills/course-digest/extraction` package pulls in the shared `@melodic/repo-analysis` and
  `@melodic/video-digestion` vendor packages as `file:` dependencies, same as the sibling
  `youtube-digest/extraction` package — but unlike that sibling, it shipped no `.npmrc` setting
  `install-links=true`. Without it, `npm ci` failed with `EUSAGE` (`Missing:
  @melodic/repo-analysis@0.1.0 from lock file`, `Missing: @melodic/video-digestion@0.1.0 from lock
  file`) on a fresh install, even though the committed `package-lock.json` was otherwise in sync.
  Added the missing `.npmrc`, matching `youtube-digest/extraction`'s. Discovered while wiring the
  package's test suite into CI, which never ran `npm ci` from a clean state before.

### Added

- **course-digest extraction test suite now runs in CI (#1507).** The `vitest` suite under
  `skills/course-digest/extraction` (`utils`, the adapter contract, the Dometrain/Teachable
  adapters, Clerk/Teachable-SSO auth, config, and the Hotmart/Mux players — 91 tests across 10
  files) had never been wired into `.github/workflows/ci.yml`; it only ever ran locally. Added a
  `course-digest-extraction` CI job mirroring the existing `youtube-extraction` lane (typecheck +
  `npm test`), gated behind the same docs-only scope guard as the repo's other Node lanes.

## [0.9.5]

### Fixed

- **Headless reconfigure recipe now preserves install scope (#1406).** The `claude plugin
  uninstall` → `claude plugin install ... --config` recipe in `skills/setup/SKILL.md` defaulted
  both halves to `-s user`. When this plugin is installed at `project` or `local` scope, that
  silently uninstalled a separate user-scope record while the effective project/local install kept
  loading, and the reinstall landed at a scope that does not load. Both commands now carry
  `-s <scope>`, sourced from what `claude plugin list` reports for this plugin — the same fix
  already applied to `session-flow` and `rate-limit-guard` in #1393.
  The recipe also now requires the reinstall to re-supply **every** key whose value should
  stay non-default, not only the key being changed: uninstalling drops the stored
  `pluginConfigs` entry, so an omitted key silently falls back to its manifest default.
  Record the current values before uninstalling.

## [0.9.4]

### Fixed

- **youtube-digest: resume recovers an explicit `--target`** (#1356): `watch --target <repo>`
  resolved a synthesis target, but nothing in the extraction runtime persisted it —
  `WatchState` had no target field, and `buildContinuationPrompt()` never told a resumed
  session where to find it, so an interrupted cross-repo watch lost the resolved target and
  `resume` had to re-infer or re-ask. `run-watch.js` now accepts `--target <repo>`, threads it
  into `createWatchState()`, and `watch.json` records the portable name (never a machine-local
  absolute path). `buildContinuationPrompt()` and `run-resume.js`'s JSON output now surface the
  recorded target so a resumed session reuses it instead of re-asking.

## [0.9.3]

### Fixed

- **youtube-digest: contact-sheet retention wording + `--target` resolution gap**
  (#1015): the intro paragraph called the `key-frames/contact-sheets/` snapshot
  "temp-only handling," contradicting the Output contract's "local DR snapshot,
  gitignored" characterization of the same directory; reworded to "never-committed
  handling" so the snapshot reads as a durable-on-disk-but-gitignored instance, not
  temp state. `--target <repo>` resolution now requires a **local working tree on
  disk** (not just a name) because `templates/synthesis-item.md`'s grep-backed
  **Target touchpoints** need a tree to grep; an explicit `--target` with no local
  checkout now halts and asks for its path instead of falling through to
  `CLAUDE_PROJECT_DIR`/CWD or inventing paths. `README.md`'s `**Target:**` line
  records the target's portable name only — never the machine-local checkout path,
  since that README is a staged artifact — as a record for readers and downstream
  consumers of a finished slice, not as resume state.

## [0.9.2]

### Fixed

- **youtube-digest extraction: deterministic dev installs** (#905): `npm ci` in
  `skills/youtube-digest/extraction` failed from a clean checkout — the committed
  lockfile pins the shared `vendor/` packages as packed installs (the mode
  `setup-deps.mjs` uses via `--install-links`), while a plain `npm install`
  resolved them as symlinks, skipped their dependencies (`imghash`), and rewrote
  the lockfile into the mismatched link shape. A committed `.npmrc`
  (`install-links=true`) pins the packed mode for every install command, so dev
  installs match the runtime path and the lockfile stays stable. CI gains a
  `youtube-extraction` lane (clean `npm ci` + typecheck + vitest) so this drift
  class can no longer go latent.

## [0.9.1]

### Changed

- **youtube-digest: synthesis is now framed against a resolved target, not an
  implicit "the repo I'm in".** `templates/recommendations/menu.md`,
  `templates/synthesis-item.md`, and `templates/readme-journey.md` referenced
  the invoking repo by assumption; a session running from a separate corpus
  checkout had no way to say which repo the menu was actually for. `SKILL.md`
  now documents a "Synthesis target resolution" ladder — explicit `--target
  <repo>` argument (any `watch` form) → the invoking project when run
  standalone → ask — and the templates substitute `{target}` instead of
  assuming the CWD. `recommendations/**` is documented as this skill's own
  ephemeral, target-bound deliverable, expected to be superseded by the
  designed-but-unbuilt `/knowledge:apply` report→diff→PR flow
  (`docs/knowledge-integration-design.md`) once that skill ships.
- **youtube-digest: two known agnosticism gaps are now named explicitly in
  `SKILL.md` instead of left silent.** The `library_dir` seam relocates the
  `.work/<watch-epic>/<video-slug>/` work *root* but not that sub-path's
  *shape* — a corpus consumer whose own convention differs (e.g.
  `sources/<type>/<slug>/`) does not get that shape today. Separately, raw
  video, bulk frames, and working contact sheets stay OS-temp-only by design
  (contact sheets do get a gitignored, slice-local disaster-recovery snapshot
  at `key-frames/contact-sheets/`, but that is not committed durable
  retention); a consumer that wants these retained as a committed,
  re-runnable substrate does not get that today either. Both are called out as tracked follow-ups rather
  than an unstated limitation a consumer discovers by hand. Doc-only; no
  pipeline behavior changes.

## [0.9.0]

### Added

- **`library_dir` portable value forms** (#798): the seam now accepts a leading `~`
  (home-relative) and environment-variable references `${NAME}` / `%NAME%` (e.g.
  `${KNOWLEDGE_CORPUS_DIR}`) alongside the existing relative and absolute literals, so a
  machine-varying corpus root (a non-home drive, a per-machine checkout) never requires a
  literal machine-specific path in stored configuration — the form guardrail hardcoded-path
  checks block. The youtube-digest launcher (`run.mjs`) expands both forms in `--work-root`
  (`expandPathValue` in `lib/run-args.js`), failing loud on an unset variable or a
  non-absolute expansion; literal values pass through unchanged (back-compat). The
  youtube-digest artifact-landing contract, README option table, plugin manifest option
  description, and setup mismatch guidance document the forms. Env-var indirection was
  chosen over a ghq-derived scheme, which would couple the seam to ghq presence; a ghq user
  points the variable at the ghq-derived path instead.

## [0.8.4]

### Changed

- Skills with `!` dynamic-context injections now declare `shell: bash` explicitly, per
  the pinned precompute convention — bash-only pipelines must not fall through to a
  PowerShell host.

## [0.8.3]

### Fixed

- **youtube-digest: resolved a self-contradiction in `SKILL.md` about `.work/`
  commit behavior.** The video-slug carve-out prose claimed the `.work/` root
  "self-ignores (a `.gitignore` containing `*`) and is never committed" — an
  unimplemented statement (no code writes a root `*` ignore) that directly
  contradicted the Output contract, where ~35 slice artifacts are marked
  `Staged: yes`. The prose now states the committed reality: slice artifacts are
  the durable substrate, staged and committed per the Output contract *when the
  resolved work root is not itself gitignored*, with the contact-sheet JPGs held
  out of git in every case by the per-directory `.gitignore` (`*.jpg`) that
  `snapshot-bootstrap.js` writes. It also surfaces the precondition the old text
  elided: a co-resident topic-docs convention self-ignores the shared repo-root
  `.work/` (default `memory_dir`), leaving slices local until the work root is
  relocated (e.g. a non-default `library_dir`). Doc-only; no pipeline behavior
  changes.

## [0.8.2]

### Changed

- Documentation-only: the License section now states the plugin's own MIT
  license inline and no longer points at a `LICENSE` file at the repository
  root, which an installed consumer running from the isolated plugin cache
  cannot reach. No behavior change.

## [0.8.1]

### Changed

- **youtube-digest: the `variation-matrix-backlog.json` manual smoke-test log is
  demoted out of `evals/fixtures/`.** It is a tracking backlog of candidate videos
  across footage variations (status notes, blocked-caption records), not an
  input→expected-output graded fixture — no eval `files[]` entry or test consumed
  it. Moved to the skill's `reference/`; `SKILL.md` and vendor `TUNING.md` prose now
  point at the new path, and its grandfather line is removed from
  `scripts/orphaned-fixtures-baseline.txt`.

## [0.8.0]

### Changed

- **Setup adopts the uniform `check` / `apply` contract and covers the extraction
  prerequisites.** The read-only `check` (default) verifies `library_dir` against the
  repository's artifact convention and probes the shared node dependencies, Playwright
  Chromium, and the OS-level media tools (`yt-dlp`, `ffmpeg`, ImageMagick 7) as
  PASS/FAIL/INFO. `apply` routes `library_dir` changes through Claude Code's plugin
  configuration prompt (never hand-editing `pluginConfigs`); `apply install-deps` runs the
  youtube-digest and course-digest `setup-deps.mjs` provisioners — the same idempotent
  scripts the ingest skills already run — pulling the prerequisite/provisioning surface onto
  the setup contract. The personal env-channel scalars are unchanged.

## [0.7.1]

### Changed

- README declares the shell mechanics with their Windows path (Git Bash
  bundles the `sha256sum` that `book-distill` runs on every distillation) and
  the EPUB branch's `unzip` requirement (not bundled with Git Bash) —
  cross-platform declaration wave. PDF-only use needs neither extra install.

## [0.7.0]

### Changed

- **`youtube-digest` yt-dlp / throttle scalars migrated to personal `userConfig`.** Four
  options — `yt_dlp_js_runtimes` (string, default `node`; `off` omits `--js-runtimes`),
  `yt_dlp_cookies_file` (string, path to a Netscape cookies.txt), `yt_dlp_cookies_from_browser`
  (string, e.g. `chrome`/`firefox`/`edge`), and `max_concurrent_acquires` (number, default 1,
  1–3) — are now configured through Claude Code's plugin-configuration prompt and wired into the
  extraction pipeline as leading `run.mjs` flags (`--js-runtimes`, `--cookies-file`,
  `--cookies-from-browser`, `--max-concurrent-acquires`), exactly as `library_dir` wires
  `--work-root`. The launcher translates each flag into the environment variable the extraction
  child already reads.
- **BREAKING: the `YOUTUBE_YT_DLP_JS_RUNTIMES`, `YOUTUBE_YT_DLP_COOKIES_FILE`,
  `YOUTUBE_YT_DLP_COOKIES_FROM_BROWSER`, and `YOUTUBE_MAX_CONCURRENT_ACQUIRES` shell env vars are
  no longer a documented consumer channel.** Configure the four options above instead. The env
  vars remain only as the internal launcher-to-child interface `run.mjs` sets from those options;
  setting them by hand in your shell is no longer supported. Zero-config behavior is unchanged —
  unset options contribute no flag and the pipeline keeps its built-in defaults.

### Notes

- **Course-platform credentials deliberately remain shell env vars.** `COURSE_*` / `TEACHABLE_*`
  are excluded from this migration: a `sensitive: true` userConfig option still persists as
  plaintext in `~/.claude/.credentials.json` on Windows, so those secrets stay in shell env until
  keychain-backed sensitive storage lands there (documented at the course-digest auth-env site).

## [0.6.1]

### Changed

- References to the renamed `/planning:plan` skill (was `/planning:architect`, planning 0.13.0 breaking rename) retargeted. Version bumped so existing installs receive the rewritten prompts.

## [0.6.0]

### Changed

- **BREAKING: `youtube` skill renamed to `youtube-digest`.** Invoke as
  `/knowledge:youtube-digest` (previously `/knowledge:youtube`). Sibling skills follow a
  source+operation grammar (`book-distill`, `course-digest`); the platform noun alone named
  the source but not the operation. Triggers are unchanged — "youtube", "watch this YouTube
  video", and youtube.com/youtu.be URLs still route to the skill. In-flight watch slices are
  unaffected (`.work/<watch-epic>/...` layout is unchanged); resume with
  `/knowledge:youtube-digest resume <video-slug>`.

## [0.5.6]

### Added

- Revisit condition in the README recording when the bundled `youtube` skill would
  graduate into a standalone plugin (once its vendored `video-digestion` package is
  independently distributable).

## [0.5.5]

### Fixed

- **Lossless WebVTT transcript extraction.** Cue cleanup still strips complete WebVTT tags in one
  linear pass, but now preserves an unmatched literal less-than tail instead of truncating the rest
  of programming, mathematics, or other tolerant transcript text.

## [0.5.4]

### Fixed

- **Current Claude Code configuration contract.** Setup now treats `library_dir` as a personal
  `userConfig` option, validates it against the consuming repository's artifact convention, and
  routes changes through Claude Code's configuration prompt instead of editing unsupported
  project/local `pluginConfigs` entries.
- **Repository and transcript input hardening.** GitHub repository URLs now require an exact,
  credential-free GitHub HTTPS or SSH shape before canonical clone arguments are constructed;
  clone option parsing is terminated explicitly; and WebVTT/entity cleanup uses bounded,
  single-pass transformations that cannot turn nested malformed input into active markup.

## [0.5.3]

### Changed

- **Aligned with the marketplace topic-docs convention** (`docs/conventions/topic-docs/`).
  Setup's convention inference now points at the `.claude/topic-docs.yaml` concern file and
  the `.work/` memory tier (the retired `.claude/notes/` location is no signal — the contract
  is a clean break), and the youtube/course-digest skills carry the contract's **formal carve-out**
  note (the work root resolves through this plugin's `library_dir` seam, not the concern file's
  `memory_dir`; slug conformance is form-only; nested `<epic>/<slug>/` sub-slices are
  sanctioned), linking the convention by its canonical URL. The youtube slice-lane rationale
  now records that the `verification/` lane name matches the convention's canon. Docs-only —
  no paths or behavior change; the `library_dir` seam is untouched.

## [0.5.2]

### Fixed

- **YouTube extraction — crash/incorrect-output paths on normal use.** Recovery
  (`--recover`/`resume`) now accepts an auto-caption-only `*-orig.vtt` instead of
  throwing `Missing mp4/vtt/info.json`; `watch.json` + tempSession are persisted
  before the long extraction phase so an interrupt there stays recoverable;
  exact cue/densification anchor timestamps survive the second dedup pass instead
  of being replaced by fabricated ordinals; harvested GitHub deep links are cloned
  from the canonical `https://github.com/<owner>/<repo>` URL rather than the
  un-cloneable deep link; the documented `companion` Phase 0b marker is accepted;
  recovery is no longer advertised when the acquisition `workDir` is gone;
  `--skip-research` is persisted so resume doesn't re-route into research;
  marking the terminal `synthesis` phase sets `watch.status` to `complete` so the
  blocking checklist is enforced; `resume` advertises the on-disk continuation-prompt
  path; the research gate requires a `research-agenda.md`; and contact-sheet snapshots
  write a local `.gitignore` so the JPG binaries can't be committed.
- **YouTube extraction — hardening.** Deck/attachment fetches stream to disk under a
  500 MB cap (byte-counted, not just `content-length`) instead of buffering the whole
  attacker-controlled response; the acquire throttle gained an optional overall
  `timeoutMs` and heartbeats a held slot's mtime so a long download isn't misclassified
  as stale and reclaimed; clone paths sanitize Windows-reserved characters; acquisition
  forces `--no-playlist`; and a passing key-frame quality-audit row now requires a
  substantive evidence note (an omitted note no longer bypasses the gate).

## [0.5.1]

### Changed

- **Vendored shared libraries deduplicated to one plugin-wide copy.** `@melodic/repo-analysis`
  and `@melodic/video-digestion` were vendored separately under both
  `skills/youtube/extraction/vendor/` and `skills/course-digest/extraction/vendor/`. They now
  live once at the plugin root (`vendor/`); each skill's `extraction/package.json` links it via
  `file:../../../vendor/*` and each `setup-deps.mjs` fingerprints the shared tree. Runtime install
  into `${CLAUDE_PLUGIN_DATA}` is unchanged. Internal restructure — no consumer-facing behavior
  change; the version bump delivers the moved source (and the new install fingerprint) to consumers.

## [0.5.0]

### Added

- **`course-digest` skill** (`/knowledge:course-digest`) — extract and synthesize
  online video courses (Dometrain, Teachable) into repo-applicable recommendations:
  browser-automation transcript + frame extraction, code-companion analysis, and
  multi-modal synthesis. Actions: full pipeline, `extract`, `analyze`, `status`,
  `resume`, `continue`.
- Bundled `extraction/` node pipeline for the course-digest skill, with the two
  shared libraries (`@melodic/repo-analysis`, `@melodic/video-digestion`) vendored
  under `extraction/vendor/`. Dependencies install into `${CLAUDE_PLUGIN_DATA}` via
  `skills/course-digest/extraction/setup-deps.mjs`, which also provisions Playwright's
  Chromium into `${CLAUDE_PLUGIN_DATA}/ms-playwright` (idempotent; re-run after a
  plugin update). ffmpeg and ImageMagick remain OS-level installs the skill's
  Prerequisites section documents.

### Changed

- **Credential model** — course-platform login uses the user's own shell env vars
  (`COURSE_*`/`TEACHABLE_*`, prefix driven by `platformConfig.authEnvPrefix`) with an
  interactive manual-login fallback. Session cookies persist under
  `${CLAUDE_PLUGIN_DATA}/auth/<platform>.auth-state.json` (out of the consumer repo),
  keyed per platform.

### Notes

- The course-digest pipeline is ESM and shares the youtube skill's launcher shape
  (`run.mjs` ESM resolve hook so bundled deps resolve from `${CLAUDE_PLUGIN_DATA}`);
  `run.mjs` additionally pins `PLAYWRIGHT_BROWSERS_PATH` to the data directory so the
  browser binary resolves regardless of cwd.
- Manual login (`node:readline` + headed browser) may not function under headless
  plugin execution; env-var + cookie-reuse carry the skill regardless.
- `repo-analysis` and `video-digestion` are now vendored by both the youtube and
  course-digest skills. Deduplication of the two copies is tracked separately.

## [0.4.0]

### Changed

- **`youtube` skill now honors the `library_dir` seam.** The invoking skill wires a
  non-default `library_dir` into the extraction pipeline by passing
  `run.mjs --work-root <dir>`, which the launcher translates into the
  `YOUTUBE_WORK_ROOT` environment variable the scripts already read — so watch,
  transcript, and queue artifacts land under the configured directory instead of
  always at the consuming repo root. Agent-written slice artifacts (the queue table,
  its claim stubs, and every Output-contract deliverable) anchor to the same resolved
  root, so a non-default `library_dir` never splits a slice across two directories. The default (`.`) path is unchanged: no flag,
  `resolveWorkRoot()` keeps its `CLAUDE_PROJECT_DIR` → `process.cwd()` fallback. A
  double-quoted CLI arg was chosen over an inline `YOUTUBE_WORK_ROOT=… node` prefix
  because the latter is bash-only and fails under PowerShell.
- **`setup` Output** now states that `library_dir` governs where youtube artifacts
  land, restoring the stronger wording softened while the seam was unwired
  (`book-distill` remains the documented exception).

## [0.3.0]

### Changed

- **`setup` skill** — retrofit `library_dir` precedence resolution and portability
  hardening so synthesized artifacts land at the configured library directory in the
  consuming repo.

## [0.2.0]

### Added

- **`youtube` skill** (`/knowledge:youtube`) — watch a single public YouTube video
  (transcript + visual frames), harvest reference links, drive external research,
  and synthesize a prioritized repo-applicability menu. Actions: `watch`, `queue`,
  `transcript`, `resume`.
- Bundled `extraction/` node pipeline for the youtube skill. Its dependencies are
  installed into `${CLAUDE_PLUGIN_DATA}` on first use via
  `skills/youtube/extraction/setup-deps.mjs` (idempotent; re-run after a plugin
  update). Media binaries (`yt-dlp`, `ffmpeg`, ImageMagick) remain OS-level installs
  the skill's Prerequisites section documents.

### Notes

- The youtube pipeline is ESM. Its entry points run through
  `skills/youtube/extraction/run.mjs`, which injects an ESM resolve hook so bundled
  dependencies resolve from `${CLAUDE_PLUGIN_DATA}` (NODE_PATH is CommonJS-only and
  does not apply).

## [0.1.1]

- Prior baseline: `book-distill` and `setup` skills.
