# L2 progressive disclosure: `E-session-behavior`

145 files, 38 `T2`. Plugins: `adhd`, `autonomy`, `discipline`, `playbooks`, `session-flow`.

Totals: T1=9, T2=4, T3=1.

## Split lane

This group holds two of the three invocation-loaded bodies in the corpus that are at the line
ceiling with **zero spokes**.

### `oversize`: `plugins/session-flow/skills/find-handoff/SKILL.md` (Tier 2)

486 lines, 5,813 words, **zero spokes**. 97% of the line ceiling, 16% over the recommended body
size, and no hierarchy layer.

`plugins/session-flow/skills/find-handoff/SKILL.md:80`:

> `## The recovery ladder. Read-only throughout`

Lines **80 to 365, 286 lines, 59% of the file**. Three of its six rungs carry the mass:

| Rung | Lines | Span |
|---|---|---|
| `1. **Known-location glob first (no transcript needed).**` | 82 to 184 | 103 |
| `2. **Transcript scan. Bounded, recency-ranked, cross-repo.**` | 185 to 191 | 7 |
| `3. **Marker detection over candidate tails (grep, read-only).**` | 192 to 318 | 127 |
| `4. **Confirm before resuming. Hard gate.**` | 319 to 344 | 26 |
| `5. **Chain validation (file mode).**` | 345 to 357 | 13 |
| `6. **Hand off to the resume path.**` | 358 to 365 | 8 |

Rungs 1 and 3 are 230 lines between them and are attempted in order: a run that resolves at rung 1
never executes rung 3's grep machinery, and a run that reaches rung 3 has already discarded rung
1's glob rules. That is mutual exclusivity within a ladder, the case the tier model calls out as
"keeping the paths separate will reduce the token usage".

**Split spec.**

Create `plugins/session-flow/skills/find-handoff/reference/` and add:

- `reference/rung-1-known-location.md`, holding lines 83 to 184 (rung 1's body, not its numbered
  lead line), promoted to H1 `# Rung 1: known-location glob`.
- `reference/rung-3-marker-detection.md`, holding lines 193 to 318, promoted to H1
  `# Rung 3: marker detection over candidate tails`.

Both open with a `## Contents` list.

Replaces lines 82 to 318 in `SKILL.md` with the six-rung ladder reduced to its decision spine:

