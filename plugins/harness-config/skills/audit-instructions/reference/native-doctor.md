# The bundled `doctor` skill, as this skill relates to it

Records behind the `doctor` Boundary section in `SKILL.md`. Each row is our decision, a pointer to
where the specific is read live, the date the decision was last derived, and the observable event
that obliges re-deriving it. The section carries the conclusion; this file carries what it rests
on. Nothing here asserts that the surface is present in any session.

| Decision | Pointer | As of | Recheck when |
|---|---|---|---|
| This skill offers `/doctor prompt-audit` to the person and never invokes it. The probe observed `doctor` as a bundled skill with alias `checkup`, user-invocable and not model-invocable, with an argument hint naming `prompt-audit` | The `/harness-ops:inventory` binary extraction, `bundled_skills.doctor` | 2026-10-02, Claude Code 2.1.287 | A release renames or removes `doctor`, or changes its alias, argument hint, or invocability |
| This skill keeps its own catalog and offers `/doctor prompt-audit` beside it at the end of a run; it copies none of that audit's checks | For what the audit covers: [Audit your instruction files](https://code.claude.com/docs/en/memory#audit-your-instruction-files); for the command and its version floor: the `/doctor` row of [All commands](https://code.claude.com/docs/en/commands#all-commands); for the release that added it: [changelog 2.1.283](https://code.claude.com/docs/en/changelog#2-1-283) | 2026-10-02 | That section or row changes, or a release note names `prompt-audit` |
| This skill never asks the audit to apply its proposals and never chains into `/doctor`; the person decides what to apply | For the audit's write posture: [Audit your instruction files](https://code.claude.com/docs/en/memory#audit-your-instruction-files) | 2026-10-02 | That section changes what the audit does before the person asks |
| Offer `/doctor prompt-audit` only when both `doctor` and the bundled `claude-api` skill resolve in this session; when either does not, the report says the offer was skipped | For what the audit depends on: [Audit your instruction files](https://code.claude.com/docs/en/memory#audit-your-instruction-files); for how `doctor` itself is gated: [Bundled skills](https://code.claude.com/docs/en/skills#bundled-skills); for the settings that turn bundled skills off: [`disableBundledSkills`](https://code.claude.com/docs/en/settings-reference#disablebundledskills) and [Override skill visibility from settings](https://code.claude.com/docs/en/skills#override-skill-visibility-from-settings) | 2026-10-02 | That section changes what the audit depends on, or a release adds, removes, or renames a setting that gates `doctor` or bundled skills |

## Why the verdict is complementary

The vendor pass checks prompting patterns against the current model's guidance. This skill runs a
versioned catalog with target-model scope and citations, checks claims about Claude Code's own
behavior against current docs, and runs a cross-surface conflict pass, and it never edits. Running
both finds more than either; a recurring shape the vendor pass reports belongs in this skill's
catalog as a row, not in a copy of the vendor procedure.
