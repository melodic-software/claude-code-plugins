---
name: curate-language
description: "Actively maintain a consuming project's ubiquitous-language glossary as domain understanding changes: resolve ambiguous or overloaded terms, choose canonical language, record rejected synonyms, sharpen what-it-IS definitions, and route terms to an already-known bounded context. Use when: 'update the domain glossary', 'define this domain term', 'standardize this vocabulary', 'these names conflict', domain modeling resolves vocabulary, or planning resolves domain language worth preserving. Not for passive glossary lookup, general dictionary definitions, or bounded-context discovery."
argument-hint: "[term, ambiguity, or resolved vocabulary]"
user-invocable: true
disable-model-invocation: false
metadata:
  workflow-stage: plan
  summary: Maintain the domain glossary — resolve terms, record rejected synonyms
---

## Variables

Request: `$ARGUMENTS`

## Purpose

Maintain the consuming project's active, committed vocabulary record. The glossary is not a static
dictionary and not the domain model by itself: it records language the team has actually resolved so
the same model language can be used consistently in conversation, documentation, tests, and code.

This skill owns **changing** that record. Merely reading the nearest glossary so another skill uses
the right words is a one-line habit and does not require this workflow.

Detailed entry, discovery, and multi-context rules live in
[context/glossary-contract.md](context/glossary-contract.md). Read that file before any glossary write.

## Workflow

### 1. Establish what is resolved

Start from the conversation, `$ARGUMENTS`, existing glossary entries, and relevant project artifacts.
Identify the concrete language change:

- a new project-specific concept has a stable meaning
- one term is being used for two concepts
- several names compete for one concept
- an existing definition no longer matches the team's model
- the same spelling intentionally means different things in different known contexts

Exercise the candidate language in one or two domain scenarios. If the meaning, canonical term, or
context is still disputed, ask one focused question and do not write yet. Never manufacture consensus.
When the proposed meaning describes existing software behavior, inspect the relevant code and tests.
If they contradict the conversation, surface the mismatch and resolve which model is intended before
writing; do not silently treat either source as authoritative.

### 2. Resolve the consumer's convention

Discover before choosing:

1. Read the consuming project's `AGENTS.md`, `CLAUDE.md`, `.claude/rules`, and declared documentation
   conventions.
2. From the files and domain area in scope, walk toward the repository root looking for an existing
   domain-vocabulary file or context map.
3. Prefer the nearest applicable existing convention; preserve its filename, location, headings,
   ordering, and entry syntax.
4. If no glossary exists, create one only after the first term resolves. Infer its location and shape
   from the repository's documentation layout and already-declared context artifacts. When more than
   one placement is plausible, ask. Do not impose a fixed filename.

Re-read the target file immediately before editing it. Another turn or agent may have changed it.

### 3. Route to a known language context

Use an existing context map or explicit project convention first. Otherwise infer the applicable
**already-known** context from the task, touched files, and accepted design/workshop artifacts. If two
contexts remain plausible, ask rather than putting the term in both.

Do not discover, split, merge, or name bounded contexts here. If the project has not established the
needed boundaries, stop and route that work to its domain-discovery or EventStorming capability. This
skill only maintains vocabulary inside boundaries already supplied by the project or user.

### 4. Update the record

Apply the target file's format and the contract in `context/glossary-contract.md`:

- one canonical term for one concept in one context
- a tight 1–2 sentence definition of what the concept **is**
- rejected synonyms recorded using the file's convention, with a plain `Avoid:` line as the readable
  fallback
- project-specific domain concepts only
- no implementation details, requirements, scratch notes, or speculative terms

Refine an existing entry in place instead of appending a duplicate. Preserve unrelated content and
ordering. If a term changes meaning, make the change explicit and report likely vocabulary drift; do
not silently rename code or unrelated documentation as part of this skill.

### 5. Report the maintained model language

Return:

- canonical term and definition
- rejected synonyms, if any
- bounded context, when the project has more than one
- file updated or created
- any unresolved ambiguity or observed drift that needs a separate change

## Invocation by consuming workflows

`/planning:interview` and `/planning:design` invoke this skill the moment an engineering discussion
resolves project vocabulary (the `planning` plugin declares a dependency on this plugin). They
continue their own workflow after the glossary update; this skill does not take ownership of the
Brief or design artifacts.

Other plugins may invoke `/domain-driven-design:curate-language` when it is available in the
current session. When it is unavailable, they may preserve their existing minimal fallback: update
an already-declared glossary in its own shape, or offer a discovery-first lazy creation without
inventing a filename.

## Boundaries

- **No bounded-context discovery.** Consume existing boundaries; never apply discovery heuristics.
- **No general dictionary.** Exclude generic programming and methodology terms unless the consuming
  project's domain gives them a distinct meaning.
- **No spec or scratchpad.** Behavior, implementation, acceptance criteria, and open questions belong
  in their owning artifacts.
- **No ADR ownership.** Surface consequential decisions to the planning workflow; its established ADR
  admission and placement rules remain the single owner.
- **No speculative scaffolding.** An empty glossary or map is worse than no file; create lazily.
- **No autonomous consensus.** Ambiguous language is a question, not a write.

## Gotchas

- The nearest glossary is not automatically the right one in a multi-context repo; route through the
  consumer's map and task context first.
- The same spelling in two contexts is not necessarily duplication. Keep distinct definitions when
  the established models differ.
- A request to "set up the glossary" does not override lazy creation or authorize invented terms.
