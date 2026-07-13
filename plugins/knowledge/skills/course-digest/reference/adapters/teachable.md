# Teachable Adapter

Platform-specific extraction logic for Teachable-hosted courses using the Hotmart video player.

**Implementation:** `extraction/adapters/teachable.js` — all Teachable/Hotmart-specific iframe interaction, HLS subtitle extraction, resource detection, and auth flow. Implements `CourseExtractAdapter` contract defined in `adapters/adapter-contract.js`.

## Video player

Teachable uses **Hotmart video player** (`player.hotmart.com`) embedded in a cross-origin iframe. Player is built on **Video.js** with **VHS** (Video.js HTTP Streaming) for HLS playback. Videos are AES-128 encrypted HLS streams hosted on `vod-akm.play.hotmart.com`.

Hotmart player is NOT directly accessible from parent Teachable page — all interaction must go through Playwright's `page.frames()` to access iframe's DOM and JavaScript context.

**Key technical facts:**

- Video element: standard `<video>` inside the Hotmart iframe
- Player framework: Video.js with VHS (not hls.js)
- HLS master URL: accessible via `vjsPlayer.tech({IWillNotUseThisInPlugins: true}).vhs.playlists.master.uri`
- Subtitle tracks: accessible via VHS `master.mediaGroups.SUBTITLES`
- Subtitles delivered as chunked WebVTT segments (~6s each) via HLS
- 17 subtitle languages available (Arabic, German, English, French, Hindi, Italian, Japanese, Korean, Polish, Portuguese BR/PT, Russian, Spanish, Turkish, Ukrainian, Chinese)
- ffmpeg accesses HLS streams without Referer header — AES-128 key URL is inline in manifest

## Course structure extraction (Phase 1)

Enrolled course page (`/courses/enrolled/{courseId}`) contains full curriculum.

**Modules:** `<h2>` elements with module titles like "00 - Introduction", "01 - Modular Monoliths: Introduction".

**Lessons:** `<a>` elements containing `<h3>` with lesson title. Duration in parentheses `(MM:SS)` at end of link text. Lecture IDs in href: `/courses/{course-slug}/lectures/{lectureId}`.

**URL patterns:**

- Enrolled curriculum: `https://{domain}/courses/enrolled/{courseId}`
- Lesson player: `https://{domain}/courses/{course-slug}/lectures/{lectureId}`
- Teachable API: `/api/v2/hotmart/private_video?attachment_id={attachmentId}`

## Transcript extraction (Phase 2)

Teachable has **no transcript panel** in DOM. Transcripts are extracted from Hotmart player's HLS subtitle stream.

**Steps:**

1. Navigate to lesson URL
2. Wait for Hotmart iframe to load (check `page.frames()` for `player.hotmart.com`)
3. Access Video.js player instance from iframe:

   ```javascript
   const vjsEl = v.closest('.video-js');
   const vjsPlayer = vjsEl?.player;
   const tech = vjsPlayer.tech({ IWillNotUseThisInPlugins: true });
   const vhs = tech.vhs;
   const master = vhs.playlists.master;
   ```

4. Find English subtitle playlist URL from `master.mediaGroups.SUBTITLES`
5. Fetch subtitle m3u8 manifest from inside iframe context (CORS requirement)
6. Parse manifest to get all WebVTT segment URLs (each includes auth tokens)
7. Fetch all segments in batches from inside iframe context
8. Parse, deduplicate, format into timestamped transcript

**Dedup:** HLS subtitle segments overlap by ~6s. Deduplicate by normalized `startTime + text` composite key. Use `lib/vtt-parser.js` for this.

**No-captions fallback:** If Video.js player has no subtitle tracks (SUBTITLES group empty), lesson has no captions. Mark as `[no-captions]`. Whisper transcription via ffmpeg is a documented fallback but not implemented in adapter.

## Lesson content types

Teachable uses 6 attachment types, identified by CSS class `.lecture-attachment-type-{type}`:

