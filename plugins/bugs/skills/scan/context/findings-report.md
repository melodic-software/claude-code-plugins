# Findings report format: `/bugs:scan`

Loaded on demand by `/bugs:scan` Step 5. Defines the emitted and persisted report: the run
metadata, per-finding fields, the refuted tail, the candidates not gated, the side observations, and
the cursor metadata block that the ladder's middle rung reads back.

## Run metadata

One paragraph under the title, before the first finding: mode, effort level, scope class, lens
count, the models the hunters and gates ran on, the file count, whether the hotspot ranking ran, the
cursor rung, and the candidate counts (raw, after triage, gated). A reader who sees only this
paragraph knows how narrow or wide the sample was.

## Frontmatter, and the one thing it must never declare

When persisting (never under `--dry-run`), prepend:

```markdown
---
type: bug-scan
date: <ISO-8601 UTC, e.g. 2026-08-23T09:15:00Z>
project-root: <absolute path of the scanned project root>
mode: targeted | lane | rotation
lane: <lane name, or the target expression for a targeted run>
---
```

**Never declare `type: review-findings` on this report, not now and not as an "also".** That frontmatter
alone is what routes a document into the detector-findings fix relay (`/review:fanout`), and a scan
report is intake for human judgment, not a machine-consumable detector artifact. `project-root` is
recorded because `<project-slug>` is only a basename: two checkouts sharing a basename share a
directory, and this line is how a reader tells them apart.

## Per-finding shape

One `##` section per verified finding. The five fields are `/bugs:write`'s. The canonical shape is in
[`${CLAUDE_PLUGIN_ROOT}/skills/write/context/template.md`](../../write/context/template.md) and the
severity rubric is the "Severity rubric" section of
[`${CLAUDE_PLUGIN_ROOT}/skills/write/SKILL.md`](../../write/SKILL.md); neither is restated here. Scan
adds three lines: the evidence label, the lens id, and the scope tag.

````markdown
## Finding <n>: <title, present tense, one line>

**Severity**: <low | medium | high | critical>
**Suggested fix location**: `<file path>` `<function or class>` (no patch)
**Evidence**: reproduced | verified-by-reading
**Lens**: <lens id, e.g. lens-2 boundary/edge-case>
**Scope**: in-lane | out-of-lane (via `<scoped path>`)

### Steps to reproduce

1. <the concrete path to the fault, traced from a real entry point>

### Expected behavior

<what should happen>

### Actual behavior

<what does happen>

### Severity justification

<one sentence: blast radius / blocking factor / data-integrity impact>

### Evidence

`<path>:<line>`

```<lang>
<verbatim quote of the offending source>
```

<the falsification routes the gate attempted, and why each failed>
````

Rules:

- A finding without a verbatim evidence quote does not go in the report. There is no "needs
  confirmation" tier for scan findings. The gate already decided.
- `reproduced` findings state the command that was run and what it showed. `verified-by-reading`
  findings state why no cheap check existed.
- No patch, no diff, no "change line X to Y". The fix location is a pointer; the fixer decides.

## Refuted candidates (retained tail)

Always present, even when empty. Its absence would read as "nothing was rejected".

```markdown
## Refuted candidates

| # | Candidate | Lens | Location | Refuting argument |
|---|---|---|---|---|
| 1 | <one-line symptom> | <lens id> | `<path>:<line>` | <the route that explained it away> |
```

When the gate refuted nothing, write `None — every candidate this run survived the gate.` When the
gate refuted everything, the report still ships: the refuted tail, the cursor block (rotation runs; a
targeted run uses its no-cursor line instead), and one line saying the lane produced no verified
findings.

## Candidates not gated (retained tail)

Always present, after the refuted tail. The candidates triage cut above the gate cap, with no
verdict: Step 3 of the next run over this lane seeds its triage from these rows instead of
re-deriving them, and a reader can tell a cut from a kill.

```markdown
## Candidates not gated

| # | Candidate | Lens | Scope | Location |
|---|---|---|---|---|
| 1 | <one-line symptom> | <lens id> | in-lane | `<path>:<line>` |
```

When nothing was cut, write `None.`

## Side observations

Always present, after the candidates not gated. The one-line observations that are not findings:
a candidate triage dropped as cosmetic, and anything a gate noted in passing while refuting or
confirming (a stale comment, a weaker sibling check, a missing floor). Cheap signal that would
otherwise vanish; each line names its source and a `path:line`.

```markdown
## Side observations

- <observation> (`<path>:<line>`, from <triage | gate on candidate n>)
```

When there are none, write `None.`

## Cursor metadata block

The last section of every persisted **rotation-mode** report, meaning a bare invocation or `--lane`,
the two modes that advance rotation. It is also rung 2 of the cursor ladder. Keep the key names and
the fenced-YAML shape stable: a later run parses this, not the prose. A key, once shipped, never
changes meaning; new keys are only ever added.

````markdown
## Scan cursor

```yaml
lane: <lane name>
lane-index: <0-based index in the resolved lane list>
lane-count: <number of lanes in the resolved list>
rung: tracker | report | date-floor
scanned-at: <ISO-8601 UTC>
scope-class: small | medium | large
scope-files: <count of files the hunters read>
scope-list: [<repo-relative paths the hunters read, in reading order>]
candidates: <count reaching the gate>
not-gated: <count in the candidates-not-gated tail>
verified: <count of findings in this report>
refuted: <count in the refuted tail>
out-of-lane: <count of findings and refuted candidates tagged out-of-lane>
lenses-skipped: [<lens ids skipped, with reason in prose above>]
```
````

`rung` records how *this* run chose its lane, so an operator can tell tracker-derived rotation from
the zero-state date floor. `scope-list` is what makes a lane pass reproducible: the next run on this
lane can read the same files, or deliberately sample their complement, instead of re-deriving a
subset from prose lane definitions. `--dry-run` writes no report and therefore no cursor block. That
is what "neither persists nor advances the cursor" means in practice.

**A targeted run omits this section entirely**, and says so in one line where it would have sat:

```markdown
*No scan cursor: targeted run, rotation not advanced.*
```

Its `lane`, `lane-index`, and `rung` keys have no rotation meaning, and a later run reading it as a
cursor would skip a lane. Rung 2 therefore searches backward for the newest report that *does* carry
this block, skipping targeted-run reports and `/bugs:write`'s reports, which share the
directory and never carry one, rather than trusting the newest file blindly.

## Stdout form

The same document minus the frontmatter, exactly as `/bugs:write` emits to stdout without
`--file`. When a report was also persisted, print its absolute path on the last line.

## Zero-findings form

A run that verified nothing still reports. The rotation only stays credible if empty passes are
visible. The rotation-run form:

```markdown
*No verified findings.*

**Lane**: <lane> (<n> files read, <n> candidates, all refuted)
**Cursor**: advanced to <next lane>
```

A targeted run drops that `**Cursor**` line, having advanced nothing, and keeps the `**Lane**` line
as the scope it hunted.

Followed by the refuted tail, the candidates not gated, the side observations, and the cursor block,
or, for a targeted run, the no-cursor line above. Do not pad an empty run with speculative
findings.
