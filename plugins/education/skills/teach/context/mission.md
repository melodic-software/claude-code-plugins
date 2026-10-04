# Mission Format

`MISSION.md` sits at the workspace root ([SKILL.md](../SKILL.md) "Workspace layout"). It records the
goal behind the learning. Choosing the next lesson, a resource to recommend or an exercise to set
starts from this file.

## Template

```markdown
# Mission: {Topic}

## Why

{One to three sentences naming the real result the user wants, such as a task at work they can do
afterwards. "Know more about X" is not a result; ask what knowing it lets them do.}

## Success Looks Like

- {An outcome someone could watch the user do}
- {A second outcome}
- {…}

## Constraints

- {Limits on the approach: hours per week, money, deadlines, how the user prefers to learn}

## Out of Scope

- {Nearby topics the user has said to leave for later, so lessons stay within reach}
```

## Rules

- **The `# Mission: {Topic}` title is identity, not prose.** `{Topic}` is the recorded raw subject name the slug-collision guard compares (SKILL.md "Path resolution rules"). Keep it the exact raw subject; descriptive flourish belongs in Why
- **A workspace holds one mission.** A second, unrelated subject gets its own workspace
- **Name an outcome, not a subject.** "Review my team's Terraform pull requests without help" is a mission; "get better at Terraform" is not. "Plan a week of meals on a budget" beats "learn nutrition"
- **Ask before writing when the goal is vague.** If the user cannot say what the learning is for, run the one-question-at-a-time teaching dialog (SKILL.md "Teaching Dialog") first. A vague mission misdirects every later session, which is worse than having none
- **Update it when the goal changes.** A mission the user has moved past still steers lesson choice, so edit the file as soon as the goal shifts
- **Length limit: one screen.** The file states direction; once it needs scrolling, it is holding step-by-step detail and should be cut back

## Codebase Mode Additions

For `/education:teach codebase <topic>`, MISSION.md also includes:

```markdown
## Repo Context

- **Relevant code:** {paths to modules, libs, files that embody the concept, discovered per SKILL.md "Codebase mode"}
- **Relevant docs:** {ADRs, convention files, architecture docs}
- **Relevant tests:** {test files demonstrating the concept in action}
```

This section grounds the mission in actual repo state rather than abstract goals.
