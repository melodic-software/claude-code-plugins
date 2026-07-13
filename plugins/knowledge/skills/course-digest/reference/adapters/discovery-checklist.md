# Provider Discovery Checklist

Systematic exploration process for adding a new course platform provider to the extraction pipeline, or re-verifying an existing one after platform updates.

**When to use**: before writing any adapter code for a new platform, or when extraction starts failing on an existing platform (DOM changes, auth changes, new content types).

**Tools needed**: claude-in-chrome (interactive exploration), Playwright (automated testing), ffmpeg (frame extraction verification), browser DevTools network tab.

**Prerequisite**: user must have an active account and be enrolled in at least one course on the platform. Authentication is manual for first run.

## Phase 1: Platform Identification

Determine underlying technology stack. Course platforms are often white-labeled — visible brand may not be the actual LMS.

### 1.1 Navigate to the course page

Open enrolled course URL in claude-in-chrome. Read page at depth 2-3 to get high-level structure.

### 1.2 Identify the LMS platform

Run JavaScript on the page to detect platform:

```javascript
{
  // Check for common LMS platforms
  teachable: !!document.querySelector('.lecture-content, .lecture-attachment') ||
             !!window.trackTeachableGAEvent,
  thinkific: !!document.querySelector('[data-thinkific]') ||
             location.hostname.includes('thinkific'),
  kajabi: !!document.querySelector('[data-kajabi]'),
  podia: !!document.querySelector('[data-podia]'),
  learnWorlds: !!document.querySelector('[class*="learnworlds"]'),
  custom: 'check page source for framework clues',

  // Check window globals for platform fingerprints
  platformGlobals: Object.keys(window).filter(k =>
    /course|lecture|teachable|thinkific|kajabi|podia/i.test(k)
  )
}
```

**What to record**: platform name, version if visible, any API endpoints in network traffic.

### 1.3 Identify the video player

Run JavaScript to detect video delivery system:

```javascript
{
  wistia: !!document.querySelector('.wistia_embed, .wistia_responsive_padding'),
  vimeo: !!document.querySelector('iframe[src*="vimeo"]'),
  youtube: !!document.querySelector('iframe[src*="youtube"]'),
  mux: !!document.querySelector('mux-player'),
  html5Video: !!document.querySelector('video'),
  hotmart: !!document.querySelector('.hotmart_video_player'),
  iframes: Array.from(document.querySelectorAll('iframe')).map(f => {
    try { return new URL(f.src).hostname; } catch { return 'no-src'; }
  }),
  videoPlayerScripts: Array.from(document.querySelectorAll('script[src]'))
    .map(s => { try { return new URL(s.src).hostname; } catch { return ''; } })
    .filter(h => /wistia|vimeo|mux|player|video/i.test(h))
}
```

**YouTube iframes:** when the player detect shows `youtube: true` or iframe hostnames include YouTube, stop — single public YouTube videos are handled by `/knowledge:youtube`, not course-digest adapters.

**Critical distinction**: video player may be inside a **cross-origin iframe**. If so, parent page's JS cannot access player's DOM or API. This fundamentally changes extraction strategy.

**What to record**: player type, whether it's direct or in an iframe, iframe domain, any data attributes on the player container.

### 1.4 Identify the auth model

Check for authentication patterns:

- **Cookie-based**: most LMS platforms (Teachable, Thinkific)
- **JWT/token-based**: some custom platforms, API-first platforms
- **OAuth/SSO providers**: Clerk (Dometrain), Auth0, Firebase Auth, Keycloak
- **Session storage**: check `localStorage` and `sessionStorage` for auth tokens

**What to record**: auth provider, login URL, session persistence mechanism, cookie domain, expected session duration.

## Phase 2: Lesson Content Survey

Survey multiple lesson types at different positions to build a complete content model. **Do not assume all lessons have the same structure.**

### 2.1 Systematic sampling (minimum 6 lessons)

Check at least one lesson from each of these positions:

| Position | Why | What varies |
|----------|-----|-------------|
| **Course intro** (first lesson ever) | Often video-only, no resources | Minimal content |
| **Module intro** (first in any module) | Conceptual, may have slides | Different resource mix |
| **Mid-module coding lesson** | Richest content — code, downloads, links | Maximum attachment types |
| **Module end/review** | Often has summary ZIPs, final code state | Download patterns |
| **Resource/reference page** | Non-video content — downloads, links, PDFs | No video player |
| **Course update lesson** (if exists) | May use different content patterns | Version-specific |
| **Intermission/meta lesson** | Promotional content, reviews, asks | Third-party embeds |

