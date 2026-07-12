# Mission Format

`MISSION.md` lives at the workspace root per [SKILL.md](../SKILL.md) "Workspace layout". Captures WHY the user is learning this topic. Every teaching decision — what to teach next, which resources to surface, which exercises to design — traces back to this document.

## Template

```markdown
# Mission: {Topic}

## Why

{1-3 sentences. Concrete real-world goal. What changes in their life or work when they have this skill? Avoid abstract framings like "to understand X" — push for the underlying outcome.}

## Success Looks Like

- {Specific, observable thing the user will be able to do}
- {Another specific thing}
- {…}

## Constraints

- {Time, budget, prior commitments, learning preferences, anything that bounds the approach}

## Out of Scope

- {Adjacent topics the user explicitly does not want to chase right now — protects zone of proximal development}
```

## Rules

- **One mission per workspace.** Two unrelated topics = two workspaces
- **Concrete over abstract.** "Ship a Rust CLI to my team" beats "learn Rust." "Write songs with family rhyme" beats "understand songwriting"
- **Push back on vagueness.** If the user cannot articulate WHY, interview them via the one-question-at-a-time teaching dialog (SKILL.md "Teaching Dialog") before writing anything. A bad mission is worse than no mission
- **Revise when reality shifts.** Missions change. When the goal moves, update — don't leave a stale mission steering sessions
- **Keep it short.** If MISSION.md runs past a screen, it stopped being a compass and started being a plan

## Codebase Mode Additions

For `/teach:teach codebase <concept>`, MISSION.md also includes:

```markdown
## Repo Context

- **Relevant code:** {paths to modules, libs, files that embody the concept — discovered per SKILL.md "Codebase mode"}
- **Relevant docs:** {ADRs, convention files, architecture docs}
- **Relevant tests:** {test files demonstrating the concept in action}
```

This section grounds the mission in actual repo state rather than abstract goals.
