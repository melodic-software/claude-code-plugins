# Persisting findings: this skill's read of the detector-findings contract

**Read the producer contract before the first write**:
<https://raw.githubusercontent.com/melodic-software/claude-code-plugins/main/docs/conventions/detector-findings/README.md>.
It owns the shape's authority, where the file goes, the producer-computed fields, the coexistence
obligations, the self-ignore guard, and what a minimal producer may omit. This file adds only what
an `audit-instructions` run decides for itself and cites the contract for the rest. Where the two
disagree, the contract wins and this file is the defect.

**If the contract cannot be fetched, do not write.** Report that the destination and the guard
could not be resolved from their owner, and stop. Inventing a destination reports success while
the consumer never scans that path.

## This does not loosen the read-only contract

The skill body's "Read-only contract" still holds: this skill proposes, the human applies. A
findings file is a **proposal artifact**, not an applied edit — it reaches `review:fanout`'s `fix`
action, which is itself human-gated. Persisting is therefore opt-in behind `--persist-findings`;
a bare invocation reports and stops, exactly as before. Never describe the findings file to an
operator as a change that has been made.

## Where the file goes

Resolve per the contract "Where the file goes": run the WHOLE rung order (never only its
documented default), take the non-interactive collapse for the rungs that confirm or ask, honor
the self-ignore guard including its invalid cases, and prove the destination is outside tracked
space before writing (the contract and its topic-docs binding own the proof; a destination that
cannot be proven is reported and not written to).

File name: `${TS}-audit-instructions.md`, `TS="$(date -u +%Y%m%dT%H%M%SZ)"` (colon-free,
Windows-safe). Never overwrite: when the path exists, take `-2`, `-3`, the smallest free integer —
`emit-findings.sh` does this itself.

## The body-scope fence is not optional and not the caller's alone

`plugins/skill-quality/scripts/check-skill.sh:414` hard-FAILs a dropped `'trigger phrase'` versus
the base ref ("dropped trigger keyword(s) vs HEAD (auto-invocation regression)"). A remediation
that edits a `description`, a `when_to_use`, or a quoted trigger phrase is therefore a regression
this repo's own gate rejects — not a debatable suggestion. Two consequences bind every run:

- Scan with `instruction-scan.sh --body-only` (I28) and `restatement-scan.py` (I29, body-scoped
  by construction). Concatenate both onto the `--from` stream.
- Do **not** rely on that alone. `emit-findings.sh` recomputes the fence over its input and
  additionally declines any body row quoting a trigger phrase that appears in the file's own
  `description`. A fence that lives only in the caller is one caller away from being bypassed.

A coercive phrase inside a `description` is a real observation and still belongs in the **human
report** — it is routed there, never to the relay.

## Compose by script, not by hand

Once the destination is resolved and the contract fetch succeeded, run
`${CLAUDE_SKILL_DIR}/scripts/emit-findings.sh --from <scan output file> --out <resolved path>`.
The script owns the mechanical half: the fence recomputation, cell assembly and escaping, tier
lookup (a mirror of the crosswalk — the crosswalk row is authoritative), rank ordering, the
non-overwrite suffix, and the `## Surfaces` counts. What stays with the model is everything before
the script (rung-order resolution, the fetch-and-refuse gate, the self-ignore guard) and everything
after it (reading the written file's head to confirm shape, and severity-vocabulary mapping when
the consuming project defines its own — edit the written file's `Tier` cells per the contract's
consumer-precedence rule).

## Which findings enter the file

**Only the I28 and I29 families.** `instruction-scan.sh` marks ten check families and
`restatement-scan.py` marks two more; the eight older families (I6, I8-a/b/c, I10, I23, I25, I27)
have no severity-crosswalk row, and the contract admits no row whose tier cannot be looked up
from one. They stay in the human report and are counted in `## Surfaces` as
`reason=no-severity-crosswalk-row` — declined, never silently dropped.

