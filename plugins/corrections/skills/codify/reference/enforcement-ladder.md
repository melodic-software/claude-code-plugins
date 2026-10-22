---
enforcement-ladder: 2.0.0
---

<!-- GENERATED from docs/conventions/enforcement-ladder/README.md by scripts/sync-shared-copies.sh. Do not edit this copy:
edit the canonical source, then rerun the script. -->

# Enforcement ladder

One ordered list of the ways a repository can hold a rule, from the mechanism that leaves the
least room for the mistake to the one that leaves the most. Every skill that picks a mechanism for
a rule, a finding or a lesson cites this list instead of keeping its own. Each skill applies its
own selection rule to the same list; the rules are stated below the rungs.

This file is copied into plugins by `scripts/sync-shared-copies.sh`, its text unchanged under a
generated header, so it contains no relative markdown links; neighboring files are named in
backticks instead. `scripts/shared-copies.txt` lists the copies.

## Rungs

Four tiers, strongest first. Inside a tier the rungs run strongest first too, and cost only breaks
ties. A rung id in backticks is a value skills write into proposals and stubs; a rung without an id
is named in prose only.

### Tier 1: Codebase

The code is shaped so the mistake has no place to go.

1. **`make-impossible`**: change a type, a data structure or an API so the wrong state cannot be
   written at all. Examples: an order that is either draft or submitted becomes one status field
   instead of two booleans; a function that takes a customer id and an invoice id takes two
   distinct id types so the arguments cannot be swapped. A skill on this rung only proposes. It
   hands the redesign to `/architecture:improve` when that skill is available, otherwise to
   `/planning:design`.
2. **`shared-helper`**: one shared function, component or module that every caller goes through,
   replacing hand-written copies of the same guard. An agent imitates the code it reads next to the
   code it is changing. When a guard exists as five hand-written copies of uneven quality, the
   weakest copy is as likely to be imitated as the best one, and each imitation adds another weak
   copy. One helper leaves a single version to imitate, and fixing it fixes every caller. A helper
   counts on this tier only when a lint or check names it, so a caller that bypasses it fails.
   Without one, the helper enforces nothing: it is a convention, and belongs on the guidance tier.

### Tier 2: Static analysis

A machine asserts the rule and can block. The "runs at" column says where each check runs. Unless
a row says otherwise, the same command runs at edit time and in CI, which is the default to aim for.

| Rung | What it is | Runs at |
|---|---|---|
| Compiler or type settings | a stricter compiler or type-checker option (nullable reference types, `strict` mode, warnings as errors) that rejects the mistake at build time | edit time and CI |
| `editorconfig-severity` | raise the severity of a setting `.editorconfig` already supports | edit time and CI |
| `analyzer-pack-rule` | turn on, or raise the severity of, a diagnostic an installed analyzer pack or linter already defines | edit time and CI |
| `custom-analyzer` | write a Roslyn analyzer for a project-specific invariant in C# | edit time and CI |
| `semgrep-rule` | write a Semgrep rule for a syntactic pattern in any language | edit time and CI |
| `architecture-test` | a test over the dependency graph or the module layout (which module may reference which, which namespace belongs to which layer), such as ArchUnitNET for .NET or dependency-cruiser for JavaScript and TypeScript | edit time and CI |
| Tests | a unit, integration or end-to-end test that fails when the behavior is wrong | edit time and CI |
| `harness-setting` | a Claude Code setting that blocks the action: permission deny rules, skill frontmatter flags | edit time |
| `action-guard` | a Claude Code hook on an action no file check sees, such as a force-push or a write outside the tree | edit time |
| `scaffold` | a template or generator that produces the right shape, the last rung before prose | edit time |

