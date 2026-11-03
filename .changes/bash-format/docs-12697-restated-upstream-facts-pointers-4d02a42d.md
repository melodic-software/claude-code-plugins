---
bump: patch
---

### Changed

- The README no longer describes what `.editorconfig` and `--apply-ignore` do for shfmt, or how
  ShellCheck and shfmt find their configuration. It keeps the choice to pass no style flags and
  to pass `--apply-ignore`, and that configuration comes from your repository, and points at the
  shfmt manual page and ShellCheck's RC FILES section.
