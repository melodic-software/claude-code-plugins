# L2 progressive disclosure: `D-work-planning`

109 files, 28 `T2`. Plugins: `implementation`, `planning`, `prototype`, `work-items`.

Totals: T1=4, T2=12, T3=1.

## Split lane

This group holds the two densest invocation-loaded bodies in the whole corpus by word count:
`plugins/planning/skills/interview/SKILL.md` (6,346 words) and
`plugins/planning/skills/plan/SKILL.md` (6,338 words), both roughly 27% over the recommended 5k
token body size while sitting under the line ceiling. Word density, not line count, is what fires
on both.

### `oversize` + `mixed-concerns`: `plugins/work-items/skills/setup/SKILL.md` (Tier 2)

498 lines, 6,153 words, 4 `reference/` spokes. At the line ceiling and 64% over the recommended
body size, the largest `T2` body in this group.

`plugins/work-items/skills/setup/SKILL.md:259`:

> `### Autonomous invocation (no interactive user)`

Lines **259 to 414, 156 lines, 31% of the file**, nested under `##`apply`(idempotent)` which is
itself only 27 lines. The section is explicitly a mutually-exclusive mode:

`plugins/work-items/skills/setup/SKILL.md:261-263`:

```text
When `apply` runs in an unattended or loop-driven context there is nobody to answer any of its
questions, and blocking on one strands the run.
```

An attended `apply` never executes this branch; an unattended one never executes the interactive
prompts above it. Mutual exclusivity is Anthropic's strongest split signal.

**Split spec.**

New spoke: `plugins/work-items/skills/setup/reference/autonomous-apply.md`

Moves: lines 260 to 414 verbatim, promoted to H1 `# Autonomous`apply`(no interactive user)`,
with a `## Contents` list at the top.

Replaces lines 259 to 414 with:

```markdown
### Autonomous invocation (no interactive user)

When `apply` runs unattended or loop-driven, nobody can answer its questions and blocking on one
strands the run. Read [reference/autonomous-apply.md](reference/autonomous-apply.md) before the
first decision point of an unattended `apply`, and follow it for every decision in the flow, not
only the seeding offer. It owns the silent-resolve rule, the defer-and-report rule, and what the
run must say in its report about each decision it took without asking.
```

Second split in the same file, `plugins/work-items/skills/setup/SKILL.md:122`:

```text
## `check` (read-only)
```

Lines 122 to 231, 110 lines. `check` and `apply` are separate actions in the same body and never
co-execute. Move lines 123 to 231 to
`plugins/work-items/skills/setup/reference/check.md` and replace with:

```markdown
## `check` (read-only)

`check` inspects and reports; it writes nothing. Read
[reference/check.md](reference/check.md) when invoked with `check` or with no action: it owns the
probe order, every PASS/FAIL/INFO row, and the remediation line each FAIL prints. `apply` below
consumes the same probe results but never re-derives them.
```

Resulting `SKILL.md`: 498 - 156 - 109 + 20 = **253 lines**.

### `oversize`: `plugins/work-items/skills/work-loop/SKILL.md` (Tier 2)

477 lines, 4,816 words, 4 `reference/` spokes. Two blocks dominate: `## Cycle shape` (lines 198 to
293, 96 lines) and `## Admission gate (work-class, fail-closed)` (lines 294 to 381, 88 lines).

`plugins/work-items/skills/work-loop/SKILL.md:294`:

> `## Admission gate (work-class, fail-closed)`

The section's own opening states its content is governing policy owned elsewhere and read on
demand when that plugin is installed:

`plugins/work-items/skills/work-loop/SKILL.md:296-299`:

```text
Class vocabulary and admission policy are governing policy owned by the `autonomy` plugin's
guardrail references (its `work-classes.md` and `admission-policy.md`), per the convention; when
```

**Split spec.** New spoke: `plugins/work-items/skills/work-loop/reference/admission-gate.md`
holding lines 295 to 381. Replaces lines 294 to 381 with:

```markdown
## Admission gate (work-class, fail-closed)

No item enters a cycle without clearing the admission gate, and the gate fails closed. Read
[reference/admission-gate.md](reference/admission-gate.md) before admitting the first item of a
run: it owns the binding dispositions, what they mean when the `autonomy` plugin is absent, and
the C3 first-drain ratification path. The class vocabulary itself stays owned by `autonomy`.
```

Do **not** split `## Rate-limit guard floor (inlined)` at lines 159 to 197. The convention's
inline-floor rule requires it byte-identical in the body.

