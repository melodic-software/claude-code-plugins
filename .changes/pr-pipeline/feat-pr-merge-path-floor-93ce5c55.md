---
bump: minor
---

### Added

- `merge.diff-check.floor-paths` (a list of globs) adds paths to the risk scorer's HIGH path floor
  while `high-path-floor` applies; a pull request touching one waits for a human, where a denied
  path makes it ineligible. With the floor, a changed SKILL.md, agents/**/*.md or commands/**/*.md
  file is compared by its base and head text, each read once: it scores HIGH when its frontmatter
  gains or changes `hooks`, `allowed-tools`, `tools`, `permissionMode`, `mcpServers`, `memory` or
  another capability key `babysit_risk.py` lists, when it adds or changes a `!` backtick command or
  gains a ```` ```! ```` block, when a changed line falls inside a ```` ```! ```` block, or when
  either side or changed frontmatter cannot be read. `merge.diff-check.floor-script-scopes` (a list
  of globs) holds a `.ps1` or `.cjs` file, or one with git mode 100755, inside one of them or at the
  top level the same way. This repository lists `bin/`, `.lsp.json`, `settings*.json` and the
  scripts of the plugins the CI lanes load as floor paths, with the directories of the scripts a
  SessionStart or PreToolUse hook runs by path outside its plugin's `hooks/` (`pydeps.py`,
  `arm_observer.py`, `destructive_guard.py`), held whole so a sibling module cannot shadow an import, and those plugins as script scopes
  (Q646), and sets `high-path-floor: true` (owner decision 2026-10-18, reversing Q661), so its
  pr-merge lane holds such a pull request for a human, and the scorer's fixed HIGH floor
  (`.github/**`, `docs/conventions/**`, agent instructions, hooks, `lib/`, `scripts/`, package
  manifests and more) now applies there too. The switch governs both lanes: in the local babysit
  lane, false leaves out `floor-paths`, `floor-script-scopes`, the capability check and the new
  fixed floor entries (`plugins/*/monitors/**`, `plugins/*/workflows/**`), so a local-lane pull
  request scores as it did before this release. `version` stays 2.
