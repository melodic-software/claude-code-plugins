# Mission Format

Each workspace has one `MISSION.md`, in its top directory ([SKILL.md](../SKILL.md) "Workspace layout"). It holds the
result the learner is working toward. Every later choice in the workspace (the next frontier
concept, the source to suggest, the scenario an exercise or quiz question uses) is checked against
it.

## Where the file is used

| Session moment | What happens to `MISSION.md` |
|---|---|
| New workspace, opening interview (SKILL.md "Session Flow") | The interview answers become the file; nothing is written until the result is concrete |
| `resume` | Read first, before glossary, notes and records, so the session starts from the goal |
| `explain`, `exercise`, quiz questions | Scenarios come from the Result and the Checks, not from a generic example |
| `assess` or session close finds the goal has moved | The file is edited in the same session and a learning record notes the shift ([assessment.md](assessment.md)) |
| `mission` action | The learner reviews the file and edits it with you |

## Writing it from the interview

The opening interview runs one question at a time (SKILL.md "Teaching Dialog"). Each answer fills
one part of the file:

| Interview question | Fills |
|---|---|
| What will you do with this once you have it? | Result |
| How would you and I both see that you can do it? | Checks |
| How much time, money or deadline pressure is there, and how do you like to study? | Boundaries, `Limit:` lines |
| What nearby topics should wait? | Boundaries, `Not now:` lines |

Keep asking until the Result names something the learner will do. When the learner cannot yet say
what the learning is for, keep the dialog going and write no file: every later session plans from
this text, so a vague mission does more harm than an empty workspace.

A subject is not a result. Turn one into the other before writing:

| What the learner said | What goes in Result |
|---|---|
| "PostgreSQL performance" | Find why the nightly sales report query takes forty minutes, and fix it without the database admin |
| "Learn to sail" | Take a dinghy out on the club lake alone in a moderate wind and bring it back to the dock |

## Template

```markdown
# Mission: {Topic}

## Result

{One to three sentences: the task or change in the learner's life or work that this learning is
for.}

## Checks

- {Something the learner could be watched doing, worded so an exercise or quiz question can test it}
- {Another one}

## Boundaries

- Limit: {time per week, budget, deadline, preferred way of studying}
- Not now: {a nearby topic deferred on purpose, which keeps the frontier small}
```

A workspace written before this layout may use other section names; read it by meaning and move it
to this layout the next time the file is edited.

## Rules

- **The title is the workspace identity.** `{Topic}` in `# Mission: {Topic}` is the exact raw
  subject name the slug-collision guard compares (SKILL.md "Path resolution rules"). Write it as the
  learner gave it and put any description in Result
- **One workspace, one mission.** An unrelated second subject opens its own workspace
- **Edit on the day the goal moves.** An outdated Result keeps choosing lessons for a goal the
  learner has left behind
- **It fits on one screen.** The file says where the learning is going. Lesson plans and step lists
  belong in lessons and notes; cut the file back once it needs scrolling

## Codebase mode

For `/education:teach codebase <topic>`, add a section that ties the mission to the repository as it
is now, filled from what SKILL.md "Codebase mode" discovery found:

```markdown
## Repo Context

- **Code:** {paths to the modules, libraries or files where the concept lives}
- **Docs:** {paths to ADRs, convention files, architecture notes that explain it}
- **Tests:** {paths to test files that show the concept working}
```
