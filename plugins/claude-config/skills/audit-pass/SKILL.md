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

- **`target`** — path to the git repository to audit. Default: `${CLAUDE_PROJECT_DIR}` when set, else
  `git rev-parse --show-toplevel`. Never the working directory — a run launched from a subdirectory
  must key and scan identically to one launched from the root.
- **`--fix`** — the explicit mutation override. Absent, the pass writes nothing into the target.
- **`--opinion`** — run the `OPINION`-tier checks the delegated catalogs declare default-off.
- **`--resume`** — resume the most recent incomplete run for this target's state key.
- **`--report-to <path>`** — redirect the report into the target tree. Doing so **adds that path to
  the exclusion set** for subsequent runs, and the run says so in its output.

## Phase 0 — Resolve, key, lock

Resolve the target root, compute the state key, and take the lock posture for the mode — read-only
runs take no lock and run concurrently; an applying run takes an exclusive advisory lock and refuses
rather than queues. All specified in [reference/run-contract.md](reference/run-contract.md). With
`--resume`, read the run manifest and carry forward every lane whose input digest is unchanged.

**Capture the target's HEAD commit and dirty-file count here, and again at Phase 6.** They are the
determinism gate's precondition, and a run that never measures it cannot claim it held.

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

**A lane is (check × surface class)** — not per-check (which serializes a check across the tree and
makes an interruption expensive) and not per-file (which multiplies manifest overhead by the corpus).

Dispatch, in inventory order, each invocation presence-gated with its fallback stated:

- **`/claude-config:audit-instructions`** — sibling in this plugin, always available. Carries the
  model-capability catalog over every non-memory surface, and the cross-layer conflict check. Its
  conflicts come back as **one finding carrying two sites**, never two linked findings — a
  contradiction is retired by fixing either side, so the sides are not independently correctable.
- **`/claude-memory:audit`** — invoke when the `claude-memory` plugin is installed; it owns
  memory-layer hygiene and the within-memory-layer consistency check. Not installed: the pass reports
  both as **unchecked**, names that skill as their owner, and emits the one-line pointer to the
  official memory guidance — never a silent skip, never a re-implementation here.

Structural skill lint is deliberately **not** dispatched: it answers shape rather than content, and
its fan-out over a large corpus would consume the dispatch budget reserved for instruction-content
lanes. Route it out (`skill-quality:check` when installed).

Persist each lane's findings to the partial artifact **as that lane completes**, never buffered to
the end — a lane is complete when its terminating record is in the partial. Bound concurrency to 3–5
lanes and confirm before the total dispatch count would exceed ~20; the delegated catalogs fan out
their own subagents, and incremental persistence is what degrades a blown session ceiling into a
resumed run.

## Phase 4 — The `/doctor` handoff

`/doctor` owns the `CLAUDE.md` trim-and-migrate half, for which this pass deliberately builds no
replacement. **It is interactive, so it is never dispatched** — it proposes fixes only after the
operator confirms, so the pass emits an operator instruction and stops. Its version floor, what its
presence check verifies versus what it must probe rather than assume, and its optional-capability
absence classification are in [reference/doctor-handoff.md](reference/doctor-handoff.md). When
absent, name it as the missing capability and state what goes unchecked.

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
per the config-cascade convention. An entry stores the finding's **constituents** — `check`, `claim`,
every `(surface, anchor)` site — under the `finding_id` derived from them, never a bare id: an id is
a one-way hash, so a record built on one cannot compute a tiered match. Keys, layer merge, precedence
inversion, and the four entry dispositions are in
[reference/run-contract.md](reference/run-contract.md); the cross-consumer key contract is this
marketplace's separately published **finding-suppression** convention.

Two report obligations. Every entry names its reason, its date, and **which cascade layer supplied
it**. And **only an exact match is silent** — a one-sided anchor change carries forward as
`needs-reconfirmation`, a deeper change closes the old entry and opens the new finding, and a
vanished finding must be accounted for as a fix, a successor, or an **unexplained disappearance that
fails the self-check**, the only detector the convergence property has.

## Self-check

<!-- fresh-eyes-exempt: deterministic-gate -- the tolerance comparison is set arithmetic over two runs' identity sets; its pass/fail IS the verdict and no judgment enters it -->
**Establish the precondition first.** If HEAD or the dirty-file count moved between the Phase 0 and
Phase 6 captures, the tree did not hold still and the gate reports **`indeterminate`** — never
`passed`. A shared checkout is the normal case, and an unfalsifiable pass manufactures confidence out
of a basis nobody measured.

When it held, any derived-tier inequality is a defect, and judged-tier growth beyond the tolerance in
[reference/run-contract.md](reference/run-contract.md) **fails the self-check as an instability
finding against this skill**, naming the checks that moved — never absorbed by recalibration.

## Gotchas

- **A suppression inside a registered cluster copy is a hard error, not a warning.** An inline marker
  there makes the copy differ from its siblings and breaks the sync path. Refuse; name the source.
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
