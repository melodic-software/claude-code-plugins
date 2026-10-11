---
bump: patch
---

### Fixed

- video-digest: on Windows the automatic browser-cookie fallback now moves past Chrome when yt-dlp reports `Could not copy Chrome cookie database`, so it reaches Firefox instead of stopping at the Chrome failure ([#6816](https://github.com/melodic-software/claude-code-plugins/issues/6816)).
