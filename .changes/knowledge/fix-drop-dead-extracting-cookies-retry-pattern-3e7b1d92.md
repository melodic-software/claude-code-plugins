---
bump: patch
---

### Fixed

- `video-digest` no longer lists the dead `/extracting cookies/i` cookie-profile retry hint: yt-dlp prints that line on stdout, which the stderr-only failure detail never holds. A missing browser profile still advances to the next one through `/could not find .* cookies/i`.
