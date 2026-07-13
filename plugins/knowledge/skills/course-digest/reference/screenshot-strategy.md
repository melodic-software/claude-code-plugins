# Screenshot Strategy

When and how to capture visual content from course videos.

## When to capture

Screenshots add value only when visual content provides information beyond the transcript. Transcript already captures everything the instructor says — screenshots should capture what they show.

### Always capture

- **Code on screen** — IDE, editor, terminal showing code that the transcript describes but doesn't fully dictate
- **Architecture diagrams** — visual representations of system design, data flow, dependency graphs
- **Slide content with visual elements** — charts, tables, comparison matrices, flowcharts
- **Test output** — terminal showing test results (pass/fail counts, error messages)
- **File/project structure** — solution explorer, directory trees shown on screen

### Never capture

- **Talking head (full screen)** — the instructor speaking to camera with no visual aids
- **Title slides** — "Section 3: Testing" type slides (the title is in the transcript and course structure)
- **Sponsor/promo segments** — course platform branding, ads

### Judgment calls

- **Slides with text only** — capture if text is structured (bullet points, tables) and not fully read aloud
- **Browser/UI demos** — capture if visual layout matters; skip if transcript describes the interaction
- **Configuration files** — capture if file content is complex; skip if instructor reads it line by line
- **Near-duplicate frames** — same code with minor cursor movement. Keep only the most complete version

## Proven extraction pipeline (primary method)

Empirically validated on a 30-minute code-heavy lesson ("Writing the first Tests"). Uses ffmpeg to extract frames directly from HLS video stream — no browser rendering, no CORS, no shadow DOM.

### The three-step approach

```text
1. ffmpeg scene detection (threshold 0.1) → candidate frames
2. Claude vision classification → keep code/slides, discard talking-head
3. Manifest generation → auditable proof of what was captured
```

### Step 1: Get the HLS manifest URL

From lesson page, extract `.m3u8` URL with JWT token:

```javascript
const player = document.querySelector('mux-player');
const hlsUrl = player?.src;  // Full URL with ?token=eyJ...
```

### Step 2: Scene detection with ffmpeg

```bash
ffmpeg -y \
  -user_agent "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36" \
  -headers "Referer: https://dometrain.com/" \
  -i "HLS_URL_WITH_TOKEN" \
  -vf "select='gt(scene\,0.1)',scale=1280:-1" \
  -vsync vfr \
  screenshots/scene_%04d.png
```

### Step 3 (fallback): Interval capture

If scene detection yields fewer than 5 frames for a lesson longer than 5 minutes, fall back to interval capture:

```bash
ffmpeg -y \
  -user_agent "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36" \
  -headers "Referer: https://dometrain.com/" \
  -i "HLS_URL_WITH_TOKEN" \
  -vf "fps=1/15,scale=1280:-1" \
  screenshots/interval_%04d.png
```

### Key ffmpeg parameters

- **`-user_agent`**: Required — Mux rejects requests without a browser user-agent
- **`-headers "Referer: https://dometrain.com/"`**: Required — Mux playback restrictions enforce referer checks
- **`select='gt(scene\,0.1)'`**: Scene change threshold. 0.1 is the proven default
- **`-vsync vfr`**: Variable frame rate — only output selected frames (required with `select`)
- **`scale=1280:-1`**: Downscale to 1280px wide (code is still fully legible at this size)
- Output is PNG (lossless, good for code/text readability)

## Empirical threshold calibration

Tested on "Writing the first Tests" (29m 58s, code-heavy, Rider IDE):

| Threshold | Frames | Result |
|---|---|---|
| 0.1 | 63 | Captures TDD phase transitions, code changes, dialog opens. ~2 frames/min. 100% useful content in sample |
| 0.2 | 2 | Misses almost everything — only catches very large visual changes |
| 0.3 | 0 | Catches nothing — screencast transitions are too subtle |

**Recommendation: use 0.1 as the default.** Cliff between 0.1 and 0.2 is dramatic for screencast content because visual changes are incremental (typing, scrolling) rather than hard cuts.

### Why 0.1 works for this instructor

This instructor (Guilherme Ferreira) uses **TDD phase overlays** — colored banners showing RED, GREEN, or REFACTORING that appear/change during TDD cycle. These overlays trigger scene changes at exactly the right moments: when TDD phase transitions, which is when code on screen has meaningfully changed.