### 2.2 Per-lesson inspection

For each sampled lesson, extract:

```javascript
// Attachment type inventory
Array.from(document.querySelectorAll('.lecture-attachment')).map(a => {
  const type = a.className.match(/lecture-attachment-type-(\w+)/)?.[1] ?? 'unknown';
  const linkTexts = Array.from(a.querySelectorAll('a'))
    .map(l => l.textContent.trim().substring(0, 100));
  return { type, linkTexts };
})
```

Adapt selector for non-Teachable platforms — class pattern will differ.

**What to record per attachment type**:

- **video**: player container, data attributes (attachment ID, lecture ID, course ID)
- **text**: plain text content, embedded links (label + href), heading presence
- **file**: download link labels, CDN domain, file extensions (.zip, .sql, .json)
- **code_display**: code content, language, length
- **pdf_embed**: iframe src OR download link (platforms vary)
- **code_embed**: iframe domain (may be third-party widget, low extraction value)
- **image**: direct img src or linked image
- Any other types discovered

### 2.3 Content type matrix

After sampling, build a matrix of which lesson positions have which content types. This becomes `detectResources` method's specification:

```
| Lesson Position        | video | text | file | code | pdf | embed |
|------------------------|-------|------|------|------|-----|-------|
| Course intro           |  ✓    |      |      |      |     |       |
| Module intro           |  ✓    |      |      |      |     |       |
| Mid-module coding      |  ✓    |  ✓   |  ✓✓  |  ✓   |     |       |
| Module review          |  ✓    |  ✓   |  ✓   |      |     |       |
| Resource page          |      |  ✓   |  ✓✓  |      |  ✓  |       |
| Course update          |  ✓    |  ✓   |  ✓✓  |      |     |       |
```

## Phase 3: Transcript Extraction

Most platform-dependent part. Work through these approaches in order of preference.

### 3.1 Check for built-in transcript panel (easiest)

**Dometrain pattern**: a "Transcript" button in lesson UI that opens a sidebar panel with timestamped text. Direct DOM read.

Look for:

- Buttons with text "Transcript", "CC", "Captions"
- Elements with `[class*="transcript"]`
- Hidden panels that appear on button click

If found: click the button, wait for content, read the DOM element. Simplest extraction path.

### 3.2 Check for video player subtitle/caption support

**Hotmart pattern**: subtitles are a feature of video player itself, not the LMS page.

Look for:

- Caption/subtitle toggle in the video player controls
- `<track>` elements on the `<video>` tag
- Text track overlays rendered as DOM elements (e.g., `<pre class="subtitleText">`)

If player is in a cross-origin iframe, you cannot see these from the parent page. Use Playwright's `page.frames()` to access iframe's DOM:

```javascript
const playerFrame = page.frames().find(f => f.url().includes('player.example.com'));
const buttons = await playerFrame.evaluate(() =>
  Array.from(document.querySelectorAll('button')).map(b => ({
    text: b.textContent?.trim(),
    ariaLabel: b.getAttribute('aria-label'),
  }))
);
```

### 3.3 Intercept subtitle network requests (HLS subtitles)

**Proven technique for Hotmart/HLS platforms**: subtitle text is delivered as chunked WebVTT segments alongside the video stream.

**Key insight**: Playwright's `page.on("response")` captures cross-origin iframe network traffic even though `page.on("request")` and JavaScript `fetch()` cannot cross the origin boundary. Critical discovery.

Steps:

1. Set up `page.on("response")` listener BEFORE navigating
2. Filter for subtitle manifest: URL containing `textstream_eng` + `.m3u8`
3. Capture manifest response body (contains all segment URLs with auth tokens)
4. Parse manifest to get segment filenames
5. Fetch all segments from WITHIN iframe context (`hotmartFrame.evaluate(fetch(...))`)
6. Parse WebVTT cues, deduplicate overlapping segments, sort by timestamp

```javascript
// Capture subtitle manifest body
page.on("response", async (response) => {
  if (response.url().includes("textstream_eng") &&
      response.url().includes(".m3u8") &&
      response.status() === 200) {
    const body = await response.text();
    // Parse segment URLs from manifest
  }
});
```

