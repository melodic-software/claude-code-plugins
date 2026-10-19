---
bump: minor
---

### Added

- Both lanes read `merge.diff-check.floor-paths`, globs joined to the risk scorer's HIGH path floor while the floor applies. A diff touching one scores HIGH and waits for a human, where a denied path makes the pull request ineligible. `babysit_risk.RiskInput` gains `floor_paths`.
- With the floor, a SKILL.md, agents/**/*.md or commands/**/*.md patch that adds, changes or removes `hooks`, `allowed-tools`, `tools`, `permissionMode` or `mcpServers` frontmatter at any indentation, or adds a line holding a `!` backtick command or a ```` ```! ```` block (or a line inside one the hunk shows), scores HIGH as `high-capability`, read from the patch text the files listing already returns (`ChangedFile.patch`). It splits frontmatter lines at `\r` as YAML does. A changed indented line whose hunk shows no key above it, or such a file with no patch text, also scores HIGH, as do a quoted key, an added or removed `---` line in such a file, and a rename or copy into one of those paths. The capability keys also take in `disallowedTools`, `disable-model-invocation`, `context`, `agent`, `shell`, `skills` and `memory`, and frontmatter YAML the scanner cannot read line by line (a flow collection, a tag, an explicit or merge key, an anchor or alias) scores HIGH.
- `babysit_risk.FLOOR_ADDITIONS` holds `plugins/*/monitors/**` and `plugins/*/workflows/**`.
- `merge.diff-check.high-path-floor` governs both lanes: `babysit_risk.RiskInput` gains `floor_extensions`, which gates `FLOOR_ADDITIONS`, `floor-paths`, the script scopes and the capability check, so with the switch off a local-lane pull request scores as before. The local lane still applies the rest of the fixed floor.
- `merge.diff-check.floor-script-scopes` (globs): with the floor, a `.ps1` or `.cjs` file, or one with git mode 100755, inside one of them or at the repository top level scores HIGH as `high-script`. `babysit_risk.RiskInput` gains `floor_script_scopes`.
- A floor-held pull request's reasons comment says a human merges it in person, never an agent or a lane; an unsafe-path hold does not say so.
