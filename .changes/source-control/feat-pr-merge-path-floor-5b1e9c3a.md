---
bump: minor
---

### Added

- Both lanes read `merge.diff-check.floor-paths`, globs joined to the risk scorer's HIGH path floor while the floor applies. A diff touching one scores HIGH and waits for a human, where a denied path makes the pull request ineligible. `babysit_risk.RiskInput` gains `floor_paths`.
- With the floor, a changed SKILL.md, agents/**/*.md or commands/**/*.md file is compared by content: the gate reads its base text at the base SHA (from its previous path on a rename or copy) and its head text at the head SHA, once per side, cached within the run (`babysit_merge_policy.with_capability_contents`, `ChangedFile.contents`). It scores HIGH as `high-capability` when the head frontmatter gains, loses or changes `hooks`, `allowed-tools`, `tools`, `disallowedTools`, `permissionMode`, `mcpServers`, `disable-model-invocation`, `context`, `agent`, `shell`, `skills` or `memory` against the base, read by one strict reader for both sides; when the head has a line holding a `!` backtick command the base lacks (an added, rewritten or swapped command) or more ```` ```! ```` blocks (anywhere on a line) than the base; when a changed line falls inside a ```` ```! ```` block in the head; when changed frontmatter has a shape the reader cannot follow (a BOM, a CR, a flow collection, a tag, an explicit or merge key, an anchor or alias, an indented or unkeyed line); when either side cannot be read; and on a rename or copy into one of those paths. A removed file is not read.
- `babysit_risk.FLOOR_ADDITIONS` holds `plugins/*/monitors/**` and `plugins/*/workflows/**`.
- `merge.diff-check.high-path-floor` governs both lanes: `babysit_risk.RiskInput` gains `floor_extensions`, which gates `FLOOR_ADDITIONS`, `floor-paths`, the script scopes and the capability check, so with the switch off a local-lane pull request scores as before. The local lane still applies the rest of the fixed floor.
- `merge.diff-check.floor-script-scopes` (globs): with the floor, a `.ps1` or `.cjs` file, or one with git mode 100755, inside one of them or at the repository top level scores HIGH as `high-script`. `babysit_risk.RiskInput` gains `floor_script_scopes`.
- A floor-held pull request's reasons comment says a human merges it in person, never an agent or a lane; an unsafe-path hold does not say so.
