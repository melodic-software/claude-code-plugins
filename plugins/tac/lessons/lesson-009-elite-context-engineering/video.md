# Video Metadata - Lesson 9: Elite Context Engineering (R&D Framework)

## Playback Information

| Property | Value |
| -------- | ----- |
| **Lesson ID** | `rd-framework-context-window-mastery` |
| **Duration** | 73:12 (4392 seconds) |
| **DRM Protected** | Yes (Widevine/PlayReady/FairPlay) |

## Quick Access

To watch this video:

1. Go to: <https://agenticengineer.com/tactical-agentic-coding/course/rd-framework-context-window-mastery>
2. Login with GitHub if prompted
3. Click play

## Technical Notes

- Video is delivered via Mux HLS streaming with DRM encryption
- Subtitles are available via VTT segments (not encrypted)
- Direct download is not possible due to DRM protection
- Captions have been extracted and saved to `captions.txt`
- This is an "Agentic Horizon" lesson (advanced content)

## API Reference

Token endpoint for programmatic access (requires Firebase authentication):

```text
POST https://us-central1-agentic-engineer.cloudfunctions.net/getMuxDrmVideoTokens
Content-Type: application/json
Authorization: Bearer <firebase_id_token>

{"lessonId": "rd-framework-context-window-mastery", "parentUserId": "<firebase_uid>"}
```text

Response includes: `playback_id`, `playback_token`, `drm_token`, `thumbnail_token`, `storyboard_token`, `duration`, `drm_protected`