### `oversize`: `plugins/planning/skills/interview/SKILL.md` (Tier 2)

302 lines, **6,346 words**, the densest invocation-loaded body in the corpus. 4 spokes already
exist.

### `tier-mismatch`: same file, a section its own spoke already owns (Tier 2)

`plugins/planning/skills/interview/SKILL.md:233`:

> `## Session-config recommendation (model, effort, advisor)`

Lines 233 to 274, 42 lines. The spoke `context/session-config.md` (143 lines) already opens by
declaring itself the reference layer for exactly this section:

`plugins/planning/skills/interview/context/session-config.md:3-4`:

```text
Reference detail for the `## Session-config recommendation (model, effort, advisor)`
section of `SKILL.md`.
```

and then restates the hub's own framing sentence back at it (`context/session-config.md:7-9`
against `SKILL.md:235-237`). The hub is carrying reference detail its spoke owns, and the spoke's
pointer appears only at the very end of the hub section, line 273.

**Remediation spec.** Cut lines 236 to 272 from `SKILL.md`. The section becomes:

```markdown
## Session-config recommendation (model, effort, advisor)

Turn the interview's read of complexity and ambiguity into a recommendation for how the session
carrying the work forward should be configured. *When* it lands follows from *what* it configures:
an engineering interview recommends at the stop/handoff boundary, for the downstream execution
session; a terminal interview (a general decision, per Step 5) recommends at the early
post-survey surface and again at the stop boundary, for the current session.

Read [`context/session-config.md`](context/session-config.md) at that boundary, before forming the
recommendation: it owns the model, effort, and advisor knob-picking signals and the per-surface
wording.
```

Resulting `SKILL.md`: 302 - 37 + 8 = **273 lines**, and the duplicated framing paragraph resolves
to one copy.

### `oversize` + `tier-mismatch`: `plugins/planning/skills/plan/SKILL.md` (Tier 2)

363 lines, **6,338 words**, 6 spokes including `context/plan-template.md` (355 lines).

`plugins/planning/skills/plan/SKILL.md:269`:

> `**PLAN.md anatomy.** PLAN holds Brief + Plan; per-phase status lives in the phase tags`

Lines **269 to 343, 75 lines**, are a fenced `markdown` skeleton plus its per-section commentary:
`## Brief`, `## Plan`, `### Phase 1`, `## Blast radius`, `## Stress-test summary`,
`## Execution shape`, `## Open questions`, `## Handoff to implementation`, `### User-approval
gates`, `### Execution shape`, `### Mechanical work`. That is template content, an on-demand
artifact shape, held in an invocation-loaded body at 27% over its recommended size, next to a
`context/plan-template.md` spoke that exists for template content.

**Split spec.** New spoke: `plugins/planning/skills/plan/templates/plan-md-anatomy.md` holding
lines 270 to 343, promoted to H1 `# PLAN.md anatomy`. Keep it separate from
`context/plan-template.md`: that file is the plan *body* template scaled by task size, this one is
the PLAN.md *file* skeleton with its status-tag grammar. Both are template content, neither is hub
content.

Replaces lines 269 to 343 with:

```markdown
**PLAN.md anatomy.** PLAN holds Brief + Plan; per-phase status lives in the phase tags (`[TODO]` /
`[DOING]` / `[DONE]`), never in a separate status block. Copy the skeleton from
[`templates/plan-md-anatomy.md`](templates/plan-md-anatomy.md) when writing the file at Step 4.7,
and again when a phase tag changes: it owns the section order, the tag grammar, and what each
section must contain for a cleared session to execute the plan from this file alone.
```

Resulting `SKILL.md`: 363 - 75 + 6 = **294 lines**.

### `oversize`: `plugins/work-items/skills/work/SKILL.md` (Tier 2)

264 lines, **5,058 words**, **zero spokes**. Over the recommended body size with no hierarchy
layer at all.

`plugins/work-items/skills/work/SKILL.md:214`:

> `### Step 5: Claim and execute`

Lines 214 to 261, 48 lines, the largest block, and the only one that runs after the human confirms.

**Split spec.** Create `plugins/work-items/skills/work/context/` and add:

- `context/claim-and-execute.md`, holding lines 215 to 261.
- `context/selection.md`, holding lines 105 to 179 (`## Selection Priority` plus Step 1 and Step 2),
  the candidate-finding and cross-referencing procedure that runs before any human contact.

Replaces lines 214 to 261 with:

