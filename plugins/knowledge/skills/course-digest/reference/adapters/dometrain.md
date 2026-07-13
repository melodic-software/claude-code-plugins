# Dometrain Adapter

Platform-specific extraction logic for Dometrain (dometrain.com) courses.

**Implementation:** `extraction/adapters/dometrain.js` — all Dometrain-specific DOM interaction, URL patterns, auth flow. Implements `CourseExtractAdapter` contract defined in `adapters/adapter-contract.js`.

## Video player

Dometrain uses **Mux Player** (`<mux-player>` custom element) loaded from `cdn.jsdelivr.net/npm/@mux/mux-player`. Videos are HLS streams with JWT-protected access tokens (playback-restricted, user-scoped, ~150 min expiry).

Video player is NOT a standard `<video>` element — it's a web component with a shadow DOM. Do not try to interact with `<video>` directly.

## Course structure extraction (Phase 1)

Sidebar contains full curriculum. Read page with `read_page` and look for:

**Modules:** Each module is a section with a heading followed by a progress indicator like `(2/8)`.

**Lessons:** Each lesson is a `<link>` element inside its module section, containing:

- Lesson title (text content)
- Duration (e.g., "3m 43s")
- URL (href attribute — full lesson URL)
- Completion status (checkmark icon = completed)

**Course metadata** (from the sidebar header):

- Course title: heading element near top
- Duration: text like "5h 41m"
- Subtitle: "From Zero to Hero" style label
- Progress: "5 of 67 lessons completed"

**Resources** (from the top bar):

- "Download course files" button — may trigger a download
- "Get the code" / "View course code on GitHub" link — may be `href="#"` if no repo available
- "Show lesson notes" button — opens a side panel
- "Read this lesson" button — loads written content from API

## Transcript extraction (Phase 2)

Dometrain has a **built-in transcript panel** in the sidebar. Primary extraction method — no video download needed.

**Steps:**

1. Navigate to lesson URL
2. Click "Transcript" button (find by text content match):

   ```javascript
   Array.from(document.querySelectorAll('button'))
     .find(b => b.textContent.trim() === 'Transcript')?.click()
   ```

3. Wait ~500ms for transcript to load
4. Read the transcript panel content:

   ```javascript
   document.querySelector('[class*="transcript"]')?.textContent?.trim()
   ```

**Transcript format in DOM:** Timestamps and text concatenated without clear separators. Raw text looks like:

```text
0:00Hello, and welcome...0:07My name is...0:15Not only that...
```

**Parsing:** Split on timestamp patterns (`\d+:\d{2}`) to reconstruct `[M:SS] Text` format. Timestamp marks start of each segment.

**Cleanup:** Raw text includes artifacts from hidden UI elements. Strip these before saving:

- `"Loading transcript"` prefix (appears while loading)
- `"No transcript available for this lesson."` suffix (from a fallback panel always present in DOM but hidden)
- Trailing whitespace and empty lines

**Fallback:** If transcript panel shows "No transcript available" or "Loading transcript" after 3 seconds AND no timestamp segments found, lesson may not have captions. Log and continue.

**Subtitle tracks:** Mux player loads English subtitles as chunked VTT files from `chunk-*.edgemv.mux.com/v1/subtitle/*/N.vtt`. Signed URLs that expire. DOM transcript panel is more reliable than fetching VTT chunks directly.

## Lesson notes and written content

Some lessons have supplementary written content. Three resource buttons exist in every lesson page's DOM but conditionally shown via `display:none`:

1. **"Download course files" button** (`button.download-files-btn`) — visible on module intro ("The example we will work on") and section recap lessons. Hidden on theory/welcome/code-heavy lessons. Downloads a ZIP with instructor source code for that section
2. **"Show lesson notes" button** — opens a side panel. Hidden on all TDD course lessons (this course has no lesson notes). May appear on newer courses
3. **"Read this lesson" button** — calls `api.dometrain.com/private/api/courses/{courseId}/lessons/{lessonId}/content`. Hidden on all TDD course lessons. May appear on newer courses with written content

**Detection strategy:** navigate to lesson, check `getComputedStyle(btn).display !== 'none'` for each button. All three exist in DOM on every lesson page — only visibility differs.

Both notes and written content optional — TDD course has neither, but buttons are present for courses that do.

## Video frame extraction for Dometrain

Dometrain uses Mux HLS streams that can be downloaded directly via ffmpeg. Primary method for capturing code examples, slides, other visual content.

### Getting the HLS URL

Extract `.m3u8` URL from Mux player on any lesson page:

```javascript
const player = document.querySelector('mux-player');
const hlsUrl = player?.src; // Full URL with ?token=eyJ...
```

URL includes a JWT token with ~14 minute expiry (`custom_expiration_minutes`). Extract and use promptly. To check remaining time:

```javascript
const token = player?.src?.split('token=')[1];
const payload = JSON.parse(atob(token.split('.')[1]));
const remaining = payload.exp - Math.floor(Date.now() / 1000);
```

### ffmpeg frame extraction (verified working)

Single frame at a timestamp:

```bash
ffmpeg -y -user_agent "Mozilla/5.0 (Windows NT 10.0; Win64; x64)" \
  -i "HLS_URL" \
  -ss 30 -frames:v 1 -update 1 \
  output.png
```

