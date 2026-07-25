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
delegated to the plugin that owns it. What it contributes is the run semantics the delegated skills
cannot supply individually, and which invoking them by hand yields none of: a three-scope inventory
taken before any check runs; an exclusion set derived at run time from the target's own registries
and git state; stable finding identity across runs, machines, and path separators; suppression memory
with staleness reporting; incremental persistence and resume; and one human gate for the pass instead
of one per delegated skill. The run contract — identity tuple, report location, state key,
concurrency, resumability, and the three finding tiers with their properties — is
[reference/run-contract.md](reference/run-contract.md).

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
  `/claude-config:audit-permission-grants`; the automation landscape →
  `/claude-config:audit-automation-gaps`. None is in this pass's surface set.

## Arguments

Parse `$ARGUMENTS`:

- **`target`** — path to the git repository to audit. Default: `${CLAUDE_PROJECT_DIR}` when set, else
  `git rev-parse --show-toplevel`. Never the current working directory — a run launched from a
  subdirectory must key and scan identically to one launched from the root.
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

## Phase 1 — Three-scope inventory, before any check

**Nothing is checked until all three scopes are inventoried.** A project-only inventory cannot see a
project-versus-user conflict, so a fix from one would be applied against half the picture.
Native-first: the filesystem walk produces a **candidate** set, never the answer. Prefer whatever the
target environment exposes — an `InstructionsLoaded` hook log, which enumerates exactly which
instruction files loaded and why; `/context` as ground truth for what actually loaded, since startup
scope depends on the launch directory and a walk that ignores it is wrong by construction; then
`/memory`, `/skills`, `/hooks`, `/mcp`, `/permissions`, `/status` for their respective surfaces, and
`claude --safe-mode` with a relocated `CLAUDE_CONFIG_DIR` for a clean-room comparison.

Record, per scope, every surface found **and every surface skipped with its reason**. The inventory
is a reported derived-tier artifact, so a surface that silently drops out of scope between two runs
fails the determinism property rather than looking like an improvement.

