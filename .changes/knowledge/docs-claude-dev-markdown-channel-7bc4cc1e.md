---
bump: patch
---

### Changed

- **`docpage-digest` reads `claude.dev/blog` posts through their raw-markdown channel.** The publisher profile now fetches `https://claude.dev/blog/<slug>.md` as `source.md`, keeps the rendered page as `source.html` for figure text, and falls back to `extract_blog_body.py` when the `.md` fetch fails, is not markdown, or lacks the article's title. The channel's observed shape lives in a probe record the profile points at, and a new eval case covers the raw-first, HTML-companion and fallback path.
