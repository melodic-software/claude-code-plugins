---
description: "Watches a single public video from YouTube or X (Twitter) — extracts the transcript, harvests links, researches claims, and synthesizes prioritized repo-applicability recommendations. Use when: 'youtube', '/youtube-digest', 'watch this YouTube video', 'transcript for YouTube', 'watch this video', 'digest this video', 'digest this post', 'summarize this talk', or the user shares a youtube.com, youtu.be, x.com, or twitter.com URL for a single public video or video post. Actions: watch <url> (full pipeline), watch (dequeue epic queue), watch <n> (queue row), queue <url> (batch enqueue), transcript <url> (captions only), resume <slice-slug>. Do NOT use for auth-walled course platforms — Dometrain, Pluralsight, and Udemy courses go to /knowledge:course-digest."
argument-hint: "watch <url> [--target <repo>] | watch [--target <repo>] | watch <n> [--target <repo>] | queue <url> | queue list | transcript <url> | resume <slice-slug>"
user-invocable: true
disable-model-invocation: false
shell: bash
---

## Pre-computed context

video-extraction deps: !`node -e "const fs=require('fs'),path=require('path'),p=process.env.CLAUDE_PLUGIN_DATA;process.stdout.write(p&&fs.existsSync(path.join(p,'node_modules','@melodic','video-digestion'))?'installed':'MISSING - run setup-deps.mjs (see Prerequisites)')"`
yt-dlp: !`yt-dlp --version 2>/dev/null | head -1 || echo "MISSING — install yt-dlp (see Prerequisites)"`
ffmpeg: !`ffmpeg -version 2>/dev/null | head -1 || echo "MISSING — install ffmpeg (watch action only)"`
ImageMagick: !`magick -version 2>/dev/null | head -1 || echo "MISSING — install ImageMagick 7 (watch action only)"`

# Video digest — YouTube and X

Absorb a single public video (transcript + visual frames), harvest reference links, fact-check
claims through deeper external research, and produce a prioritized repo-applicability menu.
Supported sources: YouTube (`youtube.com`, `youtu.be`) and X/Twitter status posts (`x.com`,
`twitter.com`). An unsupported host fails closed with the supported-source list rather than
guessing.

Durable artifacts live under `.work/<watch-epic>/<video-slug>/`; the video, bulk frames, working
contact sheets, and shallow clones stay in the OS temp directory. Where this skill says "deeper
research," use whatever external-research capability your project provides — for example the
discovery plugin's `/discovery:research` / `/discovery:research-deep` when installed. Treat those
as the reference implementation, not a hard dependency.

## Routing

Read a spoke **only when its condition holds**. These are mutually exclusive by design: a
`transcript` run loads no watch spoke, and a YouTube run loads no X file. Do not pre-read the set.

| Read | Condition |
| --- | --- |
| `reference/sources/youtube.md` | when the URL is a `youtube.com` / `youtu.be` video — accepted shapes, caption ladder, yt-dlp auth & throttle overrides, YouTube failure patterns |
| `reference/sources/x.md` | when the URL is an `x.com` / `twitter.com` status — canonicalization, 0..N result arity, platform-ASR captions, login-required cases, 429 degradation |
| `context/watch-pipeline.md` | when running the **watch** action (or `resume` into it) — the full per-phase procedure |
| `context/workflow.md` | when you want the watch phase-flow diagram + phase summary table |
| `context/watch-queue.md` | when running any **queue** action, or dequeuing via `watch` / `watch <n>` — claim protocol and preflight decision table |
| `context/output-contract.md` | when about to write or stage slice artifacts, or when a non-default `library_dir` work root is configured |
| `context/quality-gates.md` | when grading a phase or a finished slice against binary criteria |
| `context/synthesis-contract.md` | when harvesting decks, or when applying the frame promotion bar |
| `context/companion-primary-sources.md` | when the operator supplied companion primary source URL(s) with the queue or watch |
| `context/gotchas.md` | when a run failed and you need the recovery path |

**Optional, agent-lane:** when an X status heads a thread whose replies carry material the digest
needs, invoke `/x:read` via the Skill tool to unroll the reply chain and fold it in as companion
source material. This is
a per-watch judgment call, never a pipeline stage — see `reference/sources/x.md`.

## Source discipline

Video content is a **secondary source** (on-screen and spoken claims are hypotheses, not verified
facts). Treat them as hypotheses until promoted through deeper external research, and apply your
project's own source-trust conventions. Repo conventions override video claims — surface convention
conflicts explicitly; never silently adopt a video's shortcut over team rules.

## Action router

