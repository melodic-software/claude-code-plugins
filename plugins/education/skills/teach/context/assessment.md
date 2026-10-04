# Assessment and Learning Records

Assessment updates the learner model: what's understood, what's frontier, what misconceptions exist. Learning records are the persistent form.

## When to Assess

| Signal | Action |
|---|---|
| User explained a concept correctly in own words | Record as demonstrated understanding |
| User completed exercise without hints | Record as skill acquired |
| User identified correct tradeoff in comparison exercise | Record as wisdom demonstrated |
| User said "I already know X" | Record as prior knowledge (note depth claimed) |
| User held misconception that was corrected | Record as corrected misconception (high value) |
| Mission shifted based on learning | Record as mission shift + update MISSION.md |
| End of session | Prompt reflection, record demonstrated understanding from session |

When assessing via quiz, hold the equal-length answer rule: multiple-choice options carry equal length and formatting weight, so presentation never signals the correct answer (design rules in [context/exercises.md](exercises.md)).

## Learning Record Format

Records live per [SKILL.md](../SKILL.md) "Workspace layout" (`learning-records/` under the active topic workspace). Scan that directory for the highest existing `NNNN` and increment. Cross-link related records, the mission, and terms with wikilinks (`[[MISSION.md]]`, `[[GLOSSARY.md]]`, `[[0002-<slug>]]`).

```markdown
# {The fact now settled about the learner, as a short title}

{One to three sentences: what the user now knows or already knew, and how that changes the next lessons.}
```

A record is usually just this paragraph. Its job is to change a later teaching choice; filling in
sections does not add to that.

### Optional Sections

Add one only when a later session would need it:

- **Status** frontmatter (`active | superseded by LR-NNNN`): set once a later record replaces this one
- **Evidence**: what showed the understanding (an answer the user gave, an exercise they finished, experience they described)
- **Implications**: later lessons this record opens up or rules out

## What Does NOT Qualify as a Learning Record

- Session logs: a record is an insight that steers later teaching, not an account of what happened in a session
- A term definition: that goes in `GLOSSARY.md`, and a record does not repeat it
- A topic that was taught but not yet shown to be understood: record it once the user demonstrates it

## Supersession

A record that a later one contradicts stays on disk with `Status: superseded by LR-NNNN` in its
frontmatter. Keeping both shows the path the learner's understanding took, which helps choose what
to revisit.

## Zone of Proximal Development Calculation

Use learning records to determine what to teach next:

1. **Established floor**: concepts with active learning records (user knows these)
2. **Current frontier**: concepts one step beyond the floor (user is ready for these)
3. **Out of reach**: concepts requiring multiple prerequisites the user lacks (defer)

Pick teaching targets from the frontier. Floor revisits are **scheduled by age × domain velocity**, not occasional whim: a concept whose latest record is old relative to how fast its domain moves is due for spaced retrieval practice, surfaced at `resume`/`status` (SKILL.md "Resume, Status" + "Staleness"). Effortful recall of a due floor concept builds storage strength. Ask a quick retrieval question, not a re-lecture.
