---
bump: patch
---

### Changed

- **`docpage-digest` reads `claude.dev/blog` posts through their raw-markdown channel.** The publisher profile now fetches `https://claude.dev/blog/<slug>.md` (served `text/markdown`) as `source.md`, records that channel's known artifacts, keeps the rendered page as `source.html` for figure text, and falls back to `extract_blog_body.py` when the `.md` channel fails.
