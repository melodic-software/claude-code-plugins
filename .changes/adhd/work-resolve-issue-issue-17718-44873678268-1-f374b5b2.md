---
bump: patch
---

### Security

- **A local-file page checks its CDN library.** `/adhd:clarify`'s restatement of the rendered-views
  baseline now says each CDN `<script>` and `<link>` tag carries `crossorigin="anonymous"` and an
  `integrity` hash of the exact file its pinned URL serves, so a changed file at that URL does not
  load. ([#17718](https://github.com/melodic-software/claude-code-plugins/issues/17718))
