# curate

Change the glossary when language resolves: a new term, a term used for two concepts, competing
names for one concept, a definition that no longer matches the model, or one spelling that
intentionally means different things in different known contexts. It also removes or merges entries
a person accepted, such as `audit`'s prune candidates.

## 1. Establish what is resolved

Start from the conversation, the request, existing entries and relevant project artifacts. Exercise
the candidate language in one or two domain scenarios. If the meaning, canonical term or context is
still disputed, ask one focused question and do not write yet. Never manufacture consensus. When the
proposed meaning describes existing software behavior, inspect the relevant code and tests; if they
contradict the conversation, surface the mismatch and resolve which model is intended before writing.

When choosing among candidate terms, weigh in this order: the domain experts' word, then the code's
existing usage (counted as the contract's
[Counting a term](../context/glossary-contract.md#counting-a-term) says), then the domain's
published standards and references. A standard is an input to the decision, never its authority;
when none is known, look for one with `/discovery:research`. Where users' own words differ from the
chosen term, record that on `Shown to users as:` as the contract's bullet says (words that vary by
tenant as `configurable per tenant`).

## 2. Find the record

Run [locate.md](locate.md). Preserve whatever the winning convention already fixes: filename,
location, headings, ordering and entry syntax. With no convention, the contract's ladder proposes a
name and asks before writing; unattended, report the proposal and write nothing. Re-read the target
file immediately before editing it: another turn or agent may have changed it.

## 3. Route to a known context

Use the glossary index or an explicit project convention first. Otherwise infer the applicable
**already-known** context from the task, touched files and accepted design or workshop artifacts. If
two contexts remain plausible, ask rather than putting the term in both. Do not discover, split,
merge or name bounded contexts here; when the needed boundaries are missing, stop and route to
`/event-storming:simulation`.

## 4. Update the record

Apply the target file's format and the contract: one canonical term for one concept in one context,
a tight 1-2 sentence definition of what the concept **is**, states listed under their entity,
rejected synonyms on the `Avoid:` line (a name the resolution rules out is recorded there, not folded
into the definition), an `Actions:` line when one verb was chosen over another for an operation on
the entity, an optional `Shown to users as:` line, project-specific domain concepts only,
and no implementation details, requirements, scratch notes or speculative terms.

Refine an existing entry in place instead of appending a duplicate. Preserve unrelated content and
ordering.

**Remove or merge.** Present the prune candidates (from `audit` or the request) one group at a
time, each with its reason and, for an unused term, its count. Write only the entries the person
said yes to; a group without a yes stays as it is. A merge keeps the covering term's entry, removes
the other and records the removed phrase on the covering entry's `Avoid:` line. Then report every
reference that still names a removed term, by file and line, for the same reviewed change: bold
mentions in other entries and the glossary index (which counting skips), and docs. Unattended,
report the candidates and write nothing.

A team that wants a domain owner to review glossary changes lists the glossary path in its
`CODEOWNERS` file; this skill has no reviewer setting.

## 5. Check where the old words still live

When the change adds a rejected synonym or rejected verb, or changes a term, search the context's
code, docs, copy and error messages for the rejected words (a rejected verb only where it names that
operation on that entity, as `audit` step 4 says), counted as the contract's
[Counting a term](../context/glossary-contract.md#counting-a-term) says, and report each hit by file
and line, in these groups:

- **Code and identifiers** (types, functions, enum names, file names): hand them to
  `/docs-hygiene:rename-references <old> to <new>`, renamed in one reviewed change.
- **Docs and ADR text**: the same hand-off. Accepted ADR text takes the new term; ADR file names and
  numbers stay unchanged.
- **User-facing copy and error messages**: report only, never rewrite. Users' words may rightly
  differ from the model's; a hit matching the entry's `Shown to users as:` wording is not drift.
- **Stored values and migrations** (an enum persisted in a database, a schema value): never edited;
  each is a decision. Either migrate in expand, migrate and contract phases, or keep the stored name
  behind an explicit mapping, and record the choice with `/architecture:record-decision`.
  - **Pointer**: [Parallel Change](https://martinfowler.com/bliki/ParallelChange.html)

## 6. Report

Return the canonical term and definition, rejected synonyms and verbs, the bounded context when there is more
than one, the file updated or created (or the proposed file and its setting layer when nothing was
written), the entries removed or merged with the counts their question gave and, for each, where its
meaning went (an `Avoid:` word on the covering term, moved to code or a doc, or dropped), the
surviving references to removed terms, the step 5 hits, and any unresolved ambiguity.
