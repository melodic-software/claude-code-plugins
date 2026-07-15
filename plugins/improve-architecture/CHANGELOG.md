# Changelog

All notable changes to the `improve-architecture` plugin are documented here. Format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/); this plugin uses semantic versioning.

## [0.1.3]

### Fixed

- **Model invocation re-enabled.** `disable-model-invocation` in the `improve-architecture` skill's
  frontmatter is flipped back to `false`. The migration flipped it to `true`, silently disabling the
  automatic triggering the skill's description advertises ("Use when: 'improve architecture', 'find
  deepening opportunities', …") — the pre-migration original set `false`, and no rationale for the flip
  exists anywhere. With this fix the skill again triggers automatically when a request matches its
  description, in addition to explicit `/improve-architecture` invocation.
