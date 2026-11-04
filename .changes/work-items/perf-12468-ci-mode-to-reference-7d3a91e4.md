---
bump: patch
---

### Changed

- work: CI mode (`--issue <n> --ci`) moves from SKILL.md to `reference/ci-mode.md`, so a load that
  names one item or auto-selects no longer carries it. The text moves verbatim except one link, now
  written `<plugin-root>` as reference files require. SKILL.md keeps the pointer at its Arguments
  line and in a `## CI mode` stub: CI mode reads that file first and skips the rest. Three eval
  cases cover the moved text: the `verify-unmet:` stop on a `verify_close` run, the skipped review
  when CI holds the review venue, and the `already-done:` stop code.
