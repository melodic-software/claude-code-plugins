# Tactical Agentic Coding Course - Scraping Process

This document describes the process used to scrape lessons from the Tactical Agentic Coding course at agenticengineer.com.

## Prerequisites

- Chrome browser with DevTools MCP server connected
- Authenticated session on agenticengineer.com with course access
- Python 3.x for caption extraction scripts

## Lesson Directory Structure

Each lesson follows this standardized structure:

```text
lesson-XXX-slug-name/
  lesson.md       # Main lesson content with YAML frontmatter
  captions.txt    # Video captions extracted from Mux VTT segments
  links.md        # External links and key concept tables
  repos.md        # GitHub repository clone URLs (PATs obscured)
  video.md        # Video metadata (duration, lesson ID, API reference)
  images/         # Tactic card images (TacOilCard_LX_*.jpg)
```

## Scraping Workflow

### 1. Navigate to Lesson Page

Navigate to the lesson URL. Core lessons (1-8) have different URL patterns than Agentic Horizon lessons (9-12).

**Core Lessons URL Patterns:**

- `/tactical-agentic-coding/course/hello-agentic-coding`
- `/tactical-agentic-coding/course/12-leverage-points-of-agentic-coding`
- etc.

**Agentic Horizon URL Patterns:**

- `/tactical-agentic-coding/course/rd-framework-context-window-mastery`
- `/tactical-agentic-coding/course/seven-levels-agentic-prompt-formats`
- `/tactical-agentic-coding/course/building-domain-specific-agents`
- `/tactical-agentic-coding/course/multi-agent-orchestration-the-o-agent`

**Note:** Agentic Horizon lessons may not be directly clickable from the course page. Use the "NEXT LESSON" button or guess URL from title.

### 2. Extract Video Captions

Video captions are served via Mux HLS streaming with signed VTT segments.

**Process:**

1. Click the play button to initialize the video player
2. Monitor network requests for `subtitles.m3u8` manifest URL
3. Download and parse the manifest to extract VTT segment URLs
4. Download each VTT segment and extract text (skip WEBVTT headers, timestamps, segment numbers)
5. Concatenate all text and save to `captions.txt`

**Python Script Pattern:**

```python
import urllib.request
import re
import ssl

ssl_context = ssl.create_default_context()
ssl_context.check_hostname = False
ssl_context.verify_mode = ssl.CERT_NONE

manifest_url = 'https://manifest-oci-us-ashburn-1-vop1.edgemv.mux.com/.../subtitles.m3u8?...'

headers = {
    'User-Agent': 'Mozilla/5.0 ...',
    'Referer': 'https://agenticengineer.com/',
    'Origin': 'https://agenticengineer.com'
}

req = urllib.request.Request(manifest_url, headers=headers)
manifest = urllib.request.urlopen(req, context=ssl_context).read().decode('utf-8')

vtt_urls = re.findall(r'https://[^\s]+\.vtt[^\s]*', manifest)

all_text = []
for url in vtt_urls:
    req = urllib.request.Request(url, headers=headers)
    vtt_content = urllib.request.urlopen(req, context=ssl_context).read().decode('utf-8')

    for line in vtt_content.strip().split('\n'):
        line = line.strip()
        if line == 'WEBVTT' or '-->' in line or line.isdigit() or line == '':
            continue
        all_text.append(line)

full_text = '\n'.join(all_text)
```

### 3. Capture Loot Box Content

Take a page snapshot to capture all "Loot Box" content including:

- Key concept headings and descriptions
- External documentation links
- Repository clone URLs
- Tactic principles and frameworks

### 4. Download Tactic Card Images

Tactic card images follow the naming pattern:

```text
https://agenticengineer.com/tactical-agentic-coding/tactic-oil-cards/TacOilCard_LX_*.jpg
```

**Note:** Agentic Horizon lessons (11-12) may not have tactic card images available.

### 5. Create Lesson Files

**lesson.md** - YAML frontmatter + structured content:

```yaml
---
title: "Lesson Title"
lesson: X
level: Beginner|Intermediate|Advanced
slug: url-slug
duration: "MM:SS"
url: full-lesson-url
---
```

**links.md** - External links and concept tables

**repos.md** - GitHub repository URLs (obscure PAT tokens)

**video.md** - Video metadata including:

- Lesson ID (API identifier)
- Duration in seconds and formatted time
- DRM protection status
- Quick access URL
- API reference for programmatic access

### 6. Collect Video Metadata

Video metadata is obtained from the `getMuxDrmVideoTokens` API endpoint.

**Process:**

1. Navigate to the lesson page
2. Click play to trigger video initialization
3. Monitor network requests for `getMuxDrmVideoTokens` POST request
4. Extract from response: `playback_id`, `duration`, `drm_protected`
5. Create `video.md` with structured metadata

**API Endpoint:**

```text
POST https://us-central1-agentic-engineer.cloudfunctions.net/getMuxDrmVideoTokens
Content-Type: application/json
Authorization: Bearer <firebase_id_token>

{"lessonId": "<lesson-slug>", "parentUserId": "<firebase_uid>"}
```

**Response Fields:**

- `playback_id`: Mux playback identifier
- `duration`: Video duration in seconds
- `drm_protected`: Boolean (always `true` for this course)
- `tokens`: Object containing playback_token, drm_token, thumbnail_token, storyboard_token

