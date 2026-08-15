# RESEARCH — extractor-architecture prior art for a source-adapter contract

## Task restatement

Establish the canonical prior art for ONE-PIPELINE-N-SOURCES extractor architectures and what it
teaches about designing a source-adapter contract, anchored on yt-dlp — which solves this problem at
the largest scale in existence and which the pipeline in question literally shells out to. Six
sub-questions: `_VALID_URL` + `suitable()` dispatch from a bare URL; the required-vs-provided boundary
of the `InfoExtractor` base class; the granularity of the acquisition seam (one coarse `extract()` vs
many fine hooks) and how per-site quirks avoid duplicating shared retry/throttle machinery; the
standardized info-dict result shape including `_type: playlist` and 0/1/N media per container;
maintainer hindsight on what the contract got wrong; and a contrast survey of at least two other
mature multi-backend extraction systems.

The output decides the adapter method set, the required-vs-optional boundary, the dispatch mechanism,
and the granularity of the acquisition seam. Consumer is the design's thread set, then an
implementation plan. Deliver transferable contract-design rules, not a description of yt-dlp.

## Sidecars

| Section | Abstract | File |
|---|---|---|
| dispatch | URL-regex dispatch degrades into a hand-maintained host registry at scale; declarative host-keyed claims plus one CI collision test is the transferable shape, with an explicit trigger for adding priority later. | [`RESEARCH-dispatch.md`](RESEARCH-dispatch.md) |
| required-vs-provided | The required surface across three mature systems is exactly what the registry cannot infer — a claim, a proof-of-routing example, and one extract method; everything else is a defaulted class attribute. | [`RESEARCH-required-vs-provided.md`](RESEARCH-required-vs-provided.md) |
| granularity | All three mature systems converge on ONE coarse extract method plus an inverted-control intermediate base; per-source quirks are expressed as class attributes, namespaced config, and at most one predicate inside a shared loop — never duplicated machinery. | [`RESEARCH-granularity.md`](RESEARCH-granularity.md) |
| result-shape | yt-dlp's TwitterIE solves the 0/1/N-videos-per-post problem for our exact second source in five branches; take all five cases but reject its arity collapse, and give the four error states distinct types from day one. | [`RESEARCH-result-shape.md`](RESEARCH-result-shape.md) |
| hindsight | yt-dlp writes no retrospectives — its regret is expressed as rewrites, and the 2025 PoTokenProvider framework by the same team inverts every design axis of InfoExtractor, which is the closest thing to its own answer to "what would you do differently". | [`RESEARCH-hindsight.md`](RESEARCH-hindsight.md) |
| contrast-systems | Five contrast systems establish that scored dispatch is an upgrade forced by key collision, not handler count — and gallery-dl's BaseExtractor solves the self-hosted-instance problem yt-dlp has left open for four years, by compiling a user-extensible host table into the pattern. | [`RESEARCH-contrast-systems.md`](RESEARCH-contrast-systems.md) |

Coverage ledger and falsification queries: [`research-checklist.md`](research-checklist.md).

## Section → anchor map

| Question | Sidecar | Anchor |
|---|---|---|
| How does a bare URL reach the right adapter? | `RESEARCH-dispatch.md` | *How yt-dlp actually dispatches* |
| How do ordering and ambiguity resolve? | `RESEARCH-dispatch.md` | *Precedence was ultimately promoted to a runtime knob* / *A collision detector beats a collision policy* |
| What happens on no-match? | `RESEARCH-dispatch.md` | *How yt-dlp actually dispatches* (`report_error`); `RESEARCH-contrast-systems.md` → *The fallback tail* |
| Regex vs host registry? | `RESEARCH-dispatch.md` | *Falsification: does regex dispatch beat a host→adapter registry?* |
| What does the base demand vs provide? | `RESEARCH-required-vs-provided.md` | *What each system actually demands* |
| Why does that line sit there? | `RESEARCH-required-vs-provided.md` | *The rule the three systems jointly establish* |
| One coarse method or many hooks? | `RESEARCH-granularity.md` | *The three systems converge from different directions* |
| Per-site quirks without duplicating machinery | `RESEARCH-granularity.md` | *Per-site quirks without duplicating machinery — three tiers* |
| Site-specific tunable args | `RESEARCH-granularity.md` | *Per-adapter config: namespace it, but DECLARE it* |
| Info-dict shape and `_type` semantics | `RESEARCH-result-shape.md` | *The info dict* / *`_type` semantics* |
| 0, 1, or many media per container | `RESEARCH-result-shape.md` | *Arity — the crown jewel* |
| Error classification | `RESEARCH-result-shape.md` | *Error classification — the strongest convergence* |
| Maintainer hindsight | `RESEARCH-hindsight.md` | all |
| Contrast systems | `RESEARCH-contrast-systems.md` | all |

