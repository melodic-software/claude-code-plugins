# Qualified names for clashing terms

Read this when a term the interview asks about, or a term the user uses, may clash with a concept
the project already names (SKILL.md "Clashing terms, prototypes and fact lookups"). It extends
the glossary challenge in "Domain-aware behaviors".

## What counts as a clash

A term clashes when the same word already names a different concept in either place:

- **The code**: a type, module, table, column, config key, route or command whose name is the
  term and whose meaning differs from the one the user intends. Grep the code for the term at the
  survey and again when a round introduces it, and cite each hit as `file:line`.
- **The glossary**: the project's domain-vocabulary file (the one the survey climbed to) defines
  the term differently, or lists it as a rejected synonym.

A term used two ways by the user alone is the glossary challenge's probe, not this rule; this rule
starts once a clash with an existing concept is found.

## Propose the qualified name yourself

Never ask the user to come up with a qualifier, and never leave the bare term standing beside the
clash. The question's recommendation is a qualified name you derive from the evidence: the term
plus the word that separates the user's meaning from the existing one (for example `billing
account` when the code's `Account` is a sign-in identity, `src/auth/account.ts:12`). Ask it as a
registered question in the full layout:

- **Context**: the user's meaning in their words (`user, round <N>`), the existing concept with its
  source (`file:line` or the glossary entry), and the sentence that would be ambiguous without the
  qualifier.
- **My recommendation**: the qualified name, with the reason the qualifier fits.
- **Alternatives**: a different qualifier; qualifying the existing concept instead (a rename of the
  code or the glossary entry, which is larger work and goes to the closing summary's Glossary
  group); or keeping the bare term with a stated boundary, when the evidence shows the two meanings
  never meet in one sentence.

Add the qualified name to the ledger's `## Terminology matrix` as a `proposed` row in the same
round, citing the clash as its source; it becomes `agreed` on the user's answer. Until then, no
other question uses the qualified name as settled.

## Write the agreed name

Once the user agrees, write it through the route SKILL.md already names for a resolved term, the
inline vocabulary update (`/domain-driven-design:ubiquitous-language curate` when that plugin is
enabled; otherwise the term and its definition go in the resolution field of the register row that
resolved it), under the resolved `domain_docs` value: `auto` writes it, `ask` asks once before
writing, `off` records it in the register row only. Hand the writer the qualified name, its
definition, the existing concept it is distinguished from with that concept's source, and the bare
term as the ambiguous form to avoid. A general session writes nothing to the repository and keeps
the agreed name in the register row and the shared-understanding summary.