| Scanner family | Rule id | Tier |
|---|---|---|
| `I28-a` | `claude-config/audit-instructions/rule-coercive-emphasis` | IMPORTANT |
| `I28-b` | `claude-config/audit-instructions/rule-blanket-tool-default` | IMPORTANT |
| `I29-a` | `claude-config/audit-instructions/rule-description-restatement` | IMPORTANT |
| `I29-b` | `claude-config/audit-instructions/rule-sibling-restatement` | IMPORTANT |

The model lane's criteria carve-outs still apply **before** persistence: emphasis guarding a
destructive, security, or permission gate, a stated hard precondition, and a document *about* the
pattern are not findings (reference/criteria.md, I28). The scanner over-produces by design; drop
those candidates from the scan output handed to `--from` rather than emitting and retracting.

**Count what you drop.** Removing those rows before the writer sees them would make the exclusion
invisible in `## Surfaces`, which is precisely the silent decline this contract forbids — the
section would report fewer candidates examined than were actually looked at. Pass the number
through: `--declined-carveout <n>`, which records it as its own counted line. Zero dropped → omit
the flag.

**Surfaces outside the repository never reach the relay.** Phase A inventories user-level surfaces
under `${CLAUDE_CONFIG_DIR:-~/.claude}` as well as repo-owned ones, but `Location` is contractually
repo-relative and the fix action fences each remediation to it — an absolute path would have the
fix pass either edit a file outside the working tree or consume the finding without applying it.
`emit-findings.sh` declines any row whose path is not under the repo root and counts it as
`reason=outside-repo-root`. Those findings still belong in the **human report**; route them there,
and where the surface is upstream-owned, to its owning repository per the skill body's routing
rule.

A row whose path is not absolute is not one of them. `instruction-scan.sh` echoes the path it was
handed, so naming a repo-owned file relatively is the ordinary invocation; such a path is resolved
against the directory the scan is run from, which is the directory the writer reads the file from,
and then meets the same fence. A path holding a `..` segment is refused whatever its form: the
fence test is lexical, so a traversing path can prefix-match the root while resolving outside it.

## What each cell says

- **`branch:`** is `git branch --show-current` verbatim.
- **`Location`** is `<repo-relative path>:<line>`; never the file alone.
- **`Surface(s)`** is `claude-config:audit-instructions`.
- **`Finding`** leads with the qualified rule id and the fired marker in the run's own values
  (`marker="CRITICAL:"`, `phrase="if in doubt, use"`), then the excerpt. No rubric reasoning.
- **`Action`** states the **downgrade**: normal conditional phrasing for `rule-coercive-emphasis`,
  the targeted condition for `rule-blanket-tool-default`. **The remediation is never a deletion.**
  A finding that removes the instruction rather than its shouting is wrong, so no `Action` cell
  may instruct removal — the directive survives verbatim and only its volume changes. The single
  legitimate exception is **sentence-initial capitalization forced by dropping a leading wrapper**
  (`…MUST resolve` → `Resolve`), which the official source's own worked example also makes
  (`use` → `Use`). Any other wording change means the remediation overreached.
- **`Tier`** is LOOKED UP from the rule's crosswalk row, then mapped to the consuming project's
  severity vocabulary when it defines one. **`Confidence`** is `high` on every emitted row: a
  deterministic detector fired.

## Surfaces, and when the file is written at all

`## Surfaces` names `claude-config:audit-instructions` once, states what was scanned, and carries
the declined counts per family and reason. Omit `tier:`, `## By dimension`, and `## Unparsed`.

- Findings to emit → write.
- Files scanned, zero emittable findings → write anyway with the empty `## Findings` header:
  coverage is the payload.
- Nothing scanned (empty target set, everything excluded) → write nothing; say so in the report.

## Re-running

A re-run writes what it currently finds and never replays: never re-emit a previous file, never
copy rows forward. After the relay's `fix` applies a remediation, re-run the scan and emit a fresh
file so no stale findings file survives its own remediation.
