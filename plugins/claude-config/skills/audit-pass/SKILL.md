---
description: "Run ONE coordinated, ordered, resumable pass over a named target repository: a three-scope inventory first (managed policy read-only, user scope routed as recommendations, project scope), then delegated checks lane by lane, findings persisted per lane so an interrupted run resumes instead of restarting, and one human gate for the whole pass instead of one per skill. Adds run semantics, not checks — every check belongs to the plugin that owns it and is invoked presence-gated. Read-only on bare invocation; edits only behind an explicit --fix override, and never to managed policy or user-scope files. Use when: 'audit pass', 'run one pass over this repo', 'coordinate the audit skills', 'audit this repo end to end', 'resume the audit', 'one reconciled findings report', 'sweep all three scopes', or before a release that needs a single diffable findings artifact."
argument-hint: "[target] [--fix] [--opinion] [--resume] [--report-to <path>]"
user-invocable: true
disable-model-invocation: false
disallowed-tools: Edit, NotebookEdit
metadata:
  workflow-stage: anytime
  summary: Run one coordinated, resumable audit pass over a repo with a single human gate
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

The frontmatter carries it mechanically too: `disallowed-tools: Edit, NotebookEdit` removes both
editing tools from the pool while this skill is active, so the report-only contract is a property of
the tool set, not of model obedience. `Write` is kept — run state and the report persist under
`${CLAUDE_PLUGIN_DATA}`.

**`scripts/run-state.sh` writes under that same plugin data directory and nowhere else** — never
inside a target repository. It takes the data directory as an argument rather than discovering one,
and validates both path segments it contributes: `lib/state-key.sh` refuses a remote URL that would
become traversing directory components, and a `--run-id` outside `[A-Za-z0-9][A-Za-z0-9_.-]*` is
refused here. The run-state writes were always sanctioned; what changed is that a script performs
them.

## Scope boundary (route out)

- **One instruction surface against the model-capability catalog** → `/claude-config:audit-instructions`
  directly. This pass dispatches that skill; it does not re-answer it.
- **Config-file correctness** → `/claude-config:audit`; grant portability →
  `/claude-config:audit-permission-grants`; automation landscape → `/claude-config:audit-automation-gaps`.
  None is in this pass's surface set.

## Arguments

Parse `$ARGUMENTS`:

- **`target`** — the git repository to audit. Default: the project root Claude Code resolved for this
  session; where no such root is available, `git rev-parse --show-toplevel`. Never the working
  directory — a run launched from a subdirectory must key and scan identically to one launched from
  the root.

  **Do not express this as a condition over `${CLAUDE_PROJECT_DIR}` "when set".** That placeholder is
  substituted inline in skill content before this file reaches you, so the literal token is never
  visible and the test is not yours to make — you would be deciding "is it set?" about a value that
  has already been resolved. Work from what you can observe: the resolved path, or a command you run.
  The sibling `audit-prompting-postures` states this same rule where it derives its report path, and
  the two skills contradicted each other on it until this was fixed.

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

  **The gate enforces both halves of that first sentence: the active project root, *and* a git
  repository.** A `target` that is not inside a git repository is refused the same way — non-zero,
  before Phase 0 does any work, naming the path and the reason, writing nothing.

  **Name the directory, not an empty string.** In the case this refusal is *for*, the default
  resolution above produces nothing: with no explicit `target` and no session-resolved project root,
  `git rev-parse --show-toplevel` fails outside a repository and there is no resolved root to report.
  So for the diagnostic only, fall back to the current directory and name **that** — a refusal that
  cannot say which path it refused is barely better than a silent one. The fallback is for the message;
  it never becomes a target.
  Requiring only "the active project root" let a non-git directory through into a contract with no
  branch for it, and the run then went quiet in five places rather than one:

  - the state key (§3) has a no-**remote** fallback and no no-**git** one, and "canonicalized repo
    root" is undefined without a repository;
  - the scan baseline is *the target's HEAD commit and the run's state digest*, and HEAD does not
    exist;
  - Class 3 exclusion derives worktrees from `git worktree list`, and unlike Class 1 it is given no
    fallback;
  - assertion 2.1 is stated over `git status --porcelain`, so the top read-only assertion is
    unevaluable;
  - and — the one that is a permanent capability loss rather than a missing derivation — **only the
    team layer enacts a suppression**, and the team layer is the *tracked* layer. With nothing
    tracked, no suppression is ever enactable on such a target, so an operator could accept a finding
    and have the acceptance silently fail to persist, forever.

  **The refusal says that cost out loud** rather than reading as an arbitrary restriction, and it names
  the suppression consequence in particular. Refusing closes a target class deliberately; it is not a
  side effect. The alternative — specifying all five branches — was considered and rejected, because
  the last of them obliges the contract to promise a capability it can never deliver on that class.
  A non-git directory is audited by opening it as a repository, or by the delegated skills directly.