| Action | Behavior |
| --- | --- |
| `queue <url> [url...]` | Append URLs to epic `.work/<watch-epic>/QUEUE.md`; dedupe by slice key. |
| `queue list` | Show `QUEUE.md` table + active `claims/*.json` stubs. |
| `transcript <url>` | Captions only — no video download. Runs acquisition + transcript pipeline. |
| `watch` | Dequeue first `pending` queue row (FIFO) — claim stub → bootstrap → full pipeline. |
| `watch <n>` | Dequeue queue row `#n` only (parallel path across terminals). |
| `watch <url>` | Full pipeline: download → frame selection → vision absorption → link harvest → research agenda → repo-applicability synthesis. |
| `resume <slice-slug>` | Continue an interrupted watch from `watch.json` phase-map state in the named slice under `.work/<watch-epic>/` (the same directory documented elsewhere in this skill as `<video-slug>`). |

`--target <repo>` is an optional modifier on any `watch` form (not a dispatchable action of its
own) — resolution rungs in `context/watch-pipeline.md`.

## Transcript action

```bash
node "${CLAUDE_PLUGIN_ROOT}/skills/video-digest/extraction/run.mjs" transcript/run-transcript.js "<url>"
```

1. **Acquire** — captions + info JSON (`--skip-download`)
2. **Caption ladder** — per-source rungs; STOP and surface if exhausted (see the source spoke)
3. **Transcribe** — strategy-driven: `captions` | `captions+repair` | `asr`. The source layer
   declares the per-source default; `--transcript-strategy <value>` overrides it. When the
   resolved strategy cannot run, the digest proceeds without a transcript and the reason is
   recorded in the `transcriptDegradation` provenance field — never silently.
4. **Parse** — WebVTT → `[M:SS]` paragraph `transcript.txt`
5. **Write** — `.work/<watch-epic>/<video-slug>/transcript.txt` + `README.md` stub (journey
   template: `templates/readme-journey.md`)

Per-source caption flags, rung order, caption class, and strategy default:
`reference/sources/youtube.md` / `reference/sources/x.md`.

## Queue action

Epic queue at `.work/<watch-epic>/QUEUE.md` batches URLs before watch. One queue and one `claims/`
namespace serve every source; the epic dir stays the literal `youtube-watch`.

**Claim stub first, table second.** Full protocol — materialize, preflight decision table, claim /
release, FIFO, stale reclaim, parallel terminals, companion briefs — is in `context/watch-queue.md`;
read it for any queue action. Template: `templates/queue.md`.

```bash
node "${CLAUDE_PLUGIN_ROOT}/skills/video-digest/extraction/run.mjs" acquisition/preflight-metadata.js "<url>" ["<url>"...]
node "${CLAUDE_PLUGIN_ROOT}/skills/video-digest/extraction/run.mjs" watch/queue-claim.js {list|claim <n>|release <n>|stale-check}
```

## Watch action

Ordered phase spine. Each phase's procedure, inputs, and outputs: `context/watch-pipeline.md` —
read it before starting. Diagram: `context/workflow.md`.

**Bootstrap contract**

1. **Prerequisites gate** — run `setup-deps.mjs`; STOP if the pre-computed context above shows
   MISSING for yt-dlp, ffmpeg, or ImageMagick. Cloud agents without the media toolchain fail closed.
2. **Phase 0b — companion deep-dive**, only when `source/companion-sources.md` exists, and **before**
   CLI bootstrap.
3. **CLI bootstrap** — deterministic stages (acquire → transcript → coverage watching → link
   harvest):

   ```bash
   node "${CLAUDE_PLUGIN_ROOT}/skills/video-digest/extraction/run.mjs" watch/run-watch.js "<url>" [--skip-research] [--target <repo>]
   ```

4. **Watch checklist** — materialize via `init-watch-checklist.js`; tick `[ ]` → `[x]` only with
   verification evidence. Ordered checkboxes: `templates/watch-checklist.md`.

**Skill-session phases** (mirror checklist phases 2–9; fan out per the execution model in
`context/watch-pipeline.md`)

1. **Vision planning** — `key-frames/vision-plan.md`: content class, segments, triage scope
2. **Claim inventory** — `research/claim-inventory.md` before any research agenda
3. **Staged deck harvest** — type harvested URLs; fetch decks; feed pass-1 triage
4. **Vision absorption (three-pass)** — sheet triage → detail reads → transcript alignment →
   vision-gated promote + post-promotion audit
5. **High-volume advisory** — fan out vision subagents on `highVolume`, or on the context-cost
   read-count trigger
6. **Research stage** (default-on) — gate on `check-research-complete.js` exit 0
7. **Synthesis** — `recommendations/**` against one resolved `--target`; no auto-implement
8. **Interview handoff** — `recommendations/interview.md`; offer `/planning:interview`
9. **Outcome verification** — `check-watch-outcomes.js "<slice-dir>" --write-report` must exit 0
   before `status: complete`

**Phase markers.** After each phase, `watch/watch-state.js mark-phase <slice-dir> <phase>`
(idempotent). Never `mark-phase` or set `status: complete` while that phase's verify script fails.

