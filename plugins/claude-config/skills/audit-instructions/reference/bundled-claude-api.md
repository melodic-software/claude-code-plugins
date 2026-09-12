# The bundled `claude-api` skill, as this skill relates to it

Four-part records behind the `## Boundary` section in `SKILL.md`: each claim names its basis, its
as-of date, and the observable event that obliges re-deriving it. The section carries the
conclusion; this file carries what it rests on. Nothing here asserts that the surface is present in
any session; every claim is about what the surface does where it resolves.

## What the surface is

| Claim | Basis | As-of | Recheck trigger |
|---|---|---|---|
| The `claude-api` skill is a bundled Claude Code skill and is also published in the open-source Anthropic skills repository | The skill's platform docs page states it "comes bundled with Claude Code and is also available in the open-source Anthropic skills repository" (`platform.claude.com/docs/en/agents-and-tools/agent-skills/claude-api-skill`); the Claude Code binary registers it | 2026-09-09, against Claude Code 2.1.263 | The docs page stops carrying the bundling statement, or a release note moves the skill between bundled and marketplace distribution |
| Its `prompt-audit` subcommand scopes to the whole working directory's prompt surface: skill bodies, `CLAUDE.md` and rule files, tool descriptions, and request-building application code | The subcommand's own reference read source-as-spec from the public skills repository (`skills/claude-api`, `shared/prompt-audit.md`, inventory step) | 2026-09-09, repository HEAD of 2026-09-03 | The reference's inventory step changes scope, or the subcommand is renamed or removed |
| `prompt-audit` produces a report and a proposed diff, applying edits only when the request asked for them | Same reference, its output and apply steps | 2026-09-09 | The reference's apply posture changes |
| The bundled skill's subcommand set is wider than the public repository's: `cost-optimize`, `migrate`, `managed-agents-onboard`, `prompt-audit`, `upgrade`, `build-eval`, `hillclimb` ship in the binary, while `build-eval` and `hillclimb` are absent from the public repository and the skill's docs page | Direct read of the bundled skill inside Claude Code 2.1.263 against a clone of the public repository at HEAD `41bbe19` | 2026-09-09 | The public repository or the docs page gains the missing subcommands, or a release changes the bundled set |

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

## Presence

Bundled skills can be removed by `disableBundledSkills`, hidden by `skillOverrides`, and vary by
plan, platform, and host surface. The routing in `SKILL.md` therefore reads "when the surface
resolves in your session" and never "the surface is available". Verified against
`code.claude.com/docs/en/settings-reference.md` on 2026-09-09; recheck when a release or docs
change adds, removes, or renames a gating axis.
