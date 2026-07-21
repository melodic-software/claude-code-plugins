---
name: course-digest
description: "Extract and synthesize online video courses into repo-applicable recommendations via browser automation (Playwright + claude-in-chrome), transcript extraction, frame analysis, and LLM synthesis. Use when: 'course digest', 'digest this course', 'analyze course', 'Dometrain', 'watch this course for me', 'course takeaways', 'extract from course', 'summarize course', user shares a Dometrain/Pluralsight/Udemy course URL, or wants course patterns applied to their codebase. Single public YouTube videos → use /knowledge:youtube-digest. Actions: full pipeline (default), extract (phases 1-2 only), analyze (phases 3-5 only), status (list all digested courses), resume <slug> (continue extraction), continue <slug> (resume from saved session state)."
argument-hint: "[action] [url|slug] (e.g., /knowledge:course-digest <url>, /knowledge:course-digest extract <url>, /knowledge:course-digest resume <slug>, /knowledge:course-digest status)"
user-invocable: true
disable-model-invocation: false
shell: bash
---

## Pre-computed context

course-extraction deps: !`node -e "const fs=require('fs'),path=require('path'),p=process.env.CLAUDE_PLUGIN_DATA;process.stdout.write(p&&fs.existsSync(path.join(p,'node_modules','@melodic','video-digestion'))?'installed':'MISSING - run setup-deps.mjs (see Prerequisites)')"`
Playwright Chromium: !`node -e "const fs=require('fs'),path=require('path');const b=process.env.PLAYWRIGHT_BROWSERS_PATH||(process.env.CLAUDE_PLUGIN_DATA&&path.join(process.env.CLAUDE_PLUGIN_DATA,'ms-playwright'));const ok=b&&fs.existsSync(b)&&fs.readdirSync(b).some(n=>n.startsWith('chromium'));process.stdout.write(ok?'installed':'MISSING - run setup-deps.mjs (see Prerequisites)')"`
ffmpeg: !`ffmpeg -version 2>/dev/null | head -1 || echo "MISSING — install ffmpeg (see Prerequisites)"`
ImageMagick: !`magick -version 2>/dev/null | head -1 || echo "MISSING — install ImageMagick 7 (see Prerequisites)"`

# Course Digest

Transform online video courses into structured knowledge and actionable repo recommendations — without watching a single video.

## How it works

Uses browser automation (claude-in-chrome) to navigate course platforms, extract transcripts, capture screenshots of code/slides, and collect downloadable resources. Synthesizes raw content into analysis focused on what applies to the current repository.

Where this skill says "deeper research," use whatever external-research capability your project provides. Repo conventions override course claims — surface convention conflicts explicitly; never silently adopt a course's shortcut over team rules.

## Emit checklist

For any course digest run (multi-phase content acquisition + distillation + repo-applicability analysis), copy `templates/checklist.md` into `.work/<slug>/course-digest-checklist.md`. Tick each phase as completed.

This skill's `.work/` root is **formally carved out** of the marketplace topic-docs convention (<https://raw.githubusercontent.com/melodic-software/claude-code-plugins/main/docs/conventions/topic-docs/README.md>): the work root resolves through the knowledge plugin's own `library_dir` seam, not the concern file's `memory_dir`; slug conformance is form-only (kebab-case `[a-z0-9-]`, ≤ 40 chars, Windows-reserved base names take an `-x` suffix); and nested `<epic>/<slug>/` sub-slices are sanctioned. The root still self-ignores (a `.gitignore` containing `*`) and is never committed.

## Prerequisites (verify before starting)

