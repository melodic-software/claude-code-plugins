# record

Record one architecture decision into the repository's ADR convention: Steps 1 to 4. The whole input
is the decision text or a file path ([Input contract](../SKILL.md#input-contract)). The default
action.

## Admission test (advisory)

This section is the one statement of the test: callers hand decisions here instead of carrying a
copy ([Composition](../SKILL.md#composition)), and `audit` checks records against it.

A decision earns a record when **a real alternative was weighed** and at least one of these holds:

- it is **hard to reverse**: backing it out would take real rework (a migration, a public contract,
  data already written in the new shape);
- it **shapes the system's structure**: boundaries, dependencies, interfaces, integration patterns
  between contexts, a technology carrying lock-in;
- it **shapes a key quality attribute**, such as security, privacy, performance, availability or
  cost;
- it is **not discoverable from the code**: infrastructure, cloud or external services, or a
  decision not to do something;
- it matches an entry in `adr_extra_triggers` ([Settings](../SKILL.md#settings)), a trigger the
  team added.

No alternative weighed means nothing to record: the record would say "we did the obvious thing".
A decision still provisional on a prototype that has not run fails the test; it becomes eligible
once the prototype's verdict confirms it.
A decision that would surprise a reader without its context is a reason to write the record well,
not a gate on writing it.

When the decision plainly fails the test, say so once, naming the part it fails, and offer to skip.
The human's call wins: if they still want the record, write it.

## Step 1. Discover the convention

Read `<plugin-root>/reference/adr-discovery.md`
and walk its ladder from the working area up to the repository root, first hit wins.

Emit one paragraph naming the directory, the numbering scheme, the template source (or that there is
none), and any duplicates or shape disagreement observed. That paragraph is the evidence for
everything Step 2 does.

## Step 2a. Convention found

1. Derive the next identifier per discovery's "Inference: numbering" (the directory, its archive folder and its git history). Done when the
   identifier is one no current, archived or deleted record has carried.
2. Derive the filename in the observed form (identifier, separator, kebab-case title, extension).
   Done when it is indistinguishable in form from the records already there.
3. Derive the section set from the template source; absent a template, from the newest records. Done
   when every heading in the set is one the observed shape uses.
4. Re-read the target directory immediately before writing, confirming no record has appeared since
   Step 1 that would change the identifier.
5. Write **exactly one** new record, and report its path. Done when `git status --porcelain` shows
   that one new path and nothing else, until Step 3 or Step 4 runs.

Outside Steps 3 and 4, do not create, rename, renumber or edit any other file. Report duplicates and leave them
where they are.

## Step 2b. No convention

1. List the rungs searched, so the human can see the search was real and where it stopped.
2. Recommend one shape: `docs/adr/` with four-digit numbering (`0001-short-title.md`) and the
   template the `adr_template` setting resolves, else the bundled
   [`templates/adr.md`](../templates/adr.md): a title, a status, a few sentences of context,
   decision and why, `Considered options` (required when alternatives were weighed) and an optional
   `Consequences`. Name which template it is and the layer that supplied it. Offer one or two other
   shapes beside it, each naming a directory, a numbering scheme and a minimal section set.
3. Point at the [upstream template catalog](../SKILL.md#upstream-template-catalog) URL so the human
   can read other templates.
4. Stop. Write nothing: no directory, no file, no placeholder. Done when the report is delivered and
   `git status --porcelain` is exactly what it was before the invocation.

When the human chooses in the same session, create only what they chose (the directory plus the
first record, its sections taken from the chosen template) and nothing else, then run Step 4. A repository's own
convention, found in Step 1, always wins over `adr_template` and the bundled template.

## Step 3. Retire the record the decision replaces

Runs when the new decision reverses or replaces an existing record, and from
[`prune`](prune.md) for each record the person accepts. The new record's `Considered options` (or
the convention's equivalent) names the retired record by identifier and title and says why it was
reversed.

A changed decision gets a new record, never an amendment inside the accepted one: an accepted record
is edited in place only to rename a term, to set its status, or to repoint a citation the sweep
below lists.

**Citation sweep.** Every retirement path runs it, whatever `adr_retirement` says: `delete` and
`archive` break a path citation, and `supersede` leaves a citation naming a decision no longer in
force. Search tracked files with `git grep -n` for the old record's identifier, in each form the
records and existing citations use (`ADR 7`, `ADR-007`, `0007`), and for its filename; report the
patterns searched. Skip the old record itself and the new record's line naming it. List each hit as
`file:line` (code, docs, skills, other records) with one proposal: point it at the new record's
identifier or path, or drop it when there is no new record or the line only made sense with the old
decision. List a changelog or release-note hit as keep: it is history. List a hit that does not
refer to the record, such as another numbered series (a database migration `0007_...`), as not a
citation, with no edit. Done when every hit carries a proposal, a keep or a not-a-citation, or the
report says the search found none.

**Partial reversal.** When the new decision reverses only part of a record, keep the old file
whatever `adr_retirement` says, and in place of steps 1 to 3: after writing the new record, name the
old one and the superseded-in-part status you will set, naming the part, in the words and form the
existing records use, and run the citation sweep, proposing a change only for a citation of the
reversed part and listing the rest as keep. Ask. On a yes, edit that status and the proposed
citation lines only; on a no, leave them and say so. When the records carry no such wording, say so
and ask for it.

1. After writing the new record, name the old one, the resolved `adr_retirement` and its layer, what
   that will do to the old file, and the citation sweep's hits with their proposals. Ask; one yes
   covers the retirement and the citation edits. Act only on a yes; on a no, leave them and say so.
   Done when the person has answered.
2. Retire it, and edit each proposed citation line as proposed and nothing else in those files. Done
   when the citation edits and the one change below are on disk:
   - `delete`: remove the file. Its number is never reused (discovery's numbering rule).
   - `supersede`: set the old record's status to superseded by the new identifier, in the words and
     form the existing records use; edit only that status. Retiring a record with no new record
     (from `prune`), use the convention's word for a withdrawn record. When the records carry no
     status, or no such word, say so and ask for the wording; never invent one.
   - `archive`: move the file, name unchanged, to the ADR folder's archive folder. When none exists,
     ask where it goes, default `archive/` inside the ADR folder (`docs/adr/archive/` for
     `docs/adr/`); once it exists, its existence is the answer.
3. With `delete`, make sure the ADR folder tells agents where retired records went: one line saying
   retired records live in this folder's git history and that gaps in the numbering mark them. Put
   it in a nested `AGENTS.md` in the ADR folder, created or appended, unless the repository keeps
   folder instructions on another surface, which then holds it. Propose the line and its file, and
   write it only after a yes. Skip this when the line is already there. Done when the line is in
   place or the person declined.
   - **Pointer**: when choosing the surface, fetch
     [memory § When Claude Code reads AGENTS.md](https://code.claude.com/docs/en/memory#when-claude-code-reads-agents-md)
     live.

Done when `git status --porcelain` shows the new record, the one retirement or partial-status
change, the files whose citations were edited, and the line's file if it was written, and nothing
else.

## Step 4. Offer a pointer comment

After a record is written, offer one pointer comment at the module or line the decision governs: one
line in that file's comment syntax, citing the record in the form the repository's records and
citations already use (its identifier, or its path), and no restated reason. Write it only after a
yes; never add one unasked. The citation sweep finds it when the record is retired, so the pointer
does not outlive its record. `/code-tidying:remove-comments` (if enabled) keeps such a pointer. Done
when the pointer is written or declined.