- **`--fix`** — the explicit mutation override. Absent, the pass writes nothing into the target.
- **`--opinion`** — run the `OPINION`-tier checks the delegated catalogs declare default-off.
- **`--resume`** — resume the most recent incomplete run for this target's state key.
- **`--report-to <path>`** — redirect the report into the target tree. The destination is accepted only
  if it is an `audit-pass`-owned report or a new path that is **not a recognized instruction surface**;
  anything else is refused non-zero, naming the file. Refused on name rather than on existence,
  because `--report-to CLAUDE.md` against a repo that has none would *create* a live instruction
  surface out of a JSON report and then hide it from every later scan.

  **The self-exclusion obligation is not this flag's.** It belongs to the predicate
  `report_path ⊆ target_root`: **any** run whose resolved report path is contained in the target adds
  that path to its own exclusion set before writing — not only for later runs, or the two runs' derived
  sets could not be equal — and says so in its output. `--report-to` is one way containment arises. The
  **default** path is another, because `${CLAUDE_PLUGIN_DATA}` resolves under `~` and is inside any
  target at or above it. Full statement in
  [reference/report-location-and-schema.md](reference/report-location-and-schema.md) §2 and
  [reference/exclusion-set.md](reference/exclusion-set.md) Class 4.

## Phase 0 — Resolve, key, lock

Resolve the target root, compute the state key, and take the lock posture for the mode — read-only
runs take no lock and run concurrently; an applying run takes an exclusive advisory lock and refuses
rather than queues. All specified in
[reference/run-state-and-resumability.md](reference/run-state-and-resumability.md). With `--resume`,
read the lease, then read the partial's lane records and carry forward every lane whose input digest
is unchanged.

**Do not derive the run directory or hand-write the lease.** `scripts/run-state.sh` does both, which
is what makes this phase a mechanism rather than a description of one:

```bash
S="${CLAUDE_PLUGIN_ROOT}/skills/audit-pass/scripts/run-state.sh"
D="${CLAUDE_PLUGIN_DATA}"
bash "$S" paths --plugin-data "$D" --run-id "<run-id>"
bash "$S" lease acquire --run-dir "<run-dir>" --run-id "<run-id>" --plugin-data "$D"
```

`paths` derives `<plugin-data>/runs/<state-key>/<run-id>` through the plugin's own `lib/state-key.sh`
— the library whose header records the keying scheme as *this skill's*, and which until now three
other skills called and this one did not. Pass `--plugin-data` explicitly: `${CLAUDE_PLUGIN_DATA}`
substitutes in this text but is **not** exported to the Bash tool's environment, so a shell cannot
expand it. `acquire` takes it too, and refuses a `--run-dir` that is not under
`<plugin-data>/runs/` — it is the only command that *creates* a directory, so it is where the write
tree is pinned; a wrong or invented run dir would otherwise be created and written into.

**`--resume` never attaches to a run that is still going.** Concurrent read-only runs are safe
because each owns its own partial artifact; resume is the one operation that reaches into *another*
run's artifact, so the no-lock policy that makes concurrency safe is exactly what leaves resume
unable to tell a live run from an interrupted one. Both would then append lane attempts and
terminating records to one file, and highest-terminated-attempt assembly becomes race-dependent —
the interruption-tolerance mechanism producing a report neither run performed.

So every active run, read-only included, maintains a **lease**, and `--resume` reads it before it
reads the partial. `run-state.sh lease classify --run-dir <run-dir>` prints the verdict:
a **live** lease means the run is still going, and resume exits non-zero naming the run id rather
than attaching; a **stale** lease means the run was interrupted and its artifact is resumable; a
`released` tombstone is resumable immediately; `missing` means there is nothing to attach to. The
lease is not a lock — it excludes nothing, blocks no concurrent read-only run, and grants no
exclusivity; it answers the one question resume has to ask and previously could not.