| Type | CSS class | Content | Extraction |
|------|-----------|---------|------------|
| `video` | `.lecture-attachment-type-video` | Hotmart iframe | Transcript + frames via adapter |
| `text` | `.lecture-attachment-type-text` | Rich text, article links, labels | DOM read |
| `file` | `.lecture-attachment-type-file` | Downloadable files (ZIPs, SQL, JSON) | CDN download URLs |
| `code_display` | `.lecture-attachment-type-code_display` | Inline code blocks (`<pre><code>`) | DOM read |
| `pdf_embed` | `.lecture-attachment-type-pdf_embed` | Embedded PDF (slides) | Download link from `<a>` |
| `code_embed` | `.lecture-attachment-type-code_embed` | Third-party embed (senja.io) | Low value, skip |

### Download patterns

Source code ZIPs follow pattern: `{chapter}.{lesson} - {Title} - {Initial|Final}.zip`

- "Initial" = state before lesson's changes
- "Final" = state after lesson's changes
- Hosted on `uploads.teachablecdn.com`
- Auth not required for download (public CDN URLs with unique paths)

### Article links

Many lessons include "Helpful Articles & Resources" sections linking to Milan Jovanovic's blog (`milanjovanovic.tech/blog/*`) and external sources. These are valuable supplementary reading for analysis.

## Video frame extraction

ffmpeg works directly with HLS master URL from Video.js player:

```bash
ffmpeg -y -i "MASTER_M3U8_URL" -ss 30 -frames:v 1 -update 1 output.png
```

No Referer header needed — AES-128 encryption key URL is embedded in manifest with inline auth tokens.

## Authentication

Cookie-based via Teachable accounts. Auth flow:

1. First run: open browser, user logs in manually at `sso.teachable.com`
2. Save cookies: `await context.storageState({ path: '.auth-state.json' })`
3. Subsequent runs: inject cookies via `context.addCookies()`
4. Verify auth: navigate to a lesson, check for `.hotmart_video_player` in DOM

**Session expiry:** Teachable sessions last ~2 weeks (longer than Dometrain's Clerk sessions). `authWarnDays: 14` in platformConfig.

**Automated login** (optional): set `TEACHABLE_EMAIL` and `TEACHABLE_PASSWORD` env vars. Login URL: `sso.teachable.com/secure/{schoolId}/identity/login`.

## Teachable API

Internal API endpoint discovered during exploration:

**`GET /api/v2/hotmart/private_video?attachment_id={id}`**

Returns:

```json
{
  "duration": 927,
  "video_id": "4qXgAONNRv",
  "status": "THUMBNAIL_READY",
  "signature": "...",
  "teachable_application_key": "...",
  "user_email": "...",
  "school_name": "Milan Jovanovic Tech"
}
```

The `attachment_id` is available from Hotmart player container's `data-attachment-id` attribute.

## Gotchas

1. **Cross-origin iframe blocks `page.on("response")`:** Playwright's response interceptor does NOT reliably fire for cross-origin Hotmart iframe sub-resources. Use direct Video.js API approach instead of network interception
2. **`launchPersistentContext` vs `browser.launch`:** persistent contexts may behave differently with cross-origin iframe event handling. Adapter was developed and tested with `browser.launch` + `newContext`
3. **Video autoplay:** Hotmart videos autoplay when lesson page loads (even in Playwright's Chromium). Use `--autoplay-policy=no-user-gesture-required` for reliability
4. **VJS player access:** Video.js player instance is on `.video-js` container element's `.player` property (not `__vjs_player__`). Tech must be accessed with `{ IWillNotUseThisInPlugins: true }` flag
5. **Subtitle token expiry:** WebVTT segment URLs from manifest include `hdntl` auth tokens. Fetch all segments immediately after getting manifest — tokens may expire
6. **React-rendered curriculum:** Enrolled page uses Next.js/React (`jsx-*` classes). Standard `document.querySelectorAll('h2, a')` works but DOM may not be ready on `domcontentloaded` — wait 3-5 seconds
7. **Module ordering:** Module headings are `<h2>` elements interleaved with lesson `<a>` links. Parse sequentially to maintain correct module-lesson grouping
8. **Non-video lessons:** Resource pages (Slides, Source Code, SQL, Postman) have NO Hotmart iframe. `prepareLessonPage` detects this via `hasHotmart: false` and skips video-related setup
9. **Duplicate transcripts from WebVTT overlap:** HLS subtitle segments overlap by ~6s. VTT parser deduplicates by `startTime + text` key, but some sentence fragments may still appear duplicated at segment boundaries. Known limitation of HLS subtitle chunking
