# L2 progressive disclosure: `C-vcs-repo`

93 files, 17 `T2`. Plugins: `disk-hygiene`, `github`, `repo-fleet-hygiene`, `repo-hygiene`,
`source-control`.

Totals: T1=11, T2=7, T3=1.

## Split lane

### `mixed-concerns` + `oversize`: `plugins/disk-hygiene/skills/clean/SKILL.md` (Tier 2)

499 lines, 4,848 words. At the 500-line ceiling with one `reference/` spoke.

`plugins/disk-hygiene/skills/clean/SKILL.md:332`:

> `### Unsupported-platform handoff (Windows, macOS)`

Lines **332 to 464, 133 lines, 27% of the file**. The section opens by declaring itself
mutually exclusive with everything above it:

`plugins/disk-hygiene/skills/clean/SKILL.md:334`:

```text
Preview reports `execution-platform-unsupported` as a per-candidate blocker on these platforms, so
the engine never deletes there.
```

The engine lane (steps 1 to 6, lines 131 to 331) and the manual handoff lane never co-execute: a
run is on a supported platform or it is not. This is the strongest split signal in the rubric,
Anthropic's mutual-exclusivity rule, and it fires even before the size does.

**Split spec.**

New spoke: `plugins/disk-hygiene/skills/clean/reference/unsupported-platform-handoff.md`

Moves: lines 333 to 464 verbatim (the section body, not its `###` heading), promoted to H1
`# Unsupported-platform handoff (Windows, macOS)` with the existing `**That belt outlives this
cleanup.**` block at line 449 kept as `## Hook registration outlives the cleanup`. Add a
`## Contents` list at the top.

Replaces lines 332 to 464 in `SKILL.md` with:

```markdown
### Unsupported-platform handoff (Windows, macOS)

Preview reports `execution-platform-unsupported` as a per-candidate blocker on Windows and macOS,
so the engine never deletes there and the default outcome is the report. When, and only when,
`--execute` was requested on one of those platforms and the human approved an exact single-tier
path list in this session, read
[reference/unsupported-platform-handoff.md](reference/unsupported-platform-handoff.md) and follow
it. It owns the `handoff-paths.json` shape, the per-path revalidation, and the hook belt that
outlives the cleanup. Do not improvise a manual deletion lane from the engine steps above.
```

Resulting `SKILL.md`: 499 - 133 + 12 = **378 lines**.

### `oversize`: `plugins/source-control/skills/babysit-loop/SKILL.md` (Tier 2)

499 lines, 5,713 words, 4 existing `reference/` spokes. At the line ceiling and 14% over the
recommended body size.

`plugins/source-control/skills/babysit-loop/SKILL.md:168`:

> `## Cycle shape`

Lines **168 to 294, 127 lines**, the largest block, and a per-cycle procedure rather than a fact.
Anthropic's kind-mismatch routing rule sends a grown procedure down a tier.

**Split spec.** New spoke: `plugins/source-control/skills/babysit-loop/reference/cycle-shape.md`
holding lines 169 to 294. The skill's spokes already use `reference/` for per-mechanic detail
(`reference/telemetry-upsert.md`, `reference/no-progress-detector.md`), so the destination and
naming match.

Replaces lines 168 to 294 with:

```markdown
## Cycle shape

Read [reference/cycle-shape.md](reference/cycle-shape.md) at the start of the first cycle and
again whenever the loop resumes after an interrupt: it owns the per-cycle step order, what each
step may mutate at the resolved autonomy tier, and where the escalation and no-progress checks
attach. The stop modes above decide whether a cycle runs; that file decides what one is.
```

Do **not** split `## Rate-limit guard floor (inlined)` at lines 402 to 441. `SKILL.md:404-408`
states it is inlined verbatim on purpose, byte-identical across lanes per the loop-lane
convention's inline-floor rule. Splitting it would break a stated invariant.

### `oversize`: `plugins/source-control/skills/babysit-prs/SKILL.md` (Tier 2)

429 lines, 4,932 words, 13 existing `reference/` spokes. Densest inline block:

`plugins/source-control/skills/babysit-prs/SKILL.md:149`:

> `## Guarded mutations: deterministic gates, agent judgment`

Lines **149 to 232, 84 lines**. A per-mutation gate catalog, read only when a mutation is about to
be attempted, sitting in a body that is already the largest spoke-carrying hub in the plugin.

**Split spec.** New spoke: `plugins/source-control/skills/babysit-prs/reference/guarded-mutations.md`
holding lines 150 to 232.

Replaces lines 149 to 232 with:

```markdown
## Guarded mutations: deterministic gates, agent judgment

Every mutation this skill may attempt is gated: a deterministic precondition the script checks,
then the agent judgment the tier permits. Read
[reference/guarded-mutations.md](reference/guarded-mutations.md) before attempting any mutation
whose gate you cannot name from the tier table above. It owns the per-mutation gate list, what
each gate reads, and the failure disposition when a gate cannot be evaluated.
```

### `oversize`: `plugins/source-control/skills/pull-request/SKILL.md` (Tier 2)

290 lines but **4,764 words**, 27% over the recommended 5k-token body. The word density, not the
line count, is what fires. Largest block: `## Full lifecycle (/source-control:pull-request full)`
at lines 192 to 235, 44 lines, which is a composition of the four phase spokes the hub already
points at (`reference/prep.md`, `create.md`, `monitor.md`, `merge.md`).

