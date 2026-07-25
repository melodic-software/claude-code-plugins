---
name: audit-pass
description: "Run ONE coordinated, ordered, resumable pass over a named target repository: a three-scope inventory first (managed policy read-only, user scope routed as recommendations, project scope), then delegated checks lane by lane, findings persisted per lane so an interrupted run resumes instead of restarting, and one human gate for the whole pass instead of one per skill. Adds run semantics, not checks — every check belongs to the plugin that owns it and is invoked presence-gated. Read-only on bare invocation; edits only behind an explicit --fix override, and never to managed policy or user-scope files. Use when: 'audit pass', 'run one pass over this repo', 'coordinate the audit skills', 'audit this repo end to end', 'resume the audit', 'one reconciled findings report', 'sweep all three scopes', or before a release that needs a single diffable findings artifact."
argument-hint: "[target] [--fix] [--opinion] [--resume] [--report-to <path>]"
user-invocable: true
disable-model-invocation: false
---

## Purpose

One bounded, ordered pass over a target repository's Claude Code **instruction** surface, coordinated
across three scopes and resumable mid-run. It **adds no criteria of its own** — every check is
delegated to the plugin that owns it. What it contributes is what invoking those skills by hand
yields none of: a three-scope inventory before any check runs, a run-time-derived exclusion set,
stable finding identity, suppression memory, incremental persistence and resume, and one human gate
for the pass. All of it is specified in [reference/run-contract.md](reference/run-contract.md).

## Read-only contract, and where mutation can reach

Bare invocation reads and reports. `--fix` is the only mutation path, and it is bounded by scope:

| Scope | Posture under `--fix` |
|---|---|
| Managed policy | **Never remediated.** Read-only in every mode. A finding here reports "conflicts with org policy at `<path>`" and proposes no edit to either side — seeking a policy exception is an organizational decision, not a linting one. |
| User | **Routed as a recommendation, never edited in place.** A user-scope tree is commonly managed by a dotfiles manager, so an in-place edit is drift the operator's own sync path will fight. |
| Project | The only editable scope, per-finding confirmed. |

## Scope boundary (route out)

- **One instruction surface against the model-capability catalog** → `/claude-config:audit-instructions`
  directly. This pass dispatches that skill; it does not re-answer it.
- **Config-file correctness** → `/claude-config:audit`; grant portability →
  `/claude-config:audit-permission-grants`; automation landscape → `/claude-config:audit-automation-gaps`.
  None is in this pass's surface set.

## Arguments

Parse `$ARGUMENTS`:

- **`target`** — the git repository to audit. Default: `${CLAUDE_PROJECT_DIR}` when set, else
  `git rev-parse --show-toplevel`. Never the working directory — a run launched from a subdirectory
  must key and scan identically to one launched from the root.

  **`target` must resolve to the active project root, and a path that does not is refused.** The
  delegated interfaces accept no target: `audit-instructions` takes a surface scope and inventories
  the active project, and `claude-memory:audit` takes an action verb. This pass dispatches skills and
  never reads inside one, so there is no channel through which it could tell a delegate to look
  elsewhere — a run given `../other-repo` would key, lock, and report against that path while every
  delegated finding came from the active project. Findings attributed to the wrong repository are
  worse than a refusal, because nothing downstream can detect the mismatch.

  So the argument is validated rather than silently reinterpreted: a `target` that does not resolve
  to the active project root exits non-zero, naming both paths and the reason. Auditing another
  repository means opening it as the project. Lifting the restriction is a change to the
  **delegated** interfaces — each would have to accept and honor a target root — and belongs to
  those skills rather than this one. The argument itself survives because the state key, the lock,
  and the report are already keyed on the resolved root.
- **`--fix`** — the explicit mutation override. Absent, the pass writes nothing into the target.
- **`--opinion`** — run the `OPINION`-tier checks the delegated catalogs declare default-off.
- **`--resume`** — resume the most recent incomplete run for this target's state key.
- **`--report-to <path>`** — redirect the report into the target tree. **The redirecting run adds
  that path to its own exclusion set before writing** — not only for later runs, or the two runs'
  derived sets could not be equal — and says so in its output.

