# PLAN — source-agnostic video digest

Status: APPROVED 2026-08-15 — all six [FALLBACK] rows accepted with their RECOMMENDED options
(no `name:` pin; docs/topics + .work refs KEEP; npm package renames; CI job id by pre-check;
version 0.13.0 + keywords; ASR never auto-installed). Design inputs: `design/design-threads.md` (primary),
`design/capability-matrix.md`, `design/inherited-decisions.md`, `design/hub-split-budget.md`,
`design/consumer-context.md`. Design gate: PASSED (`design/design-handoff-gate.md`, run 2,
2026-08-15). Stress-tested 2026-08-15 (cross-vendor Codex + fresh-context devils-advocate);
findings verified and folded in — see "Stress-test summary".

Conventions for this file: phase tags `[TODO]` / `[IN-PROGRESS]` / `[DONE]`. All sanity-check
commands run in **Git Bash from the repo root** unless stated otherwise. Durable evidence for
manual/one-time checks lands under `.work/source-agnostic-video-digest/evidence/<phase>/`
(machine-local memory slice, never committed).

## Brief

**Goal.** Make the single-public-video digest pipeline source-agnostic: X (Twitter) video joins
YouTube behind an engine-layer source-adapter contract; the skill is renamed
`youtube-digest` → `video-digest`; `course-digest` receives no behavioral or structural change.

**Why.** The per-source surface is measured at 6 stages (capability matrix, after the T4/T5
stage-2 collapse); everything else is shared. An `x-digest` sibling would duplicate ~325 lines
of source-agnostic pipeline and lose listing-budget triggers; an all-sources merge fails the
500-line hard cap. The adapter seam is the extraction layer.

**Storage invariant (A1, binding — stated verbatim so no phase erodes it).** One queue root,
one `claims/` namespace; the on-disk epic directory stays the literal `youtube-watch` (stable
storage-format identifier); **source is never a directory level** — it lives only in slice
metadata (`watch.json` `sourceUrl`); mixed-source batches share the one queue; **no migration**
of any consumer's `.work/` tree; every user-facing path rendering derives from the resolved
slice dir, never from the constant.

**Scope boundaries.**

- In: adapter contract + registry + YouTube/X adapters; transcript strategy seam; error
  taxonomy; conformance suite; hub split + widened description; naming hygiene; env-var
  namespace rename with compatibility read; skill rename with breaking-change discipline.
- Out (each with recorded trigger in design): A1 move (ii) epic parameterization;
  adapter-namespaced config; ASR-as-substrate (posture iv); priority/scoring dispatch;
  content-claim capability (reserved, unimplemented); LFS retention / sub-path templating;
  scheduled liveness lane (tracked follow-up only).
- `course-digest` untouched criterion, re-scoped (user-approved 2026-08-14): *no behavioral or
  structural change; mechanical cross-reference updates forced by the rename are exempt and
  enumerated in Phase 7.* Additionally (step-zero consequence): the `checkJs` flip may force
  **type-annotation-only** edits (JSDoc, tsconfig) in `course-digest/extraction` — zero
  runtime-behavior change, proven by its test suite.

**Success criteria.**

1. `watch <x-status-url>` and `transcript <x-status-url>` run end-to-end (full watch parity).
2. All existing YouTube behavior preserved (vitest + evals green; same slice layout; epic dir
   literal unchanged). YouTube and X slices coexist under one queue root, including under a
   non-default `--work-root`.
3. `tsc --noEmit` green in both extraction lanes **with `checkJs: true`**.
4. Rename ships with breaking-change discipline (CHANGELOG + announcement naming the five
   silent consumer surfaces); the sweep regression test catches the three known-miss vendored
   refs.
5. Hub `SKILL.md` **body** (after frontmatter; baseline 37,620 chars ≈ 9,405 est. tokens at
   chars/4) lands under 20,000 chars ≈ 5,000 est. tokens; description rules per Phase 6.

## Standards grounding

No standards index (`.claude/standards.yaml`, `docs/standards/README.md` absent) — ladder
rung 4 (inference), surfaced not persisted:

| Surface | Source loaded | Provenance |
|---|---|---|
| Skill caps + gates | `plugins/skill-quality/scripts/check-skill.sh:175-177` (1536 desc / 500 hard / 200 soft; token warrant governs the split per hub-split-budget.md) | repo (team) |
| Topic docs / PLAN lifecycle | `docs/conventions/topic-docs/README.md` + planning-plugin binding | repo (team) |
| Commit convention | `docs/conventions/commit-convention/README.md` + `.claude/source-control.md` resolution | repo (team) |
| Engineering philosophy (root-cause-only, zero suppressions, comment hygiene) | user-global CLAUDE.md + `melodic-software/standards` engineering-philosophy | org + user-global |

## Plan

### Phase 0: Switch the type lane on [DONE]

Step zero, before any contract work (T3 blocking precondition; user-directed).
Landed `aaa62cc7` (2026-08-15); strict-tier posture + `@satisfies` no-op recorded in
`DEVIATIONS.md`. Checker holes for Phase 4 grew to four: (1) `noImplicitAny` off — adapter
methods need explicit parameter annotations; (2) `**/*.test.js` excluded from the type lane, so
the conformance suite itself is untyped; (3) too-few-parameters accepted silently;
(4) interpolated `import()` resolves to `any`.

- [x] `course-digest/extraction/tsconfig.json:9` — `"checkJs": false` → `true`
- [x] `youtube-digest/extraction/tsconfig.json:9` — `"checkJs": false` → `true`
- [x] Fix every surfaced diagnostic at root cause. **Zero suppressions** (`@ts-ignore` /
  `@ts-expect-error` require explicit user approval + recorded justification; target: none).
