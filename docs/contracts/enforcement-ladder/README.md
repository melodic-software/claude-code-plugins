---
enforcement-ladder: 3.4.1
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

Five tiers, strongest first. Inside a tier the rungs run strongest first too, and cost only breaks
ties. A rung id in backticks is a value skills write into proposals and stubs; a rung without an id
is named in prose only.

The tier order follows Lauren Tan's ranking of where to invest: codebase, static analysis,
verification, prose, human review ("All Code Is Slop (Except Mine)", AI Engineer Code Summit,
2026-11-11, <https://www.youtube.com/watch?v=ZZ19zhYnDKY&t=3618s>), and her principle "Encode
recurring fixes in mechanisms (tools, code, metadata, automation) rather than textual instructions"
(<https://github.com/poteto/brainmaxxing/blob/main/brain/principles/encode-lessons-in-structure.md>).
Inside the static-analysis tier a compiler setting sits above an architecture test for the reason
Simon Brown gives: "lean on the compiler to enforce your architectural principles, rather than
discipline, post-compilation tooling, and automated fitness functions"
(<https://simonbrown.je/modular-monolith>).

### Tier 1: Codebase

The code is changed so the mistake cannot be expressed.

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
a row says otherwise, the same command runs locally, at the stage the check-placement contract
assigns, and in CI, which is the default to aim for. The contract:
<https://github.com/melodic-software/claude-code-plugins/blob/main/docs/contracts/check-placement/README.md>.

| Rung | What it is | Runs at |
|---|---|---|
| `compiler-setting` | a stricter compiler or type-checker option, such as treating warnings as errors, that rejects the mistake at build time | local stage and CI |
| `formatter` | have the repository's format command, or the format setting it reads, rewrite the code into the rule's shape; the check runs the command and fails when the tree changed | local stage and CI |
| `editorconfig-severity` | raise the severity of a setting `.editorconfig` already supports | local stage and CI |
| `analyzer-pack-rule` | turn on, or raise the severity of, a diagnostic an installed analyzer pack or linter already defines | local stage and CI |
| `custom-analyzer` | write an analyzer the compiler or linter runs, for a project-specific invariant no installed pack checks | local stage and CI |
| `syntax-pattern-rule` | write a rule that matches a pattern in the syntax tree of the source, such as a dangerous call, an injection sink or a secret shape, with a matcher that can cover more than one language | local stage and CI |
| `architecture-test` | a test over the dependency graph or the module layout (which module may reference which, which namespace belongs to which layer), written with the repository's own architecture-test library | local stage and CI |
| `behavior-test` | a unit, integration or end-to-end test that fails when the behavior is wrong | local stage and CI |
| `harness-setting` | a Claude Code setting that blocks the action: permission deny rules, skill frontmatter flags | each agent action |
| `action-guard` | a Claude Code hook on an action no file check sees, such as a force-push or a write outside the tree | each agent action |
| `scaffold` | a template or generator that produces the right shape, the last static-analysis rung | generation |

Alias: `semgrep-rule` is read as `syntax-pattern-rule`, with a printed notice, through 3.x.
A skill that meets the old id, in a consumer's instructions or a stub, takes it as the new id and
prints a notice naming the rename. The alias is removed in 4.0.0.

The `formatter` rung holds a style rule a formatter can enforce, and sits above the linter rungs
because a formatter rewrites a violation as well as reporting it. The format command is the
`fix-cmd` of the repository's ecosystem record (the ecosystem-commands contract,
`docs/contracts/ecosystem-commands/`); the rule lands in that command or in the format setting it
reads. A style rule no recorded format command can enforce takes a linter rung.

The four linter rungs (`editorconfig-severity`, `analyzer-pack-rule`, `custom-analyzer`,
`syntax-pattern-rule`) sit between `formatter` and `architecture-test`, cheapest first.
Which CI lane runs a check and how its result reaches the required status check belongs to the PR
pipeline convention
(<https://github.com/melodic-software/claude-code-plugins/blob/main/docs/conventions/pr-pipeline/README.md>);
this ladder only says where a check runs. A git hook or a CI job is a place a check runs, not a
rung. A hook on code content is the same check as a linter rule or a test, so it takes that rung's
place in the table; a hook on an action is an `action-guard`.
`/harness-config:audit-automation-gaps` decides whether an `action-guard` earns its place, when
that skill is available.

### Tier 3: Verification

A machine runs the built system, or checks a model of it, and shows that a stated property holds.
Tests, property-based tests included, stay on the static-analysis tier with the other
deterministic checks that block a change. A verification rung runs the built system as its user
meets it, or checks every state a model can reach.

1. **`runtime-verification`**: the agent or a check runs the built application through the
   interface its user uses, follows each feature's path, and records evidence that the feature
   works and its invariants hold: output, a screenshot or a recording. A reviewer reads that
   evidence rather than the diff alone. It runs locally, before the change is reviewed, and in
   CI where the application can run there.
2. **`formal-verification`** (opt-in): a model of the system's states, or a proof about one
   algorithm, that a machine checks against every reachable state or input, such as a model
   checker over a state machine or a proof assistant over an algorithm. It is one more layer, not a
   replacement for the tiers above. A skill places a rule here only when the repository's project
   instructions opt in to formal verification; otherwise it skips this rung.

### Tier 4: Guidance

A model reads it and nothing blocks. Because nothing checks these rungs, state the rule where the
reader meets it and put an example of the mistake beside it.

1. **`automated-review`**: the repository's review criteria, read by the review bot on every pull
   request. It holds a rule only a reviewer applies, or a change to how severe a finding is; its
   findings are advisory. The rule goes in the review-criteria index (`docs/review/README.md` at
   the repository root, and the file its rows route the concern to) when the repository has one,
   else in a repository-owned `CODING_STANDARDS.md`, else in `REVIEW.md`. Skip a file a
   standards-sync bot owns (its commits are that bot's): the next sync overwrites a rule written
   there. When every candidate is skipped, write nothing in this repository and report the rule as
   a proposal for the repository the bot copies `REVIEW.md` from, named when the file's sync
   commits show it.
2. **`instruction`**: a lesson for the agent or person writing the code, in a `CLAUDE.md` or
   `AGENTS.md` line, or in a rules file under `.claude/rules/` (a path-scoped rule loads when a
   covered file is read).
3. **`skill`**: a procedure loaded on demand. Add the procedure to an existing skill first; a new
   skill is the last resort.

### Tier 5: Human only

1. **`human-review`**: the last rung id. Project docs a person applies: background a reader needs
   but no one enforces. It is where a concern lands when no rung above can hold it.

### Proportion

Most of a repository's enforcement belongs on the strongest tiers. The codebase and static
analysis hold the most rules, verification holds fewer, and guidance and human review hold the
least. The proportion is a direction, not a target: no share or count is set. A repository whose
rules sit mostly on guidance moves a rule up the ladder when it recurs after it was loaded, as "A
recurring correction" below says.

### Order of work

Before automating a loop (an agent making changes with no person at each step), work in this
order: lint first, so a check blocks new cases of a bad pattern; clean up the old cases the lint
reports; strengthen verification, so a change's result is shown rather than assumed; then
automate. Automation repeats what the loop already produces, so a step skipped before it is
repeated with every run. `/toolchain:ratchet` blocks new cases while old ones remain, when that
skill is available.

### Where boundary rules live

The `architecture-test` rung, and every skill that reviews or proposes a module boundary, reads a
repository's boundary rules from these places, in this order, and cites this list rather than its
own:

1. `REVIEW.md`
2. `ARCHITECTURE.md`
3. `docs/architecture*`
4. architecture decision records (ADRs)
5. layer rules and module conventions in the project's docs
6. unscoped `.claude/rules/*.md` files, meaning the ones with no `paths:` glob; how each kind of
   rule file loads is read live from <https://code.claude.com/docs/en/memory#path-specific-rules>
7. the repository's existing architecture-test configuration: an import or dependency rule already
   set in its manifest or a tool config file; read those files before naming a library

## Guardrail criterion

A finding earns a deterministic rung (the codebase or static-analysis tier) only if all eight hold.
This section is the one place the readers point to for the question.

1. It can be decided without reasoning: a machine reaches the same verdict every time.
2. It recurs past the threshold, or once if it is policy-class (a rule the repository states as
   policy, where one miss is already too many). An action that cannot be undone, exposes a secret,
   or sends data outside the repository is policy-class: git can revert code, tests and docs, so
   those can stay with the model, but not these.
3. A blocking check has no effective false positives; an advisory check stays under 10%. The 10% is
   a corpus-precision proxy, read off the corpus sweep, not a measured per-check rate. The record
   is `0003-verification-guards-earn-default-on-by-measured-precision.md` and
   `0080-set-check-precision-defaults-at-zero-false-positives-blocking-and-under-10-percent-advisory.md`
   under `docs/adr/`.
4. Its message names the owner or the API to use instead, so the person or agent who trips it knows
   the fix.
5. It fails on a planted or past violation and passes after the revert, and is recorded only with
   that proof.
6. It runs locally, at the stage check-placement assigns, and in CI, the same command in both, and
   fails only on new violations. A rung whose "runs at" column names one place (an action guard,
   a harness setting, a scaffold) meets this by running there.
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
| `/corrections:codify` | Which rung should stop this recurring mistake, described in the session, in a findings file (`findings`) or in review comments (`reviews`)? | the strongest rung that can decide the mistake and passes the guardrail criterion; a mistake that fails the criterion stays on the guidance tier or `human-review`, and `make-impossible` is only proposed |
| `/architecture:enforce-boundaries` | Which mechanism should hold this recorded boundary rule? | the first rung, strongest first, that can express the rule's form: a build-time boundary the ecosystem already has, then the boundary tool the repository already uses, then a maintained tool researched now, then a check in the repository's own check convention; a rule that fails the guardrail criterion gets no check |
| `/session-flow:retro` | Should this session finding be a check, and on which rung? | a finding a check could decide first wires or repairs an existing check that should have caught it; otherwise it goes to `/corrections:codify` when that skill is available; without it, the strongest rung that can decide the finding, once it meets guardrail criterion items 1, 2 and 7 as judged from the finding itself; a finding that fails one of them stays on the guidance tier |

"Strongest" is an order over this one list: it asks what leaves the least room for a whole class of
mistakes. No reader reorders the list.

A skill that places enforcement or an instruction and applies no selection rule of its own has no
row here: it hands the choice of rung to `/corrections:codify` when that skill is available. Some
readers with no row read a copy for the "Where boundary rules live" list only and pick no rung: the
`review` plugin's `architecture-guardian` agent, and the `boundaries` and `conventions` lenses of
`/architecture:improve` and `/architecture:improve-layout`, which read the `architecture` copy.
The `boundaries` lens sends each confirmed rule to `/corrections:codify findings` as an
`architecture-test` proposal.

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
