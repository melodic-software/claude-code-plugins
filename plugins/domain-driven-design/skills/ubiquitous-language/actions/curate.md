# curate

Change the glossary when language resolves: a new term, a term used for two concepts, competing
names for one concept, a definition that no longer matches the model, or one spelling that
intentionally means different things in different known contexts.

## 1. Establish what is resolved

Start from the conversation, the request, existing entries and relevant project artifacts. Exercise
the candidate language in one or two domain scenarios. If the meaning, canonical term or context is
still disputed, ask one focused question and do not write yet. Never manufacture consensus. When the
proposed meaning describes existing software behavior, inspect the relevant code and tests; if they
contradict the conversation, surface the mismatch and resolve which model is intended before writing.

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

## 5. Check where the old words still live

When the change adds a rejected synonym or rejected verb, or changes a term, search the context's code, docs, copy and
error messages for the rejected words (whole words, case-insensitive; a rejected verb only where it
names that operation on that entity, as `audit` step 3 says) and report each hit by file and line, in
two groups:

- **Code and docs names** (types, functions, enum values, file names, prose): hand them to
  `/docs-hygiene:rename-references <old> to <new>` as their own reviewed change; a stored value
  (an enum persisted in a database, a schema value) needs a data migration, named in the report.
- **User-facing copy and error messages**: report only, never rewrite. Users' words may rightly
  differ from the model's; a hit matching the entry's `Shown to users as:` wording is not drift.

## 6. Report

Return the canonical term and definition, rejected synonyms and verbs, the bounded context when there is more
than one, the file updated or created (or the proposed file and its setting layer when nothing was
written), the step 5 hits, and any unresolved ambiguity.
