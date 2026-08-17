---
description: "Iteratively reduce coupling at any altitude — documents, code modules, applications, or repositories: scan for change-transmitting dependencies typed against a coupling model, verify each finding, apply a budgeted batch of safe behavior-preserving reductions, and ledger structural candidates for design routing so repeated runs continue where the last stopped. Use when: 'reduce coupling', 'decouple', 'loosen coupling', 'too tightly coupled', 'high cohesion low coupling', 'break this dependency', 'dependency injection pass', 'externalize this config', 'connascence', 'coupling scan', 'these files always change together', 'stop copying between repos'. Skip when: reviewing a diff before merge (review tools), deep-designing one already-chosen boundary (/architecture:improve), general structural tidyings with no coupling focus (/code-tidying:tidy), or a docs noise/dedup pass with no cross-artifact coupling angle (docs-hygiene)."
argument-hint: "[<scope> | dry-run [<scope>] | status | help]"
user-invocable: true
disable-model-invocation: false
shell: bash
metadata:
  workflow-stage: anytime
  summary: Scan for change-transmitting coupling, apply safe reductions in a budgeted batch, route the rest
---

## Pre-computed context

Current branch: !`git branch --show-current 2>/dev/null || echo "unknown"`
Recent commits: !`git log --oneline -10 2>/dev/null || echo "no commits"`
Working tree status: !`git status --porcelain 2>/dev/null | head -10 || echo "clean"`

## Variables

Arguments: `$ARGUMENTS`

## Purpose

Answer one question, repeatedly: **which dependency in this repository transmits the most
unnecessary change, and what is the smallest mechanism that stops the transmission?** Each
invocation is one pass — scan, verify, reduce what is safely reducible within a scope budget,
surface what is not, and record everything in a durable ledger so the next invocation resumes
instead of restarting. Coupling goes down monotonically across runs; no single run tries to
finish the job.

Two lanes, split by the nature of the finding, never by convenience:

- **Apply lane** — mechanical, contained, behavior-preserving reductions (weaken a
  connascence form, de-duplicate a stated fact into a pointer, inject a hard-wired volatile
  collaborator, name a magic value). Applied this run, verified, shipped as one
  structure-only change set.
- **Route lane** — cross-file remediation and architectural judgment (move a boundary,
  introduce a seam, split a shared database, merge two repos' duplicated logic). Coupling
  findings of this shape exist to inform a human: they are surfaced, ranked, and routed —
  never auto-applied.

This is not a diff reviewer, not a designer of one chosen boundary, and not a general tidy
pass — see "What this skill does NOT do".

## Actions

| Argument | Action |
|----------|--------|
| *(empty)* | Full pass over an inferred scope: scan → verify → apply lane → route lane → ledger |
| `<scope>` | Same pass narrowed to a path, module, or altitude keyword (`docs`, `code`, `app`, `repo`) |
| `dry-run [<scope>]` | Scan, verify, rank, and ledger only. Do NOT edit, branch, push, or file tracker items |
| `status` | Read the ledger and report open candidates, applied reductions, and what the next run should take |
| `help` | Print this table with one worked example per action |

## The model

Hub-and-spoke; read the spoke before the phase that needs it:

- [`reference/coupling-model.md`](reference/coupling-model.md) — what counts as coupling, the
  strength ladder, connascence axes, volatility weighting, per-altitude mechanisms, and the
  not-a-finding list. Read before scanning; findings are typed against it.
- [`reference/remediations.md`](reference/remediations.md) — mechanism per finding kind, each
  with its over-abstraction counterweight and the sequencing rule (smallest mechanism first).
  Read before applying or routing anything.
- [`reference/ledger.md`](reference/ledger.md) — ledger entry schema, status lifecycle, and
  re-run semantics. Read at phase A and phase H.

## Workflow

Phases run in order; each gate is hard. `dry-run` stops after D (ledger write included).

**A. Orient.** Resolve scope from the argument, else infer from the conversation, else pick
the hottest area by commit frequency. Resolve the ledger path per this plugin's topic-docs
[binding](../../reference/topic-docs.md) — memory tier, constant slug, default
`.work/coupling/coupling-ledger.md`, one ledger per repo regardless of scope — and create or
resume it. Discover the consuming repo's
own review/engineering conventions (a review-criteria file such as `REVIEW.md`, a
`docs/conventions/` or standards directory, CLAUDE.md rules) and align finding vocabulary and
severity with them; the bundled model is the fallback, never an override of the consumer's
own standards.

**B. Scan.** Fan out fresh-context Explore subagents over the scope, each briefed with the
coupling model and returning findings in ledger-entry form (edge, kind, mechanism, strength,
degree, locality, evidence). In parallel, mine co-change evidence from version-control
history: file pairs that repeatedly change in the same commits without a declared dependency
are coupled through a channel the import graph cannot see, and they outrank most statically
visible findings.

**C. Verify (hard gate).** Scan agents have a demonstrated error rate. Reproduce every
finding against the actual artifacts before it reaches the ledger or the user — confirm the
edge exists, the mechanism is what the scan claims, and the depended-on side actually changes
(volatility from history, not vibes). Drop or downgrade what does not reproduce, and record
that the ledger reflects verified state, not raw scan output.

**D. Partition and rank.** Every verified finding gets a lane. Apply lane requires ALL of:
mechanical, contained in scope, behavior-preserving, and reversible by revert. Anything
cross-file in remediation or architectural in judgment is route lane — when in doubt, route.
Rank by `strength × degree × distance × volatility`; a weak-but-everywhere coupling on a hot
path outranks a strong-but-local one in cold code. Write the full ranked set to the ledger.

**E. Apply (apply lane only, scope-budgeted).** Work on a short-lived branch created from
the repository's default branch — resolve that branch (remote HEAD or the repo's own
convention), never assume its name, and never base the batch on whatever feature branch the
session happens to be on: inherited unrelated commits would break the structure-only
invariant. Never commit directly on the default branch. Before editing any target, require
it clean in `git status --porcelain`; a target carrying pre-existing local modifications
defers its finding with the reason recorded — foreign edits are never mixed into the batch.
Budget per run: target ≤200 changed lines across ≤8 files, hard cap 400/15; overflow stays
`proposed` in the ledger for the next run. Use the Edit tool; one atomic commit per logical
reduction; stage listed paths only and inspect the staged diff before each commit. Never
touch CI workflow files, hook or settings surfaces, lint configs, database migrations, or
any published contract surface (API shapes, message schemas, tool schemas) — those are route
lane by definition.