**Note:** All videos use Mux with Widevine/PlayReady/FairPlay DRM. Direct video download is not possible due to DRM protection. Captions (VTT) are the only unencrypted video-related content.

## Lesson Statistics

| Lesson | Title | Duration | Captions | Level |
| ------ | ----- | -------- | -------- | ----- |
| 1 | Hello Agentic Coding | - | - | Beginner |
| 2 | 12 Leverage Points | - | - | Beginner |
| 3 | Success is Planned | 41:11 | ~40K chars | Intermediate |
| 4 | AFK Agents | 38:00 | ~38K chars | Intermediate |
| 5 | Close The Loops | 33:30 | ~33K chars | Intermediate |
| 6 | Let Your Agents Focus | 47:30 | ~47K chars | Advanced |
| 7 | ZTE Secret | 41:00 | ~41K chars | Advanced |
| 8 | The Agentic Layer | 51:00 | ~51K chars | Advanced |
| 9 | Elite Context Engineering | 73:14 | 76,655 chars | Intermediate |
| 10 | Agentic Prompt Engineering | 57:30 | 64,936 chars | Intermediate |
| 11 | Building Domain-Specific Agents | 67:30 | 75,957 chars | Advanced |
| 12 | Multi-Agent Orchestration | 56:30 | 58,560 chars | Advanced |

## Technical Notes

### Mux Video Player

- Videos use Mux streaming with DRM (Widevine)
- Subtitles are served via HLS manifest (`subtitles.m3u8`)
- Each VTT segment is ~30 seconds of content
- Signed URLs expire (check `expires` parameter)

### URL Discovery

- Core lessons are linked from course page
- Agentic Horizon lessons may require URL guessing or NEXT LESSON navigation
- URL slugs don't always match lesson titles

### Authentication

- Requires authenticated session (Firebase Auth)
- Session cookies must be passed with requests
- Some URLs have signed tokens that expire

## Troubleshooting

**404 on lesson URL:**

- URL pattern doesn't match title - navigate from course page
- Use NEXT LESSON button to discover correct URL

**Click timeout on video:**

- Video still loads via network requests
- Check network requests for subtitle manifest

**Missing tactic card image:**

- Not all lessons have tactic cards (especially Agentic Horizon)
- Try variations of image name based on lesson title

## Scraping History

### 2025-12-04 - Rescrape Updates

**Lesson 4 (AFK Agents):**

- Rescraped to capture unlocked lootbox content
- Added new external links: ngrok, GitHub Webhooks (creating), Cloudflare Tunnel
- Updated lesson.md structure with better organization
- Updated links.md with new Tunneling Tools section

**Lessons 11-12 Image Verification:**

- Confirmed Agentic Horizon lessons (11-12) do NOT have tactic card images
- This is by design - only Core Lessons (1-8) include TacOilCard images
- Empty images/ folders in L11-12 are expected and should remain empty

**Loot Box Timing Note:**

- Loot boxes unlock progressively as you watch the video
- If scraping before watching, some content may be locked (shows as gift emoji boxes)
- For complete content, watch the full lesson first to unlock all loot boxes

**Video Metadata Investigation:**

- Investigated video download possibilities for all 12 lessons
- **Finding:** ALL lessons now use Mux with Widevine DRM protection
- Previously cached `signedVideoUrl` fields in Pinia store were from an earlier R2-based system
- The course has migrated entirely to DRM-protected streaming
- Direct video download is NOT possible due to DRM encryption
- Created `video.md` files for all 12 lessons documenting:
  - Lesson IDs (API identifiers)
  - Durations (from Pinia store `completeDurationSecs`)
  - DRM protection status
  - API endpoint reference for programmatic access
- Mux playback IDs can be obtained on-demand via `getMuxDrmVideoTokens` endpoint

**White Hat Security Analysis (Video Download Investigation):**

Comprehensive security testing was performed to determine if videos could be downloaded or accessed without browser authentication. All attack vectors were blocked:

| Attack Vector | Result | Details |
| ------------- | ------ | ------- |
| R2 unsigned URL | BLOCKED | CORS error, requires signature |
| R2 expired signature | EXPIRED | URLs from Oct 2024, 1-hour expiry |
| `getSignedVideoUrls` endpoint | DISABLED | Returns 403 "Insufficient access" |
| Mux public stream URL | BLOCKED | 403 without token |
| Mux thumbnail without token | BLOCKED | 403 |
| Mux MP4 download URLs | BLOCKED | 403 on /low.mp4, /medium.mp4, /high.mp4 |
| Mux progressive URL | NOT FOUND | 404 on .mp4 extension |
| Chunk URLs without signature | BLOCKED | 403 |
| Chunk URLs with fake signature | BLOCKED | 403 |

**Security Model:**

- Multi-layer authentication: Firebase Auth (GitHub OAuth) -> Cloud Function -> Mux tokens -> Widevine CDM
- All tokens are RS256-signed JWTs with expiration (1-hour Firebase, 7-day Mux)
- Every URL (manifests, chunks, even subtitles) requires valid cryptographic signatures
- Video segments use SAMPLE-AES encryption with Widevine/PlayReady/FairPlay DRM

**Conclusion:** Video download is NOT possible through any technical means without breaking DRM (illegal under DMCA). Legal alternatives: screen recording (OBS), requesting offline feature from IndyDevDan, or using browser caching during playback.

**What IS accessible:** Subtitles (VTT), thumbnails (with token), storyboards (with token) - all of which have already been scraped