- [x] Standardize contract-bearing annotations on `@satisfies`. (No applicable sites — lands
  with Phase 1 contract authorship; DEVIATIONS.md.)
- [x] Known checker holes recorded for Phase 4 to cover at runtime: too-few-parameters
  accepted silently; interpolated `import()` resolves to `any`.

**Sanity Check:**

- [x] `grep -rn '"checkJs": true' plugins/knowledge/skills/*/extraction/tsconfig.json` → 2 rows
- [x] `npx tsc --noEmit` exit 0 in both extraction dirs
- [x] `git grep -n -e '@ts-ignore' -e '@ts-expect-error' -- 'plugins/knowledge/skills/*/extraction'` → 0 rows (git-grep form per DEVIATIONS.md — the raw grep matches node_modules)
- [x] Both lanes' vitest suites exit 0 (no runtime change)

### Phase 1: Adapter contract, registry, YouTube adapter (behavior-preserving) [TODO]

Review: architecture
Review: security

Integration-first slice: after this phase the existing YouTube path runs **through** the
adapter seam with observably identical behavior.

**Pre-flight consumer check (FIRST item — the result envelope is a contract migration):**

- [ ] Inventory every producer/consumer of acquisition metadata and result shape before
  defining the envelope: `run-watch.js`, `run-transcript.js`, `preflight-metadata.js` +
  `queue-claim.js` (queue lane), `watch-state.js` (state + resume prompts),
  `post-bootstrap-slice.js` / `snapshot-bootstrap.js`, `export-sheet-frame-index.js`,
  `harvest-links.js`, `evals/check-*.js`. Document each one's current single-result
  assumption; every touched assumption gets a work item below.

**Contract (`extraction/adapters/adapter-contract.js`):**

- [ ] 5 required methods: `matchUrl(url)` (claim + canonicalization; no I/O);
  `extractSliceKey(url, metadata)` (signature fixed even though both sources need only `url`);
  `acquire(...)`; `harvestLinks(metadata)`; `acceptForEnqueue(url)`.
- [ ] `acquire` specified executably: inputs = canonical URL + resolved slice dir + options
  (auth/throttle context supplied by the shared driver); required outputs = media path(s),
  caption path(s), metadata object — never specified by yt-dlp invocation. Shared call sites
  that drive it: `acquisition/acquire.js` via `acquire-with-retry.js` (the generic spawn
  wrapper stays shared machinery).
- [ ] Declared attributes: `hosts` (registry keys); `extractorArgs` (string | null) **and**
  `comments` capability — BOTH `--write-comments` and `--extractor-args` at
  `build-yt-dlp-args.js:113-115` become adapter-declared, neither pushed unconditionally;
  `captionClass`; `errorPatterns` table; `transcriptStrategy` default; capabilities object
  (closed by default); reserved-unimplemented content-claim capability.
- [ ] **Result envelope defined in the contract file** (T6): a collection of 0..N entry
  results + a shared metadata object; arity is a property of the result, never the adapter; a
  convenience accessor may collapse at a call site, the contract never does; open metadata
  namespace with reserved `source:`-prefixed keys for source-specific fields; transcript
  travels as a replayable file path. 0-entry results are well-formed (metadata-only), never
  null, never a throw.
- [ ] Error taxonomy (T11) defined here: exactly **four** types — `UnsupportedSourceError`
  (dispatch-level, deliberately OUTSIDE the adapter error hierarchy), retryable source error,
  fatal source error, login-required. Degradation detail (e.g. 429-syndication) is **metadata
  on the retryable type**, never a fifth type. Concrete identifier names implementer's
  discretion.
- [ ] `validateAdapter` + factory; contract stability posture declared in-file (private,
  versioned with the plugin); construction performs no network/filesystem I/O (cheap pure
  normalization permitted).

**Registry (`extraction/adapters/registry.js`):**

- [ ] Static host-keyed map of **statically-imported** module references — never a computed
  dynamic import in any spelling (template, variable, concatenation, helper-mediated). The
  course-digest resolver shape (`config.js:44-51`, CWE-829/22) must not be replicated.
- [ ] Unknown host fails closed with the supported-source list; regex evaluated only after
  owned-host selection; subdomain handling defined and tested.

**YouTube adapter (`extraction/adapters/youtube.js`):**

- [ ] `extractVideoId` (from `acquire.js:116-138`) behind `matchUrl` / `extractSliceKey`
  (URL-authoritative, closing the redirect divergence).
- [ ] Preflight acceptance: the **whole** YouTube-shaped pattern set at
  `preflight-metadata.js:58-63` and `:226-227` moves behind `acceptForEnqueue` /
  `errorPatterns` — not just the `Incomplete YouTube ID` line — so none of it applies YouTube
  semantics to X.
- [ ] Link harvest incl. pinned comment; `extractorArgs =
  "youtube:max_comments=20,all,top;comment_sort=top"`; `comments` capability true;
  `errorPatterns` from `YOUTUBE_BOT_CHALLENGE_PATTERNS` (`acquire-yt-dlp-auth.js:8`).

**Shared rewiring:**

- [ ] `acquire.js` routes source-id + acquisition through the registry/adapter
- [ ] `build-yt-dlp-args.js:113-115` — comment flags + extractor-args from adapter declarations
- [ ] `preflight-metadata.js` stage-13 delegates to `acceptForEnqueue`
- [ ] `harvest-links.js` delegates to adapter `harvestLinks`
- [ ] `run-watch.js:95,105` — slice key from `extractSliceKey`; slug FORMAT stays in shared
  `deriveVideoSlug`
