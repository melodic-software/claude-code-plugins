# Glossary

The project's ubiquitous language: terms this marketplace has deliberately resolved, so the same
words carry the same meaning in conversation, skill bodies, docs, and commit messages.

This file records **vocabulary only**: what a term is, and which names were considered and
rejected for it. The reasoning behind a decision lives in the artifact that made it; entries cite
that artifact rather than restating it. New terms are curated through
`/domain-driven-design:ubiquitous-language curate` rather than hand-written, so the entry discipline stays
uniform.

This marketplace is a single language context, so there is no glossary index: every entry below
applies repository-wide.

Naming rule: split a concept into its core responsibilities and name each piece so the pieces
compose, as **approve** is the triage verdict followed by **admission**.

## Terms

**AFK criterion**

The test of whether remaining work is scoped to run without a human at the keyboard: no decision
still owed to it, no mid-flight approval it must stop for.

Avoid: away-from-keyboard check

**asset rush**

The failure mode where a session drives toward producing the deliverable while the job is still
reaching shared understanding of what the deliverable should be. Names the critique that the
interview-first pipeline answers.

**shared understanding**

The state where the people on a task agree on the problem, its constraints and what done means,
confirmed in their own words before the deliverable is built.

**context load**

What a surface costs an agent that reads it: the tokens, charged on every session for always-loaded
ones, and the adherence it costs, since the agent follows a longer instruction file less reliably
([memory: write effective instructions](https://code.claude.com/docs/en/memory#write-effective-instructions),
read 2026-11-21). Paired with cognitive load below; the two are distinct budgets and cutting one
can overspend the other.

**cognitive load**

The attention a human maintainer pays to hold where things live across a doc set. Ten small
fragment files can be cheap in context load and expensive in cognitive load.

Avoid: mental overhead

**navigation pointer**

A curated entry in an instruction file that routes a reader to a genuinely non-obvious document the
work depends on, stating where to look and when to look there. Distinct from a file-by-file inventory,
which an agent can rebuild from the tree and which the memory audit flags. Distinct from a **pointer
record**, which records a decision about something an upstream source owns.

Avoid: highway, stale highway

**phase boundary**

The moment a stage has produced its artifact and the next has not begun.

**save-point**

What a session leaves for a fresh session to resume from: a resume prompt, always, plus an optional
handoff file the prompt points to.

Pushed commits with no pull request are PR-less, not a save-point.

Avoid: checkpoint

**primary source**

A record read directly from its origin, unmediated: the on-disk transcript, a live documentation
page, a shipped script's actual emitted strings. Stays primary across compaction.

Avoid: original source

**secondary source**

A description or summary standing in for a primary source: the model-visible conversation after
compaction, a header comment describing code beneath it, another agent's summary. Usable, but a
claim resting on one is verified against the primary before it ships.

**light zone**

The healthiest of `context-usage`'s three context zones (`light` / `moderate` / `heavy`), naming
the band rather than any token figure.

Avoid: smart zone

**unknowns quadrants**

The four-way pre-prompt breakdown used to decide which unknown-finding pass a task needs: known
knowns, known unknowns, unknown knowns, unknown unknowns. Owned by
[`finding-your-unknowns.md`](finding-your-unknowns.md); entries cite it rather than restating the
quadrants.

**blindspot finding type**

One type in the taxonomy a blindspot pass reports its findings in: Landmine (breaks something
non-obvious), History (a constraint the code no longer shows), Convention (an unwritten team
rule), Missing concept (a domain idea the prompt never named). The output contract lives in
`discovery:blindspot`; the taxonomy's rationale in
[`finding-your-unknowns.md`](finding-your-unknowns.md).

**seam**

A word with five defined senses in this repository, each owned by one file. Say which one is
meant; a bare "seam" outside these files reads as the module-design sense.

- module design: the spot where one adapter is swapped for another with no edit there
  ([`plugins/architecture/reference/vocabulary.md`](../plugins/architecture/reference/vocabulary.md)),
  the only sense an architecture finding uses;
- a presence-gated reference from one plugin to another
  ([`contracts/seam-phrasing/README.md`](contracts/seam-phrasing/README.md));
- the provider-neutral interface to a work-item tracker
  ([`plugins/work-items/reference/tracker-seam.md`](../plugins/work-items/reference/tracker-seam.md));
- the autonomy plugin's binding and runner interfaces
  ([`binding-seam.md`](../plugins/autonomy/reference/binding-seam.md),
  [`runner/seams.md`](../plugins/autonomy/reference/runner/seams.md));
- the four channels through which a consumer configures a plugin
  ([`migration-playbook.md`](migration-playbook.md#extensibility-contract-v21-the-four-seams)).

Each sense keeps its name by a recorded decision.

**harness**

The program that runs a model as an agent: it gives the model its tools, gates their use, loads
its instructions and memory, and repeats the model-then-tools cycle. In this repository the
harness is Claude Code, the sense in the `harness-config`, `harness-memory` and `harness-ops`
plugin names ([Claude Code glossary](https://code.claude.com/docs/en/glossary), read 2026-11-21).

### Work items

**work item** (short: **item**)

A node in the tracker's dependency graph, the same node through planning, implementation and
review.

Also called: ticket, issue

**container**

An ordinary work item marked as a navigable graph root (a wayfind map or a decompose breakdown),
grouping the items beneath it. It is never claimable, so it is never on its own frontier.

**spec container**

The container `/work-items:decompose` publishes over one plan or spec, standing for one macro
journey (discovery through review) whose items share one execution shape.

**frontier**

The set of work items ready to take now: open, unblocked, unassigned, and not a container. Scoped
to one container, it is that container's frontier.

For the model level the word is **frontier tier**, a capability tier.

**slice**

The per-topic working folder `<memory_dir>/<topic-slug>/` (default `.work/`) that holds a topic's
plans and research. Checkout-local and never committed. Also written **memory slice** or **topic
slice**; a folder nested inside one is a **sub-slice**.

A work item cut through every layer is a **vertical slice**.

**vertical slice**

A work item cut as a narrow but complete path through every layer, verifiable on its own and small
enough to finish in one fresh context window.

**canonical role**

A fixed name for a meaning a tracker label carries. Skills use the role name, and each repository's
tracker binding supplies the label.

**autonomous-eligible**

The role, and final triage state, of a briefed work item an agent may claim with no person present:
it has no open decision, or one defaulted to a recommended answer a maintainer can veto before
merge.

Shown to users as: configurable per binding (default `agent-ready`)

**human-gated**

The role of a work item that waits for a person to decide or act before work proceeds: an
irreversible act, a person's consent, a secret, an unmade design choice, a security issue or a cost.

Shown to users as: configurable per binding (default `needs-human`)

**escalated item**

A work item a lane handed to a person.

**operator-parked item**

A work item the operator set aside for a person.

**approve**

The step that decides a work item will be built, in two pieces: the triage verdict, a judgment of
intent, security and cost that sets `status: ready`, then **admission**, which applies rules and
capacity with no model.

**admission**

The check, with no model, that moves an issue from `status: ready` to `agent-ready`, or defers,
refuses or parks it (`status: confirmed`, `attended`, `host-run`). It is the second piece of
**approve**, at the point Kanban calls the commitment point
([`admit.mjs`](../.github/scripts/intake-triage/admit.mjs)). The local `work-loop`'s admission gate
is the same step in a local loop. The ADR admission test
([`adr`](../plugins/architecture/skills/adr/SKILL.md#admission-test-advisory))
is a separate sense.

Distinct from the **queue**: the `agent-ready` issues admission let in, waiting for a build run.

Avoid: approval, commitment point

**deferred**

The state of an issue admission has deferred. The `admission-deferred` label and the `deferred`
Work status option both mean it; it is admitted once there is room.

**work class**

One of the classes (C1 to C5) a unit of work falls into, assigned by its blast radius,
reversibility, input provenance and verifiability, not by its description.

Avoid: risk class

**security-surface work**

Work that changes how the system authenticates, authorizes, handles tokens or secrets, grants
permissions, or crosses a network boundary: a property of the work beside its work class, not a
work class. Owned by the loop-lane convention's
[capability tiers](contracts/loop-lane/README.md#3-capability-tiers). Distinct from the `autonomy`
plugin's security surface, the security binding agents cannot write.

Avoid: security-surface work class

### Lanes and pull requests

**lane**

One worker with a single authority, run as a CI workflow or a local loop, that serves one
**stage** and never does another lane's job
([pr-pipeline convention, Lanes](conventions/pr-pipeline/README.md#lanes)). Bare *lane* means this;
the qualified forms below name a run mode.

Avoid: task, factory workflow

**stage**

The step in the chain a lane serves. For CI lanes it is the `stage` field in
[`lane-rules.json`](../.github/actions/resolve-config/lane-rules.json).

**software factory**

Every lane together, from intake through post-merge and maintenance.

Also called: kitchen

**lane leg**

One Claude Code session inside one CI lane run: the key, subscription or fallback leg
([`pull.mjs`](../scripts/lane-transcripts/pull.mjs) `LEGS`).

**brake**

A mechanism that slows or stops work on its way to merge: a hold, a cap, a gate.

**accelerator**

A mechanism that moves work forward with no person: an auto-admit, an auto-merge, a chained
trigger.

**loop lane**

A lane run as a local loop: a long-running session that repeats one single-pass mechanic over a
repository's backlog or pull-request queue, either standing or draining until the queue is empty.

**pipeline lane**

One workflow of the pull-request pipeline, named for that workflow, that does one job no other lane
does.

**CI lane**

Any lane that runs as a CI workflow, inside the pull-request pipeline or not.

**attended queue**

The escalated and held work that waits for a person, and the session in which a person works it.

Avoid: human queue

**PR hold**

A stop on merging a pull request until it is lifted. Which holds each gate enforces is in
AGENTS.md, Merging.

**merge rung**

A level of merge authority a repository grants its lanes, from human-only merge upward.

**changelog fragment**

A note a pull request adds for each plugin it changes, declaring the version bump (or none) and the
release notes. A release turns a plugin's pending fragments into one version and changelog entry.

### Models

**capability tier**

One of the ordered levels of model capability (frontier, strong, fast) that work is routed to,
named by order and never by model family.

Avoid: model tier

**model-adaptation chapter**

A chapter for one model version, read when a session runs on that version, stating what the
playbook does differently on it.

Avoid: delta chapter

### Upstream records

**pointer record**

Our decision, in our own words, about something an upstream source owns, plus a pointer to the
exact upstream section, issue or probe. It stores no upstream value. Distinct from a **navigation
pointer**, which routes a reader to a document inside the repository.

**stored value** *(the upstream-drift sense)*

A number or string copied or measured from an upstream source and kept in our text, with an as-of
date and a recheck trigger.

**recheck trigger**

The stated observable event, never a bare date, whose firing obliges re-deriving a stored value or
the decision the trigger guards.

Avoid: revisit trigger, re-derivation trigger

## Rejected terms

Names considered for a concept this project already owns, recorded so they are not reintroduced.
Each maps to the term or doctrine that owns the concept.

| Rejected | Owned by |
|---|---|
| design concept | **shared understanding** above |
| grill-execute-clear | the house workflow taxonomy, which already names the loop |
| push vs point | always-loaded versus on-demand surfaces, the load tiers the `instruction-placement` plugin places content in |
| highway / stale highway | **navigation pointer** above; survives only as a quoted mnemonic |
| cache *(the doc-restating-environment sense)* | `docs-hygiene:audit-derivability`'s derivable-from-environment doctrine; the word is overloaded here (plugin cache, prompt cache) |
| sediment | the `docs-hygiene` audit family's pruning doctrine; collides with the code-sense use in `playbooks:fable-5` |
| sycophancy | nothing. It is a generic LLM-behavior term with no distinct project meaning. Free-prose use is unaffected; it is not project vocabulary |
| slice *(the work-item sense)* | **vertical slice** above; bare "slice" means the topic folder |
| task *(for a lane)* | **lane** above; collides with the `Task` Issue Type admission reads ([`admission-rules.json`](../.github/actions/resolve-config/admission-rules.json)) |
| factory workflow *(for a lane)* | **lane** above; not every workflow is a lane |
| approval *(for admission)* | **admission** above; implies a judge, and admission runs no model |
| commitment point | **admission** above; Kanban's name for the point, which collides with a git commit |
| map / territory | the source author's metaphor, cited where it appears in [`finding-your-unknowns.md`](finding-your-unknowns.md) "The unknowns taxonomy"; never house vocabulary (metaphor-jargon risk) |
