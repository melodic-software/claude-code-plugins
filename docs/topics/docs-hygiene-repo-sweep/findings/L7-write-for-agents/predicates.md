# L7 predicates: `write-for-agents` doctrine as testable predicates

`docs-hygiene:write-for-agents` is authoring-time doctrine with no scan mode. This file is the
first step of the lane: every prescription the skill body makes, restated as something a file can
be tested against, and traced to the passage it comes from.

Source of every prescription: `plugins/docs-hygiene/skills/write-for-agents/SKILL.md` and its one
reference, `plugins/docs-hygiene/skills/write-for-agents/reference/agent-doc-surfaces.md`.

## How decidability was assigned

`docs/specs/d1-model-already-knows-measurement.md` measured a cue-based predicate over this exact
corpus (895 agent-facing files, 13,529 instruction sentences) and found a 94.1% false-positive
rate, with the verdict *"never rule on it"*. Its diagnosis generalizes: a predicate whose target
property is not readable off the text returns confident verdicts on an unfalsifiable question. That
record also names the two shapes that survived as genuinely text-decidable (D2 coercive emphasis,
D3 negation without a positive), which is the calibration used below.

So each predicate carries a decidability grade:

- **Decidable.** A cue plus a bounded read settles it. Findings are emitted.
- **Judgment.** A cue narrows the candidate set; the verdict needs the file read in context.
  Findings are emitted only after that read, and carry the reasoning.
- **Not auditable.** The property is not readable off the text (it is model-relative, or it
  depends on facts the doc does not carry). No findings are emitted. Named here so the omission is
  deliberate rather than an oversight.
- **Routed.** Text-decidable, but the doctrine itself or the sweep's lane split assigns it to
  another lane. No findings are emitted; the overlap is recorded in `README.md`.

## The predicates

| ID | Doctrine passage | Predicate | Decidability |
|---|---|---|---|
| P1 | Budget both loads, "an instruction earns its place with observed-stumble evidence, or it goes" | An instruction with no observed-stumble evidence behind it should not be present | Not auditable |
| P2 | Budget both loads, "When the two budgets conflict, say which one you spent and why" | A file that trades context load against maintainer cognitive load names which budget it spent | Not auditable |
| P3 | Write pointers, "Front-load the leading word" | A pointer opens with the term the reader matches on, not with a routing verb; `See X for deploys` fails, `Deploys: see X` passes | Decidable |
| P4 | Write pointers, "Cover the branches" | A pointer states both when to follow it and what the reader gets | Routed to L2 (the skill body itself delegates: "The full pointer-quality criteria are owned by the sibling audit skill") |
| P5 | Write pointers, third bullet, "A pointer that exists only because changes must be mirrored across distant folders can mask a cohesion problem" | A mirror-maintenance pointer (`keep in sync with`, `mirror`, `must match`) is a cohesion defect to restructure, not a pointer to add | Judgment |
| P6 | Separate steps from reference, "Put the procedure in one contiguous block; move lookup material below it or into a spoke file" | An ordered procedure is not interrupted by reference material (a lookup table, a long definition list) between its steps | Decidable |
| P7 | Separate steps from reference, "Distance a reader must jump during execution is a defect" | A step does not defer a fact it needs to a distant section (`see the table above`, `as described in the section below`) | Judgment |
| P8 | Separate steps from reference, "when a file serves several audiences or moments, split it along who-reads-when lines" | A file serves one audience-moment | Routed to L2 (mixed-concerns and tier-mismatch shapes) |
| P9 | Give every step a completion criterion, "State what done observably is, and demand it" | Every step in an ordered procedure carries an observable completion criterion | Judgment |
| P10 | Give every step a completion criterion, "Make the criterion the goal-state, never the attempt" | A completion criterion names a goal-state, not the act of attempting the step | Decidable |
| P11 | Give every step a completion criterion, "When finishing creates an obligation, state it in the step" | A step whose completion creates a downstream obligation states that obligation | Not auditable (requires knowing an obligation exists, which the text does not carry) |
| P12 | Give every step a completion criterion, "The agent does the legwork" | A step resolves its own facts from the environment rather than sending the human to look up something the agent could read | Judgment |
| P13 | Split by sequence, "When one doc serves two moments in time, split it at the moment boundary" | A doc covering two moments splits at the boundary | Routed to L2 (split-opportunity shapes) |
| P14 | Split by sequence, "follow the invocation-mode rubric ... rather than deciding it ad hoc" | A doc that rules on a skill's invocation mode cites `docs/conventions/invocation-mode/README.md` | Decidable |
| P15 | Prompt the positive, "Keep a negation only when the positive form genuinely loses the constraint, then pair it with the positive alternative in the same sentence" | A prohibition is paired with its positive alternative in the same sentence | Decidable, but routed to L5 (`audit-noise` shape 9 owns the same text; see `README.md`) |
| P16 | Prompt the positive, "pretrained leading words are the compact anchors that steer (Prefer X over Never do Y unless)" | A directive opens with a positive leading word where one is available | Decidable |
| P17 | After writing, first bullet, "Repeated the same prose in another file ... invoke `/docs-hygiene:extract-ssot`" | Prose is not repeated across files | Routed to L3 |
| P18 | After writing, second bullet, "never hand-write a glossary entry" | A doc does not hand-write a glossary; it routes term curation to `domain-driven-design:curate-language` | Decidable |
| P19 | After writing, third bullet, "invoke the fitting audit sibling rather than expanding this write into an audit" | The author routed incidental defects to the audit siblings | Not auditable (a property of the authoring session, not of the artifact) |
| P20 | Why this skill exists, "Write differently for an always-loaded surface than for an on-demand one", plus `reference/agent-doc-surfaces.md` | A file's density matches its load tier: a `T1`/`T2` surface carries no material that only matters on demand | Routed to L2 (tier-mismatch shape), except where the file misstates its own load semantics |
| P21 | `reference/agent-doc-surfaces.md`, "Load-semantics facts that change how you write" | A doc that asserts a harness load-semantics fact states it correctly (scope order, `@` import cost, `/compact` re-injection, MEMORY.md truncation, context is not enforcement) | Decidable |

P21 is not a separate prescription in the skill body; it is the reference's content turned into a
conformance test, because the reference exists precisely so that writers do not assert these facts
wrongly. It is kept separate from P20 so a factual error is not scored as a tiering judgment.

## Predicates this lane emits findings for

P3, P5, P6, P7, P9, P10, P12, P14, P16, P18, P21.

P1, P2, P11, P19 emit nothing by design. P4, P8, P13, P15, P17, P20 emit nothing because another
lane owns them; the overlaps are listed in `README.md` under `Cross-lane observations`.

## Severity scale

Severity is the predicate's cost multiplied by the file's load tier, since tier sets how often the
cost is paid.

| Severity | Meaning |
|---|---|
| `S1` | Predicate violated on a `T1` or `T2` surface, and the violation changes what the agent does |
| `S2` | Predicate violated on a `T2` surface without changing behavior, or on a `T3` surface in a way that changes behavior |
| `S3` | Predicate violated on a `T3` surface without changing behavior |

## Slice

997 rows carry `audience=AGENT` in `inventory/manifest.tsv` (3 `T1`, 250 `T2`, 744 `T3`). PLAN.md
states 994; the three-row difference is reported in `README.md`.
