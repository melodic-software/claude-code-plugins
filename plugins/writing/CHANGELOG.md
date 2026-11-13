# Changelog

All notable changes to the `writing` plugin are documented here.

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.4.0] - 2026-11-13

### Changed

- **Breaking:** the `verification` level now defaults to `light` when the default branch sets no `verification` key or cannot be read: verifier dispatches are skipped and the skip line is written. An invalid value or a team file that does not parse still resolves `standard`, naming the error. Set `verification: standard` (or `strict`), or `verification_skills.<skill>`, in the team file on the default branch to raise it.

## [0.3.4] - 2026-11-12

### Changed

- Pointer records no longer carry an as-of date or recheck trigger; stored values keep theirs.

## [0.3.3] - 2026-11-11

### Changed

- `be-concise`'s doctrine cites the reading-share and usability figures through their records in `sources.md` instead of repeating the percentages. No behavior change.

## [0.3.2] - 2026-11-09

### Changed

- Simplified the shared yaml-subset parser copies; behavior is unchanged.

## [0.3.1] - 2026-11-09

### Changed

- Simplified the shared resolve-convention-home.sh, resolve-convention-pattern.sh and rewrite-guard.sh copies; behavior is unchanged.

## [0.3.0] - 2026-11-06

### Added

- A `verification` level (`off`, `light`, `standard`, `strict`) and per-skill `verification_skills` in `<home>/writing.yaml`, read from the default branch by `lib/read-verification.sh` and validated by the new `schemas/writing.schema.json`. `/writing:be-concise` follows it for its fresh-context semantic diff: `strict` runs the diff on every rewrite whatever its size, and `light` and `off` run none, record `verification: skipped (<level>)` and say the meaning was not independently checked.

## [0.2.2] - 2026-11-03

### Fixed

- `be-concise` declines again to restructure a dense message without shortening it and to reshape agent-facing instruction prose, even when the plugin it routes to is not enabled ([#12846](https://github.com/melodic-software/claude-code-plugins/issues/12846)).
- `be-concise` runs its semantic-diff check when the original has more than three paragraphs or more than 250 words. It used to say "longer than a few paragraphs", which a model could not check.
- Routes to `docs-hygiene` skills say "enabled" where they said "installed".
- The wall-of-text eval fixture uses a relative deadline in place of a date that has passed.

## [0.2.1] - 2026-11-03

### Changed

- The eval suite moved from `skills/*/evals/evals.json` to `evals/<case>/case.yaml` and `prompt.md`, with deterministic graders where an expectation is mechanical ([#8635](https://github.com/melodic-software/claude-code-plugins/issues/8635)).
- Its fixtures moved to `evals/fixtures/`, copied into the workspace by each case's scaffold.

## [0.2.0] - 2026-10-20

### Added

- Three outcome eval cases under `evals/` and a frozen trigger-probe set under `probes/`.

### Changed

- Shorter body for `be-concise`. Eval cases measured it against the old text before it shipped. Its description keeps the original text, because the shorter description triggered on fewer held-out requests.

## [0.1.6] - 2026-10-13

### Changed

- be-concise: stop restating which content the Claude Code Concise output style keeps; point at its live section from one record.

## [0.1.5] - 2026-10-03

### Changed

- Cross-plugin routing to plugins that now install disabled says "enabled" where it said "installed": an installed but disabled plugin exposes no skills ([#5934](https://github.com/melodic-software/claude-code-plugins/issues/5934)).

## [0.1.4] - 2026-10-02

### Fixed

- `plugin.json` no longer sets `$schema`. claude.ai's marketplace sync stripped it with a warning, and Claude Code ignores it at load time.
- The plugin description is 500 characters or fewer, the limit claude.ai's marketplace sync enforces.

## [0.1.3] - 2026-10-02

### Fixed

- The `be-concise` `argument-hint` uses Claude Code's official bracket notation: it drops the prose
  after the grammar, which the skill body now carries.

## [0.1.2] - 2026-09-28

### Changed

- The `be-concise` reference spoke `sources.md` opens with a Contents block of section anchors,
  so skill-quality check 26 (long spoke files carry a table of contents) passes on it.

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
