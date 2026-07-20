# Changelog

All notable changes to the `debugging` plugin are documented here. Format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/); this plugin uses semantic versioning.

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
