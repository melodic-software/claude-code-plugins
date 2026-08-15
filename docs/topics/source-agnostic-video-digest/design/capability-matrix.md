# Capability matrix — single-public-video digest pipeline

Scope: `library` (contracts + module topology). Decomposes the existing
`plugins/knowledge/skills/youtube-digest/` pipeline into capabilities and classifies each as
**shared** (source-agnostic) or **per-source** (adapter-owned), so the adapter contract covers
exactly the per-source set and no more.

Classification is measured against the current `main` tree, not assumed. Every row cites the file
that carries the capability.

## Bootstrap stages (`watch/run-watch.js`, 247 lines)

`run-watch.js` is the **`watch <url>` entry point only — not the whole deterministic lane**, and its
call graph is therefore not the authoritative stage list. `acquisition/preflight-metadata.js` and
`watch/queue-claim.js` form a second, independent entry point serving the `queue <url>` and
`watch <n>` actions, with their own hard rejects that `run-watch.js` never reaches (stage 13 below).
`transcript/run-transcript.js` is a third. The stage list below is the union, not one call graph.

| # | Stage | Implementation | Classification | Evidence |
|---|-------|----------------|----------------|----------|
| 1 | URL → source id + acceptance | `acquisition/acquire.js` → `extractVideoId` | **per-source** | `acquire.js:267` calls `extractVideoId(url)` and hard-fails `"Could not extract YouTube video id from URL"`; `extractVideoId` (`acquire.js:116-138`) only parses `youtu.be`, `?v=`, and `live\|embed\|shorts\|v` path forms |
| 1b | Downloader argument construction | `acquisition/build-yt-dlp-args.js` | **per-source** | `build-yt-dlp-args.js:9` `YT_DLP_EXTRACTOR_ARGS = "youtube:max_comments=20,all,top;comment_sort=top"` is pushed **unconditionally** at `:113-114` alongside `--write-comments`. X has no comment list. This is the deciding evidence for the T4 granularity question |
| 1c | Retry / throttle / auth-fallback driver | `acquisition/acquire-with-retry.js`, `acquire-throttle.js`, `spawn-yt-dlp-with-auth-fallback.js` | **shared** | Generic retry and concurrency machinery — the part a coarse per-adapter `acquire()` would duplicate |
| 2 | Caption rung classification | `acquisition/select-caption.js` | **per-source** (classification), **shared** (ladder order) | `select-caption.js:23` `MANUAL_EN_PATTERN = /\.en(?:-[a-z]{2,3})?\.vtt$/` matches X's `.en.vtt`, yielding `isAutoCaption: false` for what is actually X ASR |
| 3 | Slice **key** | `run-watch.js:95` `deriveVideoSlug(metadata.title, metadata.id)` | **per-source** | X's URL status id ≠ yt-dlp `id`; a quote-tweet resolves to a different status entirely. Note the call trusts yt-dlp's id over the URL's even for YouTube |
| 3b | Slug **format** (kebab-case, 40-char cap) | `transcript/derive-video-slug.js:31` `deriveVideoSlug` | **shared** | Format is source-independent and separately tested (`derive-video-slug.test.js`). Only the key is per-source — forking the formatter per source would be the duplication this refactor exists to prevent |
| 4 | Transcript write (VTT → paragraphs) | `transcript/write-transcript.js` | **shared** | Routes only on the `isAutoCaption` boolean (stage 2's output), not on source |
| 5 | VTT cue parse | `@melodic/video-digestion/transcript/vtt-parser` | **shared** | Generic cue-tag state machine; strips X's nonstandard `<X-word-ms …>` per-word tags at no cost |
| 6 | Frame selection / watching orchestration | `watching/orchestrate-watching.js` | **shared** | Consumes `videoPath` + `cues` only — no source-shaped input |
| 7 | Coverage plan | `watching/compute-coverage-plan.js` | **shared** | Zero matches for chapter / heatmap / description signals |
| 8 | Watching manifest write | `watching/write-watching-manifest.js` | **shared** | Writes temp paths + timestamps only |
| 9 | Link harvest | `harvesting/harvest-links.js` → `harvestMetadataLinks(metadata)` | **per-source** | Hard-coupled to description + chapters + pinned comment; X exposes only description, and the real links live in reply chains |
| 10 | Watch state / phase map | `watch/watch-state.js` | **shared** | Phase names are pipeline-shaped, not source-shaped |
| 11 | Slice lanes + work root | `lib/slice-lanes.js`, `lib/work-root.js` | **shared** | Path seams only |
| 11b | **Epic directory constant** | `transcript/derive-video-slug.js:7` `export const YOUTUBE_WATCH_EPIC_DIR = "youtube-watch"` | **neither — a naming decision, not an adapter concern** | Not a path seam. It is a hardcoded YouTube name baked into every user's durable `.work/` tree: `derive-video-slug.js:45` builds the slice path from it, `queue-claim.js:31` resolves the **queue root** from it, and `watch-state.js:169,193` writes it into resume prompts. Owned by thread A1 |
| 12 | Post-bootstrap slice snapshot | `watch/post-bootstrap-slice.js`, `watch/snapshot-bootstrap.js` | **shared** | Operates on the slice dir |

## Slice key — CORRECTED. yt-dlp already exposes the URL status id; it is `display_id`, not `id`.

The invariant was right; the mechanism recorded for it was not. Gate-passed research, confirmed live
and against yt-dlp's own first `twitter.py` test (`id: 643211870443208704`,
`display_id: 643211948184596480`):

