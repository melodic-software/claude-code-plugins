# Persisting findings: this skill's read of the detector-findings contract

**Read the producer contract before the first write**:
<https://raw.githubusercontent.com/melodic-software/claude-code-plugins/main/docs/conventions/detector-findings/README.md>.
It owns the shape's authority, where the file goes, the producer-computed fields, the coexistence
obligations, the self-ignore guard, and what a minimal producer may omit. This file adds only what
an `audit-noise` run decides for itself and cites the contract for the rest. Where the two
disagree, the contract wins and this file is the defect.

**If the contract cannot be fetched, do not write.** Report that the destination and the guard
could not be resolved from their owner, and stop. Inventing a destination reports success while
the consumer never scans that path.

## This does not loosen the read-only contract

The skill body's read-only hard rule still holds, and it now states the distinction this file
depends on: **target mutation is forbidden unconditionally; artifact emission is not target
mutation.** No audited file becomes writable here. The findings file is a **proposal artifact** — a
NEW file in the gitignored memory tier that reaches `review:fanout`'s `fix` action, which is itself
human-gated. Persisting is opt-in behind `--persist-findings`; a bare invocation reports and stops.
Never describe the findings file to an operator as a change that has been made.

## Where the file goes

Resolve per the contract "Where the file goes": run the WHOLE rung order (never only its
documented default), take the non-interactive collapse for the rungs that confirm or ask, honor
the self-ignore guard including its invalid cases, and prove the destination is outside tracked
space before writing (the contract and its topic-docs binding own the proof; a destination that
cannot be proven is reported and not written to).

File name: `${TS}-audit-noise.md`, `TS="$(date -u +%Y%m%dT%H%M%SZ)"` (colon-free, Windows-safe).
Never overwrite: when the path exists, take `-2`, `-3`, the smallest free integer —
`emit-findings.sh` does this itself.

## The body-scope fence is not optional and not the caller's alone

`plugins/skill-quality/scripts/check-skill.sh:414` hard-FAILs a dropped `'trigger phrase'` versus
the base ref ("dropped trigger keyword(s) vs HEAD (auto-invocation regression)"). A remediation
that edits a `description`, a `when_to_use`, or a quoted trigger phrase is therefore a regression
this repo's own gate rejects — not a debatable suggestion. Two consequences bind every run:

- `detect.sh` never leaves YAML frontmatter, so no scanner row can point into one.
- Do **not** rely on that alone. `emit-findings.sh` recomputes the frontmatter fence over its input
  and additionally declines any body row quoting a trigger phrase that appears in the file's own
  `description` or `when_to_use`. A fence that lives only in the caller is one caller away from
  being bypassed.

A prohibition inside a `description` is a real observation and still belongs in the **human
report** — it is routed there, never to the relay.

## Compose by script, not by hand

Once the destination is resolved and the contract fetch succeeded, run
`${CLAUDE_SKILL_DIR}/scripts/emit-findings.sh --from <detect output file> --out <resolved path>`.
The script owns the mechanical half: the fence recomputation, cell assembly and escaping, tier
lookup (a mirror of the crosswalk — the crosswalk row is authoritative), rank ordering, the
non-overwrite suffix, and the `## Surfaces` counts. What stays with the model is everything before
the script (rung-order resolution, the fetch-and-refuse gate, the self-ignore guard) and everything
after it (reading the written file's head to confirm shape, and severity-vocabulary mapping when
the consuming project defines its own — edit the written file's `Tier` cells per the contract's
consumer-precedence rule).

## Which findings enter the file

**Only `negation`.** The scanner marks nine shapes; the other eight (`citation`, `ghost-ref`,
`preamble`, `enum-list`, `scope-meta`, `plan-reference`, `conversational-antecedent`,
`ticket-pr-residue`) have no severity-crosswalk row, and the contract admits no row whose tier
cannot be looked up from one. They stay in the human report and are counted in
`## Surfaces` as `reason=no-severity-crosswalk-row` — declined, never silently dropped. The count
is the one `audit_noise_detect_shapes_into` in `scripts/lib/noise-shapes.sh` actually appends, plus
`negation`; re-derive it there rather than trusting this sentence.

| Scanner shape | Rule id | Tier |
|---|---|---|
| `negation` | `docs-hygiene/audit-noise/rule-negation-without-positive` | IMPORTANT |

The scanner's own carve-outs (paired positive, hard guardrail, worked example) already ran at
classification time, so a carved-out candidate never reaches this file **and never reaches the
human report either** — one candidate, one disposition on every surface, which is what the
contract's "fall-through takes effect before the producer's FIRST output" requires of a producer
with more than one output surface.

The judgment lane's dismissal grounds still apply **before** persistence: a document *about* the
pattern, and a shape-definition or output-schema example matching its own pattern (SKILL.md
"Dismissal grounds"), are not findings. Drop those candidates from the scan output handed to
`--from` rather than emitting and retracting.

**Count what you drop.** Removing those rows before the writer sees them would make the exclusion
invisible in `## Surfaces`, which is precisely the silent decline this contract forbids. Pass the
number through: `--declined-carveout <n>`, which records it as its own counted line. Zero dropped →
omit the flag.

**Targets outside the repository never reach the relay.** `Location` is contractually
repo-relative and the fix action fences each remediation to it, so `emit-findings.sh` declines any
row whose path is not under the repo root and counts it as `reason=outside-repo-root`. Those
findings still belong in the **human report**.

## What each cell says

- **`branch:`** is `git branch --show-current` verbatim. With no branch resolvable the script
  refuses and writes nothing: the consumer admits a candidate only on an exact branch match, so a
  branch-less file is one the relay could never match.
- **`Location`** is `<repo-relative path>:<line>`; never the file alone.
- **`Surface(s)`** is `docs-hygiene:audit-noise`.
- **`Finding`** leads with the qualified rule id and the fired prohibition in the run's own values
  (`prohibition="do not"`), then the excerpt. No rubric reasoning.
- **`Action`** states the **rewrite to the positive target**. The remediation is never a deletion:
  the constraint survives and only its framing changes, so no `Action` cell may instruct removal of
  the instruction itself.
- **`Tier`** is LOOKED UP from the rule's crosswalk row (IMPORTANT), then mapped to the consuming
  project's severity vocabulary when it defines one. **`Confidence`** is `high` on every emitted
  row: a deterministic detector fired. Confidence is confidence-of-realness — the rule's repair
  needs authorial judgment, and that is said in the crosswalk's `Auto-applicable` cell and in the
  `Action` wording, never by downgrading `Confidence`.

## Surfaces, and when the file is written at all

`## Surfaces` names `docs-hygiene:audit-noise` once, states what was scanned, and carries the
declined counts per shape and reason. Omit `tier:`, `## By dimension`, and `## Unparsed`.

- Findings to emit → write.
- Files scanned, zero emittable findings → write anyway with the empty `## Findings` header:
  coverage is the payload.
- Nothing scanned (empty target set, everything excluded) → write nothing; say so in the report.

## Re-running

A re-run writes what it currently finds and never replays: never re-emit a previous file, never
copy rows forward. After the relay's `fix` disposes of a row, re-run the scan and emit a fresh file
so no stale findings file survives its own remediation.
