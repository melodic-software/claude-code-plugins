---
description: "Record an architecture decision into the repository's existing ADR convention: discovers the ADR directory, numbering scheme, and record shape in use and writes one record that follows them; when no convention exists it names what it searched, offers common shapes, and writes nothing until the human chooses. Use when: 'record this decision', 'write an ADR', 'architecture decision record', 'capture this decision', 'document why we chose X', or after a design handoff or interview resolves a decision worth keeping. Skip when: the decision is easily reversed and unsurprising (no ADR earned), or the ask is supersession, an index, or status lifecycle beyond what the convention already defines."
argument-hint: "[decision and its rationale, or a path to a file holding them]"
user-invocable: true
disable-model-invocation: false
shell: bash
metadata:
  workflow-stage: anytime
  summary: Record an architecture decision in the repository's existing ADR convention
---

## Repository context. Gather first

Collect these with **individual** Bash calls, one command per call, never combined into a single
invocation:

- Current branch, `git branch --show-current`
- Working tree status (empty = clean), `git status --porcelain | head -10`

The pipe is the bound and belongs in the command. A read-time cap ("read only the first 10 entries")
bounds nothing: the Bash tool returns the command's complete output into context before there is
anything to decide about.

Treat a failure (not a repository, git unavailable) as an unknown value and carry on. Keep these as
separate body Bash calls rather than pre-compute lines: the harness runs a skill's whole pre-compute
block as one shell invocation, and a worktree-isolated session refuses a compound command that
contains git.

## Variables

Arguments: `$ARGUMENTS`

## Purpose

Record one architecture decision into whatever ADR convention the repository already has. The
convention is discovered and followed, never prescribed: this skill owns discovery, the next
identifier, the record shape, and the single write. Where no convention exists it reports what it
searched, offers common shapes, and defers to the human rather than inventing one.

## Input contract

The decision comes from `$ARGUMENTS` and the conversation. A file path the user names is read
verbatim. This skill never reads `design-threads.md`, `PLAN.md`, or any other planning artifact on
its own; those formats belong to the planning capability, and callers pass the decision and its
rationale in the invocation text. When context, decision, or consequences are missing, ask for them.
Never invent them.

## Admission test (advisory)

A decision earns a record when ALL three hold: it is **hard to reverse**, it is **surprising without
context** (a future reader would wonder why it was done this way), and it is **the result of a real
trade-off** (genuine alternatives existed and one was picked for stated reasons).

When the decision plainly fails the test, say so once and offer to skip. The human's call wins: if
they still want the record, write it.

## Step 1. Discover the convention

Read [`${CLAUDE_PLUGIN_ROOT}/reference/adr-discovery.md`](${CLAUDE_PLUGIN_ROOT}/reference/adr-discovery.md)
and walk its ladder from the working area up to the repository root, first hit wins.

Emit one paragraph naming the directory, the numbering scheme, the template source (or that there is
none), and any duplicates or shape disagreement observed. That paragraph is the evidence for
everything Step 2 does.

## Step 2a. Convention found

1. Derive the next identifier: highest existing plus one, preserving the observed zero-pad width and
   separator. A date-prefixed scheme uses today's date in the observed format. Done when the
   identifier is one no existing filename already carries.
2. Derive the filename in the observed form (identifier, separator, kebab-case title, extension).
   Done when it is indistinguishable in form from the records already there.
3. Derive the section set from the template source; absent a template, from the newest records. Done
   when every heading in the set is one the observed shape uses.
4. Re-read the target directory immediately before writing, confirming no record has appeared since
   Step 1 that would change the identifier.
5. Write **exactly one** file, and report its path. Done when `git status --porcelain` shows that one
   new path and nothing else.

Do not create, rename, or renumber any other file. Report duplicates and leave them where they are.

## Step 2b. No convention

1. List the rungs searched, so the human can see the search was real and where it stopped.
2. Offer two or three common shapes, each naming a directory, a numbering scheme, and a minimal
   section set.
3. Point at the upstream catalog URL below so the human can read templates and pick one.
4. Stop. Write nothing: no directory, no file, no placeholder. Done when the report is delivered and
   `git status --porcelain` is exactly what it was before the invocation.

When the human chooses in the same session, create only what they chose (the directory plus the
first record) and nothing else.

## Upstream template catalog

Templates for the human to read, cited by URL:
`https://github.com/joelparkerhenderson/architecture-decision-record`.

License: **CC BY-NC-SA 4.0** (`https://creativecommons.org/licenses/by-nc-sa/4.0/`).

- **Claim**: README-authored content in that repository is licensed CC BY-NC-SA 4.0; the bundled
  templates carry their own licenses, stated per template.
- **Basis**: `https://raw.githubusercontent.com/joelparkerhenderson/architecture-decision-record/main/LICENSE.md`.
- **As of**: 2026-09-06.
- **Recheck trigger**: that `LICENSE.md` changes, or the repository moves.

Rule beside it: catalog templates are cited for the human to read, never pasted into this skill, into
the reference file, or into a record. When asked to paste one, decline, name the URL and the license,
and offer the repository's own observed shape instead.

## What this skill does NOT do

- **Supersession workflows.** Marking a record superseded, and the bookkeeping around it
- **Index generation.** README tables, `index.md`, or any catalog of records
- **Status lifecycle** beyond what the convention already defines
- **Migrating existing records** to a different template or numbering scheme
- **Prescribing a convention** to a repository that has none
- **Reading planning artifacts.** Callers pass the decision in; this skill does not open them

## Composition

| When | Then | How |
|------|------|-----|
| An interview resolves a decision that earns a record | Invoked from `/planning:interview` when that plugin is installed | The caller passes the decision and its rationale; the gate lives at the caller |
| A design handoff lists ADR candidates | Invoked from `/planning:design-handoff` when that plugin is installed | One invocation per candidate; the offer never blocks the handoff |
| A scan needs to read existing records | `/architecture:improve` reads the same ladder | Both skills load the plugin's shared discovery reference; neither carries a second copy |

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
  beats observed: create the record at the declared path and state in the report that the directory
  was created because the declaration named it.
