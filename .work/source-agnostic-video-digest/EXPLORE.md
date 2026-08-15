# EXPLORE — source-coupled surfaces and adapter idioms

Grounding pass for the source-adapter design. Every path is repo-root-relative.
Read against the working tree of `refactor/source-agnostic-video-digest`
(which is identical to `origin/main` — see §9).

Method: files read, not inferred. Three subagents covered repo-wide idiom scan,
git history, and the test/eval surface; the coupling map, entry points, error
taxonomy, vendor boundary, `course-digest`, and `x` were read directly.

---

## 0. Corrections to the map the design currently rests on

Read `docs/topics/source-agnostic-video-digest/design/capability-matrix.md` and
`design-threads.md`. They are accurate where they go. Six deltas:

| # | Claim in the design tree | Correction |
|---|---|---|
| C1 | `SKILL.md:48` "eleven run-script sites" is the entry-point surface | Eleven is what **`SKILL.md` itself** enumerates. `context/watch-pipeline.md` and `context/quality-gates.md` document **six more** agent-invoked `run.mjs` sites, and `detect-recoverable-bootstrap.js:112` **generates a seventh** as a copy-paste command. Full tiering in §1 |
| C2 | Per-source stage list is complete at 7 (+11b) | Two per-source stages are missing: **stage 15** `watch/recover-watch-bootstrap.js:224` synthesizes `https://www.youtube.com/watch?v=${metadata.id}` — a hard YouTube URL literal in the recovery path that writes `sourceUrl` into `watch.json`; and **stage 16** the `VideoMetadata` model itself (`acquisition/video-metadata.js`), whose `chapters` / `heatmap` / `comments[].is_pinned` fields are yt-dlp-YouTube-shaped and are what stage 9 consumes |
| C3 | `vendor/video-digestion/` is the source-agnostic kernel | **Three of its fourteen exports are YouTube-named in their own headers** and one carries a Hotmart-specific branch. `transcript/auto-caption-clean.js:2`, `transcript/manual-caption-clean.js:2`, `transcript/progressive-cue-merge.js:2,31` all say "YouTube"; `transcript/vtt-parser.js:121` has a Hotmart-VTT dedup branch. `shared/media-artifacts.js:10` types `metadataPath` as "path to yt-dlp info JSON". Detail in §4 |
| C4 | `select-caption.js` is a MANAGED surface (sync-manifest) | **Not corroborable in this repo.** No `scripts/sync-*.sh` copy list, `scripts/cross-plugin-source-registry.txt` entry, or `docs/` reference names it. The only mentions of `select-caption` repo-wide are the design's own three files. The claim may hold in `melodic-software/standards`, which is not this tree — but nothing here marks the file as managed, and a design invariant should not rest on it unverified |
| C5 | T2b: `.github/workflows/ci.yml` = "1 file, 5 occurrences" | **11 lines** carry `youtube` (`:855,864,888,892,896,900,903,914,956,962,1163`). Six are functional: the job name `youtube-extraction:` (`:864`), `cache-dependency-path` (`:888`), three `working-directory:` values (`:892,896,900`), and the required-job `needs:` entry (`:1163`). Five are comment/echo prose. All hand-edited — no generator |
| C6 | (brief's premise) the lane reached its shape through an extraction split, queue introduction, preflight introduction | **None of that happened.** The whole 176-file structure landed fully formed in one import commit `c4aa3515` (2026-07-12). Only 22 commits have ever touched the skill dir. §9 |

Also worth stating plainly for T2b: the design's blast-radius table counts
`youtube-digest` occurrences today, which is the right number — but the
**historical** rename commit (`f0aa5727`) touched 166 files and did **not** touch
CI, registries, or catalogs, because those surfaces did not exist yet. Every
gate listed in §9's tooling table postdates that rename. The precedent is
therefore weaker evidence than it looks.

---

## 1. Entry points into `plugins/knowledge/skills/youtube-digest/extraction/`

Everything runs through the launcher
`plugins/knowledge/skills/youtube-digest/extraction/run.mjs`, which:

- refuses any target resolving outside `extraction/` (`run.mjs:57-62`);
- parses leading flags via `extraction/lib/run-args.js` and translates them to
  `YOUTUBE_*` env vars for the child (`run-args.js:21-35`);
- re-execs `node --import register-hook.mjs <target>` so bare
  `@melodic/video-digestion` specifiers resolve out of `${CLAUDE_PLUGIN_DATA}`
  (`register-hook.mjs`, `resolve-hook.mjs`).

`run.mjs` itself is source-agnostic apart from the five `YOUTUBE_*` variable
names it emits.

### Tier A — the eleven sites `SKILL.md:48` enumerates

| # | Script | Args | YouTube-coupled? | How |
|---|---|---|---|---|
| 1 | `transcript/run-transcript.js` | `<url>` | **Yes** | calls `acquireYouTubeMedia(url, {mode:"transcript"})` (`:33`); temp prefix `youtube-extraction-` (`:30`) |
| 2 | `acquisition/preflight-metadata.js` | `<url>…` | **Yes — independent hard reject** | `extractVideoId` (`:217`), `"not a YouTube video URL"` (`:226`), `"URL does not resolve to a YouTube video id"` (`:227`), `PREFLIGHT_UNAVAILABLE_PATTERNS` incl. `/Incomplete YouTube ID/i` (`:62`), yt-dlp `--print` template (`:36-41`), "never appears in a YouTube title" delimiter rationale (`:32`) |
| 3 | `watch/queue-claim.js` | `claim\|release\|list\|stale-check` | **Yes — indirectly** | imports `YOUTUBE_WATCH_EPIC_DIR` (`:20`) and resolves the **queue root** from it (`:31`). Note `--epic-dir` already overrides it (`:197-199`); the singleton is only `resolveEpicDir`'s default (`:30`) and the CLI default (`:191`) |
| 4 | `watch/run-watch.js` | `<url> [--skip-research] [--target] [--recover]` | **Yes** | `acquireYouTubeMedia(..., mode:"full")` (`:88`); three temp prefixes `youtube-extraction-` / `youtube-frames-` / `youtube-sheets-` (`:83-85`) |
| 5 | `watch/watch-state.js` | `mark-phase <slice-dir> <phase>` | **Yes — display leak** | imports the epic constant (`:16`) and interpolates it into user-facing continuation prose (`:169,193`) |
| 6 | `watch/vision-gated-promote.js` | `<slice-dir> [--dry-run]` | No | slice-dir + lane paths only |
| 7 | `watch/init-watch-checklist.js` | `<slice-dir> [--force]` | No | reads `watch.json` + bundled template |
| 8 | `harvesting/analyze-harvested-repos.js` | `<slice-dir>` | Cosmetic only | temp prefix `youtube-repo-analysis-` (`:96`); operates on GitHub URLs |
| 9 | `evals/check-research-complete.js` | `<slice-dir>` | No | lane-path assertions only |
| 10 | `evals/check-watch-outcomes.js` | `<slice-dir> [--write-report]` | No | artifact-shape assertions only |
| 11 | `watch/run-resume.js` | `<video-slug>` | **Yes — indirectly** | `resolveWorkSliceDir` (`:37`) → epic constant; re-renders `buildContinuationPrompt` (`:46`) |

### Tier B — invoked but NOT in the eleven

Every one of these is a documented `run.mjs` invocation in a `context/` file or
a command string a script prints for the operator to paste.

| Script | Documented at | Coupled? |
|---|---|---|
| `watch/merge-triage-json.js` | `context/watch-pipeline.md:9`, `quality-gates.md:127` | No |
| `watch/validate-triage-json.js` | `context/watch-pipeline.md:9` | No |
| `watch/render-triage-log.js` | `context/watch-pipeline.md:9`, `quality-gates.md:125,127` | No |
| `watch/render-quality-audit.js` | `context/watch-pipeline.md:15` | No |
| `watch/render-key-frames-manifest.js` | `context/watch-pipeline.md:15` | No |
| `watch/repair-synthesis-promotions.js` | `context/watch-pipeline.md:16` | No |
| `watching/run-watching-pipeline.js` | `context/watch-pipeline.md:30` | Cosmetic — temp prefixes `youtube-frames-` / `youtube-sheets-` (`:33-34`) |
| `harvesting/run-harvest.js` | `context/watch-pipeline.md:36` | **Yes** — parses yt-dlp info JSON through `parseVideoMetadata` (`:14`) |
| `watch/recover-watch-bootstrap.js` | **generated** by `watch/detect-recoverable-bootstrap.js:112` as a paste-ready command; also reachable as `run-watch.js --recover` (`run-watch.js:41-65`) | **Yes — hardest coupling in the tree**: `:224` synthesizes `https://www.youtube.com/watch?v=${metadata.id}` |

**Design consequence:** the adapter surface is not bounded by the eleven. A
source-agnostic pass must re-audit the paste-command generator
(`detect-recoverable-bootstrap.js:112` also hardcodes the string
`skills/youtube-digest/extraction/run.mjs`, so it breaks on the T2b rename too).

### Tier C — internal-only modules with a CLI guard but no documented invocation

`watch/snapshot-bootstrap.js`, `watch/export-sheet-frame-index.js`,
`watch/promote-key-frames.js`, `watch/list-promotion-candidates.js`,
`watch/expand-visual-gaps.js`, `watch/rebuild-visual-frames.js`,
`watch/sanitize-slice-temp-paths.js`, `watch/finalize-vision.js`.
The first two run automatically via `watch/post-bootstrap-slice.js` from
`run-watch.js:196`. Only `export-sheet-frame-index.js:75` is coupled (see §2).

---

## 2. YouTube coupling inventory

Grep baseline, measured under `plugins/knowledge/skills/youtube-digest/extraction/`
excluding `*.test.js` (reproducible, `grep -rIoE`):
**147 matching lines across 30 files** for
`youtube|youtu\.be|YouTube|YOUTUBE|yt-dlp|YT_DLP`; **220 occurrences across 31
files** when `yt_dlp|ytDlp|video_?[Ii]d|videoId` are added. Grouped by *class*, because that is what
the contract has to cover — the design's 7-stage count is a stage count, not a
coupling-point count, and the two do not correspond one-to-one.

### 2.1 URL parsing and id semantics

- `acquisition/acquire.js:101` `YOUTUBE_VIDEO_ID_PATTERN = /^[\w-]{11}$/` — an
  11-character id shape. X status ids are 19 digits.
- `acquisition/acquire.js:116-138` `extractVideoId` — hosts `youtu.be`, query
  `?v=`, path prefixes `live|embed|shorts|v`. Returns `null` for anything else.
- `acquisition/acquire.js:267-276` — hard fail `"Could not extract YouTube video
  id from URL"`.
- `acquisition/preflight-metadata.js:217-233` — the **second, independent** hard
  reject on the same function, serving `queue <url>` and `watch <n>`.
- `watch/recover-watch-bootstrap.js:224` — reconstructs a YouTube watch URL from
  the media id. Not id *parsing* but id → URL *synthesis*; equally per-source.

### 2.2 Downloader arguments (`acquisition/build-yt-dlp-args.js`)

- `:9` `YT_DLP_EXTRACTOR_ARGS = "youtube:max_comments=20,all,top;comment_sort=top"`
  — pushed **unconditionally** at `:113-115`, alongside `--write-comments`
  (`:113`). The `youtube:` prefix is a yt-dlp extractor namespace; it is inert
  but wrong for another extractor.
- `:5` `YT_DLP_SUB_LANGS = "en.*,-live_chat"` — `live_chat` is a YouTube-only
  subtitle track.
- `:8` `YT_DLP_VIDEO_FORMAT = "bestvideo[height<=1080]+bestaudio/best[height<=1080]"`
  — format-selector syntax is generic but the height ladder assumes a source
  offering ≥1080p renditions.
- `:101` `--no-playlist` — pushed unconditionally; interacts with T6 (X
  multi-media posts return `_type: playlist`).

### 2.3 Caption filename patterns (`acquisition/select-caption.js`)

Six regexes, all derived from **yt-dlp's YouTube naming convention**:
`:19 TLANG_TRANSLATE_PATTERN`, `:20 EN_ORIG_PATTERN`, `:21
EN_ORIG_LOCALIZED_PATTERN`, `:22 EN_AUTO_PATTERN`, `:23 MANUAL_EN_PATTERN`,
`:24 AUTO_TRANSLATE_EN_PATTERN`. The ladder order itself (`:17`) is generic; the
classification is not. `:93` is a hard fail when the ladder is exhausted — an
unconditional stop for any source with no `.vtt` at all.

### 2.4 Error-string matching — three separate, unrelated pattern lists

| List | File:line | Gates |
|---|---|---|
| `YOUTUBE_BOT_CHALLENGE_PATTERNS` (3) | `acquisition/acquire-yt-dlp-auth.js:8-12` | the **cookie-fallback retry** |
| `COOKIE_PROFILE_RETRY_HINT_PATTERNS` (5) | `acquisition/acquire-yt-dlp-auth.js:15-21` | whether to try the *next* browser profile |
| `PREFLIGHT_UNAVAILABLE_PATTERNS` (8) | `acquisition/preflight-metadata.js:55-64` | **enqueue vs reject** |
| `RETRYABLE_ACQUIRE_PATTERNS` (8) | `acquisition/acquire-retry-policy.js:11-20` | 429/503/timeout backoff — **genuinely source-agnostic** |

### 2.5 Metadata model and comment fetching

- `acquisition/video-metadata.js` — `parseVideoMetadata` maps yt-dlp info JSON
  onto `{id, title, description, chapters, heatmap, comments}`. `chapters`
  (`:46`), `heatmap` (`:101`) and `comments[].is_pinned` (`:80`) are
  YouTube-specific concepts. `findPinnedComment` (`:122`).
- `harvesting/harvest-links.js:57-78` — `harvestMetadataLinks` reads exactly
  those three: description, chapters, pinned comment. `summarizeHeatmap` (`:86`).
- Fixtures encode the same shape: `extraction/harvesting/fixtures/{pinned-present,
  no-pinned-comment,null-heatmap}.json`.

### 2.6 Epic / queue directory naming

- `transcript/derive-video-slug.js:7` `export const YOUTUBE_WATCH_EPIC_DIR = "youtube-watch"`.
- Consumed at `derive-video-slug.js:45` (slice path), `watch/queue-claim.js:20,31`
  (queue root + `claims/` root), `watch/watch-state.js:16,169,193` (resume prose).
- `SKILL.md:112` calls `youtube-watch` "canonical epic dir";
  `context/watch-queue.md` describes the whole queue around it.
- Slug **format** is separately owned and source-neutral:
  `derive-video-slug.js:15-35` (`slugifyTitle`, 40-char cap, `-<id>` suffix),
  with its own tests.

### 2.7 Environment variable names — five, and one is undocumented

| Var | Set by | Read by | In `plugin.json`? |
|---|---|---|---|
| `YOUTUBE_WORK_ROOT` | `lib/run-args.js:22` | `lib/work-root.js:19` | via `library_dir` |
| `YOUTUBE_YT_DLP_JS_RUNTIMES` | `run-args.js:23` | `build-yt-dlp-args.js:18,63` | yes |
| `YOUTUBE_YT_DLP_COOKIES_FILE` | `run-args.js:24` | `build-yt-dlp-args.js:16,51` | yes |
| `YOUTUBE_YT_DLP_COOKIES_FROM_BROWSER` | `run-args.js:26-29` | `build-yt-dlp-args.js:17,55` | yes |
| `YOUTUBE_MAX_CONCURRENT_ACQUIRES` | `run-args.js:30-34` | `acquisition/acquire-throttle.js:23` | yes |
| **`YOUTUBE_ACQUIRE_PHASE_GAP_SEC`** | **nothing** | `acquisition/acquire.js:24,58` | **no** | 

The last one is a **finding for A2**: it is a real runtime knob with no launcher
flag and no `userConfig` entry — reachable only by setting the env var by hand,
which `run-args.js`'s own header calls "not a consumer-facing channel". Any
namespace decision must account for it or it silently keeps the old prefix.

### 2.8 Published plugin config keys

`plugins/knowledge/.claude-plugin/plugin.json` (`knowledge` v0.12.0):
`library_dir` (`:36`, shared across all knowledge skills), then four titled
`"… (youtube-digest)"`: `yt_dlp_js_runtimes` (`:42`), `yt_dlp_cookies_file`
(`:48`), `yt_dlp_cookies_from_browser` (`:54`), `max_concurrent_acquires`
(`:60`). Plugin `description` (`:5`) and `keywords` (`:11-34`) both enumerate
sources; `.claude-plugin/marketplace.json` mirrors the tags.

### 2.9 Temp-path and package-identity strings (cosmetic but user-visible)

Five OS-temp prefixes: `youtube-extraction-` (`transcript/run-transcript.js:30`,
`watch/run-watch.js:83`), `youtube-frames-` (`run-watch.js:84`,
`watching/run-watching-pipeline.js:33`), `youtube-sheets-` (`run-watch.js:85`,
`run-watching-pipeline.js:34`), `youtube-repo-analysis-`
(`harvesting/analyze-harvested-repos.js:96`), and the lock dir
`youtube-extraction-acquire-locks` (`acquisition/acquire-throttle.js:34`).

**One of these is serialized into a committed artifact:**
`watch/export-sheet-frame-index.js:75` writes the fallback literal
`"{tmp}/youtube-sheets-unknown"` into `key-frames/sheet-frame-index.json`, which
the Output contract stages. That is a YouTube string landing in a consumer's git
history.

Package identity: `extraction/package.json:2` `@melodic/youtube-extraction`;
`extraction/setup-deps.mjs:64` stamp file `.youtube-extraction.stamp` under
`${CLAUDE_PLUGIN_DATA}` (renaming it re-triggers one install, harmless but
worth naming).

### 2.10 Genuinely source-agnostic (verified by reading, not naming)

`lib/slice-lanes.js` (six-lane registry + `lanePath`), `lib/work-root.js` (modulo
the var name), `lib/temp-session-paths.js` (`{tmp}` tokenization),
`lib/synthesis-filename.js`, `lib/watch-slice-sessions.js`,
`lib/watch-vision-validation.js`, the whole of `watching/` (consumes
`videoPath` + `cues`), all of `evals/` (slice-shape assertions; a targeted grep
for `youtube|videoId|watch\?v` across `extraction/evals/**` returns zero hits),
`acquisition/acquire-retry-policy.js`, `acquisition/acquire-with-retry.js`,
`acquisition/acquire-throttle.js` (modulo var + lock-dir names).

---

## 3. Error taxonomy — verdict

**Where failures are produced.** Three shapes coexist and do not compose:

1. **`Result`** (`vendor/video-digestion/shared/result.js`) — `{success, data,
   error: string|null, operation, durationMs, context}`. `fail()` carries a
   *human-readable string*; there is no code, class, or category field.
   `acquireYouTubeMedia` returns this.
2. **`SpawnResult`** (`vendor/video-digestion/shared/process.js`) — carries
   `stderr`, flattened by `spawnFailureDetail` (`acquire-with-retry.js:20-22`)
   into one string.
3. **Ad-hoc CLI exit codes** — `preflight-metadata.js` exit `2` on any reject
   (`:306-308`); `queue-claim.js` exit `2` on `ClaimExistsError` (`:244-248`);
   `run.mjs` exit `2` on bad args. There is no exit-code taxonomy of the kind
   `plugins/work-items/tools/work-item-tracker/CONTRACT.md` defines (§5).

**Classification is entirely `RegExp.test()` over a flattened stderr string.** No
error type, no code, no structured field. Four unrelated pattern lists (§2.4).

**Would a non-YouTube source's failures traverse a YouTube-shaped path? Yes — in
two directions, both silent.**

- **Auth fallback never fires.** `spawnYtDlpWithAuthFallback` is the single spawn
  path for **both** acquisition and preflight
  (`acquisition/spawn-yt-dlp-with-auth-fallback.js:35`; called from
  `acquire.js:181` and `preflight-metadata.js:239`). Its gate is
  `isYoutubeBotChallengeError(detail)` at `:49` — three YouTube-literal patterns.
  An X auth/geo/withheld failure matches none, so `:50` returns the raw failure
  immediately and **no cookie fallback is ever attempted**. The failure direction
  is *under*-recovery: a recoverable non-YouTube failure is reported as fatal.
- **Preflight misclassifies dead links as live.** `classifyPreflightFailure`
  (`preflight-metadata.js:151-156`) returns `"transient"` for **anything not
  matching the eight patterns**, and `"transient"` maps to
  `action: "enqueue"` (`:267`). So a permanently deleted / protected / suspended
  X post is appended to `QUEUE.md` as a live row with a
  `preflight: …` note. The failure direction here is the opposite —
  *over*-acceptance. A batch of dead X URLs drains as repeated `failed` rows.

**Unconditional hard rejects a non-caption source hits regardless of
classification** (these are not pattern-matched at all — they fail closed):

| Reject | Site |
|---|---|
| ladder exhausted, no English caption | `select-caption.js:91-95` → surfaced by `acquire.js:327-329` |
| `"yt-dlp did not write info JSON"` | `acquire.js:331-333` |
| `"yt-dlp did not download video file"` | `acquire.js:227-233`, `:335-337` |
| `"Transcript mode must not download video"` | `acquire.js:339-341` |
| `"Could not extract YouTube video id from URL"` | `acquire.js:269-276` |
| `"not a YouTube video URL"` (enqueue) | `preflight-metadata.js:226` |

**Retry policy is the one shared piece.** `RETRYABLE_ACQUIRE_PATTERNS`
(`acquire-retry-policy.js:11-20`) is HTTP/network-shaped and transfers unchanged,
as does `withAcquireThrottle` (`acquire-throttle.js:128`) and
`spawnWithAcquireRetry` (`acquire-with-retry.js:35`). This confirms the design's
stage-1c "shared" classification and supports T4's fine-grained
`buildDownloaderArgs`-over-shared-driver direction.

**For T11:** the concrete decision is not "should `classifyError` be a method" but
**which of the four lists is per-source**. Measured: `RETRYABLE_ACQUIRE_PATTERNS`
is shared; `COOKIE_PROFILE_RETRY_HINT_PATTERNS` is *tool*-specific (yt-dlp cookie
extraction), not source-specific; `YOUTUBE_BOT_CHALLENGE_PATTERNS` and
`PREFLIGHT_UNAVAILABLE_PATTERNS` are per-source. That is a 2-of-4 split, and the
two per-source lists gate **different decisions** (retry-with-cookies vs
enqueue-vs-reject) — so a single `classifyError(stderr)` returning one category
would have to serve both, or the contract needs two hooks.

---

## 4. `plugins/knowledge/vendor/video-digestion/` — boundary

**Exports map** (`vendor/video-digestion/package.json:7-22`) is closed — 14
subpaths, no wildcard, so an adapter surface added inside would need a manifest
edit:

`frames/{models,contact-sheet,dedup,scene-detect}` ·
`media/ffprobe-duration` ·
`shared/{logger,media-artifacts,process,progress,result,terminal}` ·
`transcript/{auto-caption-clean,manual-caption-clean,vtt-parser}`

**How both skills import it.** Identical mechanism, no divergence:
`skills/youtube-digest/extraction/package.json` and
`skills/course-digest/extraction/package.json` each declare
`"@melodic/video-digestion": "file:../../../vendor/video-digestion"`, with
`extraction/.npmrc` = `install-links=true` so it installs as a packed copy rather
than a symlink. `setup-deps.mjs` installs into `${CLAUDE_PLUGIN_DATA}` and stamps
a SHA-256 over `package.json` **plus the whole `vendor/` tree**, so a vendor-only
edit forces reinstall.

**Genuinely source-agnostic:** `shared/result.js`, `shared/process.js`,
`shared/terminal.js`, `shared/logger.js`, `shared/progress.js`, all of `frames/`,
`media/ffprobe-duration.js`. `frames/scene-detect.js:5` states it explicitly
("Provider-agnostic — consumers pass HLS or file URLs").

**Leaks a source assumption — four places:**

| File:line | Leak |
|---|---|
| `shared/media-artifacts.js:10` | `@property {string} metadataPath - path to yt-dlp info JSON` — **the acquisition output contract itself names the tool**. This is the type an adapter contract must honor or replace |
| `transcript/auto-caption-clean.js:2,4` | "YouTube auto-caption WebVTT cleaning"; "yt-dlp downloads auto-captions as-is" |
| `transcript/manual-caption-clean.js:2` | "YouTube manual-caption cleaning" |
| `transcript/progressive-cue-merge.js:2,31` | "shared by auto and manual YouTube VTT"; "YouTube manual-EN uses touching timestamps" |
| `transcript/vtt-parser.js:121` | a dedup branch justified by "Hotmart VTT repeats each line" — a *course-digest* source leaking the other way |

So the vendor package is not the neutral kernel the T1 recommendation assumes —
its `transcript/` third is **bi-directionally** source-coupled (YouTube from one
consumer, Hotmart from the other). This does not change T1's recommendation (a)
— it *strengthens* it, because it shows the current vendor boundary was drawn by
"what both happened to need", not by a source-agnosticism principle.

**Ownership rule that binds any change here** (`vendor/README.md:15-19`): single
authoring source, no byte-drift gate; **editing it obligates a plugin `version`
bump**, and `vendor/video-digestion/README.md:5` adds "changing it means
exercising both consumers". `plugins/skill-quality/scripts/check-skill.sh` check
8 enforces `vendor/` byte-identity vs HEAD unless paired with an upstream-version
bump.

Two stale pre-rename references live here and are the T2b regression test the
design already names: `vendor/video-digestion/README.md:5`,
`vendor/repo-analysis/README.md:5`, `vendor/video-digestion/TUNING.md:55`.

---

## 5. Repo-wide adapter / seam idioms — reuse-or-replace

### 5.1 Governance: there is no repo-wide rule, and the two that exist conflict

**Verified directly** (not relayed): `docs/MIGRATION-PLAYBOOK.md` § "Persistence,
configuration & external integration" states verbatim:

> "A skill is a markdown prompt (plus optional scripts), not a compiled runtime — so ports / adapters / CQS layering is a **category error** here."

and closes:

> "This is deliberately **not** ports / adapters: there is no runtime seam to invert in a prompt medium, so a declared config surface, not an abstraction layer, is the extension point."

Its prescribed extension mechanism is **one `userConfig` knob with a sane
default**, gated by Rule of Three ("no speculative knobs").

**Verified directly:** `plugins/work-items/tools/work-item-tracker/CONTRACT.md:6`
cites "ADR 0022" as locking its direction. **`docs/adr/` contains only
`0001`–`0009`. ADR 0022 does not exist in this repository** (confirmed by
listing the directory and by a repo-wide grep, which returns only
`CONTRACT.md:6` and `conformance/bindings/github.sh:5`). The repo's most
developed adapter seam is authorized by a document that is not here.

The only positive bar found: `plugins/architecture/skills/improve/research/deepening/dependencies.md:29`
— *"One adapter = hypothetical seam. Two adapters = real seam. Don't introduce a
port unless at least two adapters are justified."* The X design clears this bar
(YouTube + X).

**Reuse-or-replace framing this produces:** the playbook's rule binds *prompt-medium*
extensibility. This lane is **not** the prompt medium — it is a 157-file Node
package. The design should say so explicitly rather than appear to contradict
the playbook silently, and should note that `course-digest` already carved the
same exception without recording it.

### 5.2 The two real code contracts (both plugin-local, mutually divergent)

**A. `plugins/work-items/tools/work-item-tracker/`** — the most engineered seam
in the repo.
- Selection: tracked config value (`.work-item-tracker.json` → `provider`), then
  a **two-root directory resolution** (`WIT_ADAPTERS_DIR` → `$CLAUDE_PROJECT_DIR/tools/work-item-tracker/adapters/<p>` → plugin-bundled). **The only idiom in the repo letting a consumer add or shadow an implementation without forking.**
- Contract: verb-per-script filename convention (`create-item`, `get-item`,
  `claim`, `renew-lease`, `reclaim`, `link-blocks`, `add-sub-item`, `list-items`,
  `list-sub-items`, `capabilities`), JSON-only stdout with `schema_version`, and a
  **9-value exit-code taxonomy** (`0 ok · 1 internal · 2 usage · 3 binding · 4 auth · 5 not-found · 6 capability-unsupported · 7 conflict · 8 provider-unavailable`).
- **Capability declaration**: `adapters/<p>/capabilities.json`, gated *before*
  dispatch — the only explicit-degradation mechanism in the repo.
- Enforcement: `conformance/run-conformance.sh` runs **one abstract suite over
  every adapter through the core CLI only** — the only cross-implementation
  conformance harness here.
- Adapters: `adapters/{github,jira,local-markdown}/`.

**B. `plugins/knowledge/skills/course-digest/extraction/adapters/`** — §7.

They diverge on all four axes: contract medium (shell+JSON vs JS object),
capability declaration (present vs absent), conformance (one abstract suite vs
per-adapter suites), consumer extension (possible vs fork-only). **Nothing in the
repo tells a third seam author which to copy.** `design-threads.md:41-45` already
records the divergence as deliberate *at the contract level*; it is not recorded
at the meta level.

### 5.3 Config-selected backends (the playbook-sanctioned shape)

- `vault_backend` — `docs/conventions/topic-docs/README.md:44,325-333,431`,
  schema `topic-docs.schema.json:25-29`; second backend formally deferred by
  `docs/adr/0001-defer-gitbook-as-knowledge-vault-backend.md`.
- `HOOK_TELEMETRY_SINK` — `docs/conventions/hook-telemetry/README.md`; producer
  and sink decoupled; per-hook payload schema discovered by **filename keyed on a
  runtime envelope field** (`data/<hook>.schema.json`).
- `convention_source` — `lib/resolve-convention-pattern.sh` + owner doc
  `docs/conventions/commit-convention/README.md`; three-rung fail-closed resolver.
- `library_dir` — this plugin's own seam (`plugin.json:36`, `lib/work-root.js:19`).

### 5.4 Filename/path-convention contracts

- `.claude/ecosystems/<ecosystem>.yaml` — `docs/conventions/ecosystem-commands/README.md`
  + `ecosystem.schema.json`; **the filename stem IS the identifier**; four-rung
  layered ladder; JSON Schema enforced; degrades soft. This is the repo's
  best-documented "one contract, many implementations" convention, and it is
  data-shaped, not code-shaped.
- `plugins/machine-health/skills/audit/catalog/checks.jsonc` — the repo's only
  **explicit JSON registry map** (id → script path), with
  `catalog/schemas/checks.schema.json` constraining the `script` path pattern and
  self-maintaining lifecycle fields (`crash_count`, `identical_streak`,
  `deprecated`).
- The nine `*-format` sibling plugins — one hook contract, nine plugin
  implementations, dispatched by the Claude Code hook matcher; shared code
  **materialized, not imported**, gated by `scripts/check-cross-plugin-source-drift.sh`.

### 5.5 Prose/model-executed seams (closest cousins to this lane's problem)

- **Publisher profiles** — `plugins/knowledge/skills/docpage-digest/SKILL.md:114-116,236-241`
  + `context/anthropic-docs-profile.md`. Model matches the URL's **host** against
  profile files; no match → generic path + record "no profile". Carries an
  explicit Rule-of-Three deferral: *"Add a second publisher as a sibling profile
  file; extract a shared engine only when a THIRD profile lands."*
  **This is the closest in-repo precedent to URL-shape dispatch and it lives in
  the same plugin.** T3/T7 should either reuse it or openly replace it.
- **compress backend** — `plugins/docs-hygiene/skills/compress/` + a runtime
  capability probe script (`scripts/detect-caveman.sh`) reporting
  `available|absent|unknown`.
- **`/x:read` converter chain** — two converters selected by content shape (§8).
- `docs/conventions/seam-phrasing/README.md` — the required shape of an optional
  cross-plugin reference (presence gate + stated fallback + ownership framing;
  *"'Skip silently' is not a fallback"*). **This governs T10's `/x:read` posture
  directly.**

### 5.6 The registry-file idiom (relevant if dispatch becomes data)

A consistent repo-wide shape: a data file the gate reads, with a header comment
stating format and growth policy, so adding an entry is a data change.
`scripts/contract-clause-registry.json`'s `$comment` names it explicitly.
Members: `cross-plugin-source-registry.txt`, `skill-leaf-name-registry.txt`,
`shell-portability-tokens.txt`, `skill-portability-tokens.txt`,
`hook-userconfig-argv-allowlist.txt`, `docs-only-paths.txt`,
`contract-slice-baseline.txt`, `orphaned-fixtures-baseline.txt`,
`changelog-parity-baseline.txt`, `affected-tests-no-suite.txt`.

### 5.7 Verified absences

Repo-wide search for JS/Python implementation dispatch (`await import(<var>)`,
variable `require`, `switch` on source/kind, `register(`,
`HANDLERS`/`ADAPTERS`/`PROVIDERS` literals) found **exactly one**
implementation-dispatching dynamic import in the entire tree:
`plugins/knowledge/skills/course-digest/extraction/lib/config.js:50`. Every other
`await import()` is lazy-loading a fixed dependency.

`scripts/validate-plugin-contracts.mjs` is 314 lines of hardcoded per-plugin
checks; it knows about neither adapter contract.

---

## 6. Test and eval surface

### 6.1 vitest

`extraction/` is a self-contained npm package (`@melodic/youtube-extraction`,
`"private": true`, `"type": "module"`; `test: "vitest run"`, `build: "tsc --noEmit"`).
`extraction/vitest.config.ts` is deliberately empty (`defineConfig({ test: {} })`)
— **no `include` override**, so vitest's default glob applies and a new adapter's
`*.test.js` anywhere under `extraction/` is picked up with no config change. All
55 existing suites are strictly colocated (`foo.js` → `foo.test.js`).
`tsconfig.json` excludes `**/*.test.js` from the typecheck.

`register-hook.mjs` / `resolve-hook.mjs` are **runtime-only** (the
`${CLAUDE_PLUGIN_DATA}` loader chain); under vitest, `npm ci` creates a local
`extraction/node_modules` with packed copies of the vendored packages and
resolution is ordinary.

**Consequence for a new source:** a new vendored subpath must (a) exist under
`plugins/knowledge/vendor/`, (b) be added to `extraction/package.json`, and
(c) have `extraction/package-lock.json` regenerated — the CI lane exists
precisely to catch that drift on a clean `npm ci`.

### 6.2 CI

`.github/workflows/ci.yml:864` job `youtube-extraction` is the **only** lane that
runs these tests: `npm ci` → `npm run build` → `npm test`, each with
`working-directory: plugins/knowledge/skills/youtube-digest/extraction`
(`:891-900`), gated `if: steps.scope.outputs.docs_only != 'true'`, and a required
dependency at `:1163`.

`scripts/run-plugin-tests.sh` discovers only `*.test.sh` and does **not** reach
this lane (`plugins/knowledge` contains zero `*.test.sh` files).
`scripts/affected-tests.sh` maps `.js`/`.vtt` under this tree to **UNMAPPED**
(verified empirically) — pre-existing, not CI-gating, but it means the local
"run what I affected" path gives no signal here.

### 6.3 Fixtures

| Location | Format | Consumed by | Orphan gate applies? |
|---|---|---|---|
| `extraction/harvesting/fixtures/` | yt-dlp metadata JSON | `harvesting/harvest-links.test.js:28,40,51` | **No** (not under `*/evals/fixtures`) |
| `extraction/evals/fixtures/` | WebVTT | `extraction/evals/manual-caption-driver.test.js:12-13` | **Yes** |
| `skills/youtube-digest/evals/fixtures/` | JSON goldens | `evals/evals.json` `files[]` (3 cases) + `manual-caption-driver.test.js:16` | **Yes** |

`scripts/check-orphaned-fixtures.sh` (CI `:579-590`) requires every file under a
`*/evals/fixtures` dir to be *consumed* — named in a sibling `evals.json`
`files[]` value (extracted via `jq`, so a mention in a prompt does **not** count)
or referenced bounded-word inside a `*.test.*` under the owning skill dir.
`scripts/orphaned-fixtures-baseline.txt` holds no `knowledge` entries and fails on
stale entries; its header forbids using it to dodge the gate on new work.

### 6.4 `evals/evals.json` shape and the `skill-quality` gate

Repo convention: `{skill_name, evals: [{id, name, prompt, expected_output,
expectations[], files[]?}]}`. `youtube-digest` has 8 cases;
`course-digest` has 6 with an explicit `"files": []`; `docpage-digest` has 4 with
no `files` key.

Schema `plugins/skill-quality/reference/evals.schema.json`, validated in CI on
**every event** over `plugins/*/skills/*/evals/evals.json`:
`additionalProperties: false` at both levels (so **no new per-case key may be
invented** — e.g. no `source: "x"` field), `required: ["id","prompt"]`, and an
`anyOf` requiring at least one of non-empty `expected_output` /
`expectations[]` / `assertions[]`.

`plugins/skill-quality/scripts/check-skill.sh` — 22 static checks. The ones that
bite this work:
- **check 3** trigger-keyword preservation vs the base ref: a rewrite that drops a
  single-quoted `'phrase'` from `description` **FAILs**. Directly constrains T2a.
- **check 2** `description + when_to_use ≤ 1536` chars.
- **check 4** `SKILL.md < 500` lines (FAIL), **check 10** ≤ 200 (WARN) — the
  hub-split budget.
- **check 5** backtick-cited skill-internal files must resolve, matched only
  inside `INTERNAL_DIRS='context|templates|scripts|reference|references|actions|evals|lanes|catalog|vendor'`
  (`check-skill.sh:221`) — this is the T7 pre-check the design already recorded.
- **check 8** `vendor/` byte-identity vs HEAD unless paired with a version bump.
- **check 14** evals presence, hard-FAIL when `--require-evals`, which
  `scripts/check-changed-skills.sh` passes **whenever the skill's `SKILL.md` is
  new or modified**. A source-agnostic rewrite of `SKILL.md` therefore makes
  evals mandatory by construction — **T9's fixture question cannot be deferred.**

`plugins/skill-quality/scripts/check-evals-quality.sh` (CI, whole-repo, every
event): FAIL on duplicate `id`/`name`, non-gradeable criterion, or a `files[]`
entry that resolves to nothing **or escapes the roots** (absolute or `..`).
WARN Q9 is set-level: at least one case in the set should carry
refusal/guardrail language — both sibling knowledge skills have a routing-refusal
case; **`youtube-digest` currently has neither a routing/refusal case nor an
injection case**, which is a gap a multi-source skill should close anyway.

### 6.5 Where a new source's fixtures land

| Kind | Path |
|---|---|
| Skill-level goldens (`<source>-video-goldens.json`) | `plugins/knowledge/skills/youtube-digest/evals/fixtures/` |
| Caption/transcript snippets for the transcript graders | `plugins/knowledge/skills/youtube-digest/extraction/evals/fixtures/` |
| Adapter unit-test input (metadata JSON, API payloads) | `<adapter-dir>/fixtures/` — precedent `extraction/harvesting/fixtures/` (outside the orphan gate) |
| The adapter's own suite | colocated `<adapter>.test.js` |

Repo-level files that would need updating: `extraction/package.json` +
`package-lock.json`; `plugins/knowledge/.claude-plugin/plugin.json` (version,
description, keywords, any new `userConfig`);
`plugins/knowledge/CHANGELOG.md` (`scripts/check-changelog-parity.sh
--check-bump` fails a manifest bump without a matching entry; no baseline
grandfathering for `knowledge`); `.claude-plugin/marketplace.json` tags;
`SKILL.md`'s "Eval fixtures" table (`SKILL.md:399-408`).
Ruled out by reading: `scripts/skill-leaf-name-registry.txt`,
`scripts/cross-plugin-source-registry.txt`, `scripts/contract-slice-baseline.txt`,
`scripts/skill-portability-tokens.txt`, `scripts/docs-only-paths.txt`
(its `youtube` mention at line 21 is a comment).

---

## 7. `course-digest/extraction/adapters/` read as a spec

Files: `adapter-contract.js` (88) + `.test.js`, `dometrain.js` (380) + `.test.js`,
`teachable.js` (362) + `.test.js`, `auth-session.js` (10); resolver
`extraction/lib/config.js`; docs
`reference/adapters/{discovery-checklist.md (407), dometrain.md (209), teachable.md (146)}`.

**Contract** (`adapter-contract.js:35-41`):

```js
const REQUIRED_METHODS = [
  "extractTranscript", "extractHlsUrl", "detectResources",
  "deriveLandingUrl", "buildLessonUrl",
];
```

Optional, JSDoc-typed only (`:21-28`): `setupSession`, `prepareLessonPage`,
`extractResources`, `extractMetadata`, `authenticate`, `preflight`,
`validateConfig`, `defaults`. Every method returns a `Result`.

**Dispatch** (`lib/config.js:44-51`): `resolveAdapter(platform)` — dynamic
`import('../adapters/${platform}.js')` keyed on `course.json`'s `platform`
field. No registry map, no `matches(url)` predicate. URL→platform mapping exists
**only as prose in `course-digest/SKILL.md`**. `createAdapter(platform,
platformCfg)` (`adapter-contract.js:70`) validates config first
(`validatePlatformConfig`, `REQUIRED_FIELDS = ["videoPlayerSelector","loginUrl","authEnvPrefix"]`),
then resolves, then validates the method set — each returning a `fail` Result.

**No capability declaration.** An adapter cannot express "I do not support X";
degradation is undefined. Contrast the tracker's `capabilities.json` + exit 6.

**What is bound to Playwright/browser and does NOT transfer:**

| Element | Binding |
|---|---|
| `extractTranscript`, `extractHlsUrl`, `detectResources` | all take `import('playwright').Page` (`:16-18`) |
| `prepareLessonPage`, `extractResources`, `extractMetadata`, `preflight`, `setupSession` | same (`:21-26`) |
| `REQUIRED_FIELDS` | `videoPlayerSelector` (DOM), `loginUrl` (browser auth), `authEnvPrefix` (credential env) — all three browser-auth concepts |
| `buildLessonUrl(course, lesson, cfg)` | assumes a **multi-lesson course object graph**; a single video has no lesson |
| `lib/players/{hotmart,mux}.js`, `lib/auth/{clerk,teachable-sso,manual-login}.js` | selected by **static import inside each adapter**, not a registry; no shared interface |
| `platform` from config | this lane has no config and must **infer the source from the URL** |

**What DOES transfer:** the *pattern* — plain object, explicit `REQUIRED_METHODS`
array, `validateAdapter` + `createAdapter` factory, `Result`-typed returns,
`fail()` naming the missing methods; the per-adapter colocated `*.test.js` +
a contract test that tests the **validator**, not each adapter; and
`deriveLandingUrl` / `buildLessonUrl` as *shape* (URL construction methods).

**The documented "add a source" procedure** is
`course-digest/reference/adapters/discovery-checklist.md`: nine phases —
Platform Identification, Lesson Content Survey, Transcript Extraction (incl.
"3.5 Fallback: audio extraction + Whisper" — relevant to T5), Video Frame
Extraction, Resource Extraction, Authentication Persistence, URL Patterns,
Verification Matrix, Platform-Specific Gotchas, plus a Regression Checklist. It
is browser/LMS-shaped throughout, but the **document shape** (per-source spoke
under `reference/<kind>/<name>.md`) is exactly what T7 option (a) proposes to
reuse — this is the reuse candidate, and it is in the same plugin.

---

## 8. The `x` plugin

Whole plugin: `plugins/x/.claude-plugin/plugin.json`, `CHANGELOG.md`,
`README.md`, `skills/read/SKILL.md` (268), `skills/read/context/failure-modes.md`
(233), `skills/read/evals/evals.json`. **No `extraction/`, no scripts, no lib, no
hooks, no MCP server.**

**What it does.** Text only: an X post, note tweet, or X Article → Markdown.
A match-capture-rebuild URL gate (four anchored regexes, `SKILL.md:52-70`), then
a two-step ladder — step 1 a raw `curl -X POST https://xtomd.com/api/markdown`
spooled to `${CLAUDE_PLUGIN_DATA}` and Read in ≤256 KB slices; step 2
`WebFetch https://threadreaderapp.com/thread/<id>.html` for an unrolled chain;
step 3 ask.

**What it returns.** Markdown, attributed with handle + date and **the gate's
rebuilt URL**. `/api/fetch` (JSON) exposes `text`, `rawText`, `media`,
`quoteTweet`, `isNoteTweet`, engagement counts.

**Reusable seam? No.**
- Its only tool grant is `allowed-tools: WebFetch(domain:threadreaderapp.com)`;
  step 1 is a bash `curl` with **no Bash pre-approval, deliberately**, so the
  permission prompt is the one runtime-enforced control (`SKILL.md:114-118`).
- There is no callable function, no CLI, no exported module. It is invocable
  **only as a skill**, in the agent lane.
- The gate is explicitly *"instruction-level, model-honored, and not
  runtime-enforced"* (`SKILL.md:114`). This is the concrete basis for T10's
  unenforced-invariant sub-decision: a CLI-invoked adapter gets **no** gate.

**Video:** nothing in `/x:read` handles video. The single hint is `/api/fetch`'s
unused `media` field. Whether X video is reachable at all — and by what tool — is
the external-research agents' question, out of scope for this pass.

**Posture precedent that binds T10:** `docs/conventions/seam-phrasing/README.md`
requires an optional cross-plugin reference to carry a presence gate, a stated
fallback, and ownership framing — and states *"'Skip silently' is not a
fallback"*. `youtube-digest/SKILL.md:20` already models this for
`/discovery:research`.

---

## 9. Git history and rename blast radius

### 9.1 How the lane reached its shape

| Commit | Date | Meaning |
|---|---|---|
| `c4aa3515` | 2026-07-12 | **Import: 176 files, 15,941 insertions.** `acquisition/`, `transcript/`, `watch/`, `watching/`, `harvesting/`, `lib/`, the epic/queue machinery, and preflight **all created here**. Verified via `git log --follow --diff-filter=A` on representative files |
| `7fe8aaec` | 2026-07-12 | `library_dir` honored — work-root seam wired in (#145) |
| `5dbcb5d6` | 2026-07-13 | **Vendor dedup** — deletes youtube's own `extraction/vendor/**` copy, renames course-digest's to `plugins/knowledge/vendor/` |
| `8ea666e8` | 2026-07-13 | Recovery / throttle / path-safety hardening (#157) |
| `d4987598` | 2026-07-14 | Topic-docs convention adopted across the artifact seam (breaking) (#179) |
| `f0aa5727` | 2026-07-17 | **The rename** `youtube` → `youtube-digest` (§9.2) |
| `38f2d316` | 2026-07-17 | Skill-channel scalars migrated to native `userConfig` (#325) |
| `3b816c29` | 2026-07-21 | Portable `library_dir` value forms (0.9.0) (#894) |
| `9ec347dc` | 2026-07-21 | **`--target` seam + named agnosticism gaps** (#854) — see §9.3 |
| `54760845` | 2026-07-21 | First commit to add `youtube` to `.github/workflows/ci.yml` (0.9.2) (#906) |
| `28c34d84` | 2026-07-25 | Resolved `--target` persisted in `WatchState` (#1376) |
| `b01dace3` | 2026-08-10 | Repo-wide `/simplify` pass (#2142) |

22 commits total have touched the skill dir; the tree is 157 files today.

### 9.2 The rename — slice, commit, and today's radius

**Slice: `docs/topics/shadowed-skill-renames/PLAN.md`** (one file, 88 lines).
Locked constraints that bind T2b:
- **No `renames`-map entries in `marketplace.json`** — every rename is a clean
  breaking change with a version bump.
- Skill frontmatter `name` must match its directory.
- One PR per affected plugin, carrying **all** repo-wide reference updates
  atomically; minor version bump; `/docs-hygiene:rename-references` sweep before
  merge.
- Acceptance: no file references a dead skill name; CHANGELOG note marks it
  breaking.

**Rename commit `f0aa5727` (2026-07-17, PR #275): 166 files = 156 `R` + 10 `M`.**
The 156 renames are the whole skill dir. The 10 modified files were the **entire**
non-skill-dir radius at the time:

| Category | Files |
|---|---|
| Plugin manifest | `plugins/knowledge/.claude-plugin/plugin.json` |
| CHANGELOG | `plugins/knowledge/CHANGELOG.md` |
| Plugin README | `plugins/knowledge/README.md` |
| Repo docs | `docs/MIGRATION-PLAYBOOK.md`, `docs/knowledge-integration-design.md` |
| Sibling-skill cross-refs | `course-digest/SKILL.md`, `course-digest/context/storage-schema.md`, `course-digest/evals/evals.json`, `course-digest/extraction/setup-deps.mjs`, `course-digest/reference/adapters/discovery-checklist.md` |

Deliberately skipped then: `docs/CATALOG*.md`, cheat sheet, `scripts/*registry*`,
`.github/workflows/`, `prompts/`, `vendor/`, marketplace `renames`. `youtube` was
kept as a discovery keyword. Internal identifiers not derived from the skill name
(`@melodic/youtube-extraction`, `{tmp}/youtube-*`) were kept.

**Today's radius is larger, and the difference is entirely surfaces that postdate
the rename.** 20 tracked files outside the skill dir reference `youtube-digest`,
including `.github/workflows/ci.yml` (11 lines, 6 functional — see C5; zero hits
in the `f0aa5727` version of that file), plus `docpage-digest/SKILL.md`,
`map-corpus/SKILL.md`, `setup/SKILL.md`, `vendor/video-digestion/TUNING.md`,
`docs/CLOUD-SESSIONS.md`, and three `docs/topics/**` slices.
`docs/CATALOG-TAXONOMY.md:90` names a hypothetical standalone `youtube` **plugin**
as a graduation trigger — a source-agnostic rename makes that trigger stale.

**Tooling that must be re-run or re-checked after a rename** (each script read):

| Tool | Verdict |
|---|---|
| `scripts/generate-catalog.mjs` (CI-gated via `scripts/validate-plugins.sh:17`) | **Does not move** on a skill rename — renders `plugin.json` prose, never skill dir names |
| `scripts/generate-cheatsheet.mjs` (`validate-plugins.sh:18`) | **Does not move** — `scripts/cheatsheet-config.mjs:41` excludes the whole `knowledge` plugin |
| `scripts/check-skill-leaf-names.sh` + `skill-leaf-name-registry.txt` | No `youtube*` entry today. **Discriminating: if the new leaf name collides with an existing one (e.g. a bare `digest`), a registry entry with the exact sorted owner set becomes mandatory** |
| `scripts/check-changelog-parity.sh` (four modes, all in CI `:614-633`) | A version bump **must** add a matching `## [<v>]` heading |
| `scripts/check-orphaned-fixtures.sh` (CI `:590`) | Path/basename-coupled — re-derives if `evals/fixtures/**` moves |
| `.github/workflows/ci.yml` | **Hand-edited, no generator** — the six functional couplings must be updated by hand |
| `docs/topics/shadowed-skill-renames/PLAN.md` | The convention itself |

All of `check-skill-leaf-names.sh`, `check-changelog-parity.sh`,
`check-orphaned-fixtures.sh`, `generate-cheatsheet.mjs`, and the CI job
**postdate** `f0aa5727`. The historical rename is therefore not a full-cost
precedent.

### 9.3 Prior source-agnosticism attempts

**None.** `git log --grep` across `source-agnostic|multi-source|adapter|twitter`
returns nothing in this lane; `adapter` hits are the work-items tracker and
`ai-adoption-ladder` channel adapters. `abe914ea` (2026-07-25) added the `x`
plugin but never touched `knowledge`.

Three forms of prior art do exist:
1. **`9ec347dc` (#854)** — doc-only; added `--target` and **explicitly named two
   unbuilt agnosticism gaps** rather than leaving them silent (`library_dir`
   relocates the root but not the sub-path shape; raw media stays OS-temp-only).
   Its "Related" note is the key one: making the landing sub-path swappable
   *"means centralizing that literal path construction, which is currently
   scattered across ~10 extraction scripts"*. Tracked in #856; never executed.
   **Same scattered-literal problem this refactor hits.**
2. The vendored layer was authored provider-agnostic in intent from day one
   (`frames/scene-detect.js:5`, `transcript/vtt-parser.js:19`) — though §4 shows
   the intent is not fully honored.
3. `course-digest`'s adapter seam — real code, not just docs, and its `SKILL.md`
   is **224 lines while carrying two platforms**, against this skill's 410 with
   one.

### 9.4 Branch state

`refactor/source-agnostic-video-digest` has **zero commits vs `origin/main`**
(`merge-base == HEAD == d4372fbc`). The entire delta is **untracked**:
`docs/topics/source-agnostic-video-digest/design/{capability-matrix.md,
design-threads.md,hub-split-budget.md,inherited-decisions.md}` and
`.work/source-agnostic-video-digest/`.

---

## 10. Open questions and unverified claims

Flagged rather than resolved.

1. **`select-caption.js` "MANAGED"** (C4). Nothing in this repo marks it. Either
   verify against `melodic-software/standards`'s
   `distribution/sync-manifest.yml` or drop the invariant — two design threads
   (T5, and `inherited-decisions.md:17`) currently rest on it.
2. **ADR 0022 is absent from this repo** (verified). If the reuse-or-replace
   argument cites the tracker seam's authorization, that citation is
   unresolvable here.
3. **`YOUTUBE_ACQUIRE_PHASE_GAP_SEC`** (`acquire.js:24`) is an undocumented env
   knob outside both `run-args.js`'s flag map and `plugin.json`. A2's namespace
   decision must cover it explicitly.
4. **`detect-recoverable-bootstrap.js:112`** hardcodes both the YouTube-named
   script path and the recovery command shape — it is a rename surface *and* an
   entry-point surface, and appears in neither the eleven nor T2b's blast radius.
5. **`export-sheet-frame-index.js:75`** writes `"{tmp}/youtube-sheets-unknown"`
   into a **staged** artifact. Any "the epic constant is the only YouTube string
   in a consumer's git history" claim is false while this stands.
6. **X video reachability** is out of this pass's scope — `/x:read` is text-only
   and nothing in-repo acquires X media. Deferred to the external-research lane.
7. **`youtube-digest/evals/evals.json` has no routing/refusal or
   injection-resistance case**, unlike both sibling knowledge skills. Q9 is only
   a WARN, but a multi-source skill that dispatches on URL host should carry an
   unsupported-host refusal case regardless.