| Field | Value |
|---|---|
| `display_id` | **always the URL status id**, on every entry |
| `id` | the **media** id for `extended_entities`/`unified_card` videos; the **status** id for card/vmap videos |
| playlist container | `id` = status id, `display_id` **absent** |

So `extractSliceKey` does not need to re-parse the URL for X — the extractor already carries the
right value. It does need to read the **right field**, and the field differs by result shape.

**Recommendation: key the slice on the pair `(display_id, id)`**, because two aliasing hazards make
either alone insufficient:

- **Retweets** — `:1206` `traverse_obj(status, 'retweeted_status', None, …)` **replaces the entire
  status with the original**, so metadata and media belong to a different post than `display_id`
  names. (Source-derived; not probed live.)
- **Quote tweets** — `:1349` traverses `(None, 'quoted_status')`, concatenating the quoted post's
  media. Verified live; upstream issue **#14664 open**.

**Free detector, no API call:** X ids are snowflakes (`ts_ms = (id >> 22) + 1288834974657`), so a
media id materially older than the status id flags a quote or retweet.

## CORRECTNESS HAZARD — silent off-platform ingestion. Must be designed against.

Gate-passed research, reproduced firsthand.

When an X post links to a site yt-dlp **supports**, the extractor does not error. `twitter.py:1381`
returns `url_result(expanded_url, display_id=twid, **info)`.

