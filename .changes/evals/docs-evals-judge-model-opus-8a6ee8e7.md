---
bump: patch
---

### Changed

- plugin-eval: decision runs pass `--judge-model opus`. A 2026-10-11 pass at Claude Code 2.1.296 averaged more than the 0.1 USD fresh-suite headroom, so the headroom is re-derived to 0.2 USD per run; the `price-before-running` case now expects about 4.8 USD for four cases. The haiku-judge anchor says it was measured with a Haiku 4.5 judge, and the ci-pin-models samples no longer pin `claude-haiku-4-5`.