```markdown
### Step 5: Claim and execute

Read [context/claim-and-execute.md](context/claim-and-execute.md) once the human has confirmed a
candidate at Step 3 and the staleness pre-check at Step 4 passed: it owns the claim marker, the
execution handoff, and what to do when the claim races another lane. Do not claim before Step 4
clears.
```

Replaces lines 104 to 179 with:

```markdown
## Selection Priority and candidate discovery

Read [context/selection.md](context/selection.md) at the start of every invocation, before any
tracker query: it owns the priority order, the candidate query, and the open-item cross-reference
that keeps two lanes off the same item. Steps 3 onward assume its output shape.
```

### `oversize`: `plugins/work-items/skills/triage/SKILL.md` (Tier 2)

198 lines, **4,070 words**, **zero spokes**. 9% over the recommended body size.

`plugins/work-items/skills/triage/SKILL.md:137`:

> `### 5. Apply outcome`

Lines 137 to 178, 42 lines, plus `## Needs-info template` at 179 to 193. Both are terminal-step
material read only after the interview concludes.

**Split spec.** New spoke: `plugins/work-items/skills/triage/context/apply-outcome.md` holding
lines 138 to 193 (step 5 and the needs-info template together, since the template is step 5's
output). Replaces lines 137 to 193 with:

```markdown
### 5. Apply outcome

Read [context/apply-outcome.md](context/apply-outcome.md) once the category and state are settled,
before writing anything to the tracker: it owns the per-state mutation, the comment bodies
including the needs-info template, and the AI disclaimer each written comment carries.
```

### `oversize`: `plugins/work-items/skills/attend-queue/SKILL.md` (Tier 2)

338 lines, 3,400 words, **zero spokes**.

`plugins/work-items/skills/attend-queue/SKILL.md:162`:

> `## Telemetry`

Lines **162 to 277, 116 lines, 34% of the file**, and the section itself says it is the same
inlined upsert the worker loop carries:

`plugins/work-items/skills/attend-queue/SKILL.md:167-168`:

> `Same inlined upsert as the worker loop, including the lane-instance resolution and validation`

The sibling lane already owns this as a spoke at
`plugins/work-items/skills/work-loop/reference/telemetry-upsert.md`.

**Split spec.** Move lines 163 to 277 to
`plugins/work-items/skills/attend-queue/reference/telemetry-upsert.md`. Do not merge with the
work-loop copy in this lane; the two-copy question is L3's, and this lane's job is only to get the
mass out of the invocation-loaded body. Replace lines 162 to 277 with:

```markdown
## Telemetry

This lane maintains exactly one sentinel-identified status comment per lane instance on its
per-lane tracking issue, edited in place each pass. Read
[reference/telemetry-upsert.md](reference/telemetry-upsert.md) before the first upsert of a run:
it owns the lane-instance resolution, the pre-write validation, the comment body rows, and the
guard-mode field.
```

Do **not** split `## Rate-limit guard floor (inlined)` at lines 278 to 319.

### `oversize`: `plugins/implementation/skills/implement-dispatch/SKILL.md` (Tier 2)

118 lines but **3,420 words**, roughly 29 words per line. Under the recommended body size, so no
treatment; recorded because the density is unusual enough that a future addition crosses the line
without the line count moving.

### `oversize`: `plugins/work-items/skills/decompose/SKILL.md` (Tier 2)

317 lines, 3,580 words, **zero spokes**.

`plugins/work-items/skills/decompose/SKILL.md:194`:

> `### Container lifecycle (spec-on-tracker). Opt-in`

Lines 194 to 260, 67 lines, declared opt-in by its own heading, so it never executes in a default
run. Plus `## Re-decompose (rerouting)` at 265 to 317, 53 lines, which runs only on a re-invocation
against an already-decomposed item. Neither co-executes with the default first-pass flow.

**Split spec.** Create `plugins/work-items/skills/decompose/context/` and add
`context/container-lifecycle.md` (lines 195 to 260) and `context/re-decompose.md` (lines 266 to
317). Replacements:

```markdown
### Container lifecycle (spec-on-tracker). Opt-in

Off by default. Read [context/container-lifecycle.md](context/container-lifecycle.md) only when
the consumer has opted into spec-on-tracker containers: it owns the container item shape, its
state transitions, and how child slices attach.
```

```markdown
## Re-decompose (rerouting)

Read [context/re-decompose.md](context/re-decompose.md) when the target item already carries
slices from a previous decomposition: it owns the reroute rules, what is preserved, and what is
retired. A first-pass decomposition never reaches it.
```