1. **course-extraction deps** — `node "${CLAUDE_PLUGIN_ROOT}/skills/course-digest/extraction/setup-deps.mjs"`. Installs the pipeline's node dependencies into `${CLAUDE_PLUGIN_DATA}` (persists across plugin updates) and provisions Playwright's Chromium into `${CLAUDE_PLUGIN_DATA}/ms-playwright`. Idempotent — safe to re-run, and re-run after a plugin update.
2. **Platform auth** — set `COURSE_EMAIL`/`COURSE_PASSWORD` (Dometrain → Clerk) or `TEACHABLE_EMAIL`/`TEACHABLE_PASSWORD` (Teachable) in your shell before invoking; they inherit into the pipeline's node subprocess. The env-var prefix is course-config-driven via `platformConfig.authEnvPrefix`. Session cookies persist under `${CLAUDE_PLUGIN_DATA}/auth/<platform>.auth-state.json` and are reused across runs. **Interactive manual login is the fallback** when no credentials are set — it opens a browser window for you to log in. NOTE: the manual-login prompt (`node:readline` + headed browser) may not function under headless plugin execution; env-var + cookie-reuse carry the skill regardless, and manual login is a known limitation there, not a blocker. These credentials stay in shell env (rather than migrating to plugin `userConfig` like this plugin's non-secret scalars) deliberately: a `sensitive: true` userConfig option still persists as plaintext in `~/.claude/.credentials.json` on Windows, so they remain in env until keychain-backed sensitive storage lands there.
3. **ffmpeg** — required for video frame extraction (scene detection, interval capture). Check: `ffmpeg -version`. Install: `winget install Gyan.FFmpeg` (Windows), `brew install ffmpeg` (macOS), `sudo apt install ffmpeg` (Linux). Floor 7.1+ (newer codecs — AV1, Opus — degrade or fail below this).
4. **ImageMagick 7** — required by `classify-frames.js` for contact sheet generation (`magick montage`). Check: `magick -version`. Install: `winget install ImageMagick.ImageMagick` (Windows), `brew install imagemagick` (macOS), `sudo apt install imagemagick` (Linux). Ubuntu <26.04 ships v6 — v7 may require building from source.
5. **claude-in-chrome MCP** — needed for Phase 1 (course discovery) and frame extraction HLS URL retrieval. Run `tabs_context_mcp` as preflight.

If any prerequisite fails, stop and inform the user. Re-run `setup-deps.mjs` for the node dependencies + Chromium; the media binaries (ffmpeg, ImageMagick) are OS-level installs via your platform's package manager per the commands above.

## Running the pipeline scripts

Every extraction script runs through the launcher, which resolves the vendored node dependencies from `${CLAUDE_PLUGIN_DATA}` and pins Playwright's browser path:

```bash
node "${CLAUDE_PLUGIN_ROOT}/skills/course-digest/extraction/run.mjs" <script.js> [args…]
```

Gate on `setup-deps.mjs` first (Prerequisites above).

### Consolidated extraction (Phases 1-2)

The Playwright batch script handles transcripts, video frame extraction, and course metadata in a single run:

```bash
# Full extraction: transcripts + frames + metadata
node "${CLAUDE_PLUGIN_ROOT}/skills/course-digest/extraction/run.mjs" extract-course.js --course-dir <path-to-course-data> --extract-frames

# Transcripts only (faster, no ffmpeg needed)
node "${CLAUDE_PLUGIN_ROOT}/skills/course-digest/extraction/run.mjs" extract-course.js --course-dir <path-to-course-data>

# Frames only (skip transcripts already extracted)
node "${CLAUDE_PLUGIN_ROOT}/skills/course-digest/extraction/run.mjs" extract-course.js --course-dir <path-to-course-data> --extract-frames --skip-transcripts

# Course metadata only
node "${CLAUDE_PLUGIN_ROOT}/skills/course-digest/extraction/run.mjs" extract-course.js --course-dir <path-to-course-data> --metadata-only
```

Script uses Playwright's bundled Chromium with a fresh temp context (not Chrome itself — Chrome 136+ blocks CDP on default profiles). Auth handled via `addCookies()` after context launch: with credentials set it logs in and saves state; subsequent runs inject cached cookies automatically. Skips already-extracted lessons (crash-safe, resumable). Runs headless by default (`--show-browser` to show the browser).

**Key technical details:**

