# Assessment and Learning Records

Assessment keeps the learner model current: which concepts are understood, which sit at the
frontier, and which misconceptions have shown up. A learning record is how one finding outlives the
session it happened in. The model is read at every `resume` and `status` to choose what comes next.

## Evidence by coaching moment

Our sessions produce evidence in the dialog, in exercises and in quizzes. Each moment below is
worth a record when it happens:

| Moment | What it shows | Record it as |
|---|---|---|
| A dialog question, answered in the learner's own words and correctly | Understanding of the concept | Demonstrated understanding |
| An exercise finished with no hints | The skill | Skill acquired |
| A comparison exercise where the learner picks the right tradeoff | Judgment about when and why | Wisdom demonstrated |
| A quiz, from a lesson or a `/education:quiz-me` report (same-plugin sibling) | Recall of what the questions covered | Demonstrated understanding, with the quiz as evidence |
| The learner says they already know something | Prior knowledge, at the depth they claim | Prior knowledge, noting that depth |
| An answer reveals a wrong belief, and the dialog corrects it | Where related concepts may trip them up | Corrected misconception (the most useful kind) |
| The learning changes what the learner wants | A new direction | Mission shift; edit `MISSION.md` too ([mission.md](mission.md)) |
| Session close | Whatever was shown during the session | Ask for the learner's reflection, then record what they demonstrated |

Quiz options keep the equal-length rule: every choice in a multiple-choice question has the same
length and formatting weight, so the presentation never points at the answer (design rules in
[exercises.md](exercises.md)).

## Routed elsewhere, not recorded

| What happened | Where it goes |
|---|---|
| A term was defined | `GLOSSARY.md` ([glossary.md](glossary.md)); a record does not repeat the definition |
| A running account of the session | Not kept; a record exists to change a later teaching choice |
| A concept was taught, with no sign yet that it landed | Nowhere yet; record it once the learner shows it |

## Writing a record

Records go in `learning-records/` under the active workspace (SKILL.md "Workspace layout"). Number a
new one by finding the highest `NNNN` already there and adding one. Link related records, the
mission and terms with wikilinks: `[[MISSION.md]]`, `[[GLOSSARY.md]]`, `[[0002-<slug>]]`.

The title states the fact now settled about the learner. The body is one to three sentences: what
they know or already knew, and what that changes about upcoming lessons. That paragraph is normally
the whole record. Example from a workspace on PostgreSQL query plans:

```markdown
# Reads estimated against actual row counts in a plan

In the third session the learner found a misestimated join by comparing the planner's rows estimate
with the actual rows in the EXPLAIN ANALYZE output, without hints. Skip plan-reading basics in later
lessons and move on to statistics targets.
```

Two optional body lines, used only when a later session would act on them:

- **Evidence:** what showed the understanding (an answer, a finished exercise, a quiz result, an
  experience the learner described)
- **Next:** which planned lessons this record moves earlier, later or off the plan

## Supersession

When a newer record contradicts an older one, the older file stays and gets a status line in its
frontmatter:

```markdown
---
Status: superseded by LR-NNNN
---
```

The `status` action excludes these records with a grep on that line (SKILL.md "Resume, Status"), so
keep the wording exact. Keeping the old record shows how the learner's understanding moved, which
helps decide what to revisit. An active record needs no status line; `Status: active` is allowed.

## Choosing the next concept

Sort concepts by what the active records show:

1. **Floor:** concepts with an active record. The learner has these.
2. **Frontier:** concepts one step past the floor. Teach from here.
3. **Out of reach:** concepts that need several prerequisites the learner lacks. Leave them for
   later.

Revisits to the floor follow a schedule, not a whim: when a concept's latest record is old for how
fast its domain moves, it is due for spaced retrieval practice, and `resume` and `status` list it
(SKILL.md "Resume, Status" and "Staleness"). Recalling a due concept with effort builds storage
strength, so open with one short retrieval question about it, not a second lecture.
