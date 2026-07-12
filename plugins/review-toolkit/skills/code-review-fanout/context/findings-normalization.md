# Findings normalization — runtime pipeline

The 5-stage main-thread pipeline that turns heterogeneous free-text findings from every dispatched surface into one severity-ranked, deduplicated report.

**Why a pipeline:** the surfaces emit several free-text shapes on two independent axes (severity, confidence) and most populate only one. No surface returns clean structured output, so extraction is an LLM stage, and severity/confidence must be normalized across incomparable vocabularies before ranking. Runs on the main thread in every mode.

## Per-surface parse contracts (Stage-0 inputs)

| Surface | Native severity | Native confidence | Line basis |
|---|---|---|---|
| `code-reviewer` | CRITICAL / IMPORTANT / SUGGESTION | — | `file:line` (inferred) |
| `security-reviewer` | P1–P5 (CVSS); A04 tier-less | high / medium / low | `file:line` or `module` (inferred) |
| `architecture-guardian` | Violations / Risks / Opportunities | — | file-only (Violations); none (Risks/Opportunities) |
| `doc-drift-detector` | Stale / Missing / Aspirational | — | doc-file line (table) |
| slice-subagents | project's tiers (or baseline) | — | `file:line` (inferred) |
| `code-review` plugin | none (flat issue list) | 0–100, filters <80 | GitHub permalink `#L[s]-L[e]` |
| `pr-review-toolkit` orchestrator | Critical / Important / Suggestion | — | `[file:line]` (inferred) |

Line numbers from LLM reviewers drift — treat inferred lines as approximate and keep dedup noise-tolerant.

## Stage 0 — Extraction

Per-surface free-text → records `{surface, file, line, line_basis, category, native_severity, native_confidence, raw_text}`.

- **Line normalization** — permalink range → start line. `file:line` → as-is, `line_basis: inferred`. No-line findings → `line: null`, file-scoped bucket. Doc-drift lines → `space: doc` (never bucket against source lines).
- **Category normalization** — a small enum (`security`, `architecture`, `performance`, `testing`, `error-handling`, `concurrency`, `docs`, …; unmappable → `other`), NOT raw per-source strings (they false-split).
- **Parse-failure accounting** — record raw vs normalized counts per surface; preserve unparsable findings as raw text in the report's `## Unparsed` appendix. NEVER drop.

## Stage 1 — Severity crosswalk

Map native severity → the tier vocabulary in effect (the project's own, else `${CLAUDE_PLUGIN_ROOT}/context/severity.md`):

- security-reviewer: P1/P2 → CRITICAL; P3 → IMPORTANT; P4/P5 → SUGGESTION; A04/tier-less → SUGGESTION + `forward-flag: design-review`.
- code-reviewer, slice-subagents, pr-review-toolkit: identity mapping (Critical/Important-or-Warning/Suggestion).
- architecture-guardian: Violation → CRITICAL (broken rule today) or IMPORTANT (drift) by content; **Risk → SUGGESTION + `forward-flag: future` (NEVER a blocking tier)**; Opportunity → SUGGESTION.
- doc-drift: Stale → IMPORTANT; Missing/Aspirational → SUGGESTION.
- **Surfaces emitting no severity (e.g. the `code-review` plugin)** → DERIVE from content: bug/correctness → CRITICAL or IMPORTANT by impact; convention-adherence → IMPORTANT; ambiguous → IMPORTANT + `pending: human-tier`. A confidence filter having passed is confidence-of-realness, NOT severity — a high-confidence nitpick is still a nitpick.

## Stage 2 — Confidence enum

Per `${CLAUDE_PLUGIN_ROOT}/context/severity.md` "Confidence axis": plugin-filtered high scores → `high`; security-reviewer high/medium/low straight through; surfaces emitting none → `unscored`. **Absent confidence ≠ low.**

## Stage 3 — Dedup

Key = normalized file path + line-proximity bucket (±3 lines), NOT category. File-scoped findings (null `line`) bucket by path + category + a content-gist check — merge two line-less records only when their `raw_text` describes the same issue; path alone would collapse distinct architecture/doc findings in the same file. Doc-space never merges with source-space. **Minimize FALSE-MERGE over FALSE-SPLIT** — a false merge silently drops a real issue; a false split only adds noise. When in doubt, do NOT merge.

## Stage 4 — Agreement / rank

- **Cross-surface merge takes MAX severity + MAX confidence** — never a filtered value.
- **Agreement = positive presence only.** Count the surfaces that flagged the issue; a surface's ABSENCE carries no signal (it may have been confidence-filtered, not judged absent).
- **Rank:** (1) tier CRITICAL → IMPORTANT → SUGGESTION; (2) agreement count descending; (3) confidence `high` > `medium` > `unscored` > `low`. Render `pending: human-tier` and `forward-flag` markers visibly.