- Uses `--disable-blink-features=AutomationControlled` to bypass automation detection on course platform logins
- Chrome profiles are NOT used — Playwright's own Chromium with a dedicated temp context dir in the OS temp directory
- Auth state saved to `${CLAUDE_PLUGIN_DATA}/auth/<platform>.auth-state.json` (session expiry depends on the platform's auth provider, configured in `platformConfig.authWarnDays`)
- HLS video URLs captured via DOM read from the video player element (selector from `platformConfig.videoPlayerSelector`) — no claude-in-chrome needed
- Frame extraction via ffmpeg scene detection (threshold 0.1), with interval fallback for sparse results
- Content type derived from extraction results (scene detection = code, interval + high dup = talking head) — no manual tagging
- Progress tracking with per-lesson elapsed time, ETA, structured `run-report.json` output
- SIGINT handler saves progress on Ctrl+C — no work lost on interruption

**Long-running extractions (50+ lessons):** the CC Bash tool has a hard 10-minute timeout limit. For large courses:

```bash
# Run in background with nohup — no timeout limit
nohup node "${CLAUDE_PLUGIN_ROOT}/skills/course-digest/extraction/run.mjs" extract-course.js --course-dir <path> > extraction.log 2>&1 &
echo $!  # save PID

# Monitor progress periodically
tail -20 extraction.log

# Check run report after completion
cat <course-dir>/run-report.json
```

## Platform detection and adapter architecture

Extraction pipeline uses a **provider adapter pattern**. Platform-specific code lives in adapter modules (`extraction/adapters/{platform}.js`). The orchestrator (`extract-course.js`) delegates to adapters via a contract — zero platform-specific code in the orchestrator.

**Architecture:**

```text
extraction/
  adapters/
    adapter-contract.js       # JSDoc interface + validation + factory
    dometrain.js              # Thin adapter: composes mux (player) + clerk (auth)
    teachable.js              # Thin adapter: composes hotmart (player) + teachable-sso (auth)
  lib/
    players/
      hotmart.js              # Hotmart HLS: intercept, iframe subtitle fetch, canvas frames
      mux.js                  # Mux: DOM src read from mux-player element
    auth/
      clerk.js                # Clerk two-step login flow
      teachable-sso.js        # Teachable simple form login flow
    auth-store.js             # Resolves per-platform auth-state path under ${CLAUDE_PLUGIN_DATA}
    browser.js                # Shared Playwright launch, cookie injection, auth age check
    validators.js             # extraction validators
    config.js                 # platformConfig validation, adapter resolution
  # shared kernel + transcript: @melodic/video-digestion (vendored plugin-wide under ../../vendor/)
  extract-course.js           # Orchestrator only — delegates to adapter + lib
  discover-resources.js       # Discovery tool — uses adapter.detectResources()
  download-resources.js       # Download lesson resources (ZIPs, PDFs) from resources.json
  build-course-json.js        # Teachable-specific: scaffold course.json from curriculum page
  classify-frames.js          # Frame classification (provider-agnostic, no adapter needed)
  generate-manifests.js       # Manifest generation (provider-agnostic, no adapter needed)
  utils.js                    # Provider-agnostic utilities only
```

Adapters are thin composition layers — delegate to shared `lib/players/` and `lib/auth/` modules for reusable tech-layer concerns, keeping only platform-specific DOM selectors, URL patterns, and orchestration logic.

**Every adapter method returns `Result`** (`ok`/`fail` from `@melodic/video-digestion/shared/result`) — explicit success/failure with timing, operation name, context. No silent catches, no null returns.

| URL pattern | Platform | Adapter | Reference |
|---|---|---|---|
| `dometrain.com` | Dometrain | `adapters/dometrain.js` | [reference/adapters/dometrain.md](reference/adapters/dometrain.md) |
| `*.teachable.com`, `courses.*.tech` | Teachable (Hotmart video) | `adapters/teachable.js` | [reference/adapters/teachable.md](reference/adapters/teachable.md) |
| Single public YouTube videos | — | use /knowledge:youtube-digest | — |
| `pluralsight.com` | Pluralsight | (future) | — |
| `udemy.com` | Udemy | (future) | — |

**To add a new platform adapter:** follow [Provider Discovery Checklist](reference/adapters/discovery-checklist.md) to explore the platform systematically, then create `adapters/{platform}.js` implementing the 5 required methods (`extractTranscript`, `extractHlsUrl`, `detectResources`, `deriveLandingUrl`, `buildLessonUrl`). Compose from shared modules where the tech stack matches — e.g., a new platform using Hotmart video + Clerk auth would `import * as hotmart from "../lib/players/hotmart.js"` and `import * as clerk from "../lib/auth/clerk.js"`, then delegate player/auth methods while implementing only platform-specific DOM selectors and URL patterns. Add the platform to `course.json` `platform` field; the factory auto-discovers it via dynamic import. The discovery checklist also serves as regression guide when existing adapters break.

## The pipeline

Follow the 8-phase workflow in [context/workflow.md](context/workflow.md), each building on the previous — Discover → Extract → Process Frames → Analyze Code Repo → Validate → Synthesize → Analyze → Recommend (phases 1, 2, 2b, 2c, 2d, 3, 4, 5). Phases 1-2d are extraction (browser + CLI); 3-5 are analysis (LLM-heavy, parallelizable across modules). Storage runs continuously throughout.

**Critical rule:** ALL context (transcripts + frames + code repo) must be gathered before Phase 3.
Module summaries note their context level: `[transcript-only]`, `[transcript+frames]`, `[full-context]`.

### Phase 3 modalities (`[full-context]` requires all three)

Synthesis combines three modalities — transcript (`transcript.md`), visual frames (PNG files + `manifest.json`), and companion code (`code/repo/<section>/`). Each module gets parallel agents (transcript + visual + code exploration), then a synthesis pass. Full modality table + multi-agent approach: [context/workflow.md](context/workflow.md) Phase 3.

Multi-modal extraction gaps beyond these three (code OCR from frames, slide-text extraction, audio re-transcription) are evaluated with priority and effort in [context/multimodal-evaluation.md](context/multimodal-evaluation.md).

### Dedup semantics

Dedup phase (`classify-frames.js --phase dedup`) **reports** near-duplicates but does NOT
delete frame files. Actual frame curation happens in `generate-manifests.js` which sets
`keep: true/false` per frame. Frame PNG files remain on disk — manifests define which frames to use
during synthesis.

### Phase tracking

`course.json` includes a `phases` object recording which pipeline phases have completed and
when. Each phase is `null` (not started) or an object with `completedAt` timestamp and
phase-specific metrics. On resume, check which phases are non-null to skip completed work.

### Repo freshness caveat

Companion GitHub repos may be updated after course publication; classify transcript/code discrepancies per [context/workflow.md](context/workflow.md) "Freshness verification". **All course action items require external research verification before adoption** — course content is a starting point for research, not a final answer.

## Invocation patterns

Skill supports different scopes:

| User says | Action |
|---|---|
| `/knowledge:course-digest <url>` | Full pipeline — discover + extract all + analyze |
| `/knowledge:course-digest extract <url>` | Phases 1-2 only — extract raw content, skip analysis |
| `/knowledge:course-digest analyze <slug>` | Phases 3-5 only — analyze previously extracted content |
| `/knowledge:course-digest status` | Show all digested courses and their completion state |
| `/knowledge:course-digest resume <slug>` | Resume extraction from where it left off (reads course.json phases) |
| `/knowledge:course-digest continue <slug>` | Continue from a prior session — reads continuation prompt file |
| `/knowledge:course-digest` (no args) | Auto-detect: check for in-progress courses, resume the most recent |

### Session handoff protocol

When context is getting large (>40% used) or a session ending mid-pipeline:

1. **Write a continuation prompt** to `<course-dir>/continuation-prompt.md`
2. Include: what was completed, what remains, task-by-task breakdown, known issues, quality notes
3. Update `course.json` phase markers with timestamps
4. Tell the user: *"Session state saved. Start a new session and run `/knowledge:course-digest continue <slug>` to pick up where we left off."*

The `continue` action reads the continuation prompt and reconstructs task context. No args defaults to checking `course.json` for the most recent in-progress course.

## Pacing and user interaction

Courses can have 60+ lessons. Processing all in one session may hit context limits.

- **After discovering course structure** (Phase 1): present module/lesson list and ask user which modules to process, or confirm "all"
- **After every 5 lessons extracted**: report progress ("Extracted 5/67 lessons. Continuing...")
- **After each module completes**: save progress immediately — a crash shouldn't lose work
- **If context is getting large** (>50% used): suggest saving progress and resuming in a new session with `/knowledge:course-digest resume <slug>`

## Analysis output format

Repo-applicability analysis follows the template in [reference/analysis-template.md](reference/analysis-template.md). Key deliverables:

- **`repo-candidates.md`** — Specific patterns/practices from the course that could improve the repository, with references to where in the course they're taught
- **`action-items.md`** — Concrete next steps: rule candidates, skill suggestions, architecture patterns, testing practices, work-item candidates

## Storage

Generated course output lands under the invoking project's `library_dir` seam (or `${CLAUDE_PLUGIN_DATA}` when no library dir is configured), one self-contained directory per course slug. See [context/storage-schema.md](context/storage-schema.md) for the full directory structure.

**Critical rules:**

- No video or audio files — transcripts and screenshots capture the content
- Screenshots are PNG files — keep small (resize to 1280px wide max)
- Save progress incrementally — never buffer an entire course in memory
- Each course is self-contained under its own slug directory
