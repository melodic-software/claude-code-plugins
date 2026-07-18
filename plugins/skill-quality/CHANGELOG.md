# Changelog

All notable changes to the `skill-quality` plugin are documented here. Format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/); this plugin uses semantic versioning.

## [0.4.1]

### Changed

- **Freshness rider on the setup skill's `pluginConfigs` claim** (fleet
  conformance wave). The claim is re-verified, dated, and pinned to the
  release that introduced the behavior (≥ 2.1.207).

## [0.4.0]

### Changed

- Renamed the `skill-quality` skill → `check`. Update any `/skill-quality:skill-quality` invocations
  to `/skill-quality:check`; the plugin ID (`skill-quality`) is unchanged, only the skill's leaf name
  moved.

## [0.3.0]

### Added

- **Post-commit audit ref.** `CHECK_SKILL_BASE_REF` (default `HEAD`) selects the ref the git-backed
  checks (3 trigger-preservation, 8 vendor byte-identity, 9 stale-tracking metadata) diff the working
  tree against. The default still catches an uncommitted rewrite; pointing it before a change (e.g.
  `HEAD^` or a merge-base) and running on a clean tree catches an already-committed change that the
  `HEAD` == working-tree comparison would miss.

### Changed

- **Block-scalar descriptions are unfolded.** A `description: |` / `>-` block scalar is now expanded to
  its text before the length (2), trigger-preservation (3), and phrasing (12) checks, which previously
  operated on the `|` / `>` marker instead of the content.
- **Frontmatter must open on line 1.** The YAML frontmatter fence is required at line 1; content before
  it is no longer treated as frontmatter, closing a path where a stray `---` further down could satisfy
  check 1.
- **Unquoted `Use when:` triggers warn (check 12).** Trigger-drop protection (check 3) tracks only
  single-quoted `'phrase'` triggers; an unquoted `Use when:` list now raises a warning so those phrases
  get quoted and covered, rather than silently going unprotected.
