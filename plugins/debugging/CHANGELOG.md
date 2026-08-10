# Changelog

All notable changes to the `debugging` plugin are documented here. Format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/); this plugin uses semantic versioning.

## [0.6.1]

### Removed

- **The bare `/<skill>` alias for this plugin's skills.** Their `SKILL.md` files no longer
  declare a frontmatter `name`. The field is optional and defaults to the directory name, so
  declaring it only restated the path while registering a second, unnamespaced command — which
  the slash-command picker then echoed back as `/plugin:skill (skill)`. Invoke a skill by its
  namespaced command; the command itself is unchanged.

## [0.6.0]

### Removed

- **The bare `/<skill>` alias for this plugin's skills.** Their `SKILL.md` files no longer
  declare a frontmatter `name`. The field is optional and defaults to the directory name, so
  declaring it only restated the path while registering a second, unnamespaced command — which
  the slash-command picker then echoed back as `/plugin:skill (skill)`. Invoke a skill by its
  namespaced command; the command itself is unchanged.

## [0.5.0]

### Added

- **`debug`: standing redaction guard.** A new section ahead of the phases requires every
  secret to be redacted (`<REDACTED>`) before commands, outputs, or captured artifacts appear
  in a transcript, work note, or commit; loops read credentials from env vars, captured
  artifacts are quoted only at the lines carrying the diagnostic signal, and insufficient
  redacted output routes to the user instead of a wider quote. The no-loop escape hatch now
  asks for a *redacted* captured artifact. (Guard from upstream mattpocock/skills
  `diagnosing-bugs` v1.2.3; registry: the marketplace repository's
  `docs/upstream/mattpocock-skills.md`.)

## [0.4.2]

### Changed

- Skills with `!` dynamic-context injections now declare `shell: bash` explicitly, per
  the pinned precompute convention — bash-only pipelines must not fall through to a
  PowerShell host.

## [0.4.1]

### Changed

- Documentation-only: the License section now states the plugin's own MIT
  license inline and no longer points at a `LICENSE` file at the repository
  root, which an installed consumer running from the isolated plugin cache
  cannot reach. No behavior change.

## [0.4.0]

### Changed

- **BREAKING: `/debugging:diagnose` is renamed `/debugging:debug`** — the skill runs the full
  repro → hypothesize → fix → regression-test loop, while "diagnose" promised only the first half
  and twinned confusingly with `/testing:diagnose` (a different skill, which keeps its name).
  Clean break per the marketplace naming effort: no renames-map entry; update invocations to
  `/debugging:debug`. "diagnose" stays a trigger word in the skill description. Claude Code's
  built-in bundled `/debug` skill is unaffected — the plugin skill has no bare command form and
  is invoked only as the namespaced `/debugging:debug`.
