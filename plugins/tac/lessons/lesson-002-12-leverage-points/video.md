# Video Metadata - Lesson 2: The 12 Leverage Points

## Playback Information

| Property | Value |
| -------- | ----- |
| **Lesson ID** | `the-12-leverage-points` |
| **Mux Playback ID** | `L2s0000bKtnRumkxw7eXjbYF02GQor01YYESDs9vQo9Nxpg` |
| **Duration** | 47:15 (2835 seconds) |
| **DRM Protected** | Yes (Widevine/PlayReady/FairPlay) |

## Quick Access

To watch this video:

1. Go to: <https://agenticengineer.com/tactical-agentic-coding/course/the-12-leverage-points>
2. Login with GitHub if prompted
3. Click play

## Technical Notes

- Video is delivered via Mux HLS streaming with DRM encryption
- Subtitles are available via VTT segments (not encrypted)
- Direct download is not possible due to DRM protection
- Captions have been extracted and saved to `captions.txt`

## API Reference

Token endpoint for programmatic access (requires Firebase authentication):

```text
POST https://us-central1-agentic-engineer.cloudfunctions.net/getMuxDrmVideoTokens
Content-Type: application/json
Authorization: Bearer <firebase_id_token>

{"lessonId": "the-12-leverage-points", "parentUserId": "<firebase_uid>"}
```text

Response includes: `playback_id`, `playback_token`, `drm_token`, `thumbnail_token`, `storyboard_token`, `duration`, `drm_protected`
