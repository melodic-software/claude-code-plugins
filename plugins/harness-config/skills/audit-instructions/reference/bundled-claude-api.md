# The bundled `claude-api` skill, as this skill relates to it

Records behind the `## Boundary` section in `SKILL.md`. Each row is our decision, a pointer to the
upstream section that holds the specific, the date the decision was last derived, and the
observable event that obliges re-deriving it; the specific itself is read live at the pointer. The
section carries the conclusion; this file carries what it rests on. Nothing here asserts that the
surface is present in any session.

Pinned commit for the `anthropics/skills` links below: `8a1541c4a3ffa5a20a5a91de0dcf3f0bab1d1ef4`.

## Records

| Decision | Pointer | As of | Recheck when |
|---|---|---|---|
| This skill routes to `claude-api` as a bundled surface and keeps no copy of its guides | For distribution: [the Claude API skill page, "In Claude Code (bundled)"](https://platform.claude.com/docs/en/agents-and-tools/agent-skills/claude-api-skill#in-claude-code-bundled) and [Bundled skills](https://code.claude.com/docs/en/skills#bundled-skills) | 2026-10-02 | Either section changes how the skill is distributed, or a release note moves it between bundled and marketplace distribution |
| This file keeps no list of the skill's subcommands; a reader takes the set from the pointer. This skill routes to `prompt-audit` only | For the subcommands and the version each needs: [Work on Claude API projects](https://code.claude.com/docs/en/skills#work-on-claude-api-projects); for their published guides: [`skills/claude-api/shared/`](https://github.com/anthropics/skills/tree/8a1541c4a3ffa5a20a5a91de0dcf3f0bab1d1ef4/skills/claude-api/shared) at the pinned commit | 2026-10-02 | The [Claude API skill page](https://platform.claude.com/docs/en/agents-and-tools/agent-skills/claude-api-skill) lists `build-eval` and `hillclimb` (then repoint there), or a release note changes the skill's subcommand set |
| We route Claude Code configuration audits to `/doctor prompt-audit [path]`, the same audit's Claude Code door, and application-code prompts to `/claude-api prompt-audit`; its scope, write posture and version floor are read live at the pointer | Pointer: [Audit your instruction files](https://code.claude.com/docs/en/memory#audit-your-instruction-files) and the `/doctor` row of [Commands](https://code.claude.com/docs/en/commands#all-commands) | 2026-10-01 | Either docs section changes the scope, write posture or version floor, or a release note changes `/doctor prompt-audit` |
| Application-code prompts route to `prompt-audit`; this skill keeps to Claude Code instruction surfaces and does not widen to application code | For what the subcommand inventories: [`prompt-audit.md`, Step 1](https://github.com/anthropics/skills/blob/8a1541c4a3ffa5a20a5a91de0dcf3f0bab1d1ef4/skills/claude-api/shared/prompt-audit.md#step-1-inventory-the-prompt-surface) at the pinned commit | 2026-10-02 | A commit to `anthropics/skills` changes `skills/claude-api/shared/prompt-audit.md`, or a release note names `prompt-audit` |
| This skill never asks `prompt-audit` to apply its proposed diff and never chains into an apply; it names the option and the person runs it | For its output and apply steps: [`prompt-audit.md`, Step 6](https://github.com/anthropics/skills/blob/8a1541c4a3ffa5a20a5a91de0dcf3f0bab1d1ef4/skills/claude-api/shared/prompt-audit.md#step-6-produce-the-proposed-diff) onward at the pinned commit | 2026-10-02 | Same as the row above |
| A model change runs the vendor's procedure, the model-migration guide with its eval grounding and `prompt-audit`; this catalog cites the per-model prompting guides directly ([criteria.md](criteria.md), Sources) and copies neither vendor guide. Re-derived from the published copies at the pinned commit with Claude Code 2.1.287 installed; the bundled copies were not extracted, and our reading of the changelog through 2.1.287 found no later release naming either guide | For the eval grounding: [`model-migration.md`, "Ground the migration with an eval"](https://github.com/anthropics/skills/blob/8a1541c4a3ffa5a20a5a91de0dcf3f0bab1d1ef4/skills/claude-api/shared/model-migration.md#ground-the-migration-with-an-eval); for the audit procedure: [`prompt-audit.md`](https://github.com/anthropics/skills/blob/8a1541c4a3ffa5a20a5a91de0dcf3f0bab1d1ef4/skills/claude-api/shared/prompt-audit.md); both at the pinned commit. For the last release that changed `prompt-audit`: [changelog 2.1.283](https://code.claude.com/docs/en/changelog#2-1-283) | 2026-10-02 | A release note names `prompt-audit` or the model-migration guide, or a commit to `anthropics/skills` changes either file |
| The routing in `SKILL.md` reads "when the surface resolves in this session" and never "the surface is available" | For the settings that turn bundled skills off: [`disableBundledSkills`](https://code.claude.com/docs/en/settings-reference#disablebundledskills) and [Override skill visibility from settings](https://code.claude.com/docs/en/skills#override-skill-visibility-from-settings) | 2026-10-02 | A release or docs change adds, removes, or renames a setting or host restriction that gates bundled skills |

## Why the verdict is complementary

Both surfaces judge prompt text against current-model doctrine, and neither replaces the other:

- The bundled subcommand is the vendor's procedure for the vendor's own model. Its catalog moves
  with each model generation, it covers application code this skill deliberately does not, and it
  applies edits. Running it is how a repository absorbs a model change; converting its findings
  into local criteria would be a copy that drifts.
- This skill is a standing, report-only audit over a versioned catalog whose rows carry
  target-model scope, deterministic pre-scans, and citations. It covers cross-surface conflicts and
  harness-behavior claims the vendor sweep does not look for, and it never edits.

The composite posture follows: run the vendor procedure on every model change and for application
prompts; run this skill continuously on Claude Code surfaces; feed recurring gap shapes the vendor
sweep surfaces into the catalog as rows rather than re-running the sweep to find them again.