**Output styles are the case a walk alone cannot get right.** They modify the system prompt directly,
leave out the built-in software-engineering instructions unless `keep-coding-instructions: true`, and
a plugin's `force-for-plugin` "overrides the user's `outputStyle` setting" — so a walk plus settings
reports a selection as live when it is not
([output styles](https://code.claude.com/docs/en/output-styles), verified 2026-07-24). Report the
resolved live style and what resolved it.

**Shadowed definitions fall out of this inventory, not out of a catalog.** Skills, subagents, and MCP
servers override *by name*: where two share a name across scopes, exactly one is live. That is name
comparison across a fixed precedence order — deterministic, model-free, derived tier — reported at
`info` in its own section naming the live definition and the shadowed one. It is not a conflict
finding and is never merged into one.

## Phase 2 — Derive the exclusion set

**Derived at run time from the target's own state. Never transcribed, and no count of any class is
ever carried in this skill** — a count written down is wrong on the next commit and wrong in every
other repository. Four classes: registered byte-identical cluster copies (read from the target's own
shared-source registry, when it documents one — empty and reported as such when it does not);
vendored upstream materializations, by the `vendor/` layout rule; worktrees, from `git worktree list`
plus gitignore-awareness; and the pass's own artifacts, meaning the suppression record and any
previously redirected report. The derivation per class, its fallback on a failed read, and the hard
error when a suppression targets an excluded path are in
[reference/exclusion-set.md](reference/exclusion-set.md).

## Phase 3 — Lanes and dispatch

**A lane is (check × surface class)** — not per-check (which serializes a check across the tree and
makes an interruption expensive) and not per-file (which multiplies manifest overhead by the corpus).
Surface class is already the granularity the inventory and the exclusion set work at.

Dispatch, in inventory order, each invocation presence-gated with its fallback stated:

- **`/claude-config:audit-instructions`** — sibling in this plugin, always available. Carries the
  model-capability catalog over every non-memory surface, and the cross-layer conflict check.
- **`/claude-memory:audit`** — invoke when the `claude-memory` plugin is installed; it owns
  memory-layer hygiene and the within-memory-layer consistency check. Not installed: the pass reports
  both as **unchecked**, names that skill as their owner, and emits the one-line pointer to the
  official memory guidance — never a silent skip, never a re-implementation here.

Structural skill lint is deliberately **not** dispatched: it is a per-skill deterministic gate whose
fan-out over a large corpus would consume the dispatch budget reserved for instruction-content lanes,
and it answers shape rather than content. Route it out (`skill-quality:check` when installed).

Persist each lane's findings to the partial artifact **as that lane completes**, not buffered to the
end — a lane is complete when its terminating record is in the partial, so completion state is
derivable from the artifact rather than tracked beside it. Bound concurrency to 3–5 lanes, and
confirm with the user before the total dispatch count would exceed ~20; the delegated catalogs fan
out their own subagents inside each lane, and incremental persistence is precisely what degrades an
exceeded session ceiling into a resumed run rather than a lost one.

## Phase 4 — The `/doctor` handoff

`/doctor` owns the `CLAUDE.md` trim-and-migrate half, for which this pass deliberately builds no
replacement. **It is interactive, so it is never dispatched** — it proposes fixes only after the
operator confirms, so the pass emits an operator instruction and stops. Its output is the delegated
tier and carries no property. Its version floor, what its presence check verifies versus what it must
probe rather than assume, and its optional-capability absence classification are in
[reference/doctor-handoff.md](reference/doctor-handoff.md). When absent, name it as the missing
capability and state what goes unchecked.

## Phase 5 — Apply, only under `--fix`

Per-finding confirmation, project scope only, bounded by the table above. Refuse and name the
canonical source if a fix or a suppression would write into a derived-exclusion path.

The apply-verify step judges work this same run produced, so it is delegated: dispatch a
**fresh-context (non-fork) subagent** as the verifying worker, handed the applied diff and the
finding it claims to resolve — the artifact, not this run's reasoning. Prefer a cross-vendor advisor
when one is installed and set up (the OpenAI Codex plugin, say, invoked per its own docs), with that
fresh-context subagent as the stated fallback — never a route to a command that may not resolve.

## Phase 6 — Report

Two artifacts, because incremental persistence and a sectioned report want different shapes: an
append-only `findings.partial.jsonl` during the run, assembled into a single `findings.json` at the
end. Both schemas, the `mechanical` / `behavioral` / `suppressed` / `delegated` / `skipped` sections,
and the tier memberships are in [reference/run-contract.md](reference/run-contract.md). Tiers stay in
separate sections because their guarantees differ: exact equality, a tolerance, and none at all.

Every run emits, in **one line**: how many `OPINION`-tier checks were available, how many were not
run, and the exact argument that enables them (`--opinion`). Without it the tier ships unreachable.

## The suppression record

A deliberately-kept finding is recorded per `finding_id` at `.claude/audit-pass.md` in the target
repository, layered per the marketplace's config-cascade convention. Its keys, per-entry shape,
required reason and date, merge form, and policy-floor precedence inversion are owned by
[docs/conventions/finding-suppression](../../../../docs/conventions/finding-suppression/README.md).

Two obligations land in the report. The `suppressed` section names per entry its reason, its date,
and **which cascade layer supplied it** — a reader who cannot tell a team floor from a personal
addition cannot tell why the pass behaved as it did. And an entry whose `finding_id` matches no
current finding is reported as **stale**, never silently ignored: a suppression that has outlived its
finding is how a corpus quietly loses a check.

## Self-check

<!-- fresh-eyes-exempt: deterministic-gate -- the tolerance comparison is set arithmetic over two runs' identity sets; its pass/fail IS the verdict and no judgment enters it -->
Compare this run's derived-tier identity set against the previous run's for the same state key; any
inequality over an unchanged tree is a defect. Judged-tier growth beyond the tolerance in
[reference/run-contract.md](reference/run-contract.md) **fails the self-check and is reported as an
instability finding against this skill**, naming the checks that moved — never absorbed by recalibration.

## Gotchas

- **A suppression inside a registered cluster copy is a hard error, not a warning.** An inline marker
  there makes the copy differ from its siblings and breaks the sync path. Refuse; name the source.
- **`/doctor` cannot be driven** — it asks for confirmation before changing anything, and an
  unattended run cannot answer. Emit the operator instruction; never dispatch.
- **A judged finding does not contribute to the determinism gate — the norm, not a weakness.** Every
  delegated catalog check passes through model refinement before it is a finding. The gate belongs to
  the derived tier, which is where a silent scope regression would show up.
- **Never propose an `@path` import as a context saving.** Splitting into imports "helps organization
  but doesn't reduce context, since imported files load at launch"
  ([memory](https://code.claude.com/docs/en/memory), verified 2026-07-24). A split remediation must
  name a load-deferring destination and price what it costs.

## What this skill does NOT do

- Never defines a check. Adding criteria here instead of to the owning plugin's catalog is the defect
  this skill's whole shape exists to avoid.
- Never reads another plugin's files. Cross-plugin cooperation is invocation only — there is no
  shared criteria artifact and none is to be introduced.
- Never edits managed policy or a user-scope file, in any mode.
- Never writes into its own scan set without `--report-to`, and never scans what it wrote.