**Gotchas**:

- Tokens in URLs expire quickly — capture response body directly, don't try to re-fetch URL later
- CORS blocks `fetch()` from parent page to video CDN — must fetch from inside iframe context
- HLS subtitle segments overlap by design (each ~6s segment includes adjacent cues for smooth playback) — deduplicate by `startTime + text` key
- Subtitle manifest only loads after video playback starts — must trigger play first
- Seeking the video does NOT reliably trigger new subtitle segment loads — player caches them

### 3.4 Check for platform API transcript endpoints

Some platforms expose transcripts via API:

- **Teachable**: `/api/v2/hotmart/private_video?attachment_id={id}` — returns video metadata (video_id, duration, signature) but NOT transcripts
- **Wistia Data API**: has a captions endpoint but requires the account owner's API token — unusable for third-party courses
- **Single public YouTube videos**: use `/knowledge:youtube` (`transcript` / `watch` actions) — caption acquisition via yt-dlp is `/knowledge:youtube`'s concern, not course adapters

### 3.5 Fallback: audio extraction + Whisper

If no subtitle source exists:

1. Capture HLS master URL via network intercept
2. Extract audio with ffmpeg: `ffmpeg -i "HLS_URL" -vn -acodec pcm_s16le -ar 16000 -ac 1 audio.wav`
3. Transcribe with Whisper (local or API)
4. FFmpeg 8.0+ has native Whisper filter support

Slower and less accurate than platform-provided captions but works universally.

## Phase 4: Video Frame Extraction

### 4.1 Capture the HLS/video stream URL

Use `page.on("response")` to intercept master HLS manifest (`.m3u8`):

- Filter: URL contains `master` + `.m3u8`
- Manifest URL may include auth tokens that expire
- Manifest BODY contains variant stream URLs with their own tokens

### 4.2 Test ffmpeg access

```bash
ffmpeg -y -headers "Referer: https://player.example.com/\r\n" \
  -i "MASTER_M3U8_URL" \
  -ss 30 -frames:v 1 -update 1 \
  test-frame.png
```

**Gotchas**:

- Some platforms require `Referer` header, others don't (Hotmart works without it)
- Some platforms use AES-128 encryption — ffmpeg handles this automatically if key URL is in manifest
- Token expiry varies: Mux (Dometrain) ~150 min, Hotmart tokens are in manifest body

### 4.3 Verify frame quality

Read extracted frame with Claude's multimodal capability to verify it captures useful content (slides, code, diagrams) — not just a talking head.

## Phase 5: Resource Extraction

### 5.1 File downloads

Check for downloadable files (ZIPs, SQL scripts, Postman collections, OpenAPI specs):

- **Teachable**: `.lecture-attachment-type-file a[href]` — URLs on `uploads.teachablecdn.com`
- **Dometrain**: "Download course files" button — triggers browser download
- Other platforms may use different CDN domains

**What to record**: file naming pattern (e.g., "02.4 - Lesson Title - Initial.zip"), CDN domain, whether auth is needed for download.

### 5.2 Code snippets

Inline code blocks shown below the video:

- **Teachable**: `.lecture-attachment-type-code_display pre` or `code` elements
- Other platforms: look for `<pre>`, `<code>`, or syntax-highlighted containers

### 5.3 Article/resource links

External links provided as supplementary reading:

- **Teachable**: `.lecture-attachment-type-text a[href]` — links with labels
- Record both URL and link label text (e.g., "Monolith First, by Martin Fowler")

### 5.4 PDF embeds/downloads

Slide decks or documentation provided as PDFs:

- **Teachable**: `.lecture-attachment-type-pdf_embed a[href]` — direct download from `teachablecdn.com`
- Other platforms may use embedded PDF viewers (Google Docs, PDF.js)

### 5.5 Course-level resources

Check for dedicated resource sections/pages:

- Source code repository (GitHub link)
- Postman collections
- SQL migration scripts
- Slide decks
- API specifications (OpenAPI/Swagger)

These are often in a separate "Resources" or "Helpful Resources" module at the end of the course.

## Phase 6: Authentication Persistence

### 6.1 Test cookie-based auth

1. Log in via Playwright browser (manual, one-time)
2. Save auth state: `await context.storageState({ path: '.auth-state.json' })`
3. In subsequent runs, inject cookies: `await context.addCookies(state.cookies)`
4. Navigate to a protected page and verify access