- [ ] Error classification: adapter `errorPatterns` consumed by the classification predicates
  in `spawn-yt-dlp-with-auth-fallback.js` (`:49` `isYoutubeBotChallengeError`, `:60`
  `isCookieProfileRetryableError` — the design's ":54 single site" citation names the spawn
  call; the predicates at :49/:60 are the actual seam, recorded here as a design-artifact
  precision fix, same intent). The **browser-cookie-profile fallback loop is gated on an
  adapter capability** — X (cookies-file only) must never iterate browser profiles. Cookie
  fallback fires on login-required classification only.

**Sanity Check:**

- [ ] Conformance-style unit test asserts every registry value is a statically-imported module
  object (no thenable/specifier strings) AND `git grep -n "import(" -- plugins/knowledge/skills/youtube-digest/extraction/adapters` → 0 rows
- [ ] Unknown-host unit test: dispatch of `https://vimeo.com/1` throws the dispatch-level
  unsupported-source error listing supported sources; exit non-zero via CLI wrapper test
- [ ] Envelope tests: 0, 1, and N entries constructed and consumed through both `watch` and
  `transcript` code paths (fixture-driven, offline)
- [ ] vitest exit 0; `npx tsc --noEmit` exit 0
- [ ] One-time evidence (NOT a merge gate): manual run `transcript <known yt-url>` produces a
  slice layout-identical to a pre-change run; diff summary saved to
  `.work/source-agnostic-video-digest/evidence/phase1/yt-parity.md`

### Phase 2: X adapter [TODO]

Review: security

`extraction/adapters/x.js` + registration:

- [ ] `matchUrl` claims `x.com` / `twitter.com` status URLs; **adapter-level canonicalization**
  re-derives the canonical status URL itself (T10 (ii)). Entry-path inventory it must cover
  (all reach dispatch through the shared seam): `run-watch.js` (`watch <url>`),
  `preflight-metadata.js` + `queue-claim.js` (`queue <url>` / `watch <n>`),
  `run-transcript.js`, `run-resume.js` / `watch-state.js` resume, and the recovery command
  emitted by `detect-recoverable-bootstrap.js` — canonicalization lives in the adapter so
  every path gets it by construction; test at least watch, queue, and transcript entries.
- [ ] `extractSliceKey` → pair `(display_id, id)`. **Canonical identity = `display_id`** (the
  URL status id — the design invariant "slice key is the id captured from the URL"); `id`
  rides as the media discriminator. Same pair → same slice (no duplicates). Tolerates the
  link-post branch where `id` = twid. Snowflake timestamp delta (`(id >> 22) + 1288834974657`)
  flags quote/retweet aliasing; a flagged aliasing is recorded in slice metadata. Fixtures:
  original post, quote tweet, retweet, link post.
- [ ] **Provenance guard**: any yt-dlp result whose `extractor` is not `twitter` is a
  **blocked delegation**, never followed (upstream #9715). The post itself then resolves as a
  0-video result (next item) — the guard blocks foreign media, it does not error the post.
- [ ] 0..N per `twitter.py`'s five branches: N → collection; 1 → single-entry collection
  (never bare-object); `/video/<n>` pinned index honored; 0-with-outbound-link → provenance
  guard blocks the delegation, post yields a well-formed metadata-only 0-result with the
  blocked link recorded in provenance/harvested links; 0-no-link → metadata-only 0-result.
  Both 0-cases produce a **text-only digest with populated provenance** (T6 D-A).
- [ ] `errorPatterns`: the three observed X failures (`No video could be found in this tweet`,
  `No video formats found!`, `Unsupported URL:`) → fatal-source (the first two are
  post-content facts; with the 0..N envelope the first typically resolves as a 0-result before
  spawn-level classification). **Login-required = exactly the three documented cases**
  (NSFW/age-restricted; protected account — cookie account must follow the author; any
  `not authorized` API message), all `raise_login_required`-shaped — only these gate the
  cookie fallback. Auth-dependence note carried into the source spoke: X auth-fallback
  windows are weeks-to-months, not days (design volatility measurement).
- [ ] **429 silent-degradation compound detector**: warning text `Rate-limit exceeded;
  falling back to syndication endpoint` AND/OR missing `*_count` metadata AND multi-media
  collapse to one entry → classified retryable (degradation metadata set), never success.
  Fixtures: degraded response (positive), legitimate single-video post (negative — must NOT
  flag), boundary (counts present but warning seen).
- [ ] `harvestLinks`: post-text links only (reply-chain harvest is agent-lane `/x:read`,
  optional — hub routing, Phase 6).
- [ ] Captions: `--write-subs` never `--write-auto-subs`; raw `LANGUAGE` subtitle keys
  (`en`, `en-US`, `en-GB`, `und`) — no hardcoded `subtitles['en']`; literal `<X-word-ms`
  detection with `--convert-subs srt` cleanup path; `captionClass` declares platform-ASR.
- [ ] `extractorArgs = null`; `comments` capability false; browser-cookie-fallback capability
  false (cookies file is the only auth route).

**Sanity Check:**

- [ ] Offline fixture tests exit 0 covering: slice-key pair + all four identity fixtures,
  provenance-guard block + 0-result production, both 0-case digest paths, compound 429
  detector (3 fixtures), error-pattern mapping incl. login-required-only cookie gating,
  canonicalization via watch/queue/transcript entries
- [ ] `git grep -n -e "automatic_captions" -e "write-auto-subs" -- plugins/knowledge/skills/youtube-digest/extraction/adapters/x.js` → 0 rows
- [ ] Storage invariant test: X slice + YouTube slice created under one queue root in a temp
  `--work-root`; both resolve; `QUEUE.md` claims namespace shared; no source directory level
- [ ] One-time evidence (NOT a merge gate): manual anonymous download of the design's verified
  public status; media + `.vtt` + `sourceUrl` recorded to
  `.work/source-agnostic-video-digest/evidence/phase2/x-live-probe.md`

### Phase 3: Transcript strategy seam [TODO]

`transcriptStrategy` = `captions` | `captions+repair` | `asr`; per-source default declared by
the adapter, pipeline-overridable.

- [ ] YouTube default `captions` — behavior unchanged for every existing user.
- [ ] `acquisition/select-caption.js` (shared ladder — editable, T12): consumes the adapter's
  declared `captionClass`; fixes X `.en.vtt` → `manual-en` misclassification; stage 2 stays
  shared.
- [ ] **Selection rule (binding):** X caption-present → `captions+repair`; X caption-absent →
  `asr` **whenever the ASR capability is available**; capability absent → explicit degradation
  (digest without transcript, degradation stated in a named provenance field), never silent.
- [ ] `captions+repair`: proper-noun repair over platform VTT; lexicon = post text
  (`description`) + harvested links.
- [ ] ASR rung: faster-whisper large-v3, `batch_size=8`; optional closed-by-default
  capability; delivery = documented optional prerequisite + runtime detection, no
  auto-install.
- [ ] **T5 probes — write a dated stub row here BEFORE running each; fill outcome after.**
  Evidence: `.work/source-agnostic-video-digest/evidence/phase3/`.
  - `[T5-ASR-ENTITY]` input: one known X clip with technical proper nouns; expected output:
    side-by-side entity transcription (X ASR vs faster-whisper); pass criterion: decision-grade
    verdict on entity fidelity (general WER is NOT an answer; "no advantage" is itself
    decision-grade). Governs any future upgrade to ASR-replace — no plan change either way.
  - `[T5-ASR-TIMESTAMPS]` input: known clip with platform VTT; expected: cue-boundary deltas;
    pass criterion: word-level timestamps usable for frame alignment (load-bearing — blocks
    the asr rung shipping as default-on for caption-absent if it fails; degradation path then
    covers caption-absent until resolved).
  - `[T5-ASR-LEXICON]` input: one clip with/without post-text `initial_prompt`; expected:
    entity-error delta; pass criterion: measurable proper-noun improvement → lexicon also
    feeds the ASR rung; else lexicon stays repair-only.

**Sanity Check:**

- [ ] Fixture: X `.en.vtt` classifies per declared class; YouTube classification tests
  unchanged and green
- [ ] Fixture: strategy resolution — per-source default; explicit pipeline override wins;
  caption-absent + capability-available selects `asr`; capability-absent exits 0 with the
  named provenance degradation field set
- [ ] Three probe rows present with dated stub + outcome (grep `T5-ASR-` in this file → 3
  rows with `outcome:` filled)

### Phase 4: Conformance suite + fixtures [TODO]

- [ ] Shared suite asserted once against the contract, star-imported into a thin per-adapter
  test file each adapter owns (SQLAlchemy shape).
- [ ] Capability declarations skew closed; **explicit test: a fixture adapter omitting every
  optional capability passes the suite** (absence is a declaration, not a failure).
- [ ] Runtime `validateAdapter` covers Phase 0's checker holes (method arity, required-method
  presence, attribute shapes).