## Phase 0 — Resolve, key, lock

Resolve the target root, compute the state key, and take the lock posture for the mode — read-only
runs take no lock and run concurrently; an applying run takes an exclusive advisory lock and refuses
rather than queues. All specified in [reference/run-contract.md](reference/run-contract.md). With
`--resume`, read the run manifest and carry forward every lane whose input digest is unchanged.

**`--resume` never attaches to a run that is still going.** Concurrent read-only runs are safe
because each owns its own partial artifact; resume is the one operation that reaches into *another*
run's artifact, so the no-lock policy that makes concurrency safe is exactly what leaves resume
unable to tell a live run from an interrupted one. Both would then append lane attempts and
terminating records to one file, and highest-terminated-attempt assembly becomes race-dependent —
the interruption-tolerance mechanism producing a report neither run performed.

So every active run, read-only included, maintains a **lease**, and `--resume` reads it before it
reads the manifest. The lease is fully specified in
[reference/run-contract.md](reference/run-contract.md) §3 — its path, refresh interval, and
staleness threshold — because "on the same heartbeat the applying lock uses" named a mechanism that
did not exist and left the classification unimplementable. A **live** lease means the run is still
going: resume exits non-zero naming the run id rather than attaching. A **stale** lease means the run
was interrupted and its artifact is resumable. The lease is not a lock — it excludes nothing, blocks
no concurrent read-only run, and grants no exclusivity; it answers the one question resume has to ask
and previously could not.

**The scan baseline is captured after the inventory is frozen and before any lane reads.** The
digest spans every inventoried scope, so it cannot be computed before Phase 1 has produced that
inventory — taking it at the top of Phase 0 would either omit the user and managed surfaces, which
are exactly the mid-run external edits the gate exists to detect, or force an unspecified second
inventory. So Phase 0 resolves, keys, and locks; Phase 1 freezes the inventory; the **scan baseline**
— the target's HEAD commit and the run's state digest — is taken at that boundary, and the matching
**audit endpoint** capture is taken when the last lane completes, before any Phase 5 mutation.

Baseline to endpoint is therefore exactly the window in which lanes read, which is what the
determinism gate is a claim about — a run that never measures it cannot claim it held. The digest
pairs each path with a hash of its current content, because a *count* holds still while a dirty
file's contents change underneath the run.

## Phase 1 — Three-scope inventory, before any check

**Nothing is checked until all three scopes are inventoried.** A project-only inventory cannot see a
project-versus-user conflict, so a fix from one would be applied against half the picture.
Native-first: the filesystem walk produces a **candidate** set, never the answer.

**Liveness has two ground-truth sources, and neither alone covers the surface set.**
`InstructionsLoaded` payloads name exactly which instruction files loaded and through which parent,
but only for the memory layer (`CLAUDE.md`, `.claude/rules/*.md`); `/context` covers what that misses
— Skills, Custom Agents, MCP Tools — and is where launch-directory dependence becomes visible. Take
**both** and report a disagreement rather than picking a winner; a single-source design under-covers
silently, and under-coverage reads as a clean report. **Neither observes `managed-settings.json`'s
`claudeMd` key** — a limitation of these two sources, not a claim about the harness: probe for it and
name it in `skipped`. Then `/memory`, `/skills`, `/hooks`, `/mcp`, `/permissions`, `/status`, and
`claude --safe-mode` with a relocated `CLAUDE_CONFIG_DIR` for a clean-room comparison.

**`InstructionsLoaded` is normally UNAVAILABLE, and the run says so rather than requiring it.** This
plugin wires no `InstructionsLoaded` hook, the only producer in this marketplace
(`claude-ops/hooks/instructions-loaded-audit.sh`) is optional, is a no-op without a telemetry sink,
and drops `session_start` events by default — and the startup events this skill would need have
already fired before it is invoked, so there is nothing to subscribe to at dispatch time even where a
producer exists. Requiring data the plugin never records would make the memory-layer liveness
inventory unbuildable in the ordinary installation, which is the one every first operator has.