Multiple frames at regular intervals:

```bash
ffmpeg -y -user_agent "Mozilla/5.0 (Windows NT 10.0; Win64; x64)" \
  -i "HLS_URL" \
  -vf "fps=1/15" \
  screenshots/frame_%04d.png
```

**Key flags:**

- `-user_agent` is required — Mux rejects requests without a browser user-agent
- `-ss BEFORE -i` for fast keyframe-based seeking
- `-update 1` for single-frame output (avoids "no image sequence pattern" error)
- Output: 1920x1080 PNG by default

### Content type detection

| Content type | How to detect from transcript | Frame extraction? |
|---|---|---|
| Talking head | Opinions/concepts, no code keywords | Skip — transcript covers it |
| IDE/code demo | File names, classes, `dotnet`, code constructs | Yes — extract at code cue timestamps |
| Slides | Conceptual explanations with diagrams | Yes — extract at slide transitions |
| Terminal output | Running commands, test results | Yes — extract at output timestamps |

### Mux player API (verified on Dometrain)

The `<mux-player>` element exposes standard HTMLMediaElement properties:

- `player.currentTime` — get/set playback position (seconds)
- `player.duration` — total length (read-only)
- `player.paused` — playback state (read-only)
- `player.play()` / `player.pause()` — control playback
- `player.media.nativeEl` — access the underlying `<video>` element
- `player.src` — the HLS manifest URL with JWT token
- `player._hls` — the underlying hls.js instance

**Note:** `crossOrigin` set to `"anonymous"` by default on Dometrain; inner `<video>` element is accessible via `player.media.nativeEl`.

## Navigation between lessons

To move between lessons, use direct URL navigation rather than clicking Next/Previous buttons. Lesson URLs follow the pattern:

```text
https://dometrain.com/take/course/{course-slug}/lesson-slug/
```

Each lesson link is available from sidebar after Phase 1 extraction. Navigate directly to each lesson URL — more reliable than clicking through UI.

## Course landing page

Public landing page URL pattern differs from lesson player URL:

- **Lesson player:** `dometrain.com/take/course/from-zero-to-hero-test-driven-development-tdd-csharp-2732006/welcome-54128298/`
- **Landing page:** `dometrain.com/course/from-zero-to-hero-test-driven-development-tdd-csharp/`

**Derivation:** strip `/take/` prefix, remove numeric courseId suffix, remove lesson slug. Course slug portion (between `/course/` and numeric ID) is the landing page slug.

**Available metadata:**

- **JSON-LD** (`@type: "Course"` in `@graph`): `aggregateRating` (ratingValue, ratingCount), `author`, `name`, `description`
- **OpenGraph meta tags**: `og:title`, `og:description`, `og:image` (course thumbnail URL), `og:url`
- **Visible sections**: "About This Course" (description), "Course Curriculum" (sections with lesson counts and durations), "Meet Your Instructor" (bio, photo, "View all courses" link)
- **Course Details sidebar**: Level, Duration, Rating (star display)

**No date metadata found** — no `dateCreated`, `dateModified`, `datePublished` in JSON-LD or meta tags. Course freshness is not available from the landing page.

## Additional platform features (discovered 2026-04-01)

- **AI Assistant** — button in top-right bar. Platform-level AI chatbot for course questions
- **Coding exercises** — "Give me a hint", "Review my code", "Explain the failure", "Review Solution" buttons. Interactive coding environment with Console and Test Results panels
- **Quizzes** — "Submit Quiz", "Review Answers" buttons
- **Certificates** — "Get Your Certificate" button (behind completion gate)
- **XP system** — gamification with XP points and leaderboard
- **Autocomplete** — toggle to auto-mark lessons as completed

These features are platform-level and not course-specific. They don't contain extractable content for course digest pipeline.

## Dometrain-specific gotchas

1. **Auto-play:** Videos may start playing when you navigate to a lesson. Doesn't affect transcript extraction (transcripts load independently of playback)
2. **Trial limits:** If user's subscription lapses, "Upgrade to Dometrain Pro" modal appears. Check for "Trial Limit Reached" or "Sign in to watch" text in page — if found, stop and inform user
3. **Rate limiting:** Don't navigate to lessons faster than ~2 seconds apart. Rapid navigation may trigger platform protections
4. **Session expiry:** Mux JWT tokens expire after ~150 minutes. For long extraction sessions, user's Dometrain session may expire — watch for login redirects
5. **Course IDs:** Course URL contains numeric course ID (e.g., `2732006`); lesson URL contains numeric lesson ID (e.g., `54128298`). Stable identifiers
6. **Windows convert.exe conflict:** On Windows, `convert` resolves to FAT/NTFS converter (`C:\Windows\system32\convert.exe`), not ImageMagick. Always use `magick` (ImageMagick 7) — never `convert`
7. **Never guess the instructor.** Course author is NOT inferrable from platform or course URL. ALWAYS extract from landing page JSON-LD (`@graph` → `Course` → `author[].name`) or "Meet Your Instructor" section. Do not assume based on Dometrain association — Dometrain hosts courses from many instructors