The four linter rungs (`editorconfig-severity`, `analyzer-pack-rule`, `custom-analyzer`,
`semgrep-rule`) sit between the compiler settings and `architecture-test`, cheapest first. Which CI
lane runs a check and how its result reaches the required status check belongs to the PR pipeline
convention
(<https://github.com/melodic-software/claude-code-plugins/blob/main/docs/conventions/pr-pipeline/README.md>);
this ladder only says where a check runs. A git hook or a CI job is a place a check runs, not a
rung. A hook on code content is the same check as a linter rule or a test, so it takes that rung's
place in the table; a hook on an action is an `action-guard`.
`/harness-config:audit-automation-gaps` decides whether an `action-guard` earns its place, when
that skill is available.

### Tier 3: Guidance

A model reads it and nothing blocks. Because nothing checks these rungs, state the rule where the
reader meets it and put an example of the mistake beside it.

1. **`automated-review`**: `REVIEW.md`, read by the review bot on every pull request. It holds a
   rule only a reviewer applies, or a change to how severe a finding is; its findings are
   advisory.
2. **`instruction`**: a lesson for the agent or person writing the code, in a `CLAUDE.md` or
   `AGENTS.md` line, or in a rules file under `.claude/rules/` (a path-scoped rule loads when a
   covered file is read).
3. **`skill`**: a procedure loaded on demand. Add the procedure to an existing skill first; a new
   skill is the last resort.

### Tier 4: Human only

1. **`human-review`**: the last rung id. Project docs a person applies: background a reader needs
   but no one enforces. It is where a concern lands when no rung above can hold it.

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

## Guardrail criterion

A finding earns a deterministic rung (tier 1 or 2) only if all eight hold. This section is the one
place the readers point to for the question.

1. It can be decided without reasoning: a machine reaches the same verdict every time.
2. It recurs past the threshold, or once if it is policy-class (a rule the repository states as
   policy, where one miss is already too many).
3. A blocking check has no effective false positives; an advisory check stays under 10%. The 10% is
   a corpus-precision proxy, read off the corpus sweep, not a measured per-check rate. The record
   is `0003-verification-guards-earn-default-on-by-measured-precision.md` and
   `0080-set-check-precision-defaults-at-zero-false-positives-blocking-and-under-10-percent-advisory.md`
   under `docs/adr/`.
4. Its message names the owner or the API to use instead, so the person or agent who trips it knows
   the fix.
5. It fails on a planted or past violation and passes after the revert, and is recorded only with
   that proof.
6. It runs at edit time and in CI, the same command in both, and fails only on new violations. A
   rung whose "runs at" column names one place (an action guard, a harness setting, a scaffold)
   meets this by running there.
7. No stronger rung already covers it.
8. It has a kill switch, a "not useful" exit, and exceptions with an expiry.

A finding that fails the criterion stays on the guidance tier or `human-review`.

### A recurring correction

When the same correction recurs, ask first whether the rule was loaded. If the rule was not loaded,
fix where it lives: move or reword it so the reader meets it. If it was loaded and ignored, move it
up the ladder. Judge whether it was loaded by native means only: what the session's own instruction
loading shows, not a guess about what the model remembered.

## Selection rules

Each reader walks the same rungs with a different question.

| Reader | Question | Rule |
|---|---|---|
| `/harness-config:audit-automation-gaps` | Is this concern already covered, and if not, what should cover it? | the strongest rung that covers the concern; a concern a stronger rung already covers is not a gap |
| `/review:audit-enforceability` | Which check could have caught this one finding? | the cheapest rung whose check can actually assert the finding and passes the guardrail criterion; for a finding of class `invalid-state` it offers `make-impossible` first |
| `/session-flow:retro` codify | Where should this repeated correction be encoded? | its encode policy: by default a repeated correction becomes an `instruction` edit (a `CLAUDE.md` or rules-file line), and a rule that must hold every time moves up to a rung that enforces it; retro documents the setting that changes this |

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
- Renaming or removing a rung id, or moving a rung between tiers: major. Every skill that writes
  the id is updated in the same change. `CHANGELOG.md` lists each rename.

Every change to this file regenerates the copies, and each plugin that carries a copy takes a
version bump.