So the source is **probed, not assumed**, and its absence is a reported state rather than a failure:

- **Present** — a recorded payload set for this session exists and is fresh — take it as ground truth
  for the memory layer, as specified above.
- **Absent** — the ordinary case — report `InstructionsLoaded: unavailable` in `skipped`, naming the
  capture prerequisite that would supply it. `/context` alone then carries the memory layer, and
  every memory-layer liveness claim in the report is marked **single-sourced**, because the whole
  reason for two sources is that neither covers the set alone.

Marking is what keeps this honest: a single-sourced inventory is usable, and silently presenting it
as the two-source result would be the same under-coverage-reads-as-clean failure the two-source rule
exists to prevent. The liveness basis records which sources were live, so a run with the hook and a
run without are **not comparable** and cannot fail P1 against each other.

Record, per scope, every surface found **and every surface skipped with its reason**. The inventory
is a reported derived-tier artifact, so a surface that silently drops out of scope between two runs
fails the determinism property rather than looking like an improvement.

**Output styles are the case a walk alone cannot get right.** They modify the system prompt directly,
drop the built-in software-engineering instructions unless `keep-coding-instructions: true`, and a
plugin's `force-for-plugin` "overrides the user's `outputStyle` setting" — so a walk plus settings
reports a selection as live when it is not ([output styles](https://code.claude.com/docs/en/output-styles),
verified 2026-07-24). Report the resolved live style and what resolved it.

**Shadowed definitions fall out of this inventory, not out of a catalog.** Skills, subagents, and MCP
servers override *by name*: where two share a name across scopes, exactly one is live. That is name
comparison across a fixed precedence order — deterministic, model-free, derived tier — reported at
`info` in its own section naming the live definition and the shadowed one. It is not a conflict
finding and is never merged into one.

## Phase 2 — Derive the exclusion set

**Derived at run time from the target's own state. Never transcribed, and no count of any class is
ever carried in this skill** — a count written down is wrong on the next commit and wrong in every
other repository. Four classes: registered byte-identical cluster copies, vendored upstream
materializations, worktrees, and the pass's own artifacts. Each class's derivation, its fallback on a
failed read, and the hard error when a suppression targets an excluded path are in
[reference/exclusion-set.md](reference/exclusion-set.md).

## Phase 3 — Lanes and dispatch

**A lane is one delegated invocation at the finest filter that skill's own interface accepts** — the
granularity the pass can actually dispatch, since it invokes skills and never reaches inside one. A
finer lane is unbuildable, not merely inconvenient: per-lane persistence, input digests, and
selective resume all key on something the pass can re-invoke on its own.

So the split falls out of the delegated interfaces rather than being asserted over them: a skill
taking a **surface-class filter** yields one lane per filter value it is given, and a skill taking
only an action verb yields **one lane** covering everything it audits. Where a skill runs its whole
catalog per invocation, the lane carries that whole catalog — the pass never splits a catalog it
cannot address. Extending a delegated interface to accept a finer filter is a change to that skill,
and until it lands the lane stays at the coarser grain.

Dispatch, in inventory order, each invocation presence-gated with its fallback stated:

- **`/claude-config:audit-instructions`** — sibling in this plugin, always available. Carries the
  model-capability catalog over every non-memory surface, and the cross-layer conflict check. It
  takes a **surface-class scope**, so it yields **one lane per scope value dispatched**, each running
  that skill's whole catalog over that class. Its conflicts come back as **one finding carrying two
  sites**, never two linked findings — a contradiction is retired by fixing either side, so the sides
  are not independently correctable.
- **`/claude-memory:audit`** — invoke when the `claude-memory` plugin is installed; it owns
  memory-layer hygiene and the within-memory-layer consistency check. It takes an **action verb and
  no surface filter**, so it is **exactly one lane** covering the whole memory layer. Not installed:
  the pass reports both as **unchecked**, names that skill as their owner, and emits the one-line
  pointer to the official memory guidance — never a silent skip, never a re-implementation here.

Structural skill lint is deliberately **not** dispatched: it answers shape rather than content, and
its fan-out over a large corpus would consume the dispatch budget reserved for instruction-content
lanes. Route it out (`skill-quality:check` when installed).

Persist each lane's findings to the partial artifact **as that lane completes**, never buffered to
the end — a lane is complete when its terminating record is in the partial, and every record carries
its attempt id so an abandoned re-attempt is discardable rather than merely older.

**The lane count is bounded by the delegated interfaces, not chosen here** — one per scope value the
instruction catalog accepts, plus one for the memory layer — so it is a handful, and a per-run
dispatch ceiling would never bind. What is *not* bounded here is the fan-out inside a lane: the
delegated catalogs spawn their own subagents. So cap concurrency at 3–5 lanes and let incremental
persistence carry the rest — it is what degrades a blown session ceiling into a resumed run.

## Phase 4 — The `/doctor` handoff

`/doctor` owns the `CLAUDE.md` trim-and-migrate half, for which this pass deliberately builds no
replacement. **It is interactive, so it is never dispatched** — it proposes fixes only after the
operator confirms. Its version floor, what its presence check verifies versus what it must probe
rather than assume, and its optional-capability absence classification are in
[reference/doctor-handoff.md](reference/doctor-handoff.md). When absent, name it as the missing
capability and state what goes unchecked.

**Phase 4 records the handoff; it does not stop the pass.** Emitting the instruction and halting here
meant a `--fix` run never reached Phase 5 and *no* run reached the Phase 6 report — so the presence
of an optional collaborator cancelled the coordinated pass that is this skill's entire purpose,
leaving the operator worse off than if `/doctor` had been absent. It also contradicted
`reference/doctor-handoff.md`, which says to finish the pass's own phases first.

So Phase 4 opens the `delegated` lane, records the instruction in the report, and continues. Phases 5
and 6 run normally, and the assembled report carries the handoff as an outstanding item with its lane
terminated `open` — routed and not yet returned. The operator runs `/doctor` when they choose; a
later `--resume` closes that lane by re-prompt rather than re-scan, because nothing about it needs
the sweep to run again.

## Phase 5 — Apply, only under `--fix`

Per-finding confirmation, project scope only, bounded by the table above. Refuse and name the
canonical source if a fix or a suppression would write into a derived-exclusion path.

The apply-verify step judges work this same run produced, so it is delegated: hand the applied diff
and the finding it claims to resolve — the artifact, not this run's reasoning — to a cross-vendor
advisor when one is installed and set up (the OpenAI Codex plugin, say, invoked per its own docs),
with a **fresh-context (non-fork) subagent** as the stated fallback.

## Phase 6 — Report

Two artifacts, because incremental persistence and a sectioned report want different shapes: an
append-only `findings.partial.jsonl` during the run, assembled into `findings.json` at the end. Both
schemas, the identity-versus-presentation field split, the sections, and the tier memberships are in
[reference/run-contract.md](reference/run-contract.md). Tiers stay in separate sections because their
guarantees differ. Every run also emits, in **one line**, how many `OPINION`-tier checks were
available, how many were not run, and the argument that enables them (`--opinion`) — without it the
tier ships unreachable.

## The suppression record

A deliberately-kept finding is recorded at `.claude/audit-pass.md` in the target repository, layered
per the config-cascade convention. **It is the only suppression mechanism — there is no inline
marker**, at any target: a marker would have to carry the same constituents, could not express a
two-site finding at all, and would write into a tree the pass must leave clean. An entry stores the
finding's **constituents** — `check`, `claim`, every `(surface, anchor)` site — under the
`finding_id` derived from them, never a bare id: an id is a one-way hash, so a record built on one
cannot compute a tiered match. Keys, layer merge, precedence inversion, and the four entry
dispositions are in [reference/run-contract.md](reference/run-contract.md); the cross-consumer key
contract is this marketplace's separately published **finding-suppression** convention.

**Only the team layer enacts a suppression.** A personal entry for an id the team layer does not
carry is reported as `personal-only, not applied` rather than applied — absence from the team layer
is the team's *unsuppressed* state, so honoring a personal-only entry would hide a finding the team
never accepted. A suppression is a decision about the repository, so it belongs in the layer the
repository tracks; a personal layer drafts one for promotion.

Two report obligations. Every entry names its reason, its date, and **which cascade layer supplied
it**. And **only an exact match is silent** — a one-sided anchor change carries forward as
`needs-reconfirmation`, a deeper change closes the old entry and opens the new finding, and a
vanished finding must be accounted for as a fix, a successor, or an **unexplained disappearance that
fails the self-check**, the only detector the convergence property has.

## Self-check

<!-- fresh-eyes-exempt: deterministic-gate -- the tolerance comparison is set arithmetic over two runs' identity sets; its pass/fail IS the verdict and no judgment enters it -->
**Establish the precondition first.** If HEAD or the state digest moved between the **scan-baseline**
and **audit-endpoint** captures — or if two lanes recorded different content for a path they share — the
tree did not hold still and the gate reports **`indeterminate`**, never `passed`. A shared checkout
is the normal case, and an unfalsifiable pass manufactures confidence out of a basis nobody measured.

**The audit endpoint is taken before Phase 5, not after it.** Under `--fix`, Phase 5 edits project
files *by design*, so an endpoint captured after it necessarily differs from Phase 0 — which would
mark **every successful mutating run** `indeterminate` and skip P1–P3, the gate firing hardest on
runs that did exactly what was asked. What the precondition is about is whether the tree held still
*while the lanes were reading it*, and that window closes when the last lane completes. So the
capture bounds the read window, Phase 0 to end-of-lanes; Phase 5's writes fall outside the measured
interval rather than needing to be subtracted from it, which also avoids having to tell an accepted
mutation apart from a coincidental identical one.

A **third** capture is taken after Phase 5 and compared against the audit endpoint, for a different
purpose: it confirms the applied set matches the accepted set, so a `--fix` run that changed
something nobody approved is visible. That is a mutation-integrity check, reported separately from
the determinism one.

When it held, any derived-tier inequality is a defect, and judged-tier growth beyond the tolerance in
[reference/run-contract.md](reference/run-contract.md) **fails the self-check as an instability
finding against this skill**, naming the checks that moved — never absorbed by recalibration.

## Gotchas

- **A suppression naming a registered cluster copy is a hard error, not a warning.** The copy is
  excluded from the scan set, so an entry against it is stale by construction and the finding it
  claims to hold belongs to the canonical source. Refuse; name that source.
- **A whole-surface (`s:`) suppression survives every edit to the file and dies on a rename.** Not a
  bug: a finding about a file *as a whole* must not be retired by editing a line inside it.
- **A judged finding does not contribute to the determinism gate — the norm, not a weakness.** Every
  delegated check passes through model refinement first; the gate belongs to the derived tier.
- **Never propose an `@path` import as a context saving.** Splitting into imports "helps organization
  but doesn't reduce context, since imported files load at launch"
  ([memory](https://code.claude.com/docs/en/memory), verified 2026-07-24). A split remediation must
  name a load-deferring destination and price what it costs.

## What this skill does NOT do

- Never defines a check. Adding criteria here rather than to the owning plugin's catalog is the
  defect this skill's whole shape exists to avoid.
- Never reads another plugin's files. Cross-plugin cooperation is invocation only.
- Never edits managed policy or a user-scope file, in any mode.
- Never writes into its own scan set without `--report-to`, and never scans what it wrote.
