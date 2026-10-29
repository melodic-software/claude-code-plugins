---
bump: minor
---

### Changed

- Both interview pages now render markdown through one renderer in `question-shape.js`, which builds elements and text nodes only. It reads the union of the two pages' dialects. Blocks are paragraphs, `#` headings, bullet and numbered lists, and `>` quotes. Inline it renders code, bold, emphasis, `[text](url)` and bare http(s) links, and `owner/repo#N`. When the session names a repository it also links `#N`, and with a commit, repository paths. Each page adds its own plain-text runs to that: the shared page its @mention chips, the 1:1 page its question-id chips and glossary terms. The shared page now renders headings, quotes, emphasis, markdown links and `owner/repo#N`, and the 1:1 page now renders bare links and keeps a paragraph's line breaks. The page-local `md`/`inline` (1:1 page) and `rich`/`inline`/`links` (shared page) builders are gone (#10210).
