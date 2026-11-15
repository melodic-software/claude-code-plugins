# Findings normalization, runtime pipeline

The 5-stage main-thread pipeline that turns heterogeneous free-text findings from every dispatched surface into one severity-ranked, deduplicated report, plus the proof stage (Stage 5) that runs when `reproduce_findings` is not `off`.

**Why a pipeline:** the surfaces emit several free-text shapes on two independent axes (severity, confidence) and most populate only one. No surface returns clean structured output, so extraction is an LLM stage, and severity/confidence must be normalized across incomparable vocabularies before ranking. Runs on the main thread in every mode.

## Per-surface parse contracts (Stage-0 inputs)

| Surface | Native severity | Native confidence | Line basis |
|---|---|---|---|
| `code-reviewer` | CRITICAL / IMPORTANT / SUGGESTION | high / medium / low (smells capped at medium, except a Duplicated Code finding naming the diverging change, which may be high) | `file:line` (inferred) |
| `security-reviewer` | P1–P5 (CVSS); A04 tier-less | high / medium / low | `file:line` or `module` (inferred) |
| `architecture-guardian` | Violations / Risks / Opportunities | high / medium / low | file-only (Violations); none (Risks/Opportunities) |
| `doc-drift-detector` | Stale / Missing / Aspirational | high / medium / low (table column) | doc-file line (table) |
| slice-subagents | project's tiers (or baseline) | high / medium / low (template column) | `file:line` (inferred) |
| `code-review` plugin | none (flat issue list) | none (validation subagents drop unconfirmed issues; → `high` in Stage 2) | GitHub permalink `#L[s]-L[e]` |
| `pr-review-toolkit` orchestrator | Critical / Important / Suggestion | none | `[file:line]` (inferred) |
| council member (`/review:council`) | CRITICAL / IMPORTANT / SUGGESTION (its brief's line format) | none | `path:line` (inferred) |

Line numbers from LLM reviewers drift. Treat inferred lines as approximate and keep dedup noise-tolerant.

**One row's raw text is not returned to the session:** `/review:fanout` dispatches the `code-review` plugin only in its `--comment` form, which ends by posting its findings to the PR, so the dispatch itself yields no parsable output. After an opted-in dispatch, fetch that comment and feed the body to Stage 0 as this surface's raw text, identified as the comment this invocation created, never by position.

Fanout's SKILL.md "Orchestrator plugins" takes the pre-dispatch comment-ID snapshot, because that is the step that runs before the dispatch. Splice the array it printed in here as a literal. A shell variable set in an earlier tool call is gone by the time this one runs:

```shell
gh pr view <n> --json comments |
  jq -r --argjson seen '<the recorded id array>' '[.comments[]
    | select(.id as $id | $seen | index($id) | not)
    | select(.body | startswith("### Code review"))
    | select(.body | contains("🤖 Generated with [Claude Code]"))]
    | if length == 1 then .[0].body else empty end'
```

Identity, not position or time. `.comments[-1]` is whatever landed most recently, with no filter at all. Any bot or reviewer commenting between the dispatch and this fetch is normalized as `code-review` findings and corrupts the persisted report. A timestamp cutoff narrows the window but still cannot say who wrote a comment inside it, so a third party quoting the `### Code review` heading mid-dispatch would win it. The ID-set difference answers the question actually being asked: which comment did not exist before this invocation.

Identity says a comment is new, not whose it is, so shape is the second filter. A third party quoting the review mid-dispatch posts a genuinely new comment carrying the heading, and when the dispatch itself posted nothing that quotation is the only new match, so a substring test would normalize it as this surface's findings. The plugin's command file mandates ("follow the following format precisely") a body that begins with the `### Code review` heading and carries the `🤖 Generated with [Claude Code]` trailer; a quotation fails both, because `> ### Code review` is not a `startswith`. Match the trailer by that prefix, never its full link. The URL is free to change upstream and would silently un-match. Author is deliberately not a third filter: the plugin posts via `gh pr comment` under whatever credential invoked it, so there is no fixed login to match and a hardcoded one would break for the next consumer.

The `length == 1` guard is the refusal to guess. Zero new heading-bearing comments means the dispatch produced none; two or more means the window is genuinely ambiguous. Both yield empty output. The row has no input, so the surface is not normalized and belongs in `## Surfaces` as a skip. Never widen the filter or fall back to the latest comment to fill it.

**Not in this table:** the bundled `/code-review` command and the managed Code Review GitHub App service (fanout's SKILL.md "Boundary, the bundled command and the managed service"), both distinct from the `code-review` plugin row above. The managed service posts its findings to the PR rather than returning them to normalize; bare `/code-review` is report-only, but is itself a multi-agent review of the same diff whose output has no documented schema to parse. Neither is dispatched as a fan-out leaf here.

## Stage 0: Extraction (`review:stage-normalizer`)

Per-surface free-text → records `{surface, file, line, line_basis, category, native_severity, native_confidence, raw_text}`.

- **Line normalization**: permalink range → start line. `file:line` → as-is, `line_basis: inferred`. No-line findings → `line: null`, file-scoped bucket. Doc-drift lines → `space: doc` (never bucket against source lines).
- **Category normalization**: a small enum (`security`, `architecture`, `performance`, `testing`, `error-handling`, `concurrency`, `docs`, …; unmappable → `other`), not raw per-source strings (they false-split).
- **Parse-failure accounting**: record raw vs normalized counts per surface; preserve unparsable findings as raw text in the report's `## Unparsed` appendix. Never drop.
- **Reviewer coverage**: judge a `code-reviewer` or `security-reviewer` report by its closing `Coverage:` line as [`reviewer-handback.md`](reviewer-handback.md) "Incomplete reply" says. Extract its findings, and when that section makes the report partial or no result, add one record for that surface saying so and naming what it did not reach, so the surface never merges as clean.

## Stage 1: Severity crosswalk (deterministic)

Map native severity → the tier vocabulary in effect (the project's own, else `<plugin-root>/context/severity.md`):

- security-reviewer: P1/P2 → CRITICAL; P3 → IMPORTANT; P4/P5 → SUGGESTION; A04/tier-less → SUGGESTION + `forward-flag: design-review`.
- code-reviewer, slice-subagents, pr-review-toolkit: identity mapping (Critical/Important-or-Warning/Suggestion).
- architecture-guardian: Violation → CRITICAL (broken rule today) or IMPORTANT (drift) by content; **Risk → SUGGESTION + `forward-flag: future` (never a blocking tier)**; Opportunity → SUGGESTION.
- doc-drift: Stale → IMPORTANT; Missing/Aspirational → SUGGESTION.
- **Surfaces emitting no severity** → derive from content: bug/correctness → CRITICAL or IMPORTANT by impact; convention-adherence → IMPORTANT; ambiguous → IMPORTANT + `pending: human-tier`. A confidence filter having passed is confidence-of-realness, not severity. A high-confidence nitpick is still a nitpick.

## Stage 2: Confidence enum (deterministic)

Per `<plugin-root>/context/severity.md` "Confidence axis": the `code-review` plugin's validated issues → `high`; a native high/medium/low label (every agent leaf per its output format; slice-subagents via the per-slice template's Confidence column) passes straight through; surfaces emitting none → `unscored`. **Absent confidence ≠ low.**

## Stage 3: Dedup (`review:stage-normalizer`)

Key = normalized file path + line-proximity bucket (±3 lines), not category. File-scoped findings (null `line`) bucket by path + category + a content-gist check: merge two line-less records only when their `raw_text` describes the same issue. Path alone would collapse distinct architecture/doc findings in the same file. Doc-space never merges with source-space. **Minimize false-merge over false-split.** A false merge silently drops a real issue; a false split only adds noise. When in doubt, do not merge.

## Stage 4: Agreement / rank (deterministic)

- **Cross-surface merge takes max severity + max confidence**, never a filtered value.
- **Agreement = positive presence only.** Count the surfaces that flagged the issue; a surface's absence carries no signal (it may have been confidence-filtered, not judged absent).
- **Rank:** (1) tier CRITICAL → IMPORTANT → SUGGESTION; (2) agreement count descending; (3) confidence, in the rank order [`context/severity.md`](../context/severity.md) "Confidence axis" owns. Render `pending: human-tier` and `forward-flag` markers visibly.
- **Two-axis presentation:** the merged ranked queue is the primary view; the report also regroups the same findings by review dimension (the Stage-0 category enum) under per-dimension headings. A merged rank can mask one dimension failing badly while the others pass.

## Stage 5: Proof (`reproduce_findings`)

The caller resolves `reproduce_findings` and `reproduce_findings_floor` ([`config.md`](config.md)) and whether the run is unattended before this stage. Under `off`, skip the stage: the report is unchanged. The rule for running reviewed code, its labels and the gate prompt are in [`run-reviewed-code.md`](run-reviewed-code.md), this plugin's copy of the marketplace contract; this stage applies them.

1. **Floor.** A merged row whose tier is at or above `reproduce_findings_floor` (CRITICAL above IMPORTANT above SUGGESTION) goes to the gate. Every row below it is labeled `not-attempted`. A floor that resolved to no tier ([`config.md`](config.md) `reproduce_findings_floor`) sends every row to the gate.
2. **Gate.** For each row at or above the floor, dispatch one `review:finding-prover` agent (Read, Grep and Glob only), one row per dispatch, never the surface that raised it. Its prompt is every block of [`run-reviewed-code.md`](run-reviewed-code.md) "The gate prompt", verbatim, then the row's tier, Location, Finding and Action and the diff hunk at its Location, all quoted as data (the gate holds no shell, so it cannot read a diff itself). Nothing else: no other row, no reviewer rationale beyond the row. A gate returning `VERDICT: refuted` labels the row `refuted`; `VERDICT: finding` labels it `verified-by-reading` and may carry a `proposed-check:`. A trailing line naming what the gate did not reach is allowed after either shape. A gate that errors, returns nothing or returns neither shape leaves the row `verified-by-reading` with Basis `gate returned no verdict`.
3. **Checks.** In an attended run, ask the person about each proposed check by [`run-reviewed-code.md`](run-reviewed-code.md) "Asking for a check", one question per command, and relabel the row by its outcome. `--yes`, an allow rule, auto mode or a setting never counts as the person's yes. In an unattended run, run no check: count the proposed checks and record each unrun.
4. **Labels in the report.** Write `## Evidence` after `## Surfaces`: one row per finding, `| Rank | Location | Label | Basis |`, where Basis is the approved command and what it showed, the refuting argument, the proposed check and why it did not run, or `below the <floor> floor`. Under it, one line: `Checks proposed: <n>; run: <n>` and, in an unattended run, `none run (unattended)`. The labels are `reproduced`, `verified-by-reading`, `refuted` and `not-attempted`; this stage never writes `unverified`.
5. **Demotion.** A demoted row stays in `## Findings` with its confidence set to `low` and is not acted on (in a fanout report its `Act on` cell reads `no`, and it is not counted against the cap). Each gets one line in the report's `## Dismissed` section, `- <rank>, <location>: <reason>`. In an unattended run the reason reads exactly `not reproduced: unattended run, nothing ran`; in an attended run it reads `not reproduced (<label>): <the Basis cell>`, the `## Evidence` row keeping the detail either way. A row the caller's CRITICAL check already demoted still gets one line, carrying both reasons: the check's reason, a semicolon, then the reason above.
6. **`label`** demotes every row labeled `refuted`. No other row's tier, confidence or place changes.
7. **`require`** demotes every row at or above the floor whose label is not `reproduced`, the `refuted` rows included. In an unattended run, the report's first line after the frontmatter, before `## Findings`, reads: `Nothing could be checked: this run was unattended, so no finding was reproduced (<n> checks proposed, none run). This is not a clean review.`

The gate is a judgment step that reads untrusted text, so it runs as `finding-prover`, never as a general-purpose subagent. The floor, the labels and the demotions are applied on the main thread.

## Axis assignment

After ranking, give each merged finding exactly one axis:

- `spec` when the finding says the change does not do what the intent paragraph (the calling skill's SKILL.md "Intent paragraph") says it is for, or does only part of it.
- `standards` for every other finding.
- `standards` for every finding when the intent paragraph reads `Intent: not stated`.

The axis comes from what the finding says about the change against the intent paragraph, never from its surface, category or tier: a security finding that a stated goal is missing is `spec`. The report lists the findings by axis under `## By axis`, spec first ([`findings-file-shape.md`](findings-file-shape.md) "Findings-file shape").

## Model assignment

Stages 0 and 3 are judgment steps and run as `review:stage-normalizer` agent calls: Stage 0 for parse fidelity, Stage 3 for semantic merge. They read untrusted reviewer output, so they run as `stage-normalizer`, which holds Read only, never as a general-purpose subagent. Stages 1, 2, and 4 are table lookups and a sort; apply them directly on the main thread, never through a model call. Stage 5's gate runs as `review:finding-prover` agent calls, one per row. Axis assignment runs on the main thread too: it compares each already-normalized finding with the intent paragraph the main thread wrote.