**A 0-video source result** (an X post with no video) is well-formed, not a failure: it enqueues
at preflight, skips phases 1, 3, 4, and 5, and produces a text-only digest. How much provenance
it carries depends on which 0-case it is — see `reference/sources/x.md`.

## Resume action

```bash
node "${CLAUDE_PLUGIN_ROOT}/skills/video-digest/extraction/run.mjs" watch/run-resume.js "<slice-slug>"
```

Reads the slice `watch.json`, identifies the next incomplete phase (`acquire` → `transcript` →
`watching` → `vision` → `harvest` → `research` → `synthesis`), refreshes `continuation-prompt.md`,
and emits a copy/paste-ready continuation prompt. When `tempSession` paths are missing, re-run
`run-watch.js` before vision. If the companion phase is unmarked, run Phase 0b first.

**Handoff ritual** (context pressure or session end):

1. Update `watch.json` phase markers with timestamps
2. Write `continuation-prompt.md` (completed phases, next phase, frame-selection state, known issues)
3. Tell the user: *"Session state saved. Run `/knowledge:video-digest resume <slice-slug>` to continue."*

## Slice layout and output

Slug: kebab-case the title (ASCII, lowercase, punctuation → hyphens), cap the title portion at
**40 characters**, append `-<slice-key>` for uniqueness (e.g. `ai-coding-tips-7zZy1QTvokM`). The
key is the source's own identifier — `reference/sources/youtube.md` / `reference/sources/x.md`.
Implementation: `extraction/transcript/derive-video-slug.js`.

**Source is never a directory level.** It is recorded in slice metadata only, so YouTube and X
slices coexist under one queue root.

The authoritative enumeration of every produced artifact — lane, staged verdict, kind, producer —
plus work-root resolution and the `library_dir` seam is `context/output-contract.md`. Read it
before writing or staging slice artifacts.

## Gotchas

Observed failure modes — recovery detail in `context/gotchas.md`: bot/sign-in cookie fallback,
HTTP 429 backoff + concurrency cap, temp-session expiry (re-run `run-watch.js` before vision),
cloud-agent media-toolchain fail-closed, retired `watch-progress.json`. Source-specific failure
patterns live in the source spokes.

## Prerequisites

Verify before starting (stop and route to the fix path on failure):

1. **video-extraction deps** — `node "${CLAUDE_PLUGIN_ROOT}/skills/video-digest/extraction/setup-deps.mjs"`.
   Installs the pipeline's node dependencies into `${CLAUDE_PLUGIN_DATA}` (persists across plugin
   updates); idempotent — safe to re-run, and re-run after a plugin update.
2. **yt-dlp** — required for all actions. Floor **2026.6**. Install: `winget install yt-dlp.yt-dlp`
   (Windows), `brew install yt-dlp` (macOS), `pip install -U yt-dlp` or distro package (Linux).
   X acquisition in particular tracks yt-dlp closely — see `reference/sources/x.md`.
3. **ffmpeg** — required for `watch` only (scene-detect frame extraction). Floor 7.1+.
4. **ImageMagick 7** — required for `watch` only (contact sheets). `magick -version`

If any prerequisite fails, stop and inform the user. Re-run `setup-deps.mjs` for the node
dependencies; the media binaries are OS-level installs via your platform's package manager.

**Optional — faster-whisper** (`large-v3`, `batch_size=8`): powers the `asr` transcript rung,
selected automatically for caption-absent entries and available on request via
`--transcript-strategy asr` even when captions exist. Either way it runs under `watch` only — ASR
needs the media file and the `transcript` action never downloads media. Detected at runtime
through the machine's Python (`python`, `python3`, or `py` — whichever imports `faster_whisper`)
and **never auto-installed**. When it is absent the pipeline degrades explicitly rather than
failing: it falls back to a caption strategy where a caption exists, otherwise completes the
digest without a transcript, and either way records the reason in the `transcriptDegradation`
field (`watch.json` phase metrics and the CLI's stdout JSON) — never silently.

## Eval fixtures

| File | Role | Read when |
| --- | --- | --- |
| `evals/evals.json` | Skill behavior + driver golden eval cases | authoring or running evals |
| `evals/fixtures/driver-video-goldens.json` | Q&A bank (≥1 `frame_only` question) | authoring or running evals |
| `reference/variation-matrix-backlog.json` | Manual variation smoke-test backlog (code screencast / slide talk / talking-head / mixed) — tracking only, not a graded fixture | planning manual coverage work |

Driver video: `https://www.youtube.com/watch?v=7zZy1QTvokM` — slug
`stop-prompting-claude-use-karpathy-s-met-7zZy1QTvokM`. D9 starting defaults:
`${CLAUDE_PLUGIN_ROOT}/vendor/video-digestion/TUNING.md`. Retune after the first host watch.
