# Glossary Format

Each workspace keeps its word list in `GLOSSARY.md`. Lessons, exercises, quiz questions and learning records
use the names it fixes and no others. Each entry also records something the learner has shown: a
term goes in after the learner has used or explained it correctly, and stating it in a sentence or
two is part of that evidence.

## When an entry is added

The file does not exist in a new workspace. It is created at the first term the learner
demonstrates, usually at session close (SKILL.md "Session Close") or during `assess`.

A term qualifies once there is evidence of the kind [assessment.md](assessment.md) records: the
learner explained it in their own words in the dialog, used it correctly in an exercise answer, or
answered a quiz question that depends on it. A term that was only shown in a lesson waits. The
glossary records what the learner knows; it is not reading material for learning the term.

## Writing an entry

1. **Look for an existing entry first.** If the concept is already there under any name, edit that
   row. Understanding changes over sessions and early definitions turn out wrong; the row is
   corrected in place, never duplicated.
2. **Fill the Meaning here cell.** A sentence or two on the concept itself, built from rows already
   in the file where possible; how it is used and how to do it belong in lessons and `reference.md`.
   When the field uses the word for more than one thing, this cell also states the one this
   workspace uses and rules out the others (see the `Cost` row in the example below).
3. **Fill the Not called cell.** When the field has several words for the concept, the row's Term is
   the clearest and the rest go here. Leave the cell empty when there is no real competitor; never
   invent one to fill it.
4. **Use the Term column everywhere.** Lessons, exercises, quiz questions and other rows use the
   name in the Term column, never a synonym, so a hard term later reads as a combination of known
   ones.

## Template

```markdown
# Glossary: {Topic}

{One or two sentences naming the subject these terms belong to.}

| Term | Meaning here | Not called |
|---|---|---|
| {term} | {what it is, one or two sentences} | {competing names, or empty} |
| {term 2} | {built from terms above where possible} | |
```

When the terms fall into clear groups, give each group its own `## {Group}` heading and table. One
table is enough for a small or uniform set.

Example rows from a workspace on PostgreSQL query plans:

| Term | Meaning here | Not called |
|---|---|---|
| Sequential scan | A plan node that reads every row of a table in storage order | table scan, full scan |
| Index scan | A plan node that finds rows through an index, then fetches each from the table; faster than a sequential scan only when few rows match | |
| Cost | The planner's estimate of the work a plan node needs, in arbitrary units; not elapsed time, which only EXPLAIN ANALYZE reports | |

A workspace written before this layout may hold bold-term entries instead of a table; read it by
meaning and convert it when the file is next edited.

## On revisit

The glossary is reread as settled fact, so it can go stale. Treat every entry as unverified when a
later session opens it, and re-check terms from fast-moving domains per SKILL.md "Staleness" before
teaching from them.

## Codebase mode and a repository's own vocabulary

In `codebase` mode the glossary may point to or build on the repository's shared vocabulary
document when one exists (a `UBIQUITOUS-LANGUAGE.md`, or a domain glossary under `docs/`). The two
stay separate. The repository's document is the team's agreed vocabulary and is authoritative; the
learning glossary records this one learner's understanding, which may still be partial.
