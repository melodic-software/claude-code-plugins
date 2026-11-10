---
description: "The project's ubiquitous-language glossary: locate, lookup (read terms), seed a first one, curate (canonical terms, rejected synonyms, definitions), audit. Use when: 'what does this domain term mean', 'update the domain glossary', 'define this domain term', 'standardize this vocabulary', 'these names conflict', 'we have no glossary yet', 'check our glossary', domain modeling resolves vocabulary, or a skill needs domain terms before naming something. Not for dictionary definitions or bounded-context discovery."
argument-hint: "[locate|lookup|seed|curate|audit] [term, ambiguity, or resolved vocabulary]"
user-invocable: true
disable-model-invocation: false
metadata:
  workflow-stage: plan
  summary: Find, read, seed, maintain and check the domain glossary
---

## Variables

Request: `$ARGUMENTS`

## Purpose

Own every operation on the consuming project's ubiquitous-language record: finding it, reading it,
starting it, changing it and checking it. The glossary is not a static dictionary and not the domain
model by itself: it records language the team has actually resolved, so the same words are used in
conversation, documentation, tests and code within one bounded context.

Other skills never find or parse the glossary themselves: they invoke the `lookup` action, so the
file's location and shape are resolved in one place.

Entry discipline, the convention-resolution ladder and the multi-context rules live in
[context/glossary-contract.md](context/glossary-contract.md). Read it before any action.

## Action router

Take the first token of `$ARGUMENTS` as the action when it is one of the five names; the rest is the
action's input.

| Action | Writes | When | Read |
|---|---|---|---|
| `locate` | nothing | Which glossary and glossary index cover a scope | [actions/locate.md](actions/locate.md) |
| `lookup [term...]` | nothing | A skill or a person needs the domain terms before naming, writing or explaining something | [actions/lookup.md](actions/lookup.md) |
| `seed` | accepted terms only | The project has no glossary for the scope | [actions/seed.md](actions/seed.md) |
| `curate` | the glossary | A term resolved, conflicts, or changed meaning | [actions/curate.md](actions/curate.md) |
| `audit` | nothing | Check entries against the contract and find rejected words in use | [actions/audit.md](actions/audit.md) |

With no action token: a question about what a term means, or a request to read the glossary, is
`lookup`; a resolved, disputed or changed term is `curate`; anything else asks which action.

## Invocation by consuming workflows

- **Readers** (`/planning:interview`, `/planning:plan`, `/planning:prd`, `/testing:write`,
  `/work-items:decompose`, `/naming:name-it-better` and others) invoke `lookup` at the step where they
  choose or judge a name, and use its canonical terms. `lookup` never writes.
- **Writers** (`/planning:interview`, `/planning:design`, `/architecture:improve`, EventStorming
  wrap-up) invoke `curate` when a discussion resolves vocabulary, then resume. This skill does not
  take ownership of the caller's Brief or design artifacts.

## Boundaries

- **Loaded on demand only.** The glossary reaches a session through `lookup`, never through an
  `@` import in `CLAUDE.md` or an always-loaded rule: a session that names nothing pays nothing.
- **No bounded-context discovery.** Consume existing boundaries. When the project has not
  established the boundaries a term needs, route that work to `/event-storming:simulation`.
- **No general dictionary.** Exclude generic programming and methodology terms unless the consuming
  project's domain gives them a distinct meaning.
- **Domain only.** Framework and tooling nouns belong in the project's architecture docs.
- **No spec or scratchpad.** Behavior, implementation, acceptance criteria and open questions belong
  in their owning artifacts.
- **No ADR ownership.** Surface consequential decisions to the planning workflow.
- **No speculative scaffolding.** An empty glossary or index is worse than no file; create lazily.
- **No autonomous consensus.** Ambiguous language is a question, not a write; `seed` writes only
  terms a person accepted one by one.
- **Never rewrites code or copy.** Code names follow the glossary, but the rename goes through
  `/docs-hygiene:rename-references` in its own reviewed change; user-facing copy and error messages
  are reported, never rewritten.

## Next

/planning:plan. The plan uses the curated terms as its canonical vocabulary.

## Gotchas

- The nearest glossary is not automatically the right one in a multi-context repo; route through the
  glossary index and task context first.
- A walk up from the code never reaches a sibling `docs/` folder; `locate` searches the repository,
  not only the ancestors.
- The same spelling in two contexts is not necessarily duplication. Keep distinct definitions when
  the established models differ.
- A request to "set up the glossary" does not override lazy creation or authorize invented terms.
