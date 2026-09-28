# Changelog

All notable changes to the `writing` plugin are documented here.

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.1.2] - 2026-09-28

### Changed

- **Long reference spoke opens with a Contents block** ([#4071](https://github.com/melodic-software/claude-code-plugins/issues/4071)). `be-concise` `reference/sources.md` is over 300 lines and had no table of contents in the first 40 lines. Each now lists its section anchors after the title, following Anthropic's skill-authoring guidance to put a table of contents at the top of a long reference file so a partial read still shows its scope. `skill-quality:check` check 26 no longer warns on it. No content moved.

## [0.1.1] - 2026-09-21

### Changed

- American spellings throughout this plugin's prose, ahead of the `en-us` locale the
  shared typos config adopts. Wording only: no behavior, option, default, or identifier
  changes. Released sections were corrected in place on the same terms.

## [0.1.0] - 2026-09-05

### Added

- Initial release: the `be-concise` skill, which reshapes prose so a scanning
  reader gets the point. Bottom line first, no more words than the meaning
  needs, structure that survives scanning, factual tone.
- Two modes: bare invocation sets a standing posture for the session; a target
  gets reshaped, with before and after word counts reported.
- A completeness floor that never drops a decision, number, ask, error or
  warning, never breaks a destination's structural contract, and never edits an
  already-posted record in place without being told to.
- `reference/doctrine.md` and `reference/sources.md`, paraphrasing Nielsen
  Norman Group, GOV.UK, the US federal plain-language guidelines, Google,
  Microsoft and BLUF with drift stamps. No upstream article text is vendored.
