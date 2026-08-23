# Design resolution — bug-finding-skill

outcome: early-exit (Tier B — light design, resolved upstream)

Reason: the design-significant contracts were designed and adversarially validated upstream of
planning — a relentless `/planning:interview` (25 register rows), two `/planning:audit-answers`
rounds (four fresh-context validators, zero reclassified-to-human), and three verifier-PASSed
discovery artifacts. Re-running `/planning:design` would re-derive already-locked shapes. This is
prompt-ware (markdown skills + evals), not typed code; the "types" are the two file contracts below.

## Contract sketch 1 — tracked team config `.claude/bug-report.md`

Config-cascade-governed, three layers (user-global `~/.claude/bug-report.md` → project tracked →
`.local.` personal overlay), merge semantics declared beside the keys (codebase-health model —
concatenating lists with declared empty-list opt-out). Keys:

- `lanes` — list of named lane entries `{name, globs[]}` rotated by bare scan (concatenating merge)
- `filing_posture` — team policy for the explicit filing argument (e.g. `manual-only` | `allowed`)
- Partition rule: `output_dir` stays native userConfig only, never duplicated into this file.

## Contract sketch 2 — persisted findings report

Persisted per `write`'s plugin-data convention (`${CLAUDE_PLUGIN_DATA}/bug-reports/<project-slug>/`),
NEVER `type: review-findings` (that frontmatter would route it into the detector-findings fix relay).
Per finding: the 5 fields (title / steps to reproduce / expected vs actual / severity+justification /
suggested fix location) + `evidence: reproduced | verified-by-reading` + lens id. Report tail:
refuted-candidates section (retained, marked `refuted`, with the refuting argument) + cursor metadata
block (lane scanned, timestamp, findings count) — the middle rung of the stateless cursor ladder.

## Threads resolved elsewhere

Verifier shape, lens set, budget, cursor ladder, filing beats, fences: interview ledger
(`.work/bug-finding-skill/interview-checklist.md`) + Brief constraints. No open design threads.
