---
bump: patch
---

### Fixed

- `video-digest` `fetch-deck-attachments` now fetches only `https:` links whose host resolves to public addresses, follows redirects manually (up to 5 hops) and re-checks each hop, so loopback, private, link-local and unique-local targets from harvested links are skipped.
