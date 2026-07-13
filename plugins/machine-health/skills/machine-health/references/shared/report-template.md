# Report template

The markdown report at `<OutputBase>/reports/health-<UTC-timestamp>.md` (one file per run, e.g. `health-2026-07-12T153327123Z.md`) is the primary human deliverable. Keep it scannable in the first screen and navigable for detail.

Placeholder tokens use `{{double-braces}}`. The orchestrator performs simple textual substitution — no templating engine required. Tokens resolving to structured content (tables, lists) are pre-rendered by the orchestrator and substituted as markdown fragments.

## Required token conventions

- `{{hostname}}`, `{{os}}`, `{{os_version}}` — from the run snapshot.
- `{{run_id}}` — ISO 8601 timestamp.
- `{{run_duration_seconds}}` — number, formatted as `"4m 07s"` or `"47s"` in the header.
- `{{elevated}}` — `"yes"` / `"no"` (or `"no — N admin-gated capabilities skipped"` when non-elevated).
- `{{elevation_coverage}}` — collapsed `<details>` block enumerating admin-gated features skipped this run, or `"Elevated run — full coverage."` when elevated.
- `{{severity_counts_oneline}}` — e.g., `"1 CRIT, 2 WARN, 0 INFO, 12 OK, 1 UNKNOWN"`.
- `{{delta_vs_prior_oneline}}` — e.g., `"WARN +1 (disk-space crossed 85%), OK -1"`.
- `{{at_a_glance_table}}` — pre-rendered markdown table.
- `{{crit_findings}}`, `{{warn_findings}}`, `{{info_findings}}` — pre-rendered finding sections (see below).
- `{{ok_checks_collapsed}}` — a `<details>`/`</details>` block listing OK checks with one-line summaries.
- `{{unknown_checks}}` — section if any UNKNOWN checks; otherwise replaced with empty string.
- `{{remediations_section}}` — markdown for remediations attempted this run.
- `{{discovery_section}}` — markdown listing new checks added to the catalog, with rationale.
- `{{open_questions}}` — pointer list to new `TODO.md` entries added this run.
- `{{appendix}}` — collapsed `<details>` blocks with full inventories (driver list, winget list, etc.).

## The template

```markdown
# Machine health — {{hostname}} — {{run_id_date}}

**Host:** `{{hostname}}` ({{os}} {{os_version}})
**Run:** {{run_id}} · {{run_duration_seconds}} · elevated: {{elevated}}
**Severity:** {{severity_counts_oneline}}
**Delta vs prior run:** {{delta_vs_prior_oneline}}

{{elevation_coverage}}

## At a glance

{{at_a_glance_table}}

## Findings

### CRIT

{{crit_findings}}

### WARN

{{warn_findings}}

### INFO

{{info_findings}}

### UNKNOWN

{{unknown_checks}}

<details>
<summary>OK checks ({{ok_count}})</summary>

{{ok_checks_collapsed}}

</details>

## Remediations

{{remediations_section}}

## Newly discovered checks

{{discovery_section}}

## Open questions for the operator

{{open_questions}}

## Appendix

{{appendix}}
```

## At-a-glance table format

One row per check. Trend arrow uses `↑` (worsening), `↓` (improving), `→` (steady), `·` (no prior data).

```markdown
| Category | Check | Severity | Summary | Trend |
|---|---|---|---|---|
| storage | disk-space | **WARN** | C: at 87% used (13% free) | ↑ +8pp |
| security | defender | OK | Signatures 1 day old, RTP on | → |
```

## Finding section format

Each finding within CRIT/WARN/INFO gets this structure:

```markdown
#### {{check.id}} — {{check.summary}}

**Severity:** {{check.severity}} {{trend_arrow}} {{trend_note}}

{{check.detail_rendered_as_prose_or_table}}

**Reproduce:**

```powershell
{{check.commands joined by newlines}}
```

**Suggested action:** {{human_authored_or_omitted}}

```

The **Suggested action** line is only rendered when the catalog entry or check script itself provides one. Skills should not manufacture actions; an empty action line encourages the human to investigate rather than rubber-stamp.

## Rendering conventions

- Use markdown **bold** for severity labels in tables; use level-4 headings (`####`) for per-finding blocks inside severity sections.
- Keep the first screen under 30 lines so header + at-a-glance table are visible without scrolling.
- Collapse any list longer than 10 rows into a `<details>` block with count in the summary.
- Prefer short reproduction snippets; if a command produces a lot of output, show only the command in the finding and include full output in the appendix.

## Empty sections

When a section has no content (e.g., no CRIT findings), replace with a single line:

```markdown
_No findings at this severity._
```

Do not omit the heading — missing heading breaks scannability across runs.