- [ ] CI collision test: full-registry round-trip — each adapter's canonical example URL
  resolves to that adapter; duplicate/overlapping host claims fail (insurance for adapter
  three, stated as such).
- [ ] X golden eval fixture under `evals/` with defined assertions: expected 0..N result
  shape, slice-key pair, provenance fields; wired into the offline CI eval gate.
- [ ] Conformance = offline, fixture-based, CI-gated. Liveness lane = tracked follow-up work
  item (never on the merge path); file it in the tracker at phase close.

**Sanity Check:**

- [ ] Mutation probes: deleting a required method from a test double fails the suite;
  registering a second adapter claiming `x.com` fails the collision test
- [ ] CI green with suite + X golden eval wired into the existing extraction test step
- [ ] Tracker item for the liveness lane exists (search-before-create; record number here)

### Phase 5: Naming hygiene + env namespace [TODO]

Runs AFTER Phase 3 lands (shares `run-watch.js` / `acquire.js` territory with P1–P3 — see
Execution shape). Epic constant `YOUTUBE_WATCH_EPIC_DIR` **unchanged** per the storage
invariant.

**Display/staged-artifact hygiene:**

- [ ] `watch/watch-state.js:169,193` — resume-prompt paths render from the resolved slice dir,
  never the epic constant
- [ ] `watch/export-sheet-frame-index.js:75` — `"{tmp}/youtube-sheets-unknown"` → source-
  neutral literal
- [ ] Temp prefixes → `video-*`: `watching/run-watching-pipeline.js:33-34`
  (`youtube-frames-` / `youtube-sheets-`), `watch/run-watch.js:83-85` (incl.
  `youtube-extraction-`), `transcript/run-transcript.js:30` (`youtube-extraction-`)
- [ ] **KEEP** `acquisition/acquire-throttle.js:34` lock dir
  `youtube-extraction-acquire-locks` — stable cross-version coordination identifier (same
  A1 (4) rule as the epic constant; renaming it breaks mutual exclusion across the upgrade
  boundary and silently defeats `max_concurrent_acquires`). Recorded in Decisions table.
- [ ] Repo-wide staged-artifact literal audit (not just `extraction/`): any `youtube-`-named
  literal that can reach a **staged** artifact is fixed; every deliberate survivor gets a KEEP
  row with reason here

**Env namespace (A2 (c)) — all six, enumerated:**