**Split spec.** New spoke: `plugins/source-control/skills/pull-request/reference/full-lifecycle.md`
holding lines 193 to 235. Replaces lines 192 to 235 with:

```markdown
## Full lifecycle (`/source-control:pull-request full`)

`full` chains prep, create, monitor, and merge in one invocation. Read
[reference/full-lifecycle.md](reference/full-lifecycle.md) when invoked with `full`, and only
then: it owns the phase-to-phase handoff state, the abort points, and what `full` does
differently from running the four phases by hand. Any other action routes through the phase table
above instead.
```

### `oversize`: `plugins/source-control/skills/worktree/SKILL.md` (Tier 2)

205 lines but **4,169 words**, 11% over the recommended body size, with 4 `context/` action
spokes already in place. The word mass sits in `## Repository context. Gather first` (lines 12 to
47) and `### The nesting invariant, verified` (58 to 83).

**Split spec.** New spoke: `plugins/source-control/skills/worktree/context/nesting-invariant.md`
holding lines 59 to 83. Replaces lines 58 to 83 with:

```markdown
### The nesting invariant, verified

A worktree is never created inside another worktree. Read
[context/nesting-invariant.md](context/nesting-invariant.md) when `create` is asked for from a
session already inside a worktree, or when `audit` reports a nested path: it owns the verification
procedure and what each failure mode means.
```

### `oversize`: `plugins/source-control/skills/setup/SKILL.md` (Tier 2)

343 lines, 3,384 words, one `reference/` spoke. Two same-named `### Babysit config` sections at
lines 118 to 211 (94 lines) and 249 to 289 (41 lines) split a single concern across the file.

**Split spec.** New spoke: `plugins/source-control/skills/setup/reference/babysit-config.md`
holding lines 119 to 211 and 250 to 289 merged under one H1, key-by-key. Both hub sites collapse
to a pointer:

```markdown
### Babysit config

Read [reference/babysit-config.md](reference/babysit-config.md) when `check` or `apply` touches a
`babysit.*` key: it owns every key, its default, its validation, and what `apply` writes. The
`check` and `apply` flows above name which keys they visit, not what the keys mean.
```

## Structure lane

### `missing-toc` (Tier 1)

| Path | Lines |
|---|---|
| `plugins/source-control/skills/babysit-prs/reference/orchestration.md` | 962 |
| `plugins/source-control/skills/babysit-prs/reference/safety.md` | 910 |
| `plugins/source-control/skills/babysit-prs/reference/loop.md` | 639 |
| `plugins/source-control/skills/pull-request/reference/create.md` | 616 |
| `plugins/disk-hygiene/skills/clean/reference/safety-model.md` | 481 |
| `plugins/source-control/skills/pull-request/reference/monitor.md` | 438 |
| `plugins/disk-hygiene/README.md` | 407 |
| `plugins/source-control/README.md` | 401 |
| `plugins/source-control/skills/setup/reference/apply-convention.md` | 394 |
| `plugins/source-control/reference/review-discipline.md` | 336 |
| `plugins/source-control/reference/config-resolution.md` | 331 |

The `babysit-prs` three are the sharpest case: `SKILL.md:411-419` sends the reader to
`orchestration.md` and `safety.md` for named sub-topics ("fan-out gate", "concurrency cap",
"leases", "the two gates", "stop-ask and never-do lists"), and neither file opens with a way to
reach a named sub-topic without reading 900 lines.

Remediation, all eleven: insert a `## Contents` anchor list under the H1, matching
`plugins/docs-hygiene/skills/audit-progressive-disclosure/context/tier-model.md:3-9`. For the two
files above 900 lines, make the list two levels deep (H2 and H3) so the named sub-topics the hub
cites are individually addressable.

### `blind-pointer`: `## References` with no load condition (Tier 2)

`plugins/source-control/skills/babysit-prs/SKILL.md:409`:

> `## References`

Eleven rows, each naming what the spoke holds, none naming when to open it. Row at line 423:

> `- [reference/worktrees.md](reference/worktrees.md), ephemeral worktree policy and prune commands.`

The sibling skill in the same plugin gets this right at
`plugins/source-control/skills/commit/SKILL.md:377` (`## Reference index. Load on demand`).

Remediation: rename line 409 to `## Reference index. Load on demand`, and give each row a
when-clause. For the sampled row:

```markdown
- [reference/worktrees.md](reference/worktrees.md). Read before creating or pruning an ephemeral
  worktree for a PR: the policy and the prune commands.
```

### `missing-toc`, 100 to 300 lines (Tier 3, awareness only)

29 files. No treatment.

## Cross-lane observations

- `plugins/source-control/skills/commit/.claude/source-control.md`,
  `commit/.claude/source-control.local.md`, and `pull-request/.claude/source-control.md` are
  sample config files bundled inside skill roots. They are not disclosure spokes and are correctly
  not reachable from either `SKILL.md`. Whether a skill should ship a `.claude/` tree at all is an
  L1 derivability question, not a disclosure one.
- `reference/orchestration.md` and `reference/safety.md` both describe the fan-out worker contract.
  L3.
