---
bump: patch
---

### Changed

- **The docs lookup procedure no longer asks for a coverage check before answering
  ([#6501](https://github.com/melodic-software/claude-code-plugins/issues/6501)).** The step that
  sliced extra sections for each uncovered part of the question is removed from
  `reference/docs-lookup-procedure.md`: its re-measure in
  [#6538](https://github.com/melodic-software/claude-code-plugins/pull/6538) used more bytes than
  its pre-registered cost limit allowed.