### Caveat: instructor variability

Not all instructors use visual overlays. For courses without overlays:

- Scene detection at 0.1 will still catch IDE ↔ terminal ↔ slide transitions
- But within a sustained coding segment, it may only catch significant scrolls or file switches
- **Supplement with interval capture (fps=1/15)** for code-heavy lessons without overlays
- Use vision classification more aggressively to deduplicate near-identical frames

Test on the first code-heavy lesson of any new course to calibrate before processing the rest.

## Vision classification (Step 2)

After frame extraction, classify each frame using Claude vision:

**Classification categories:**

| Category | Keep? | Description |
|---|---|---|
| `code` | Yes | IDE showing source code (C#, tests, config) |
| `terminal` | Yes | Terminal/console output (test results, build output) |
| `slide` | Yes | Presentation slide with visual content |
| `diagram` | Yes | Architecture diagram, flowchart, UML |
| `test-explorer` | Yes | Test runner showing pass/fail results |
| `dialog` | Maybe | IDE dialog (refactoring, search, settings) — keep if shows important action |
| `talking-head` | No | Full-screen face, no code visible |
| `duplicate` | No | Near-identical to a previous frame (same code, minor cursor change) |

**For courses with picture-in-picture webcam:** Instructor's face appears as a small overlay in the corner of every frame. Classification is "what is the PRIMARY content" — IDE is primary, face overlay is irrelevant.

**At 1280px width, code is fully legible** — method names, test assertions, class structure, even parameter types are readable. No need to keep 1920x1080 for vision analysis.

## Manifest generation (Step 3)

Generate a JSON manifest per lesson pairing frames with transcript context. This is the **proof of correctness** — anyone can audit it against the actual video.

```json
[
  {
    "file": "scene_0001.png",
    "timestamp": 15,
    "timestampEstimated": true,
    "type": "code",
    "description": null,
    "keep": true,
    "transcriptContext": "So my first step will be creating a solution..."
  }
]
```

**Manifest fields per frame (course-agnostic):**

- `file`: Frame filename
- `timestamp`: Estimated video timestamp in seconds
- `timestampEstimated`: `true` if linearly interpolated (scene frames), `false` if derived from extraction interval
- `type`: Classification category (`code`, `slide`, `talking-head`)
- `description`: One-line description (null until visual analysis fills it)
- `keep`: Boolean — true for unique valuable content, false for duplicates/talking-head
- `transcriptContext`: Nearest transcript segment text (paired by timestamp proximity)

## Empirical findings (from TDD course extraction, March 2026)

Validated across 57 lessons, 992 frames:

| Finding | Details |
|---------|---------|
| **`-vsync vfr` must NOT be used with `fps` filter** | Drops all frames on static content (talking-head slides). Only use with `select` filter (scene detection) |
| **HLS JWT tokens expire mid-extraction** | Mux tokens are short-lived. Re-navigate to the lesson page before each extraction to get a fresh token |
| **`spawnSync` with args array, not `execSync`** | CRLF in `-headers` value breaks shell parsing on Windows. `spawnSync` bypasses the shell |
| **Fresh temp dir per Playwright run** | Stale persistent context profiles interfere with cookie injection. Use `course-extraction-${Date.now()}` |
| **`page.evaluate()` for shadow DOM detection** | `locator.isVisible()` fails on web components (mux-player). Use `document.querySelector()` via evaluate |
| **File-size dedup outperforms perceptual hash** | For this content type, consecutive interval frames within 8% file size = duplicate. RMSE/phash/SSIM tested but file-size was more reliable |
| **Scene threshold 0.1 is the only viable value** | 0.2 catches almost nothing for screencast content. The cliff is dramatic |
| **Timestamp estimation is approximate for scene frames** | Linear interpolation across video duration. Accurate for interval frames (fixed fps), approximate for scene-detected frames |

## File size management

- Scene detection at 0.1: ~63 frames for a 30-min lesson, ~22 MB total at 1280px
- Interval at 15s: ~120 frames for a 30-min lesson, ~40 MB total at 1280px
- After vision filtering (discard talking-head/duplicates): expect 70-90% retention for code lessons
- For a 67-lesson course: estimate 200-400 MB total with screenshots

Keep screenshots in `.gitignore` — they're generated artifacts, not source material. Manifest JSON and transcripts are the permanent records.
