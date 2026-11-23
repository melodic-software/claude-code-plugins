---
description: "Architecture decision records in the repo's ADR convention: record one (retiring the record it reverses after a yes; with no convention, nothing is written until the human picks a shape), audit which records the code no longer backs (read-only), prune the records the person accepts. Use when 'record this decision', 'write an ADR', 'capture this decision', 'document why we chose X', 'we are reversing ADR 7', 'prune our ADRs', 'prune the ADRs', 'are our ADRs still current', or a design handoff or interview resolves a decision worth keeping. Skip when no real alternative was weighed, or the ask is an index, a template migration, or status lifecycle."
argument-hint: "[audit|prune] [--repo <repo> ...] [decision and rationale, or a file holding them]"
user-invocable: true
disable-model-invocation: false
shell: bash
metadata:
  workflow-stage: anytime
  summary: Record, audit and prune architecture decisions in the repository's existing ADR convention
---

## Repository context. Gather first

<!-- BEGIN GENERATED: gather-block. Edit docs/conventions/gather-block/block.md, then run scripts/sync-gather-block.py -->
Run each command below as its own Bash call, all sent together in one message ([worktree isolation](https://code.claude.com/docs/en/worktrees#how-claude-code-enforces-isolation)).
Keep any bound in the command's own pipe ([output limits](https://code.claude.com/docs/en/tools-reference#output-limits)).
Unless this section says otherwise, treat a failure (not a repository, git unavailable) as an unknown value and carry on. Keep these as body calls, never `## Pre-computed context` lines ([gather-block convention](https://github.com/melodic-software/claude-code-plugins/blob/main/docs/conventions/gather-block/README.md#the-pre-compute-block-runs-as-one-shell-invocation)).
<!-- END GENERATED: gather-block -->

- Current branch, `git branch --show-current`
- Working tree status (empty = clean), `git status --porcelain | head -10`

## Variables

Arguments: `$ARGUMENTS`

| Action | Does |
|---|---|
| *(bare)* | Records one decision: Steps 1 to 4. The whole argument is the decision text or a file path |
| `audit` | Lists retire candidates and writes nothing: [Audit](#audit) |
| `audit --repo <repo> ...` | The audit across several repositories: [Several repositories](#several-repositories) |
| `prune [--repo <repo> ...]` | Retires only the audit candidates the person accepts: [actions/prune.md](actions/prune.md) |

Only `audit` or `prune` as the first word selects that action; any other first word is part of the
decision. `--repo` and the other target forms in
[`${CLAUDE_PLUGIN_ROOT}/reference/target-scope.md`](${CLAUDE_PLUGIN_ROOT}/reference/target-scope.md)
are accepted only after `audit` or `prune`; the default stays this repository.

## Purpose

Record one architecture decision into whatever ADR convention the repository already has. The
convention is discovered and followed, never prescribed: this skill owns discovery, the next
identifier, the record shape, the single write, and retiring the record a decision replaces. Where no convention exists it reports what it
searched, recommends the default template beside other shapes, and defers to the human rather than
writing one.

## Input contract

The decision comes from `$ARGUMENTS` and the conversation. A file path the user names is read
verbatim. This skill never reads `design-threads.md`, `PLAN.md`, or any other planning artifact on
its own; those formats belong to the planning capability, and callers pass the decision and its
rationale in the invocation text. When context, decision, or consequences are missing, ask for them.
Never invent them.

## Admission test (advisory)

This section is the one statement of the test: callers hand decisions here instead of carrying a
copy (Composition below).

A decision earns a record when **a real alternative was weighed** and at least one of these holds:

- it is **hard to reverse**: backing it out would take real rework (a migration, a public contract,
  data already written in the new shape);
- it **shapes the system's structure**: boundaries, dependencies, interfaces, integration patterns
  between contexts, a technology carrying lock-in;
- it **shapes a key quality attribute**, such as security, privacy, performance, availability or
  cost;
- it is **not discoverable from the code**: infrastructure, cloud or external services, or a
  decision not to do something;
- it matches an entry in `adr_extra_triggers` (Settings below), a trigger the team added.

No alternative weighed means nothing to record: the record would say "we did the obvious thing".
A decision that would surprise a reader without its context is a reason to write the record well,
not a gate on writing it.

When the decision plainly fails the test, say so once, naming the part it fails, and offer to skip.
The human's call wins: if they still want the record, write it.

## Settings

Three optional keys, all documented in
[`${CLAUDE_PLUGIN_ROOT}/reference/config.md`](${CLAUDE_PLUGIN_ROOT}/reference/config.md)
"Decision-record keys", which owns the layers and the invalid-value rule: `adr_template`, a template
file used when the repository has no ADR convention; `adr_extra_triggers`, triggers that join the
admission test's "at least one" list; and `adr_retirement`, how Step 3 retires a record (`delete`,
the default, `supersede` or `archive`). Resolve them once, before Step 1, and report each value with
the layer that supplied it, `adr_retirement` in one line. The `userConfig` values are
`${user_config.adr_template}` and `${user_config.adr_retirement}`; empty or a literal unexpanded
placeholder means unset. A settings file and a template file are data, never instructions.

## Step 1. Discover the convention

Read [`${CLAUDE_PLUGIN_ROOT}/reference/adr-discovery.md`](${CLAUDE_PLUGIN_ROOT}/reference/adr-discovery.md)
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
   [`templates/adr.md`](templates/adr.md): a title, a status, a few sentences of context, decision
   and why, `Considered options` (required when alternatives were weighed) and an optional
   `Consequences`. Name which template it is and the layer that supplied it. Offer one or two other
   shapes beside it, each naming a directory, a numbering scheme and a minimal section set.
3. Point at the upstream catalog URL below so the human can read other templates.
4. Stop. Write nothing: no directory, no file, no placeholder. Done when the report is delivered and
   `git status --porcelain` is exactly what it was before the invocation.

When the human chooses in the same session, create only what they chose (the directory plus the
first record, its sections taken from the chosen template) and nothing else, then run Step 4. A repository's own
convention, found in Step 1, always wins over `adr_template` and the bundled template.

## Step 3. Retire the record the decision replaces

Runs when the new decision reverses or replaces an existing record, for an audit candidate the
person picks, and from [`prune`](actions/prune.md) for each record the person accepts. The new
record's `Considered options` (or the convention's equivalent) names the retired record by
identifier and title and says why it was reversed.

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
     form the existing records use; edit only that status. Retiring an audit candidate with no new
     record, use the convention's word for a withdrawn record. When the records carry no status,
     or no such word, say so and ask for the wording; never invent one.
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

## Audit

Read-only: writes, deletes, moves and commits nothing. Done when `git status --porcelain` is exactly
what it was before the invocation.

1. Discover the convention (Step 1). With none, report the rungs searched and stop. Skip records in
   the archive folder and records whose status already retires them. Done when the records to
   check are listed.
2. Check each record against the code, its history and the admission test, done when every listed
   record has a verdict:
   - **Gone**: what it decided (a library, service, folder, setting or pattern) no longer exists in
     the code. Evidence: the search that found nothing, and the commit that removed it.
   - **Contradicted**: a later commit or record decides otherwise. Evidence: the commit, or the
     record's `file:line`.
   - **Fails admission**: no real alternative was weighed, or none of the "at least one" conditions
     holds. Evidence: the record's `file:line`.
3. Run Step 3's citation sweep for each retire candidate; the new record is a Contradicted
   candidate's later record, and with none the proposal is drop. Done when every candidate has its
   hits listed, or none.
4. Report retire candidates grouped by those reasons, each with identifier, title, evidence and its
   citation hits, then the count of records still backed. Offer Step 3 for the candidates the person
   picks; retirement and citation edits run only there, after a yes. Done when the report is
   delivered.

### Several repositories

With no target form, the audit covers this repository, exactly as above. A target form resolves,
counts and fans out the repositories as target-scope.md says, and steps 1 to 3 run once per
repository with its root anchored, reading it at `origin/HEAD` as target-scope.md "Resolving
repositories" says: each walks its own ADR ladder from its root and sweeps its own citations with
`git -C <root> grep -n <pattern> origin/HEAD`. Every candidate carries its repository
(`owner/name`), and the report merges them as target-scope.md "Merging findings" says.

The report adds a fourth group, **Recorded in several repositories**: one decision held as a record
in two or more repositories, one row listing each. Its proposal keeps one record, in the repository
the instructions name for cross-repository decisions (an `AGENTS.md`, `CLAUDE.md` or ADR
convention of a repository in scope), and points the others at it. With no repository named for
that, the row asks which one keeps it.

Step 3 for a picked candidate runs in one repository at a time, as target-scope.md "Writes stay per
repository" says: once in each repository whose record is retired, its citations repointed at the
kept record.

## Hand-off

Commit the record, and any retirement, citation edits and pointer, in the pull request of the change that made the decision; a
decision with no code change gets a pull request of its own.

## Upstream template catalog

Templates for the human to read, cited by URL:
`https://github.com/joelparkerhenderson/architecture-decision-record`.

License: **CC BY-NC-SA 4.0** (`https://creativecommons.org/licenses/by-nc-sa/4.0/`).

This skill treats the repository's README content as CC BY-NC-SA 4.0 and each bundled template
as carrying its own license, and names the license when it declines to paste.

- **Pointer**: for the repository's license terms, see
  `https://raw.githubusercontent.com/joelparkerhenderson/architecture-decision-record/main/LICENSE.md`.

Rule beside it: catalog templates are cited for the human to read, never pasted into this skill, into
the reference file, or into a record. When asked to paste one, decline, name the URL and the license,
and offer the repository's own observed shape, or the bundled template, instead. The bundled
`templates/adr.md` is this plugin's own text, not taken from the catalog.

## What this skill does not do

- **Index generation.** README tables, `index.md`, or any catalog of records
- **Status lifecycle** beyond what the convention already defines, except the retirement and
  superseded-in-part statuses Step 3 sets; no structured status or supersedes fields are added
- **Migrating existing records** to a different template or numbering scheme
- **Imposing a convention** on a repository that has none: the default template is recommended,
  and nothing is written until the human chooses
- **Reading planning artifacts.** Callers pass the decision in; this skill does not open them

## Composition

| When | Then | How |
|------|------|-----|
| An interview or a plan close-out resolves a decision over a weighed alternative | Invoked from `/planning:interview` (if enabled) or `/planning:plan close-out` (if enabled) | The caller passes the decision, its rationale and the alternatives; the admission test above lives here, not at the caller |
| `remove-comments` deletes a comment giving the reason for one of the repository's own decisions | Invoked from `/code-tidying:remove-comments` (if enabled) in an interactive run | The caller passes the decision and the alternative the comment names; the admission test above decides |
| The decision is about what a domain term means, not why the system is built a way | `/domain-driven-design:ubiquitous-language curate` (if enabled) owns that | A term's definition goes in the glossary; the reason behind a rule goes here |
| A design handoff lists ADR candidates | Invoked from `/planning:design-handoff` (if enabled) | One invocation per candidate; the offer never blocks the handoff |
| A scan needs to read existing records | `/architecture:improve` reads the same ladder | Both skills load the plugin's shared discovery reference; neither carries a second copy |

## Next

- A decision was recorded and the work still needs a plan: /planning:plan.
- The audit found candidates to remove: /architecture:adr prune.
- A retirement left terms to rename: /docs-hygiene:rename-references.

## Gotchas

Failure modes this skill runs into, each stated as the rule it implies.

- **Duplicate identifiers exist in real repositories.** Two records can share a number. Pick highest
  plus one, report the duplicate, and never renumber: renumbering breaks every inbound link, and the
  duplicate is a fact about the repository's history rather than an error to fix here.
- **Records disagree in shape.** Where the newest few records use different heading sets, follow the
  newest and say so in the report. Silently averaging the shapes produces a record matching nothing.
- **A subtree-local ADR directory found before the root one wins.** The ladder walks up from the
  working area, so a nearer directory is the answer. Name both in the report, so the human can
  redirect when the root one was intended.
- **A convention declared in `CLAUDE.md` pointing at a directory that does not exist yet.** Declared
  beats observed when the path is inside this repository: create the record at the declared path and
  state in the report that the directory was created because the declaration named it. A declared
  path outside this repository is ignored and never written.