## Next-stage handoff

### Settled facts — documented, Tier 0/1

1. **yt-dlp dispatch is first-match-wins over an ordered dict of extractors**, with `suitable()`
   defaulting to a `_VALID_URL` regex match. No scoring, no explicit priority, no ambiguity detection.
   The one ordering fact that matters — `GenericIE` last — is *asserted* in the codegen script, not
   commented. `YoutubeDL.py:1706-1725`, `common.py:616-632`, `make_lazy_extractors.py:84`.
2. **Regex-on-URL dispatch does not avoid a host registry — it becomes one, by hand.** Measured over
   940 extractor modules at `5d6b8c8`: 74 `suitable()` overrides, 88 cross-extractor `suitable()` call
   sites, 54 files needing a negative-lookahead `_VALID_URL`. `YoutubeIE.suitable()` dispatches on the
   **query string**, which the regex cannot model.
3. **The required surface is two things: `_VALID_URL` and `_real_extract`.** The latter is the only
   `NotImplementedError` in the 4,176-line base class. Roughly 200 other methods are helpers the base
   provides free. Peers agree on shape: gallery-dl requires `pattern` + `example` + `items()`;
   streamlink requires `_get_streams()` + ≥1 `@pluginmatcher` + a `__plugin__` export.
4. **The acquisition seam is one coarse method plus four optional lifecycle stubs.** `extract()` and
   `initialize()` are template methods owning geo-bypass retry, error tagging, and login ordering.
   Streamlink has exactly one abstract method across 135 plugins; gallery-dl offers both a coarse seam
   and an inverted-control intermediate that reduces a leaf adapter to six lines.
5. **Per-site quirks are attributes, namespaced config, and at most one predicate inside a shared
   loop.** gallery-dl's `_handle_429` is the model — the only such override across 257 modules.
6. **The info dict requires only `id`, `title`, and one of `formats`/`url`.** `_type` ∈ {absent/`video`,
   `playlist`, `multi_video`, `url`, `url_transparent`}, each specified in prose only.
7. **`TwitterIE` already solves 0/1/N for our exact second source, in five branches** —
   `twitter.py:1348-1390` — including delegating to another adapter when a post has no video but an
   outbound link, and returning a metadata-only result when it has neither.
8. **yt-dlp derives adapter arity from test fixtures** (`_RETURN_TYPE`, `common.py:3822-3832`) and
   drives user-facing behaviour off that inference.
9. **The extractor plugin API has no stability statement anywhere**, while the same team's 2025
   `PoTokenProvider` framework leads with a declared three-module public surface and inverts every other
   design axis too.
10. **Per-extractor network `_TESTS` are excluded from CI**; every workflow runs `pytest -m 'not
    download'`.
11. **Scored dispatch is an upgrade forced by key collision, not handler count.** A hostname is a unique
    key; a file extension and a MIME type are not.

### Recommendations this research supports