**F. Verify the batch.** Invoke `/toolchain:check` via the Skill tool for the affected
ecosystems when the `toolchain` plugin is installed; otherwise run the consuming project's
own build, test, and lint commands (its CLAUDE.md or rules may name them). A reduction that
breaks a test was secretly behavioral: revert that reduction, reclassify it as route lane,
and continue. Never ship red.

**G. Ship.** Present the verified diff, or when the session should open a pull request,
invoke `/source-control:pull-request create` when that plugin is installed; otherwise use the
repo's own PR convention with a body listing each reduction as `edge → mechanism → why safe`.
One coupling pass per PR; structure-only, no behavioral riders. A human merges — this skill
never auto-merges.

**H. Ledger update and report.** Update statuses (`applied`, `deferred`, `routed`,
`rejected` — schema in [`reference/ledger.md`](reference/ledger.md)). For route-lane
candidates: hand the top one to `/architecture:improve` (if that plugin is installed) for
design exploration, and file the rest via `/work-items:track add` when that plugin is
installed, else the repo's own tracker, else present the list to the user. Close by reporting
the ledger path, what was applied, what was routed where, and the recommended next-run scope.

## Fresh-eyes note

Phase B/C findings are judged against artifacts this session did not author, and phase F's
verdict is a deterministic build/test/lint pass — the fresh-context scan agents plus the
objective gate carry the independence; a separate fresh-context reviewer is owed only if this
skill is ever extended to judge work its own session produced outside those gates.

## What this skill does NOT do

- **Does not review a diff** — pre-merge review is a review tool's job; this hunts standing
  coupling in existing artifacts.
- **Does not deep-design one boundary** — a route-lane candidate needing interface
  exploration goes to `/architecture:improve` (when installed) or a design session.
- **Does not apply general tidyings** — rename/inline/extract without a coupling edge is
  `/code-tidying:tidy` territory.
- **Does not chase decoupling for its own sake** — a dependency on something stable and owned
  is not a finding; see the not-a-finding list in the model.

## Composition

Graceful degradation — where a named collaborator is not installed, inline the equivalent
work or present the handoff manually; never skip silently.

| When | Then |
|------|------|
| Route-lane candidate needs design exploration | `/architecture:improve` when installed; else summarize the candidate for a design session |
| Deferred or route-lane items need tracking | `/work-items:track add` when installed; else the repo's own tracker; else present the list |
| Batch needs build/test verification | `/toolchain:check` when installed; else the project's own commands |
| Shipping a PR | `/source-control:pull-request create` when installed; else the repo's own PR convention |
| A docs finding is pure prose dedup | `/docs-hygiene:extract-ssot` when installed owns the extraction; else apply per the remediation catalog |

## Gotchas

Observed failure history and the counterweights this skill exists to hold. Add here when a
new one surfaces.

- **Over-abstraction is decoupling's own disease.** An interface with one implementation, an
  event bus for a one-to-one call, a config knob nothing varies — each adds indirection while
  the coupling remains. Every remediation entry carries a *not when*; honor it. The deletion
  test: if removing the new seam tomorrow would change nothing but line count, it earned
  nothing.
- **Cross-file and architectural findings are never auto-applied.** They are designed to
  inform a human; surfacing them ranked is the success state, not a failure to finish.
- **Identical text encoding different knowledge is coincidence, not duplication.** Two
  documents (or functions) that happen to read the same but would change for different
  reasons must not be consolidated — consolidation actively harms. Test what changes
  together, not what looks alike.
- **Unverified scan claims do not ship.** A scan agent once reported a service "registered
  but never composed" that one search disproved. Phase C exists because the report lends
  every claim its authority.
- **A reduction that breaks a test was secretly behavioral.** Revert it and reclassify;
  never patch the test to keep the reduction.
- **The ledger records what a re-scan currently finds; it never replays.** Re-emitting stale
  findings re-injects problems that may already be fixed — statuses advance, evidence gets
  re-checked, and a finding that no longer reproduces is closed, not repeated.