**This is worse than "merged metadata" — it is complete PROVENANCE SUBSTITUTION.** Reading what
`info` actually carries (`:1222-1238`): `id` (= `twid`), `title` (the tweet text, prefixed with the
**tweet author's** name), `description`, `uploader`, `uploader_id`, `uploader_url`, `channel_id`,
`timestamp`, `view_count`, `like_count`, `repost_count`, `comment_count`, `age_limit`, `tags`.

**Every authorship field names the tweet's author rather than the actual video's creator, and every
engagement count is the tweet's.** A foreign video arrives wearing the tweet's identity — and a
digest would then research, synthesize, and cite it as the X post. Silent, and it produces a
plausible-looking slice.

**Note for the slice key:** in this branch `id` is `twid`, a direct exception to "`id` is *usually*
the media id". The `(display_id, id)` key must tolerate it.

Known and unfixed upstream: **issue #9715, open 848 days** (`site-bug`, `patch-available`); also
#16585.

**Required mitigation: reject any result whose `extractor` is not `twitter`.** This is a contract
obligation on the adapter, not an optional check — it is the only thing standing between a link post
and a corrupted slice. It also resolves the T10 "unenforced invariant" question in the direction of
enforcement: the adapter validates what came back, rather than trusting that the URL that went in
determines what comes out.

Related, same mechanism, different symptom: `No video formats found!` is produced when a
`summary_large_image` card falls into the vmap `else` branch (`:1321`) with a `None`
`player_stream_url`, fabricating an empty-format entry that **suppresses** the link-chase branch. Two
identical link posts yield two different outcomes depending only on preview-card type.

## Verification of the "shared" classifications

The shared rows are negative claims — "this module has no source coupling" — and a missed coupling
would silently expand the adapter surface. Checked directly rather than inferred:

`lib/synthesis-filename.js`, `lib/watch-slice-sessions.js`, `lib/watch-vision-validation.js`, and
`watching/**` return **zero** functional matches for `youtube` / `yt-dlp` / `youtu.be` / `videoId`.

**One cosmetic exception, and it is the root of a real defect.**
`watching/run-watching-pipeline.js:33-34` names its temp directories `youtube-frames-` and
`youtube-sheets-`. That is naming, not behaviour — but it is *where the staged-artifact leak comes
from*: those prefixes flow into `{tmp}` path serialization, and
`watch/export-sheet-frame-index.js:75` writes the fallback literal `"{tmp}/youtube-sheets-unknown"`
into `key-frames/sheet-frame-index.json`, which the Output contract stages. So the temp-directory
naming in a "source-agnostic" module is the origin of a YouTube string committed to every consumer's
repo. Rename the prefixes as part of the same fix.

`run-watch.js:83-85` names its own temp dirs the same way; same treatment.

## Stages outside `run-watch.js`

Missed by a call-graph-only reading. Both are per-source and both are load-bearing.

| # | Stage | Implementation | Classification | Evidence |
|---|-------|----------------|----------------|----------|
| 13 | Preflight / enqueue acceptance | `acquisition/preflight-metadata.js` | **per-source** | An **independent** hard reject serving `queue <url>` and `watch <n>`, never reached via `run-watch.js`: `:226` `"not a YouTube video URL"`, `:227` `"URL does not resolve to a YouTube video id"`, plus `:62` `/Incomplete YouTube ID/i`. Fixing acquisition alone leaves enqueue rejecting every X URL |
| 14 | Error classification / auth fallback | `acquisition/acquire-yt-dlp-auth.js` | **per-source** | `:8` `YOUTUBE_BOT_CHALLENGE_PATTERNS`, tested at `:29`, gates the cookie-fallback retry. None of X's three observed failures (`No video could be found in this tweet`, `No video formats found!`, `Unsupported URL: <external site>`) match, so X errors would traverse a YouTube-shaped fallback unclassified |

## Skill-session stages (agent lane, not in the CLI)

| Stage | Classification | Notes |
|-------|----------------|-------|
| Vision planning + three-pass absorption | **shared** | Operates on contact sheets + transcript; no source signal |
| Claim inventory | **shared** | Transcript-driven |
| Research fan-out | **shared** | External-research capability |
| Synthesis + recommendations | **shared** | Target-repo-driven |
| Interview handoff | **shared** | |
| Outcome verification (`evals/check-watch-outcomes.js`) | **shared** | Slice-layout-driven |

## Measured split

**Per-source: 7** — 1 (URL→id), 1b (downloader args), 2 (caption rung), 3 (slice key), 9 (link
harvest), 13 (preflight acceptance), 14 (error classification). **Shared: 10.** Plus 11b, an
epic-directory naming decision that belongs to no adapter and is owned by thread A1.

Every skill-session stage is shared. The adapter surface is small and sits entirely inside
`extraction/` — the empirical basis for the "adapter seam is the engine layer" decision.

A first pass of this matrix counted four per-source stages by reading `run-watch.js`'s call graph
alone. That undercount is recorded rather than erased: it is the concrete reason the stage list is
now sourced from the union of all entry points.

## Existing shared-package seams — there are TWO, not one

Both are jointly consumed by `youtube-digest` and `course-digest`, both are private v0.1.0, and both
carry the same joint-ownership rule in their README.

### `vendor/repo-analysis/` (`@melodic/repo-analysis`)

Single export `.` → `repo-analysis.js`. Wired identically from both skills
(`youtube-digest/extraction/harvesting/analyze-harvested-repos.js:15`,
`course-digest/extraction/analyze-code-repo.js:28`, and a
`"file:../../../vendor/repo-analysis"` dependency in both `package.json`s).

**Checked: it does not touch stage 9.** `harvest-links.js` imports only `findPinnedComment` from the
local `acquisition/video-metadata.js` — no `repo-analysis` import. `analyze-harvested-repos.js` is a
**downstream consumer of stage 9's output** (`source/harvested-links.json`), not part of the stage,
and it operates on GitHub URLs, which are source-independent. So making stage 9 adapter-owned does
not reach this package, and T1's "zero blast radius on `course-digest`" holds without exception.

Recorded because the boundary is adjacent enough that the assumption had to be tested rather than
asserted.

### `vendor/video-digestion/` (`@melodic/video-digestion`)

The seam the handoff did not account for. Its `exports` map is closed and narrow:
`frames/{models,contact-sheet,dedup,scene-detect}`, `media/ffprobe-duration`,
`shared/{logger,media-artifacts,process,progress,result,terminal}`,
`transcript/{auto-caption-clean,manual-caption-clean,vtt-parser}`.

Its README declares: *"Owner: shared capability — no single skill owner; `/youtube` and
`/course-digest` jointly consume, so changing it means exercising both consumers."* That ownership
rule is a live cost on any design that places the adapter contract there — see the
`adapter-home` thread in `design-threads.md`.

Note the quoted line says `/youtube` — the **pre-rename** skill name. It is one of three surviving
stale references and is itself evidence for T2b's rename cost, not a transcription error here.

## Invariants the adapter contract must preserve

| Invariant | Source |
|-----------|--------|
| Slice key is the id captured from the **URL**, never the media id the downloader reports | Observed divergence: URL status `2088290952704151671` vs yt-dlp id `2088290500604276736`; quote-tweet URL status `1806731757049479492` → yt-dlp id `1806598014867509568`. **Mechanism now identified, not merely observed:** `twitter.py:1348-1349` traverses `(None, 'quoted_status'), 'extended_entities', 'media'`, so for a quote tweet carrying no media of its own yt-dlp deliberately extracts the **quoted** status's media. The divergence is by design and will not be fixed upstream — which upgrades this from an empirical caution to a permanent contract obligation |
| ~~`select-caption.js` is a MANAGED surface — never the site of a source-specific fix~~ **REFUTED** | `standards/distribution/sync-manifest.yml` declares 37 managed components; exactly one targets `plugins/`, and it is `plugins/guardrails/lib/path-detection/machine-path-patterns.sh`. Nothing in `plugins/knowledge/` is managed. See thread T12 — the prohibition is lifted, though an adapter-supplied classification may still win on separation-of-concerns grounds |
| Any X URL entering the pipeline has already passed the `x:read` gate's match-capture-rebuild; fetched text may never introduce a URL, host, or path | `/x:read` gate contract — **but nothing enforces this on direct CLI invocation.** The gate is agent-lane, while `SKILL.md:48` enumerates eleven run-script entry points a human or agent can call by hand. Thread T10 must resolve whether the invariant binds the skill lane only (CLI treats its URL as trusted input) or the adapter re-derives the canonical status URL itself. As written the design asserts a guarantee no code makes |
| `course-digest` stays untouched | Skill-category test — auth-walled multi-lesson courses vs a single public video from a URL |
| Hub `SKILL.md` ≤ 500 lines (FAIL) / ≤ 200 (WARN); `description` + `when_to_use` ≤ 1,536 chars | `skill-quality/0.5.0/scripts/check-skill.sh:122-124` |
