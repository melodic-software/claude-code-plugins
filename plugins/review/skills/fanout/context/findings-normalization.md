# Findings normalization — runtime pipeline

The 5-stage main-thread pipeline that turns heterogeneous free-text findings from every dispatched surface into one severity-ranked, deduplicated report.

**Why a pipeline:** the surfaces emit several free-text shapes on two independent axes (severity, confidence) and most populate only one. No surface returns clean structured output, so extraction is an LLM stage, and severity/confidence must be normalized across incomparable vocabularies before ranking. Runs on the main thread in every mode.

## Per-surface parse contracts (Stage-0 inputs)

| Surface | Native severity | Native confidence | Line basis |
|---|---|---|---|
| `code-reviewer` | CRITICAL / IMPORTANT / SUGGESTION | high / medium / low (smells capped at medium) | `file:line` (inferred) |
| `security-reviewer` | P1–P5 (CVSS); A04 tier-less | high / medium / low | `file:line` or `module` (inferred) |
| `architecture-guardian` | Violations / Risks / Opportunities | high / medium / low | file-only (Violations); none (Risks/Opportunities) |
| `doc-drift-detector` | Stale / Missing / Aspirational | high / medium / low (table column) | doc-file line (table) |
| slice-subagents | project's tiers (or baseline) | high / medium / low (template column) | `file:line` (inferred) |
| `code-review` plugin | none (flat issue list) | 0–100, filters <80 | GitHub permalink `#L[s]-L[e]` |
| `pr-review-toolkit` orchestrator | Critical / Important / Suggestion | — | `[file:line]` (inferred) |

Line numbers from LLM reviewers drift — treat inferred lines as approximate and keep dedup noise-tolerant.

**One row's raw text is not returned to the session:** the `code-review` plugin ends by posting its surviving findings as a PR comment, so the dispatch itself yields no parsable output. After an opted-in dispatch, fetch that comment and feed the body to Stage 0 as this surface's raw text — selected by the plugin's `### Code review` heading, never by position:

```shell
gh pr view <n> --json comments \
  --jq '[.comments[] | select(.body | contains("### Code review"))] | last | .body'
```

`.comments[-1]` is whatever landed most recently, with no heading, author, or timestamp filter — so any bot or reviewer that comments between the dispatch and this fetch is normalized as `code-review` findings and corrupts the persisted report. Note the newest heading match's `createdAt` BEFORE dispatching and require the selected comment to postdate it, so a leftover comment from an earlier run on the same PR is not read as this run's output.

No heading match, only a match predating the dispatch, or the retrieval skipped — the row has no input: the surface is not normalized and belongs in `## Surfaces` as a skip, never a fallback to the latest comment.

**Not in this table:** the bundled `/code-review` command and the managed Code Review GitHub App service (SKILL.md "Boundary — the bundled command and the managed service"), both distinct from the `code-review` plugin row above. The managed service posts its findings to the PR rather than returning them to normalize; bare `/code-review` is report-only, but is itself a multi-agent review of the same diff whose output has no documented schema to parse. Neither is dispatched as a fan-out leaf here.

## Stage 0 — Extraction (Sonnet)

Per-surface free-text → records `{surface, file, line, line_basis, category, native_severity, native_confidence, raw_text}`.

- **Line normalization** — permalink range → start line. `file:line` → as-is, `line_basis: inferred`. No-line findings → `line: null`, file-scoped bucket. Doc-drift lines → `space: doc` (never bucket against source lines).
- **Category normalization** — a small enum (`security`, `architecture`, `performance`, `testing`, `error-handling`, `concurrency`, `docs`, …; unmappable → `other`), NOT raw per-source strings (they false-split).
- **Parse-failure accounting** — record raw vs normalized counts per surface; preserve unparsable findings as raw text in the report's `## Unparsed` appendix. NEVER drop.

## Stage 1 — Severity crosswalk (deterministic / Haiku)

Map native severity → the tier vocabulary in effect (the project's own, else `${CLAUDE_PLUGIN_ROOT}/context/severity.md`):

- security-reviewer: P1/P2 → CRITICAL; P3 → IMPORTANT; P4/P5 → SUGGESTION; A04/tier-less → SUGGESTION + `forward-flag: design-review`.
- code-reviewer, slice-subagents, pr-review-toolkit: identity mapping (Critical/Important-or-Warning/Suggestion).
- architecture-guardian: Violation → CRITICAL (broken rule today) or IMPORTANT (drift) by content; **Risk → SUGGESTION + `forward-flag: future` (NEVER a blocking tier)**; Opportunity → SUGGESTION.
- doc-drift: Stale → IMPORTANT; Missing/Aspirational → SUGGESTION.
- **Surfaces emitting no severity** → DERIVE from content: bug/correctness → CRITICAL or IMPORTANT by impact; convention-adherence → IMPORTANT; ambiguous → IMPORTANT + `pending: human-tier`. A confidence filter having passed is confidence-of-realness, NOT severity — a high-confidence nitpick is still a nitpick.

## Stage 2 — Confidence enum (deterministic / Haiku)

Per `${CLAUDE_PLUGIN_ROOT}/context/severity.md` "Confidence axis": plugin-filtered high scores → `high`; a native high/medium/low label (all four agent leaves per their output formats; slice-subagents via the per-slice template's Confidence column) passes straight through; surfaces emitting none → `unscored`. **Absent confidence ≠ low.**

## Stage 3 — Dedup (Sonnet)

Key = normalized file path + line-proximity bucket (±3 lines), NOT category. File-scoped findings (null `line`) bucket by path + category + a content-gist check — merge two line-less records only when their `raw_text` describes the same issue; path alone would collapse distinct architecture/doc findings in the same file. Doc-space never merges with source-space. **Minimize FALSE-MERGE over FALSE-SPLIT** — a false merge silently drops a real issue; a false split only adds noise. When in doubt, do NOT merge.

## Stage 4 — Agreement / rank (deterministic)

- **Cross-surface merge takes MAX severity + MAX confidence** — never a filtered value.
- **Agreement = positive presence only.** Count the surfaces that flagged the issue; a surface's ABSENCE carries no signal (it may have been confidence-filtered, not judged absent).
- **Rank:** (1) tier CRITICAL → IMPORTANT → SUGGESTION; (2) agreement count descending; (3) confidence `high` > `medium` > `unscored` > `low`. Render `pending: human-tier` and `forward-flag` markers visibly.
- **Two-axis presentation:** the merged ranked queue is the primary view; the report ALSO regroups the same findings by review dimension (the Stage-0 category enum) under per-dimension headings — a merged rank can mask one dimension failing badly while the others pass.

## Model assignment

Stage 0 Sonnet (parse fidelity) · Stage 1–2 deterministic/Haiku (enum lookup) · Stage 3 Sonnet (semantic merge) · Stage 4 deterministic.