Refresh it at every lane's persistence point (`lease heartbeat`) and write the tombstone on a clean
exit (`lease release`). The full specification — path, contents, the two-sided liveness window, and an
explicit statement of **which clauses the script enforces and which remain the run's own discipline**
— is in [reference/run-state-and-resumability.md](reference/run-state-and-resumability.md) §3. Read
that split before relying on any of it: the section specified a refresh interval and a staleness
threshold against no writer at all, which is the same shape as "on the same heartbeat the applying
lock uses" — a mechanism named rather than provided.

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
a custom one drops the built-in software-engineering instructions unless
`keep-coding-instructions: true`, and a
plugin's `force-for-plugin` "overrides the user's `outputStyle` setting" — so a walk plus settings
reports a selection as live when it is not ([output styles](https://code.claude.com/docs/en/output-styles),
verified 2026-08-04). Report the resolved live style and what resolved it.

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
  model-capability catalog over every non-memory surface, and the cross-surface conflict check. It
  takes a **surface-class scope**, so the per-class values yield **one lane per scope value
  dispatched**, each running that skill's per-surface catalog over that class. Its conflicts come
  back as **one finding carrying two sites**, never two linked findings — a contradiction is retired
  by fixing either side, so the sides are not independently correctable.

  **The conflict pass is dispatched exactly once, as its own lane, via that skill's `conflicts`
  scope — never once per surface class.** Its unit is a *pair*, and its Phase B2 reports a pair
  whenever **at least one** anchor falls in the requested scope, so a conflict spanning a skill body
  and an agent definition would be returned by the `skills` lane *and* the `agents` lane. Both would
  carry the same identity, and the partial-log contract assembles per lane with no cross-lane
  ownership rule, so the finding would land in the report twice. Its own scope makes every pair
  belong to exactly one lane by construction rather than needing a deduplication rule downstream —
  and the per-class lanes drop the pair check, since dispatching it there is what created the
  overlap.
- **`/claude-config:audit-permission-state`** — sibling in this plugin, always available. It owns the
  permission plane as it is *in effect*: the merged allow/ask/deny set with per-rule provenance,
  what auto mode drops on entry, configuration written where nothing reads it, and which managed
  intents are enforced versus loosenable. It takes an **action flag and no target**, so it is
  **exactly one lane** covering all of that.

  **Its managed-scope reads belong to the pass's read-only managed inventory, not to a project lane.**
  It reads managed policy on every OS and never writes anywhere, in any scope, under any flag — so it
  is safe to dispatch under the pass's bare invocation. Its `--oracle` path spawns a real session and
  is **never dispatched here**: the pass has no way to price that for the operator mid-run, and the
  flag exists to make the cost an explicit choice.

  **Its optional lanes degrade rather than fail.** The `autoMode` block lane needs `python3` and
  `claude` on PATH; absent either, that lane self-reports as skipped and the rest of the skill still
  runs. Carry that skip into the report as **unchecked with its reason**, exactly as an absent plugin
  would be — the distinction between "clean" and "not read" is this skill's whole contract and the
  pass must not collapse it.
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
its attempt id so an abandoned re-attempt is discardable rather than merely older. The write is one
call per record — `bash "$S" partial append --run-dir "<run-dir>" --record '<json-line>' --epoch
"<held>"` — and the lease is refreshed at the same boundary. A lease must exist, so a record resume
could not attribute to a live-or-abandoned run is never written. **Pass the epoch you hold**: the
filename is the writer's epoch, not whatever the lease now carries, which is what keeps a fenced
writer's rows out of its adopter's file. The script validates the record as a well-formed single-line
JSON object rather than sniffing its first character — a malformed row in an append-only artifact is
permanent, and resume is its only reader.

**The lane count is bounded by the delegated interfaces, not chosen here** — one per scope value the
instruction catalog accepts, plus one for the memory layer — so it is a handful, and a per-run
dispatch ceiling would never bind. What is *not* bounded here is the fan-out inside a lane: the
delegated catalogs spawn their own subagents, and this pass cannot reach inside one to cap it. So cap
concurrency at 3–5 lanes and let incremental persistence carry the rest — it is what degrades a blown
session ceiling into a resumed run.

**That mitigation now names something that exists.** "Let incremental persistence carry the rest" was
the load-bearing answer to the *one* cost dimension this passage declines to bound, and until
`run-state.sh` shipped the persistence it named was prose — so an intra-lane overrun, the failure
mode this paragraph is explicitly about, degraded into nothing resumable. The `partial append` call
above **bounds nothing**, and the disclaimer stands unchanged; what it buys is that an overrun costs
the lanes still running rather than the whole pass.

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
marked `open` — routed and not yet returned. The operator runs `/doctor` when they choose; a later
`--resume` closes that lane by re-prompt rather than re-scan, because nothing about it needs the
sweep to run again.

**`open` is an assembly terminator, not a completion.** The two are distinct and conflating them
would have made the promised resume impossible: §7 needs a terminating record to assemble a report at
all, while §5 skips any lane whose state is complete and whose digest is unchanged — so a lane that
was both terminated *and* complete would be carried forward untouched on every resume, and the
outstanding handoff would never close. So the record terminates the attempt for assembly and marks
the lane's state **incomplete**. `--resume` therefore re-runs it, which for a delegated lane means
re-prompting rather than re-scanning. `handed-back` and `declined` are completions; only `open` is
not.

**That instruction to the operator is only true if the terminating record is actually written.**
`--resume` reads the partial, not the report, so a report telling the operator to come back with
`--resume` against a partial nothing wrote is a false instruction in the one artifact they act on. So
the `open` terminator goes through `partial append` at the moment Phase 4 records the handoff — never
deferred to Phase 6 assembly, which is exactly where a run that does not reach Phase 6 loses it.

## Phase 5 — Apply, only under `--fix`

Per-finding confirmation, project scope only, bounded by the table above. Refuse and name the
canonical source if a fix or a suppression would write into a derived-exclusion path.

The apply-verify step judges work this same run produced, so it is delegated: hand the applied diff
and the finding it claims to resolve — the artifact, not this run's reasoning — to a cross-vendor
advisor when one is installed and set up (the OpenAI Codex plugin, say, invoked per its own docs),
with a **fresh-context (non-fork) subagent** as the stated fallback.

### When dispatch is unavailable

The apply-verify step and delegated lanes that mandate subagent dispatch **require** that dispatch.
When the Agent tool is blocked, unavailable, or the session cannot spawn subagents:

1. **Record per-lane verification mode** in the lane's terminating record and the assembled report (`verified` |
   `inline` | `skipped`) for every lane that mandates independent verification.