| # | Recommendation | Strength |
|---|---|---|
| R1 | Declarative, **host-keyed** claims; no scoring, no priority scale; regex only *within* a host an adapter owns | strong — 74/88/54 counts + gallery-dl's working counter-example |
| R2 | One **CI collision test**: every adapter ships a canonical example, round-tripped through the full registry | strong — two independent instances (gallery-dl `test_init`, Tika `findDuplicateParsers`) |
| R3 | Required surface = a claim + an example + one extract method. Everything else defaulted | strong — three-system convergence |
| R4 | **Declare arity**; return a uniform 0..N collection; never collapse 1 to a bare object | strong — this is a *departure* from yt-dlp, justified by `_RETURN_TYPE`'s existence |
| R5 | Four error states, four **distinct types**, from day one | strong — streamlink's in-tree `# TODO` admission is the only documented regret in the corpus |
| R6 | Per-adapter config **namespaced AND declared** (streamlink's `@pluginargument`), never a stringly-typed bag | strong — yt-dlp's is now unfixable |
| R7 | Construction does no work; make it an executable invariant | strong — three independent post-mortems |
| R8 | Fixed envelope + **open metadata namespace**; transcript as a replayable file path | moderate — inferred from the streaming/whole-object split |
| R9 | Name the public surface on day one | strong — yt-dlp's own 2025 correction |
| R10 | Split contract-conformance tests (offline, CI-gated) from liveness tests (scheduled, alerting) | strong — yt-dlp's CI config settles it |

### Open decisions — this research cannot decide them; they are product calls

1. **What a post with no video should produce.** `TwitterIE` gives two precedents: delegate to another
   adapter if there is an outbound link, else emit a metadata-only result flagged `expected=True`. The
   digest analogue — empty digest vs error vs text-only digest — is the pipeline owner's call. The
   contract's only obligation is that **all three be expressible without an exception escaping**.
   *RECOMMENDED: text-only digest with populated provenance, matching Tika's `EmptyParser` posture (a
   well-formed empty result, never a null or a throw), because it removes a special case from every
   downstream consumer.*
2. **Where yt-dlp sits in the new architecture.** The pipeline already shells out to it, so yt-dlp is
   the acquisition mechanism for both YouTube and X *today*. gallery-dl's `ytdl` extractor is the direct
   precedent: an adapter whose entire implementation is delegation to another whole system, registered
   like any other and positioned near-last. **This changes what the method set must contain — the
   contract must not assume adapters do their own HTTP.**
   *RECOMMENDED: model yt-dlp as one adapter among N rather than as the substrate, so a future
   non-yt-dlp source (an API-only source, a local file) needs no contract change.*
3. **Whether to reserve a content-claim capability now.** yt-dlp bolted one on in 2022 at the cost of a
   4,189→1,303-line dispatcher rewrite, and expressed it by overloading `_VALID_URL = False`.
   *RECOMMENDED: reserve it as a separately-declared capability that today no adapter implements, rather
   than either building it now or overloading the URL-claim field later.*

### Seam for the sibling `internal-precedent` lane

These rules are deliberately source-agnostic and do not reference the in-repo Playwright-shaped course
adapter. The composition seam: the required-vs-provided table and the granularity recommendation are the
**criteria against which the incumbent contract should be judged**, not a template to compare it to.
Incumbency is evidence of what is, never an argument for what should be.

## Gaps and caveats

- **Babel and unified/remark were cut** from the contrast set with reason recorded; both dispatch by an
  explicit user-supplied plugin list, so they do not bear on inferring a handler from a bare URL.
- **Delegated-agent tiering.** Four sub-topics were researched by dispatched general-purpose subagents,
  not by `discovery:researcher` runs, so `discipline.md`'s scoped Tier-3 exception does not cleanly
  apply. Their findings are cited at **Tier 0/1 only where a specific file path, line range, or
  issue/PR URL was captured**; bare synthesis from those returns is not carried as an accepted claim.
  The yt-dlp core reading (dispatch, base class, lifecycle, result helpers, error helpers, `_RETURN_TYPE`,
  embed layer, `_configuration_arg`, `_yes_playlist`, `TwitterIE` arity, all four grep counts) was done
  first-hand in this context and is Tier 0.
