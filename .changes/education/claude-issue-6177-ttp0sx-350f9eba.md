---
bump: minor
---

### Added

- **`/education:illustrate` records draw their diagrams ([#6177](https://github.com/melodic-software/claude-code-plugins/issues/6177)).** Each diagram's text form in the markdown record is now followed by one fenced `mermaid` block, so a markdown viewer that renders mermaid shows the picture. Every kind is a `flowchart`: `flow` left to right (top to bottom past four steps, as the page draws it), `stack` and `timeline` top to bottom, `hub` from its center, and `compare` and `before-after` as subgraphs. Node ids come from the builder and every label is double-quoted, with line breaks collapsed, backticks and control characters removed, and `"`, `%`, `#`, `&`, `<` and `>` written as mermaid entity codes, so fetched text cannot leave its quotes, add a statement, open a `%%{...}%%` directive, or close the fence. The page view is unchanged.
