# Admit only present-text defects to the instruction-audit catalog; absence is a coverage question

- Status: accepted
- Date: 2026-08-08

## Context

Integrating Anthropic's Fable 5 prompting guide raised the same question at four of its fifteen
sections, and answered it four times by hand. The guide's sections split cleanly into two kinds:

- **Defect-shaped** — "instruction text resting on the premise that a turn is short", "instructions
  telling the model to echo its reasoning", "a delegation throttle grounded in unreliability". Each
  names something a surface *says* that current guidance contradicts. These became rows I8-d, I10,
  and I8's worked instance without argument.
- **Absence-shaped** — "ground progress claims against a tool result", "state the boundaries", "make
  self-verification explicit on long runs". Each names something a surface *should say*. None of them
  became a row, and each time the reasoning was reconstructed from scratch.

The next model guide will present the same split, and so will the one after it. A convention this
repository already holds — the catalog's own contract that every row owes "one decisive source line"
([`criteria.md`](../../plugins/claude-config/skills/audit-instructions/reference/criteria.md)) — does
not settle it, because an absence-shaped claim has a perfectly good source. It is the *observable*
that differs, not the provenance.

An independent audit of the grounding section argued the other side, and argued it well: absence is
not inherently undetectable. Fix a population (surfaces matching a "long-running loop" or
"agent reports to another agent" shape) and a pattern (grounding-shaped language), and a linter can
emit the finding. That is true, and it is why this record decides the question rather than asserting
the incumbent answer.

The counter-argument is what the two observables cost when they are wrong. A present-text row that
misfires reports one line the reader can dismiss by looking at it. An absence row that misfires
reports **every surface that does not contain the pattern** — and its false-positive set is the
entire population minus the hits, which is exactly backwards from the set a reader can audit. Worse,
its false *negatives* are invisible in the other direction: a surface that satisfies the obligation
in different words passes nothing and is reported as a gap.

The three real alternatives, and why each lost:

- **Admit absence rows into the same catalog.** Cheapest to write. It makes the report's meaning
  depend on which row emitted a finding — some findings point at a line, others at a file's silence —
  and a consumer cannot triage a report whose rows do not share an observable.
- **A second catalog for coverage.** Honest about the split, and it mints a second surface with a
  second version stream for a question no consumer has asked for yet, against this repository's own
  rule that a new surface must be defensible against the incumbent that nearly covers it.
- **Refuse the guidance entirely.** Wrong: the guidance is real, and this repository acts on it —
  through the `playbooks` doctrine a consumer installs and loads, which is an instruction surface
  rather than a detector.

## Decision

**The instruction-audit catalog admits a row only when its observable is anchored to text that is
present.** A row detects a passage a surface actually contains — either what it says, or an attribute
it lacks while saying it. An obligation that a surface *should say* something, anchored to no passage
at all, does not become a row, however well sourced.

**The line is the anchor, not the polarity of the sentence**, and getting that wrong would refuse two
shipped rows. I6 detects a prohibition carrying no rationale marker; I7 detects a request stating no
motivation. Both are worded as absences and both are admissible, because each names a line a reader
can point at and judges what is missing *from that line*. The refused shape has no such line: its
finding cites no passage, and its population is every file that lacks the pattern.

Absence-shaped guidance from a model guide routes one of two ways, and the audit records which:

1. **Into doctrine** — the `playbooks` per-model chapters and the `fable-5` skill, which a consumer
   installs and arms. That is the surface whose job is to state what a session should do.
2. **Into a mechanism** — a hook, gate, or CI check, where the obligation is enforceable rather than
   merely stated. A mechanism outranks an admonition, and this repository already prefers one
   wherever the shape allows.

**An audit that declines an absence row states the routing in the same breath**, so "no row" never
reads as "not covered". This is the same transparency the catalog already requires of a scoped row
reported `skipped-for-target`.

**This is a rule about the catalog, not a claim that absence is undetectable.** A coverage checker
over a fixed population and a fixed pattern remains a legitimate thing to build. It is a different
tool with a different report, and admitting its findings into a defect catalog is what this record
forbids — not building it.

## Consequences

Four dispositions that were argued individually now follow from one rule, and the fifth model guide
costs a lookup instead of a fresh argument. The corresponding loss is real: genuinely useful advice
stays out of the auditor's report, and a consumer who installs `audit-instructions` without
`playbooks` receives neither the row nor the doctrine. Naming the routing at decline time is what
keeps that visible rather than silent, and it is the whole of the mitigation — this record does not
oblige the two plugins to depend on each other.

The rule is a ceiling on the catalog, so it constrains future rows more than existing ones. Every row
through I23 satisfies it, **including the two whose Detect clauses are worded as absences** — the
anchor test above is what admits them, and an earlier draft of this record that tested polarity
instead would have refused both. The check is on admission, and a proposed row citing no passage at
all is refused on shape before its source is weighed.

An audit against a new model guide now has a cheap first pass: sort the guide's sections into
defect-shaped and absence-shaped before reading a single repository file, because only the first kind
can produce a row. The Fable 5 pass reached that split after the fact, which is why several sections
were read twice.
