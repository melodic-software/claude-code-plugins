# Glossary Format

`GLOSSARY.md` fixes the vocabulary of a learning workspace. Lessons, exercises and learning records
use its terms and no competing ones. Writing an entry is also a check on the learner: a concept the
user can state in a sentence or two is a concept they have grasped.

## Template

```markdown
# {Topic} Glossary

{A sentence or two saying which subject these terms belong to.}

## Terms

**{Term}**:
{A definition of one or two sentences that says what the thing is. Leave its uses and procedures to lessons.}
_Avoid_: {OPTIONAL, competing names this workspace does not use; omit the line when there is no real competitor}

**{Term 2}**:
{A definition built from terms already in this file where it can be.}
```

## Rules

- **Define the thing itself, briefly.** One or two sentences on what the term is
- **Settle loose terms in writing.** Where the wider field uses a word for more than one thing, record which meaning this workspace uses: "Here, 'cache hit' counts only reads served without a network call"
- **Choose one name per concept.** Where the field uses several words for one idea, keep the clearest and put the others on the `_Avoid_` line. Omit that line when no real competitor exists; never invent a weak one to fill the template
- **Build on earlier entries.** Once a term is defined, use it in later definitions and everywhere else in the workspace instead of a synonym; later, harder terms then read as combinations of known ones
- **An entry follows understanding.** Promote a term only once there is evidence the user comprehends it. The file is a record of what the user knows, not reading material for learning it
- **Edit entries in place as understanding grows.** An early definition is often wrong later; correct it rather than adding a second entry
- **Add subheadings when the terms fall into groups.** A single list is fine for a small or uniform set
- **Durable = rot-relevant.** The glossary is revisited as authoritative, so on revisit treat entries as unverified and re-verify volatile-domain terms per SKILL.md "Staleness" before relying on them

## Relationship to a repo's shared language

For `codebase` mode, the glossary may reference or extend the consuming repo's own shared-language / ubiquitous-language documentation when it has any (e.g. a `UBIQUITOUS-LANGUAGE.md`, a domain glossary in `docs/`). But the learning glossary is personal. It captures the USER's understanding, which may be incomplete. A team's shared language is the authoritative team vocabulary; the learning glossary is the learner's growing one.