- **Marked inferences, not documented:** the FFmpeg MIME-bonus exploit path (arithmetic verified, no CVE
  found); streamlink's `NO_PRIORITY` intent (mechanism verified, no built-in uses it, no doc explains
  it); the reading that regex dispatch "degrades into a hand-written registry" (the counts are
  documented, the characterization is mine); the reason yt-dlp never formalized the info dict.
- **Absence-of-evidence findings are reported as such**, not as rejection — most importantly that no
  yt-dlp maintainer has ever publicly proposed host-based dispatch, and that the repo has GitHub
  Discussions disabled so no such corpus exists.
- **Version pinning:** yt-dlp `5d6b8c8` (2026-08-04); gallery-dl `86047cf6` (v1.32.9); streamlink
  `c3c2e98` (2026-08-12); Apache Tika 3.3.2 with 4.0.0-beta drift flagged; FFmpeg and Pygments at
  `master`/`main` as of 2026-08-14, Pygments empirical results from 2.20.0.

---

## Parent-side rows (written by the dispatching session)

### Verifier verdict — ACCEPT with corrections

An independent verifier (independent of this producer) cloned yt-dlp at the same pinned `5d6b8c8`
and reproduced the measurements rather than reading them.

**Every count reproduced**, with two figures corrected: **55** negative-lookahead files, not 54; and
`YoutubeIE._VALID_URL` is **2,582 bytes (2.5 KB)**, not ~2.7 KB. The self-imposed tiering rule was
checked mechanically — every `url:` source across all six sidecars carries a captured citation, zero
bare synthesis, zero Tier-2 claims.

**Four of ten recommendations needed their justification rebuilt; only one conclusion changed.**

| Row | Outcome |
|---|---|
| **R1** dispatch | **Conclusion survives, stated reason WITHDRAWN.** The 74/88/55 counts measure *within-host* disambiguation (73/74 overrides sit in multi-extractor files for one site; only 15 of 88 cross-module calls are genuinely cross-module) — which the recommendation *keeps*. Read plainly the data is mild counter-evidence. Cite gallery-dl's `BaseExtractor` and the static-index measurements instead. **Do not cite the counts.** |
| **R4** declare arity | **Split.** "Never collapse 1" survives and strengthens. "Declare arity **per adapter**" fails: `twitter.py` declares no `_RETURN_TYPE`, resolving to `'any'`, because **X's arity is a property of the post, not the adapter**. |
| **R7** construction | **"No I/O", not "no work"** — the looser form contradicted the recommended canonicalize-in-constructor technique. |
| **R8** envelope | **Re-derived.** Streaming premise was backwards (this pipeline is in yt-dlp's metadata-plus-paths category). Re-grounded on Tika replayability + open-vocabulary; rating raised to strong. |
| **Open decision 2** | **Strong form withdrawn.** "Model yt-dlp as one adapter among N" is vacuous or false here — gallery-dl's `ytdl` is a *last-resort escape hatch*, off by default behind an explicit `ytdl:` prefix, the opposite role. The weak form survives: specify `acquire` by its **outputs**, not by yt-dlp invocation. |

Everything else attacked held, including the two items pre-registered as most suspicious.

### Project fit — N=2, not 940

The prior art is drawn from systems with 920–940 handlers. Sized for this lane:

**Adopt:** declared arity (R4) — the highest-value row here and **not scale-driven**, since X
specifically has the 0/1/N problem; four distinct error types (R5) — three observed X failures plus
YouTube's bot-challenge class already exist; declared namespaced config (R6) — the fix for the
`YT_DLP_EXTRACTOR_ARGS` defect; CI collision test (R2) as **insurance, not present value**.

**Explicitly out of scope:** the lazy static index / codegen layer (exists because regex compilation
is ~80% of startup across 940 modules); the registered-but-not-dispatched `_WORKING` state; runtime
extractor reordering; scoring or priority scales.

**Transfer risk:** every contrast system is **Python** with runtime class registration and metaclass
machinery. This lane is **plain ESM with JSDoc and vitest**. The *shapes* transfer — declarative
claim, canonical example, one extract method, validate-and-resolve factory. **None of the
registration mechanisms do.** Lift the contract shape, not the machinery.
