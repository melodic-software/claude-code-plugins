---
bump: minor
---

### Added

- `/planning:interview` suggests `/planning:wayfind chart` once, without stopping the round, when the ledger's register holds more questions than the new `wayfind_suggest_questions` setting (default `27`, `0` never suggests). The setting resolves through the convention home. The default is labeled `judgment` in `reference/config.md`: first-session question counts from 26 past efforts did not separate those that spanned more than one session from those that did not, so it sits at the largest single-session count and errs toward not suggesting. Eval case `interview-wayfind-size-suggestion` covers it. ([#12477](https://github.com/melodic-software/claude-code-plugins/issues/12477))