| Old (read site) | New |
|---|---|
| `YOUTUBE_WORK_ROOT` (`lib/work-root.js:19`; forwarded by `run.mjs`; documented in SKILL.md work-root section) | `VIDEO_DIGEST_WORK_ROOT` |
| `YOUTUBE_YT_DLP_JS_RUNTIMES` (`acquisition/build-yt-dlp-args.js`) | `VIDEO_DIGEST_YT_DLP_JS_RUNTIMES` |
| `YOUTUBE_YT_DLP_COOKIES_FILE` (`acquisition/build-yt-dlp-args.js`) | `VIDEO_DIGEST_YT_DLP_COOKIES_FILE` |
| `YOUTUBE_YT_DLP_COOKIES_FROM_BROWSER` (`acquisition/build-yt-dlp-args.js`) | `VIDEO_DIGEST_YT_DLP_COOKIES_FROM_BROWSER` |
| `YOUTUBE_MAX_CONCURRENT_ACQUIRES` (`acquisition/acquire-throttle.js:23`) | `VIDEO_DIGEST_MAX_CONCURRENT_ACQUIRES` |
| `YOUTUBE_ACQUIRE_PHASE_GAP_SEC` (`acquisition/acquire.js:24` — also enters the `run-args.js` flag map + docs, closing the sixth-knob gap) | `VIDEO_DIGEST_ACQUIRE_PHASE_GAP_SEC` |

- [ ] One shared `resolveEnvWithLegacy(newName, oldName)` helper in `lib/`; **every read site
  above** resolves through it (new wins; old works and warns once per process — note
  `run.mjs` re-execs a child, so "once" is per-process by design; state that in the helper's
  doc comment)
- [ ] Writers updated: `lib/run-args.js` flag map sets the NEW names; `run.mjs` forwards new
  names
- [ ] `userConfig` keys keep their names; the four `"… (youtube-digest)"` titles change in
  Phase 7