```markdown
1. **Known-location glob first (no transcript needed).** Resolve `<memory_dir>/handoffs/` for the
   current repo through the plugin binding
   ([`${CLAUDE_PLUGIN_ROOT}/reference/topic-docs.md`](${CLAUDE_PLUGIN_ROOT}/reference/topic-docs.md)),
   never the literal `.work`. Read
   [reference/rung-1-known-location.md](reference/rung-1-known-location.md) before globbing: it
   owns the fallback-root rule, the frontmatter filter, the ranking, and the short-circuit bar. A
   strong recent candidate ends the ladder here.
2. **Transcript scan. Bounded, recency-ranked, cross-repo.** Enumerate `~/.claude/projects/*/`
   only when rung 1 produced no candidate that clears the bar.
3. **Marker detection over candidate tails (grep, read-only).** Read
   [reference/rung-3-marker-detection.md](reference/rung-3-marker-detection.md) before scanning
   any tail: it owns the three marker forms, the rails-block reconstruction, the below-rail
   `/loop` re-arm capture, and the read-only bounds on the scan. Rung 1 never needs it.
```

Rungs 4 to 6 (lines 319 to 365) stay in the hub: they are the gate and handoff every path reaches.

Resulting `SKILL.md`: 486 - 237 + 20 = **269 lines**.

### `oversize` + `mixed-concerns`: `plugins/discipline/skills/sweep-all/SKILL.md` (Tier 2)

469 lines, 4,357 words, **zero spokes**.

`plugins/discipline/skills/sweep-all/SKILL.md:67`:

> `## Preflight: prove the fan-out can inherit (before step 1)`

Lines **67 to 212, 146 lines, 31% of the file**, and

`plugins/discipline/skills/sweep-all/SKILL.md:213`:

> `## The batched pass, a declared delta from the shared loop`

Lines **213 to 366, 154 lines, 33% of the file**. Together 64% of the body in two sections, in a
skill whose own line 21 declares two modes of which only one reaches them:

`plugins/discipline/skills/sweep-all/SKILL.md:23`:

> `1. **Session-start digest (cheap, default when nothing has happened yet).**`

The digest mode never executes the preflight or the batched pass. Full-batch mode executes both.
Two mutually exclusive modes with the expensive one's 300 lines resident in every invocation of
the cheap one.

**Split spec.**

Create `plugins/discipline/skills/sweep-all/reference/` and add:

- `reference/inheritance-preflight.md`, holding lines 68 to 212 (Stage 1, Stage 1b, Stage 2, the
  mint/verify pair, the degrade path, the next-actions block, and the "what is gated" note),
  promoted to H1 `# Preflight: proving the fan-out inherits`.
- `reference/batched-pass.md`, holding lines 214 to 366 (steps 1 to 5 of the batched pass),
  promoted to H1 `# The batched pass`.

Replaces lines 67 to 366 with:

```markdown
## Preflight: prove the fan-out can inherit (before step 1)

The batched pass is only meaningful if its subagents actually inherit this conversation, and its
step 4 writes their remedies to the working tree. Establish inheritance before dispatching, never
by assuming it. Read
[reference/inheritance-preflight.md](reference/inheritance-preflight.md) now, before the first
dispatch of a full batch pass: it owns the three stages, the canary, the fail-closed verify, and
the degrade path. Session-start digest mode never runs the preflight and never reads this file.

## The batched pass, a declared delta from the shared loop

Read [reference/batched-pass.md](reference/batched-pass.md) once the preflight has proved
inheritance: it owns the five steps, the per-member ledger contract, the root-cause dedup, the
rank-ordered single correction pass, and the consolidated report. Do not begin step 1 from the
preflight's output alone.
```

Resulting `SKILL.md`: 469 - 300 + 18 = **187 lines**.

### `oversize` + `mixed-concerns`: `plugins/autonomy/skills/setup/SKILL.md` (Tier 2)

494 lines, 4,527 words, 4 `context/` and 6 `templates/` spokes. 99% of the line ceiling.

The body is organized as named slices, and two of them carry 45% of the file:

| Section | Lines | Span |
|---|---|---|
| `## Guardrail slice` (line 208) | 208 to 303 | 96 |
| `## Routine slice` (line 304) | 304 to 431 | 128 |

Three sibling slices are already spoked (`context/capture-slice.md`,
`context/trigger-dispatch-slice.md`, `context/prerequisite-resolution-slice.md`), so the file
already establishes the destination convention and these two are the holdouts.

The slices are argument-selected and do not co-execute:
`plugins/autonomy/skills/setup/SKILL.md:210-211`:

> `Wires the enforced state of the [guardrail contract](${CLAUDE_PLUGIN_ROOT}/reference/guardrails.md):`
> `detect → bind → live-validate → fail-closed`

against `SKILL.md:306-307`:

> `Wires the standing-routine state of the`
> `[routine catalog](${CLAUDE_PLUGIN_ROOT}/reference/routines.md)`

**Split spec.**

- `plugins/autonomy/skills/setup/context/guardrail-slice.md`, holding lines 209 to 303, promoted
  to H1 `# Guardrail slice`. Naming matches the three existing `*-slice.md` spokes.
- `plugins/autonomy/skills/setup/context/routine-slice.md`, holding lines 305 to 431, promoted to
  H1 `# Routine slice`.

Replaces lines 208 to 431 with:

```markdown
## Guardrail slice

Wires the enforced state of the [guardrail contract](${CLAUDE_PLUGIN_ROOT}/reference/guardrails.md):
detect, bind, live-validate, fail-closed, always detect-diff-reconciling against the org's existing
guardrail surfaces. The [resolution section above](#guardrail-binding-resolution) owns how bound
policy resolves; this slice is the action that produces the binding it resolves. Read
[`context/guardrail-slice.md`](context/guardrail-slice.md) when `apply` reaches the guardrail
slice: it owns the per-layer wiring, the isolation-ladder probe, and the paid-SKU opt-in surface.

## Routine slice

Wires the standing-routine state of the
[routine catalog](${CLAUDE_PLUGIN_ROOT}/reference/routines.md): a routine is a scheduled
`temporal`-class signal adapter behind the governed queue, never a private execution or merge
path. Like the guardrail slice it prepares the security surface and never writes it. Read
[`context/routine-slice.md`](context/routine-slice.md) when `apply` reaches the routine slice: it
owns the discovery-first reconciliation against existing schedulers, the routine definitions
template, and the CI-cron handler shape.
```

Resulting `SKILL.md`: 494 - 224 + 22 = **292 lines**, and every slice in the file is then spoked
the same way.

### Not findings

`plugins/playbooks/skills/fable-5/SKILL.md` is 159 lines / 3,372 words with 12 `context/`
chapters, routed by a trigger table at line 133:

> `| Trigger, the first time you... | Read |`

Each row pairs a first-time trigger with a chapter file, and line 135 states where the chapters
live. That is the reference shape the rubric's pointer criteria describe, not a defect. The
`detect.sh` orphan report against all 12 chapters is a false positive of the script bug recorded
in `A-doc-quality.md`.

## Structure lane

### `missing-toc` (Tier 1)

| Path | Lines |
|---|---|
| `plugins/session-flow/reference/save-point.md` | 566 |
| `plugins/discipline/README.md` | 462 |
| `plugins/autonomy/reference/routines.md` | 448 |
| `plugins/session-flow/reference/structure.md` | 442 |
| `plugins/session-flow/README.md` | 437 |
| `plugins/playbooks/reference/model-adaptation/opus-5.md` | 355 |
| `plugins/playbooks/skills/boris/reference/autonomy.md` | 336 |
| `plugins/playbooks/skills/boris/reference/foundations.md` | 306 |
| `plugins/session-flow/skills/orchestrate/context/sources.md` | 306 |

`plugins/autonomy/reference/routines.md` is the sharpest: `skills/setup/SKILL.md:307` calls it
"the routine catalog" and sends a reader there to look up one routine, with no index at the
target.

Remediation, all nine: insert a `## Contents` anchor list under the H1, matching
`plugins/docs-hygiene/skills/audit-progressive-disclosure/context/tier-model.md:3-9`. For
`routines.md`, make the list enumerate the routines by name, since that is the lookup key.

### `deep-nesting` (Tier 2)

**`plugins/session-flow/skills/retro/context/session.md:184`**

```text
**Load the catalog.** Read `${CLAUDE_PLUGIN_ROOT}/skills/retro/reference/ecosystem-improvement-catalog.md`
```

`reference/ecosystem-improvement-catalog.md` (194 lines) is reached only from
`context/session.md`, which is itself a spoke: two hops from `SKILL.md`, and the wording ("Load
the catalog") makes it required reading rather than an alternate. An agent that reads
`SKILL.md` and jumps straight to the retro procedure never sees the instruction to load it.

Remediation: add a direct hub pointer in `plugins/session-flow/skills/retro/SKILL.md`, keeping
`context/session.md`'s call site:

```markdown
Read [`reference/ecosystem-improvement-catalog.md`](reference/ecosystem-improvement-catalog.md)
before classifying any improvement candidate: it owns the surface routing (project rule vs memory
vs skill vs hook) that the session flow's classification step assumes.
```

### `missing-toc`, 100 to 300 lines (Tier 3, awareness only)

45 files, the largest such band in the corpus. No treatment.

## Cross-lane observations

- `plugins/discipline/skills/sweep-all/SKILL.md:79-212` narrates the run the preflight was derived
  from ("Six of eight did in the run this preflight comes from"). That is provenance prose inside
  an instruction surface. L5 or L6.
- `plugins/session-flow/reference/save-point.md` and `plugins/session-flow/reference/structure.md`
  both define handoff frontmatter fields. L3.