### 6.2 Determine session expiry

- Check cookie expiry dates after saving auth state
- Test after 1 hour, 6 hours, 24 hours
- Record practical session lifetime for `authWarnDays` config

### 6.3 Document the auth flow for automated login (optional)

If env var based auto-login is desired:

- Record login URL
- Map form fields (email input selector, password input selector, submit button)
- Note any multi-step flows (e.g., Clerk's email-then-password flow)
- Record `authEnvPrefix` for env var naming

## Phase 7: URL Patterns

### 7.1 Lesson URL pattern

Record how lesson URLs are structured:

- **Dometrain**: `dometrain.com/take/course/{course-slug}/lesson-slug/`
- **Teachable**: `courses.{domain}/courses/{course-slug}/lectures/{lecture-id}`

### 7.2 Course curriculum URL

Page that lists all modules and lessons:

- **Dometrain**: same as first lesson URL (sidebar always visible)
- **Teachable**: `courses.{domain}/courses/enrolled/{course-id}`

### 7.3 Landing page URL (public, for metadata)

Public-facing course page with description, instructor, ratings:

- **Dometrain**: `dometrain.com/course/{course-slug}/` (derived from lesson URL)
- **Teachable**: may be on the main site, not the courses subdomain

### 7.4 API endpoints discovered

Record any internal APIs found during exploration:

- **Teachable**: `/api/v2/hotmart/private_video?attachment_id={id}` — returns video_id, duration, signature

## Phase 8: Verification Matrix

Before writing adapter code, verify every extraction path empirically:

| Extraction | Method | Tested? | Output Quality |
|------------|--------|---------|----------------|
| Course structure | DOM read (curriculum page) | | |
| Transcript | (platform-specific — document method) | | |
| Video frames | ffmpeg + HLS URL | | |
| Code snippets | DOM read | | |
| File downloads | HTTP GET from CDN | | |
| Article links | DOM read (labels + URLs) | | |
| PDF downloads | HTTP GET from CDN | | |
| Text content | DOM read | | |
| Course metadata | Landing page / API | | |
| Authentication | Cookie injection | | |

Every row must be "Tested: Yes" with a working proof-of-concept before proceeding to adapter implementation. No assumptions — empirical verification only.

## Phase 9: Platform-Specific Gotchas

Document any surprises, anti-patterns, or non-obvious behaviors discovered during exploration. These become "gotchas" section of adapter reference doc.

Common gotchas across platforms:

- **Cross-origin iframes**: video players in cross-origin iframes block JS access from parent page. Use Playwright's `page.frames()` for DOM access and `page.on("response")` for network interception
- **Token expiry**: HLS URLs, API tokens, and session cookies all have different expiry windows. Capture response bodies directly instead of re-fetching URLs later
- **Bot detection**: rapid navigation triggers platform protections. Pace at ~2s between lesson navigations
- **Automation detection**: use `--disable-blink-features=AutomationControlled` in Playwright to bypass basic detection
- **Lazy-loaded content**: video players, subtitle tracks, and some attachments only load after user interaction (play button click, scroll). Wait for specific DOM elements or network requests, not just `domcontentloaded`
- **HLS subtitle segment overlap**: segments contain overlapping cues for smooth playback. Deduplicate by `startTime + text` composite key
- **CORS on fetch**: fetching video CDN resources from parent page context fails due to CORS. Fetch from WITHIN video player's iframe context using `frame.evaluate(async () => { await fetch(...) })`
- **Platform API != documented API**: platforms often have undocumented internal APIs (like Teachable's `/api/v2/hotmart/private_video`) that are more useful than official public API. Inspect network traffic during normal page loads

## Regression Checklist (for existing providers)

When extraction starts failing on an existing provider, re-run this subset:

1. **Auth still works?** — inject saved cookies, navigate to a lesson, check for video player
2. **DOM selectors still valid?** — run the attachment type inventory on 2-3 lessons
3. **Video player changed?** — check the player type, iframe domain, control buttons
4. **Transcript still accessible?** — run the transcript extraction on one lesson
5. **HLS URL still works with ffmpeg?** — extract one frame
6. **Download URLs still valid?** — check CDN domain hasn't changed
7. **New content types?** — check if the platform added new attachment types

If any check fails, investigate the specific change and update adapter accordingly. Document the change in adapter's gotchas section with a date.
