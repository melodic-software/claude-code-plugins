# Changelog

All notable changes to the `debugging` plugin are documented here. Format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/); this plugin uses semantic versioning.

## [0.4.0]

### Changed

- **BREAKING: `/debugging:diagnose` is renamed `/debugging:debug`** — the skill runs the full
  repro → hypothesize → fix → regression-test loop, while "diagnose" promised only the first half
  and twinned confusingly with `/testing:diagnose` (a different skill, which keeps its name).
  Clean break per the marketplace naming effort: no renames-map entry; update invocations to
  `/debugging:debug`. "diagnose" stays a trigger word in the skill description. Claude Code's
  built-in bundled `/debug` skill is unaffected — the plugin skill has no bare command form and
  is invoked only as the namespaced `/debugging:debug`.
