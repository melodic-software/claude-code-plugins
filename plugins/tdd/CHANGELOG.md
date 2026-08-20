# Changelog

All notable changes to the `tdd` plugin are documented here. Format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/); this plugin uses semantic versioning.

## [0.4.1]

### Changed

- **SDK-style boundary interfaces are stated as subordinate to "mock only unmanaged dependencies"**
  (`test-doubles.md`, #2936). The section sat immediately below the five Khorikov mocking best
  practices but never declared a precedence relation to the first of them, leaving it readable as
  license to introduce an interface per external operation wherever one is convenient. It shapes a
  boundary already decided to be mocked; it never widens what gets mocked, and no interface is
  introduced for an in-process dependency to satisfy the shape.

## [0.4.0]

### Added

- **Mutation testing named as the partial exception to "no automated way to measure test suite
  quality"** (`code-coverage-khorikov.md`). The chapter's claim is about quality as it defines it and
  stands; one property — whether assertions can detect a fault rather than merely execute code — is
  automatically measurable, and a file at high coverage with a low mutation score is exercised but
  not checked. The note states the measurement's limits in the same breath (unknowable ceiling from
  equivalent mutants, and targeting the number reproduces the chapter's own perverse incentive).
- **The false-negative half of test accuracy tied to its measurement** (`four-pillars-khorikov.md`).
  A surviving mutant is a demonstrated false negative, not an estimate of one; nothing equivalent
  exists for the false-positive half, so the note is explicit that the measurement is lopsided and
  that optimizing for it trades away the other three pillars.

Both notes are presence-gated references to `/mutation-testing:principles` with the substantive
fallback stated inline, per the seam-phrasing convention.

## [0.3.0]

### Removed

- **The bare `/<skill>` alias for this plugin's skills.** Their `SKILL.md` files no longer
  declare a frontmatter `name`. The field is optional and defaults to the directory name, so
  declaring it only restated the path while registering a second, unnamespaced command — which
  the slash-command picker then echoed back as `/plugin:skill (skill)`. Invoke a skill by its
  namespaced command; the command itself is unchanged.

## [0.2.1]

### Changed

- Documentation-only: the License section now states the plugin's own MIT
  license inline and no longer points at a `LICENSE` file at the repository
  root, which an installed consumer running from the isolated plugin cache
  cannot reach. No behavior change.

## [0.2.0]

### Changed

- Renamed the `tdd` skill → `principles`. Update any `/tdd:tdd` invocations to `/tdd:principles`;
  the plugin ID (`tdd`) and marketplace listing are unchanged, only the skill's leaf name moved.
