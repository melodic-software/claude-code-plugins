---
enforcement-ladder: 1.0.0
---

# Enforcement ladder

One ordered list of the ways a repository can hold a rule, from the mechanism that leaves the
least room for the mistake to the one that leaves the most. Every skill that picks a mechanism for
a rule, a finding or a lesson cites this list instead of keeping its own. Each skill applies its
own selection rule to the same list; the rules are stated below the rungs.

This file is copied into plugins by `scripts/sync-shared-copies.sh`, its text unchanged under a
generated header, so it contains no relative markdown links; neighboring files are named in
backticks instead. `scripts/shared-copies.txt` lists the copies.

## Rungs

Strongest first. A rung id in backticks is a value skills write into proposals and stubs; a rung
without an id is named in prose only.

1. **`make-impossible`**: change a type, a data structure or an API so the wrong state cannot be
   written at all. Examples: an order that is either draft or submitted becomes one status field
   instead of two booleans; a function that takes a customer id and an invoice id takes two
   distinct id types so the arguments cannot be swapped. A skill on this rung only proposes. It
   hands the redesign to `/architecture:improve` when that skill is available, otherwise to
   `/planning:design`.
2. **Compiler or type settings**: a stricter compiler or type-checker option (nullable reference
   types, `strict` mode, warnings as errors) that rejects the mistake at build time.
3. **Analyzers and linters**, four sub-rungs, cheapest first:
   - `editorconfig-severity`: raise the severity of a setting `.editorconfig` already supports.
   - `analyzer-pack-rule`: turn on, or raise the severity of, a diagnostic an installed analyzer
     pack or linter already defines.
   - `custom-analyzer`: write a Roslyn analyzer for a project-specific invariant in C#.
   - `semgrep-rule`: write a Semgrep rule for a syntactic pattern in any language.
4. **`canonical-helper`**: one shared function, component or module that every caller goes
   through, replacing hand-written copies of the same guard. An agent imitates the code it reads
   next to the code it is changing. When a guard exists as five hand-written copies of uneven
   quality, the weakest copy is as likely to be imitated as the best one, and each imitation adds
   another weak copy. One helper leaves a single version to imitate, and fixing it fixes every
   caller.
5. **`architecture-test`**: a test over the dependency graph or the module layout (which module
   may reference which, which namespace belongs to which layer), such as ArchUnitNET for .NET or
   dependency-cruiser for JavaScript and TypeScript.
6. **Tests**: a unit, integration or end-to-end test that fails when the behavior is wrong.
7. **Git hook or CI**: a check that runs before a commit lands or on every pull request. Which CI
   lane runs a check and how its result reaches the required status check belongs to the PR
   pipeline convention
   (<https://github.com/melodic-software/claude-code-plugins/blob/main/docs/conventions/pr-pipeline/README.md>);
   this ladder only says that a CI check is this strong.
8. **`hook`**: a Claude Code hook that blocks or flags the action while an agent works.
   `/harness-config:audit-automation-gaps` decides whether a hook earns its place, when that skill
   is available.
9. **`llm-only`**: the concern stays a judgment no check can assert. It is written down for
   whoever reads it next, routed by audience:
   - a lesson for the agent or person writing the code: a `CLAUDE.md` or `AGENTS.md` line, or a
     rules file under `.claude/rules/`;
   - a rule only a reviewer applies, or a change to how severe a finding is: `REVIEW.md`, which
     AI review reads; its findings are advisory;
   - background a reader needs but no one enforces: project docs.

   Because nothing checks this rung, state the rule where the reader meets it and put an example
   of the mistake beside it.

### Where boundary rules live

The `architecture-test` rung, and every skill that reviews or proposes a module boundary, reads a
repository's boundary rules from these places, in this order, and cites this list rather than its
own:

1. `REVIEW.md`
2. `ARCHITECTURE.md`
3. `docs/architecture*`
4. architecture decision records (ADRs)
5. layer rules and module conventions in the project's docs
6. unscoped `.claude/rules/*.md` files, meaning the ones with no `paths:` glob (a path-scoped rule
   loads on its own when a covered file is read; an unscoped one has to be opened)
7. an existing architecture-test configuration (an ArchUnitNET test project, a
   `.dependency-cruiser.js` file, or the equivalent for the repository's language)

## Selection rules

Each reader walks the same rungs with a different question.

| Reader | Question | Rule |
|---|---|---|
| `/harness-config:audit-automation-gaps` | Is this concern already covered, and if not, what should cover it? | the strongest rung that covers the concern; a concern a stronger rung already covers is not a gap |
| `/review:audit-enforceability` | Which check could have caught this one finding? | the cheapest rung whose check can actually assert the finding; for a finding of class `invalid-state` it offers `make-impossible` first |
| `/session-flow:retro` codify | Where should this repeated correction be encoded? | its encode policy: by default a repeated correction becomes a `CLAUDE.md` or rules-file edit, and a rule that must hold every time moves up to a rung that enforces it; retro documents the setting that changes this |

"Cheapest" and "strongest" are both orders over this one list. Cheapest asks what costs least to
build and keep for one finding; strongest asks what leaves the least room for a whole class of
mistakes. Neither skill reorders the list.

## Reordering

A consuming repository reorders the rungs, or drops one, by writing its own order in its project
instructions: `CLAUDE.md`, an `AGENTS.md` the session reads, or a rules file. A skill that reads
this ladder reads those first and uses the repository's order where one exists. There is no
configuration key for the order.

## The codebase and its history are the memory

An agent starting a task learns how this repository does things from the code it reads and from
git history, more than from any document. That has two consequences:

- Prose that repeats what the code or its history already shows (a comment narrating the next
  line, a doc describing a function signature, a repository skill restating a script's flags) is
  removed or turned into a pointer. `/docs-hygiene:audit-derivability` and
  `/instruction-placement:audit` find it, when those skills are available.
- A pattern that appears in many places is copied more often than one that appears once, so the
  number of copies is what ranks cleanup work: the most-copied weak pattern is fixed first.

## Versioning

The ladder version is the `enforcement-ladder` key in this file's frontmatter, so every plugin copy
states which version it carries. `CHANGELOG.md` beside this file records each change.

- Wording only: patch.
- A new rung, a new reader row or a new boundary-rule location: minor.
- Renaming or removing a rung id, or moving a rung: major. Every skill that writes the id is
  updated in the same change.

Every change to this file regenerates the copies, and each plugin that carries a copy takes a
version bump.
