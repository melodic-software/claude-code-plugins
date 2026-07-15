# Glossary Format

`GLOSSARY.md` is canonical language for a learning workspace. All explainers, exercises, and learning records adhere to its terminology. Building it is itself part of learning: compressing a concept into a tight definition is evidence the user understands it.

## Template

```markdown
# {Topic} Glossary

{One or two sentence description of the topic this glossary covers.}

## Terms

**{Term}**:
{One or two sentence definition. What it IS, not what it does or how to do it.}
_Avoid_: {alternative names to NOT use — pick the best term, list rest as aliases to avoid}

**{Term 2}**:
{Definition using glossary's own terms where possible.}
_Avoid_: {aliases}
```

## Rules

- **Add a term only when the user understands it.** The glossary records compressed knowledge, not a dictionary the user reads to learn. Wait for evidence of comprehension before promoting
- **Be opinionated.** When several words exist for the same concept, pick the best one and list the rest as `_Avoid_`. This is how language compresses
- **Keep definitions tight.** One or two sentences. Define what the term IS
- **Use the glossary's own terms inside definitions.** Once a term is in the glossary, prefer it everywhere — including inside other definitions. This makes complex terms easier to grasp later
- **Group under subheadings** when natural clusters emerge. Flat list is fine when terms cohere
- **Flag ambiguities explicitly.** If a term is used loosely in the wider field, note the resolution: "In this workspace, 'set' always means a working set"
- **Revise as understanding deepens.** A definition from week one may be wrong by week six. Update in place
- **Durable = rot-relevant.** The glossary is revisited as authoritative — on revisit treat entries as unverified and re-verify volatile-domain terms per SKILL.md "Staleness" before relying on them

## Relationship to a repo's shared language

For `codebase` mode, the glossary may reference or extend the consuming repo's own shared-language / ubiquitous-language documentation when it has any (e.g. a `UBIQUITOUS-LANGUAGE.md`, a domain glossary in `docs/`). But the learning glossary is personal — it captures the USER's understanding, which may be incomplete. A team's shared language is the authoritative team vocabulary; the learning glossary is the learner's growing one.
