# Assessment and Learning Records

Assessment updates the learner model — what's understood, what's frontier, what misconceptions exist. Learning records are the persistent form.

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

## Learning Record Format

Records live per [SKILL.md](../SKILL.md) "Workspace layout" (`learning-records/` under the active topic workspace). Scan that directory for the highest existing `NNNN` and increment. Cross-link related records, the mission, and terms with wikilinks (`[[MISSION.md]]`, `[[GLOSSARY.md]]`, `[[0002-<slug>]]`).

```markdown
# {Short title of what was learned or established}

{1-3 sentences: what was learned (or what prior knowledge was established), and why it matters for future sessions.}
```

Most records are this short. Value is recording THAT this is known and WHY it changes what to teach next.

### Optional Sections

Only when they add genuine value:

- **Status** frontmatter (`active | superseded by LR-NNNN`) — when earlier understanding turns out wrong
- **Evidence** — how the user demonstrated understanding (question answered, exercise completed, prior experience cited)
- **Implications** — what this unlocks or rules out for future sessions

## What Does NOT Qualify as a Learning Record

- Material merely covered (coverage is not learning — wait for evidence)
- Anything already captured in `GLOSSARY.md` as a term definition
- Session-by-session activity logs (records are decision-grade insights, not journals)

## Supersession

When a later record contradicts an earlier one (understanding deepened or corrected), mark the old record `Status: superseded by LR-NNNN`. Don't delete — the history of how understanding evolved is itself useful signal.

## Zone of Proximal Development Calculation

Use learning records to determine what to teach next:

1. **Established floor** — concepts with active learning records (user knows these)
2. **Current frontier** — concepts one step beyond the floor (user is ready for these)
3. **Out of reach** — concepts requiring multiple prerequisites the user lacks (defer)

Pick teaching targets from the frontier. Occasionally revisit the floor for spaced practice.