- [ ] CHANGELOG deprecation for old names (folds into Phase 7's breaking entry)
- [ ] SKILL.md work-root/env documentation updates are **handed to the Phase 6 lane** as a
  reconciliation input (P6 owns skill markdown)

**Sanity Check:**

- [ ] `git grep -n "resolveEnvWithLegacy" -- plugins/knowledge/skills/youtube-digest/extraction` → ≥ 7 rows (helper + six read sites)
- [ ] Env compat tests: old alone works + warns once per process; new wins when both set; all
  six reachable (flag map test covers `--acquire-phase-gap`)
- [ ] `git grep -n -e "youtube-sheets-unknown" -e "youtube-frames-" -e "youtube-sheets-" -e "youtube-extraction-" -- plugins/knowledge/skills/youtube-digest/extraction ':!*acquire-throttle*'` → 0 rows (lock-dir KEEP excluded)
- [ ] Fixture: X resume prompt contains resolved slice path; zero epic-constant prose
  interpolations

### Phase 6: Hub split + widened description [TODO]

Warrant: **body** 37,620 chars ≈ 9,405 est. tokens ≈ 1.9× the < 5,000-token recommendation
(chars/4; the repo's own fleet-measurement method). The 200-line soft cap is NOT the warrant.

- [ ] Execute the hub-split-budget.md moves table (the single authoritative partition):
  Watch action 148 → ~30-line phase spine (rest → `context/watch-pipeline.md`); Queue 61 → ~8
  (→ `context/watch-queue.md`); Output contract + artifact landing → new spoke; yt-dlp &
  throttle overrides → `reference/sources/youtube.md`; slug derivation + eval fixtures trimmed
- [ ] Source spokes: `reference/sources/{youtube,x}.md`; any spoke > 100 lines gets a TOC
- [ ] Hub routing table: **explicit conditional rows** — "read `reference/sources/x.md` when
  the URL is an x.com/twitter.com status", "read `reference/sources/youtube.md` when the URL
  is YouTube", "read `context/watch-pipeline.md` for the watch action only". A `transcript`
  run loads no watch spoke; a YouTube run loads no X file; `/x:read` reply-chain harvest
  routed here as optional
- [ ] `reference/variation-matrix-backlog.json` disposition decided (KEEP in place —
  `vendor/video-digestion/TUNING.md:5` points at it; if it moves, Phase 7 inventory gains
  that row)
- [ ] Widened `description` (T2a, `xlsx` shape): four literal hosts + **natural-language
  triggers** ("watch this video", "digest this video/post", etc.) + explicit `Do NOT` clause
  naming course platforms (preserves `course-digest` boundary); retains `youtube` /
  `youtu.be` tokens; third person
- [ ] **Record the pre-change trigger-token baseline** (the current description's token set)
  to `.work/source-agnostic-video-digest/evidence/phase6/trigger-token-baseline.md` — Phase
  7's manual continuity check validates against this artifact
- [ ] X source section added to the hub within budget
- [ ] **Reconciliation gate (before Phase 7):** after P3 lands, diff the spokes' claims
  (adapter behavior, error semantics, ASR/degradation, env-var names from P5) against the
  final contract + fixtures; fix drift. Parallel drafting is allowed; this gate is what makes
  it safe

**Sanity Check:**

- [ ] Body size: chars after frontmatter ÷ 4 < 5,000 (small Node/awk snippet, checked in with
  the sweep script or run in Git Bash; record the number here)
- [ ] `check-skill.sh` exit 0 on the skill
- [ ] Blocking routing assertion (not check 15, which only warns): every file under
  `reference/sources/` and every `context/*.md` spoke is cited in SKILL.md **with a
  conditional "when" clause** — script-checked, not eyeballed
- [ ] Description: contains all four hosts, ≥ 2 natural-language trigger phrases, a `Do NOT`
  line naming course platforms, `youtube`, `youtu.be`; combined `description` +
  `when_to_use` frontmatter fields ≤ 1,536 chars (the check-skill DESC_CHAR_CAP definition)
- [ ] Reconciliation gate outcome recorded here (dated line)

### Phase 7: Rename `youtube-digest` → `video-digest` [TODO]

Deliberate breaking change (T2b). Terminal phase. **Resume note: the `git mv` commit is the
point of no return — after it, the pre-flight baseline command targets the NEW directory and
CI is red until the ci.yml rows land; a resuming session mid-phase continues the inventory,
never re-runs pre-flight against the old paths.**

**Pre-flight (FIRST item — reproducible baseline):**

- [ ] Run: `git grep -c "youtube-digest" -- ':!docs/topics' ':!.work'` and record file+
  occurrence counts here (approval-time measure: 30 files / 112 occurrences repo-wide
  incl. the skill dir; in-skill: 14 files / 65). Any file NOT in the inventory below gets a
  row before the sweep proceeds. (`docs/topics/` and `.work/` are excluded as immutable
  historical/session records — Decisions table.)
- [ ] Pre-check the CI job id: `gh api "repos/{owner}/{repo}/branches/main/protection"` (or
  rulesets) — is `youtube-extraction` a required status check? Required → KEEP job id with
  comment; not required → rename job id alongside the paths. Record outcome here.

**Structural move (single commit):**

- [ ] `git mv plugins/knowledge/skills/youtube-digest plugins/knowledge/skills/video-digest`
- [ ] Frontmatter `name:` — per the FALLBACK decision below (default: NO pin; T2b term
  deviation recorded with evidence)

**In-skill content sweep (14 files / 65 occurrences — same commit series):**

- [ ] `SKILL.md` (23 occ — self-references become `/knowledge:video-digest`; the
  `${CLAUDE_PLUGIN_ROOT}/skills/video-digest/extraction/run.mjs` launcher lines)
- [ ] `watch/watch-state.js:2,145,158` — **user-facing**: `:158` emits
  `# Continue /youtube-digest watch` into resume prompts (same failure class as the recovery
  command)
- [ ] `watch/detect-recoverable-bootstrap.js:112` — the twelfth entry point: emits
  `skills/youtube-digest/extraction/run.mjs` into a user-run recovery command
- [ ] `watch/run-watch.js:3`, `watch/run-resume.js:3`, `lib/slice-lanes.js:2` (comments/docs)
- [ ] `context/*.md` (5 files), `templates/*.md` (2 files), `evals/evals.json`

**Outside-skill sweep:**

- [ ] `plugins/knowledge/.claude-plugin/plugin.json` — **4 occurrences, all userConfig
  titles** (`:44,50,56,62`; no skill-path key exists — discovery is by directory)
- [ ] `plugins/knowledge/.claude-plugin/plugin.json` — `keywords`: add `x`/`twitter`/`video`;
  plugin `description` updated off "YouTube pipeline" (marketplace discoverability)
- [ ] `plugins/knowledge/CHANGELOG.md` (new entry; historical entries KEEP verbatim)
- [ ] `plugins/knowledge/README.md`, `skills/setup/SKILL.md`, `skills/docpage-digest/SKILL.md`,
  `skills/map-corpus/SKILL.md`
- [ ] `.github/workflows/ci.yml` — **5 occurrences** (`:855` comment, `:888`
  cache-dependency-path, `:892,896,900` working-directory); job id per pre-check
- [ ] `scripts/docs-only-paths.txt:21` — inertness-proof comment path updated; re-run
  `scripts/check-docs-only.test.sh`
- [ ] `docs/knowledge-integration-design.md:12`, `docs/MIGRATION-PLAYBOOK.md:1455`,
  `docs/CLOUD-SESSIONS.md`
- [ ] `extraction/package.json` — per the FALLBACK decision below (default: rename
  `@melodic/youtube-extraction` → `@melodic/video-extraction` + description; regen lockfile;
  ci.yml cache key rides the path change)

**`course-digest` mechanical refs (the exemption's exhaustive enumeration):**

- [ ] `course-digest/SKILL.md:2` (description — verify no course-digest trigger-keyword
  regression via `check-skill.sh` on course-digest)
- [ ] `course-digest/SKILL.md:138`
- [ ] `course-digest/context/storage-schema.md:7`
- [ ] `course-digest/evals/evals.json:19,21,25` (case renamed
  `youtube-url-routes-to-video-digest-skill` + expected_output + criterion)
- [ ] `course-digest/reference/adapters/discovery-checklist.md:65,221`
- [ ] `course-digest/extraction/setup-deps.mjs:50` (comment)

**Vendored stragglers (sweep regression set — fix regardless):**

- [ ] `vendor/video-digestion/README.md:5` (`/youtube`)
- [ ] `vendor/repo-analysis/README.md:5` (`/youtube`)
- [ ] `vendor/video-digestion/TUNING.md:55` (`/youtube`)
- [ ] `vendor/video-digestion/TUNING.md:5` (path ref
  `skills/youtube-digest/reference/variation-matrix-backlog.json`)

**Breaking-change discipline:**

- [ ] CHANGELOG breaking entry naming the **five silent consumer surfaces**: cloud routines;
  scheduled tasks / `/loop`; `Skill(knowledge:youtube-digest)` permission rules (exact-match —
  a **deny rule fails open**); Agent SDK `skills:` allowlists (the one loud failure);
  bare-`/name` squatting / docs. Plus the env-name deprecations (Phase 5).
- [ ] Out-of-band announcement (release notes / PR body) with a migration line per surface
- [ ] `plugin.json` version 0.12.0 → 0.13.0
- [ ] Manual trigger-token continuity check against the Phase 6 baseline artifact (the HEAD
  keyword diff is blind post-rename); result recorded here

**Sweep script (checked in, e.g. `extraction/scripts/` or repo `scripts/` per conventions):**
`git grep -n "youtube-digest" -- ':!.git' ':!docs/topics' ':!.work'` filtered by an **explicit
inline allowlist**: CHANGELOG historical entries; this PLAN's own baseline lines. Exit
non-zero on any other hit. Self-test seeds a stale ref in a temp file under `vendor/` and
asserts the sweep catches it.

**Sanity Check:**

- [ ] Sweep script exit 0; its self-test (seeded `vendor/` ref) exits non-zero
- [ ] `git grep -n "/youtube\b" -- plugins/knowledge/vendor` → 0 rows (Git Bash)
- [ ] `git grep -c "youtube-digest" -- .github/workflows/ci.yml` → 0 (static assertion — CI
  green alone does not prove textual migration)
- [ ] `bash scripts/check-docs-only.test.sh` exit 0
- [ ] `check-skill.sh` exit 0 on `video-digest` AND on `course-digest`
- [ ] Fixture tests: `detect-recoverable-bootstrap` emits the new path; `watch-state` resume
  prompt emits `/knowledge:video-digest`
- [ ] CI green on the branch

## Blast radius

**HIGH.** Published marketplace plugin; breaking rename with five silently-failing consumer
surfaces (deny rules fail open — security-relevant); CI workflow changes; 30+ files outside
the skill dir; new cross-cutting contract. Mitigants: no on-disk data migration (storage
invariant); rename isolated to the terminal phase with a self-tested sweep script; CI loud on
path misses; conformance suite offline and CI-gated.

## Stress-test summary

Two independent reviews of the draft, 2026-08-15; all findings verified against the tree
before adoption:

- **Codex (cross-vendor, /codex:rescue; artifacts inlined after a sandbox failure):** 3
  CRITICAL / 16 IMPORTANT / 2 SUGGESTION. Adopted: 0-with-link semantics (T6), storage
  invariant stated + tested, envelope schema + consumer pre-flight, acquire call-site
  definition, static-import verification, canonical identity rule, four-type taxonomy
  clarity, three login-required cases, compound 429 detector, mandatory strategy selection +
  probe pass criteria, entry-path inventory, six env vars enumerated, P5 serialization,
  Git-Bash-only sanity commands, live probes demoted to evidence, resumability
  (evidence paths + IN-PROGRESS + mid-P7 note), static ci.yml assertion, description checks,
  blocking routing assertion, capability-absence fixture, doc reconciliation gate. Rejected
  (verified false): "plugin.json has a skill path key" (4 title occurrences only);
  "select-caption.js not named" (it was).
- **Devils-advocate (fresh-context sub-agent):** 2 CRITICAL / 4 HIGH / 9 MEDIUM / 5 LOW.
  Adopted: P5 fence rewritten to the six env READ sites; `.work/` + `scripts/docs-only-paths.txt`
  in the sweep scope; `youtube-extraction-` prefix + `run-transcript.js:30`; lock-dir KEEP;
  in-skill 14-file/65-occurrence sweep + `watch-state.js:158`; `name:` pin re-decided (gate
  evidence contradicts the pin's rationale — FALLBACK row); reproducible pre-flight baseline;
  `--write-comments` adapter-declared; predicates `:49`/`:60` as the real classification seam
  plus browser-fallback capability gate; `TUNING.md:5` path ref; `@melodic/youtube-extraction`
  package identity decision; ci job-id/branch-protection pre-check; preflight `:58-63` full
  pattern set; token-basis fix (body-only). Rejected (verified false): caps line-number
  correction (they ARE at `:175-177`).

## Execution shape

### Dependency graph

- P0 → P1 → P2 → P3 → P4 (contract chain)
- P5 after P3 (shares `run-watch.js`, `acquire.js`, `run-transcript.js` territory with P1–P3);
  may run parallel with P4 (P4 = test/eval files; P5 = the enumerated source files)
- P6 drafts parallel to P2–P5; its **reconciliation gate** (post-P3, incl. P5's env names)
  must pass before P7
- P7 terminal, gated by all

### Recommended shape

> Wave A: P0 (solo gate)
> Wave B (parallel, 2 lanes): {P1 → P2 → P3} ∥ {P6 drafting}
> Wave C (parallel, 2 lanes): {P4} ∥ {P5}, then P6 reconciliation gate
> Wave D: P7 (solo)
> Cost note: 2 parallel lanes ≈ 2× token burn during Waves B/C; the saving is the full
> markdown lane off the critical path.

Sequential fallback: on any scope-fence violation, concurrent-edit race, or cannot-complete
report, abort the affected agent and run its phase sequentially at the next wave boundary;
other lanes continue.

### Per-phase routing

| Phase | Surface | Basis |
|---|---|---|
| 0 | sub-agent worker | mechanical flip + diagnostic fixes; escalates if any fix would need a suppression |
| 1 | main-session | judgment-heavy: contract authorship, security posture, shared rewiring |
| 2 | main-session | judgment-heavy: provenance guard, degradation detection, identity rules |
| 3 | main-session | design-adjacent seam + manual probes |
| 4 | sub-agent worker | suite shape fully specified; mechanical once contract is fixed |
| 5 | sub-agent worker | enumerated sites; fence below |
| 6 | sub-agent worker | measured moves table; fence below; reconciliation gate verified main-session |
| 7 | sub-agent worker | checkbox-inventory sweep; fence below |

**Scope fences (ALLOWED whitelists; everything else FORBIDDEN, incl. PLAN.md — main session
edits status tags only — and commit/push):**

| Agent | ALLOWED |
|---|---|
| P0 | both `extraction/` trees (tsconfig + JSDoc-only edits) |
| P4 | `extraction/adapters/*.test.js`, new suite files, `evals/**`, CI test-step wiring |
| P5 | `lib/work-root.js`, `lib/run-args.js`, `lib/` (new env helper), `acquisition/build-yt-dlp-args.js`, `acquisition/acquire-throttle.js` (env only — lock dir KEEP), `acquisition/acquire.js` (env line only), `run.mjs`, `watch/watch-state.js`, `watch/export-sheet-frame-index.js`, `watching/run-watching-pipeline.js`, `watch/run-watch.js` (temp-prefix lines only), `transcript/run-transcript.js` (temp-prefix line only), plus co-located tests |
| P6 | `skills/youtube-digest/{SKILL.md,context/**,reference/**}` only |
| P7 | the checkbox-inventory rows exactly, `skills/video-digest/**` (in-skill sweep), the sweep script |

Every worker brief carries the divergence-escalation clause verbatim (planning plugin
plan-template.md).

## Decisions made (gate-passed)

| Decision | What it changes in the plan | Basis |
|---|---|---|
| [EXEC-SHAPE] Rename terminal (P7) | One sweep; CI paths break in exactly one commit series | T2a design-bound "strictly prior to rename"; minimal churn |
| [EXEC-SHAPE] P5 serialized after P3; two-lane Waves B/C | Routing + fences above | Verified file overlap (`run-watch.js`, `acquire.js`, `run-transcript.js`) |
| [EXEC-SHAPE] Temp prefixes → `video-frames-` / `video-sheets-` / `video-extraction-` | Phase 5 literals | Matches new skill name; any source-neutral literal satisfies the design |
| [EXEC-SHAPE] Error-type identifier names implementer's discretion | Phase 1 detail | Design delegates "concrete identifier names are PLAN-level detail" |
| [EXEC-SHAPE] KEEP `youtube-extraction-acquire-locks` lock dir | Phase 5 exclusion | Stable cross-version coordination identifier — renaming breaks mutual exclusion across the upgrade boundary (A1 (4) rule; verified `acquire-throttle.js:34`) |
| [EXEC-SHAPE] Classification seam = predicates `:49`/`:60`, not the `:54` spawn call; browser-fallback gated on adapter capability | Phase 1 wiring | Verified in `spawn-yt-dlp-with-auth-fallback.js`; design's ":54" cites the spawn line — same intent, precise seam |
| [FALLBACK — confirm or override] `docs/topics/**` and `.work/**` KEEP their `youtube-digest` refs (immutable historical/session records); sweep excludes both | Phase 7 scope | Repo precedent (`shadowed-skill-renames/PLAN.md:32` retains pre-rename names); `.work/` is git-tracked here and contains 6 research files with the literal |
| [FALLBACK — confirm or override] **Drop the `name:` pin** — deviates from T2b's recorded "pin `name: video-digest`" term | Phase 7 frontmatter row | Verified gate evidence: `check-skill.sh:284` hard-FAILs a name≠directory mismatch, so the pin cannot buy future directory-rename freedom in this repo, and a matching pin draws a WARN + registers the bare `/video-digest` alias — the same squatting surface the breaking-change list flags. If the bare alias is wanted, override to "pin, same commit as `git mv`, alias rationale recorded" |
| [FALLBACK — confirm or override] Rename npm package `@melodic/youtube-extraction` → `@melodic/video-extraction` (+ description, lockfile regen) | Phase 7 row | Package identity survives every grep sweep otherwise; verified `package.json:2,6`. KEEP-with-reason is the cheaper alternative if lockfile churn is unwanted |
| [FALLBACK — confirm or override] CI job id `youtube-extraction`: decided by the branch-protection pre-check (required check → KEEP + comment; else rename) | Phase 7 pre-flight | Job id invisible to sweeps; protection state not readable from the worktree — `gh` check required |
| [FALLBACK — confirm or override] Plugin version 0.12.0 → 0.13.0 (pre-1.0 minor-as-breaking) + keywords/description refresh | Phase 7 rows | SemVer 0.x convention; no marketplace doc found mandating otherwise |
| [FALLBACK — confirm or override] ASR = documented optional prerequisite + runtime detection, never auto-install | Phase 3 delivery | T5: optional closed-by-default capability with explicit degradation; auto-install lands a multi-GB dependency the design rejected for existing users |

## Open questions

- None blocking. The `[T5-ASR-*]` probes run inside Phase 3 with recorded outcomes; the CI
  job-id question resolves via the Phase 7 pre-check.

## Handoff to implementation

### User-approval gates

- ~~The six `[FALLBACK]` rows above — confirm or override at plan approval.~~ Approved
  2026-08-15, RECOMMENDED options as recorded in the Status line.
- Any scope expansion beyond type-annotation-only edits in `course-digest` — STOP and surface.
- Any suppression (`@ts-ignore` etc.) — explicit approval + recorded justification.
- Mid-flight pivots that change acceptance criteria — dated scope-change note here + ask.

### Execution shape ([EXEC-SHAPE] tagged)

Waves, routing, and fences as in "Execution shape". PLAN.md is main-session-only; workers
report back.

### Mechanical work

- Commit boundaries: ≥ 1 commit per phase; Phase 7 splits the `git mv` (structural) from the
  reference sweep (Tidy First); PLAN status-tag updates ride each phase's commit.
- Verification: phase Sanity Checks gate each boundary; `npx tsc --noEmit` + vitest + affected
  eval checks at every boundary.
- The Phase 7 sweep is a checked-in, self-tested script — never copy-paste commands.
- Close-out at PR time via `/planning:plan close-out` (PLAN into PR body `<details>`, ADR
  graduation, prune slice with pointer). ADR candidates (write when the decision crystallizes):
  static-registry dispatch (T3) and the storage-format-identifier rule (A1 (4)) — both pass
  the hard-to-reverse / surprising / real-trade-off test.
