# Glossary

The project's ubiquitous language: terms this marketplace has deliberately resolved, so the same
words carry the same meaning in conversation, skill bodies, docs, and commit messages.

This file records **vocabulary only**: what a term is, and which names were considered and
rejected for it. The reasoning behind a decision lives in the artifact that made it; entries cite
that artifact rather than restating it. New terms are curated through
`/domain-driven-design:ubiquitous-language curate` rather than hand-written, so the entry discipline stays
uniform. An `Avoid:` line marks words we rejected for that entry; use the entry's term instead.

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

Avoid: design concept

**context load**

What a surface costs an agent that reads it: its tokens, charged on every session for always-loaded
ones, and the adherence a longer instruction file loses
([memory: write effective instructions](https://code.claude.com/docs/en/memory#write-effective-instructions)).
A budget separate from cognitive load below.

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

Avoid: checkpoint (for a save-point)

**handoff file**

The file in `handoffs/` that the resume prompt points at, holding only what the next session acts
on, in every handoff shape.

Avoid: hot file, resume file

**archive file**

The append-only file under `handoffs/archive/<chain>/` holding what one handoff moved out of the
handoff file, read only through a pointer in it.

Avoid: hop file

**reminder**

An item not yet started, carried across handoffs until its trigger (a time, a condition, or the
chain's close) fires, then raised to whoever acts on it. Distinct from off-thread work, which is
already running, and from a deferred item, which is an **admission** outcome.

**focus file**

`<plugin data>/focus/<session>.md`, the per-session text a `session-flow` PreCompact hook prints to
steer compaction. "Focus" is Claude Code's word for `/compact` guidance
([context window: when your context fills up](https://code.claude.com/docs/en/context-window#when-your-context-fills-up));
"focus file" is ours.

**primary source**

A record read directly from its origin, unmediated: the on-disk transcript, a live documentation
page, a shipped script's actual emitted strings. Stays primary across compaction.

Avoid: original source

**secondary source**

A description or summary standing in for a primary source: the model-visible conversation after
compaction, a header comment describing code beneath it, another agent's summary.

**light zone**

The healthiest of `context-usage`'s three context zones (`light` / `moderate` / `heavy`), naming
the band rather than any token figure.

Avoid: smart zone

**unknowns quadrants**

The four-way pre-prompt breakdown used to decide which unknown-finding pass a task needs, owned by
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

The program that runs a model as an agent, giving it tools and instructions and repeating the
model-then-tools cycle ([Claude Code glossary](https://code.claude.com/docs/en/glossary)). Bare
*harness* means Claude Code; in **vendor routing** it is any agent CLI a delegated task runs in.

### Work items

**work item** (short: **item**)

A node in the tracker's dependency graph, the same node through planning, implementation and
review.

Also called: ticket, issue

States: escalated (a lane handed it to a person), parked (the operator set it aside for a person),
deferred (admission held it until there is room)

**container**

A work item carrying the container label, grouping the items beneath it
([`label-taxonomy.md`](../plugins/work-items/reference/label-taxonomy.md#maps-and-containers)).

**wayfind map**

A work item carrying a wayfind-prefixed label, the root of one `/planning:wayfind` map of decision
items ([`label-taxonomy.md`](../plugins/work-items/reference/label-taxonomy.md#maps-and-containers)).
Not a container.

**spec container**

The container `/work-items:decompose` publishes over one plan or spec, standing for one macro
journey (discovery through review) whose items share one execution shape.

**frontier**

The set of work items ready to take now: open, unblocked, unassigned, and neither a container nor
a wayfind map item ([`CONTRACT.md`](../plugins/work-items/tools/work-item-tracker/CONTRACT.md)
`list-frontier`). Scoped to one container, it is that container's frontier.

For the model level the word is **frontier tier**, a capability tier.

**slice**

The per-topic working folder that holds a topic's plans and research, never committed. Also
written **memory slice** or **topic slice**; a folder nested inside one is a **sub-slice**.

A work item cut through every layer is a **vertical slice**.

**vertical slice**

A work item cut as a narrow but complete path through every layer, verifiable on its own and small
enough to finish in one fresh context window.

Avoid: slice (bare **slice** is the topic folder)

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

**approve**

The step that decides a work item will be built, in two pieces: the triage verdict, a judgment of
intent, security and cost that sets `status: ready`, then **admission**, which applies rules and
capacity with no model.

**admission**

The check, with no model, that lets a triage-approved issue into the build queue or defers,
refuses or parks it: the second piece of **approve**
([`admit.mjs`](../.github/scripts/intake-triage/admit.mjs)). The ADR admission test
([`adr`](../plugins/architecture/skills/adr/actions/record.md#admission-test-advisory)) is a
separate sense.

Distinct from the **queue**: the `agent-ready` issues admission let in, waiting for a build run.

Avoid: approval, commitment point

**work class**

One of the classes (C1 to C5) a unit of work falls into, assigned by its blast radius,
reversibility, input provenance and verifiability, not by its description.

Avoid: risk class (for a work class)

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

The lifecycle step a lane serves, declared per CI lane in
[`lane-rules.json`](../.github/actions/resolve-config/lane-rules.json), one of `intake`, `admit`,
`build`, `refine`, `review`, `fix`, `verify`, `hold`, `merge` and `post-merge`, plus `upstream` and
`maintenance` ([pr-pipeline convention, Stages](conventions/pr-pipeline/README.md#stages)). A step
of the session workflow, interview through retro, is a workflow stage, the sense **phase boundary**
uses.

Avoid: explore (for intake triage)

**software factory**

Every lane together, from intake through post-merge and maintenance.

Also called: kitchen

**lane leg**

One Claude Code session inside one CI lane run, on one credential
([`pull.mjs`](../scripts/lane-transcripts/pull.mjs) `LEGS`).

**lane output format**

The one shape for what a lane posts on a PR comment, check run, step summary or step log: a
heading, a plain verdict line, at most five bullets, then the **lane-outcome record** where the
surface carries it ([lane output format](contracts/loop-lane/lane-output-format.md)). Distinct
from the lane-outcome record, which names only the structured JSON part
([ADR 0087](adr/0087-keep-one-public-safe-lane-record-for-every-lane.md)).

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
AGENTS.md, Pull request states, and the hold convention in `docs/contracts/loop-lane/README.md`.

**merge rung**

A level of merge authority a repository grants its lanes, from human-only merge upward.

**merge-risk rating**

A model's rating of one pull request head, from LOW to CRITICAL, posted by the lanes App
([pr-pipeline convention](conventions/pr-pipeline/README.md)).

Avoid: risk score (that is the diff risk score)

**diff risk score**

A deterministic score of a pull request's diff, LOW, MED or HIGH, with the reason codes behind it.

Avoid: merge risk, babysit risk (merge risk is the merge-risk rating)

**changelog fragment**

A note a pull request adds for each plugin it changes, declaring the version bump (or none) and the
release notes. A release turns a plugin's pending fragments into one version and changelog entry.

### Ceilings and baselines

**ratchet**

A checked-in ceiling on a count that fails CI when the count rises and is lowered as the count
falls, so the count only moves down. Any counter can be ratcheted: lint violations, suppressions,
performance or check counts ([`/toolchain:ratchet`](../plugins/toolchain/skills/ratchet/SKILL.md)).

**ceiling**

The highest count a ratchet allows for one counter, recorded in the ceilings file.

**baseline**

A word with two senses; say which one is meant.

- check: the checked-in list of offenders a check lets through while they are paid down, one entry
  per file, rule hit or exemption; a ceiling holds a count, a baseline its members
  ([`zero-entries.md`](../plugins/toolchain/skills/ratchet/reference/zero-entries.md)). For a lint
  rule it is the linter's own baseline file, or a per-file counter where the linter has none.
- measurement: the value measured before a change, which the after value is compared against
  (`/performance:snapshot`, `/verification:measure`).

Actions: clear (Avoid: graduate, promote), deleting a check baseline once it is empty

**baselined rule**

A lint rule enforced at error severity whose existing violations a baseline holds
([`linters.md`](review/linters.md)).

Avoid: lenient rule, paying-down rule

### Models

**capability tier**

One of the ordered levels of model capability (frontier, strong, fast) that work is routed to,
named by order and never by model family.

Avoid: model tier

**model-adaptation chapter**

A chapter for one model version, read when a session runs on that version, stating what the
playbook does differently on it.

Avoid: delta chapter

### Vendor routing

**vendor routing**

Choosing the vendor (Claude, Codex or Gemini), harness, model and effort for one delegated task,
owned by [`vendors.md`](../plugins/multi-agent/reference/vendors.md). Distinct from routing a
Claude model and effort to an agent role, which `/multi-agent:route <role>` does.

**work type**

A kind of work routed on its own, such as coding (review, debugging and game development
included), web UI, knowledge work or image generation.

**workload**

A word with two senses; say which one is meant.

- benchmark workload: the subject matter a benchmark measures within a work type, such as terminal
  work or multi-file editing within coding. Sources are counted per benchmark workload.
- routing workload: a category of work a `/multi-agent:route` role can give its own model and
  effort, such as `mechanical`
  ([`config.md`](../plugins/multi-agent/reference/config.md)).

Avoid: slice (bare **slice** is the topic folder)

**benchmark registry**

The list of benchmarks and provider result pages vendor routing may read. Each row is a pointer to
a page; the scores stay on the page.

**permanent row**

A benchmark registry row with status `permanent`: it has passed the longevity, accuracy and
coverage tests. A new row starts with status `support-only`
([`vendors.md`](../plugins/multi-agent/reference/vendors.md)).

**leading source**

A permanent row that publishes an error range for its scores, so it can show a lead or a tie.

**abstain**

What a benchmark does for a vendor whose current models it does not test: it neither supports nor
blocks routing work to that vendor.

**error range**

The plus-or-minus a benchmark states beside a score. A lead smaller than it is a tie.

**trial**

Routing work to a vendor's model, version and effort not yet proven on a machine
([`vendors.md`](../plugins/multi-agent/reference/vendors.md)).

States: running, then proven (routing may send it work on that machine with no new trial) or failed.

### Configuration

**personal override**

The gitignored per-person layer of the config cascade, the highest of its four layers
([`locations.md`](contracts/config-cascade/locations.md)).

Avoid: overlay

**fallback chain**

The one order of media a view steps down when its preferred medium is unreachable, owned by the
medium registry ([rendered views](contracts/rendered-views/README.md#reachability-and-the-fallback-chain)).
The word it replaced is retired in [`vocabulary-senses.json`](../scripts/vocabulary-senses.json).

### Planning

**Brief**

The section of a `PLAN.md` that `/planning:interview` locks for an engineering task: its goal,
constraints, acceptance criteria and assumptions.

Avoid: contract

**collaborative canvas mode**

The `/visualization:visualize` mode where a person and the agent draw and revise one live canvas
(tldraw or Excalidraw) over several turns; the final text diagram, not the canvas, is the record
([`visualize`](../plugins/visualization/skills/visualize/SKILL.md)).

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
| slice *(the benchmark sense)* | **workload** above; bare "slice" means the topic folder |
| task *(for a lane)* | **lane** above; collides with the `Task` Issue Type admission reads ([`admission-rules.json`](../.github/actions/resolve-config/admission-rules.json)) |
| factory workflow *(for a lane)* | **lane** above; not every workflow is a lane |
| approval *(for admission)* | **admission** above; implies a judge, and admission runs no model |
| commitment point | **admission** above; Kanban's name for the point, which collides with a git commit |
| map / territory | the source author's metaphor, cited where it appears in [`finding-your-unknowns.md`](finding-your-unknowns.md) "The unknowns taxonomy"; never house vocabulary (metaphor-jargon risk) |