2. **Mark unverified findings.** Proposals or applied fixes that did not receive an independent
   verifier MUST carry an `(unverified)` marker and MUST NOT be presented as resolved.
3. **Do not silently complete.** The `skipped` section and report header MUST name dispatch
   unavailability when it prevented a mandated verification phase.

## Phase 6 — Report

Two artifacts, because incremental persistence and a sectioned report want different shapes: an
append-only `findings.partial.<owner_epoch>.jsonl` during the run, assembled into `findings.json` at
the end — epoch-scoped so a fenced writer cannot interleave into its adopter's file, with assembly
reading only the highest epoch present. Both schemas, the identity-versus-presentation field split,
and the sections are in
[reference/report-location-and-schema.md](reference/report-location-and-schema.md); the tier
memberships are in [reference/determinism-tiers.md](reference/determinism-tiers.md). Tiers stay in
separate sections because their guarantees differ. Every run also emits, in **one line**, how many `OPINION`-tier checks were
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
dispositions are in [reference/suppression.md](reference/suppression.md); the cross-consumer key
contract is this marketplace's separately published **finding-suppression** convention.

**Only the team layer enacts a suppression.** A personal entry for an id the team layer does not
carry is reported as `personal-only, not applied` rather than applied — absence from the team layer
is the team's *unsuppressed* state, so honoring a personal-only entry would hide a finding the team
never accepted. A suppression is a decision about the repository, so it belongs in the layer the
repository tracks; a personal layer drafts one for promotion.

Two report obligations. Every entry names its reason, its date, and **which cascade layer supplied
it**. And **only an exact match is silent** — a one-sided anchor change carries forward as
`needs-reconfirmation`, a deeper change closes the old entry and opens the new finding, and a
vanished finding must be accounted for as a fix, a successor, a **retirement with its check** when
the check that raised it is absent or renamed in this run's detection configuration, or an
**unexplained disappearance that fails the self-check** — the only detector the convergence property
has. Retirement is a reported disposition, not an exemption: it names the retiring check and the
version transition, because letting findings vanish silently on a catalog edit is the exact shape
this accounting exists to detect.

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
[reference/determinism-tiers.md](reference/determinism-tiers.md) **fails the self-check as an
instability finding against this skill**, naming the checks that moved — never absorbed by
recalibration.

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
  ([memory](https://code.claude.com/docs/en/memory), verified 2026-08-10). A split remediation must
  name a load-deferring destination and price what it costs.

## What this skill does NOT do

- Never defines a check. Adding criteria here rather than to the owning plugin's catalog is the
  defect this skill's whole shape exists to avoid.
- Never reads another plugin's files. Cross-plugin cooperation is invocation only.
- Never edits managed policy or a user-scope file, in any mode.
- Never scans what it wrote. Where its resolved report path is contained in the target — by
  `--report-to`, or by `${CLAUDE_PLUGIN_DATA}` resolving under `~` for a target at or above it — the
  path is excluded before the write and the containment is disclosed. Never silently.
- Never audits a target that is not a git repository. It refuses, and says what the refusal costs.