## Structure lane

### `orphan-spoke` (Tier 2)

**`plugins/implementation/skills/implement/context/gotchas.md`** (41 lines)

> `# Execution Phase Gotchas`
>
> `Build this file iteratively from real failure patterns encountered during implementation.`

Verified: the string `context/gotchas.md` appears nowhere in `plugins/implementation/**`. Its
three siblings are all cited from the mode table at `SKILL.md:43-45`
(`context/feature.md`, `context/bugfix.md`, `context/refactor.md`), so the omission is a gap in
one row's worth of wiring, not a missing convention. Meanwhile `SKILL.md:210` carries a
`## Gotchas` heading with its content inline, which is why the missing pointer has gone unnoticed:
the hub looks like it covers the topic.

`docs/topics/context-engineering-claude-5/design/article-sections.md:25` reached the same verdict
independently, calling it "dead within its skill, its `SKILL.md` has a `## Gotchas` heading but
never cites the file". Two measurements agree.

Three-way treatment, and **add the pointer** is right: the file is the accumulating failure record
the inline section cannot be, and the inline section is where new entries wrongly land. Replace
the body of `## Gotchas` at `plugins/implementation/skills/implement/SKILL.md:210` with:

```markdown
## Gotchas

Read [`context/gotchas.md`](context/gotchas.md) before the first execution step of a session, and
append to it whenever a run hits a failure pattern worth not repeating: it is the accumulating
record of what has actually gone wrong during execution and how to avoid it. Do not add entries
here; this section is the pointer, that file is the record.
```

Move any entry currently inline at lines 211 to 219 into `context/gotchas.md` under its
`## Initial entries` section, deduplicating against what is already there. That merge overlaps
L3; if L3 gets there first, keep the pointer above regardless, since the orphan is what this lane
owns.

### `missing-toc` (Tier 1)

| Path | Lines |
|---|---|
| `plugins/work-items/tools/work-item-tracker/CONTRACT.md` | 769 |
| `plugins/work-items/tools/work-item-tracker/adapters/github/README.md` | 422 |
| `plugins/planning/skills/plan/context/plan-template.md` | 355 |
| `plugins/planning/skills/interview/context/loop.md` | 315 |

`CONTRACT.md` is the sharpest: it is cited by verb name from several skills
(`plugins/work-items/skills/onboard-adapter/SKILL.md:205` calls it "the contract obeyed"), and a
reader arriving to check one verb has no index to reach it.

Remediation, all four: insert a `## Contents` anchor list under the H1, matching
`plugins/docs-hygiene/skills/audit-progressive-disclosure/context/tier-model.md:3-9`. For
`CONTRACT.md`, make the list enumerate the verbs, since that is the lookup key callers use.

### `blind-pointer` (Tier 2)

`plugins/planning/skills/interview/SKILL.md:277`:

```text
- `context/gotchas.md`. Failure patterns from real sessions
```

The row sits under `## What this skill does NOT do` (line 275), a heading that supplies the
opposite of a load condition. No when-clause, and the enclosing section makes the pointer read
like an exclusion rather than a reference.

Remediation: move the row out of that section into a new one at the end of the file:

```markdown
## Reference index. Load on demand

- [`context/gotchas.md`](context/gotchas.md). Read when a round is not converging or the stop
  condition keeps failing to trigger: failure patterns observed in real sessions and their
  recoveries.
- [`context/loop.md`](context/loop.md). Read before driving the frontier-rounds loop for the
  first time in a session: it owns the round mechanics Step 2 assumes.
- [`context/session-config.md`](context/session-config.md). Read at the stop/handoff boundary,
  per the section above.
```

`plugins/work-items/skills/onboard-adapter/SKILL.md:203`:

> `## Related`

Two rows (lines 205 and 206) naming what each target holds, neither naming when to read it.
Remediation: rename to `## Reference index. Load on demand` and add when-clauses.

### `missing-toc`, 100 to 300 lines (Tier 3, awareness only)

19 files. No treatment.

## Cross-lane observations

- `plugins/work-items/skills/attend-queue/SKILL.md:162-277` and
  `plugins/work-items/skills/work-loop/reference/telemetry-upsert.md` carry the same upsert
  procedure. The split above gets it out of the hub; whether the two copies collapse is L3.
- `plugins/planning/skills/interview/context/session-config.md:7-12` restates
  `SKILL.md:235-241` almost verbatim. L3.
