---
bump: patch
---

### Fixed

- `docpage-digest` digests put `**FN.**` figure rows under their own `## Figure claims` heading after Key claims, so the fence gate no longer fails them as unlabeled fences. The Anthropic profile lists the figure parts to extract (figcaption title, subtitle and id, alt and aria-label, SVG text, control labels) and checks the extracted file against them.
- A verifier arm whose effective effort is never confirmed (a Codex verifier B) is recorded as `requested <level>, unconfirmed`, and the checklist has effort lines for both arms.
- Recorded and replayed search commands call GNU grep explicitly, or check `grep --version` first, so a plain `grep` that resolves to ugrep no longer changes recorded counts.
