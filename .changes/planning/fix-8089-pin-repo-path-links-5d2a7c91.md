---
bump: patch
---

### Fixed

- **interview:** a repo-relative path such as `plugins/x.py:10` in a recommendation, a commitment or an alternative on the 1:1 interview page now links to that file at a pinned commit. Set `meta.commit` to a full 40-character SHA beside `meta.repo`, through the `meta` op or `add-round`'s `meta`. `round.py` refuses any other non-empty commit value. Without a commit, paths stay plain text ([#8089](https://github.com/melodic-software/claude-code-plugins/issues/8089)).
