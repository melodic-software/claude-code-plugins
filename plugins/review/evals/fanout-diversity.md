# Fanout reviewer-diversity eval

These cases measure whether `/review:fanout run-everything` finds one planted defect under four
reviewer arms. The parent plan runs 12 diffs, 4 arms and 3 runs to settle the lens default, panel
placement and the act-on cap. This file is the shape every slice of that eval follows.

## Arms

| Arm | `fanout_diversity` | Codex | `plugins` in `case.yaml` |
|---|---|---|---|
| `l` (L) | `lens` | left out | `["../.."]` |
| `m` (M) | `model` | left out | `["../..", "../../../multi-agent"]` |
| `mx` (M+X) | `model` | runs | `["../..", "../../../multi-agent"]` |
| `lx` (L+X) | `lens` | runs | `["../.."]` |

- Each arm's `scaffold.sh` commits `docs/conventions/review.yaml` with the arm's
  `fanout_diversity` on `main`, before the branch. The reviewed diff never edits it, so the skill
  reads the repository layer and reports `fanout_diversity: <value> (docs/conventions/review.yaml)`.
- The M arms load `multi-agent` so `/multi-agent:route` gives the role map that `model` spreads
  the review over. With fewer than two distinct tiers the sweep runs `lens`, and the arm check
  fails. Run every arm with the same `--model`, one whose role map resolves two or more distinct
  fan-out tiers.
- The X arms cannot pass as committed. A `claude plugin eval` run loads only the plugins in its
  `plugins` list and gets a temporary home and a withheld environment, so an installed `codex`
  plugin (`codex@openai-codex`) and its login are absent
  ([How runs are isolated](https://code.claude.com/docs/en/plugin-evals#how-runs-are-isolated)).
  The host run has to add the Codex plugin's directory to the X cases' `plugins` and make its
  login reachable. Without that, Codex reports a skip and the arm check marks the run invalid.

## Case directory

One directory per fixture and arm, `plugins/review/evals/fanout-diversity-<fixture>-<arm>/`,
because a case carries one prompt, one plugins list and one committed `review.yaml`:

- `case.yaml`: `schema_version: "1.1"`, `name`, the arm's `plugins`, and
  `context.scaffold_script: scaffold.sh`.
- `prompt.md`: frontmatter with `runs: 3`, then the arm's prompt.
- `scaffold.sh`: the fixture's repository, with the arm's `review.yaml` committed on `main`.
- `graders/arm-check.md`, `graders/recall.md` and `graders/false-positive.md`.
- `samples/<grader>.json` for each grader, with at least one `pass` and one `fail` entry, each an
  `answer` and a `why`. Calibration `build` skips a grader that judges a file, so the `recall`
  and `false-positive` samples record intent for a reader, not a calibration run.

| Fixture | Reuses the scaffold of |
|---|---|
| `null-user` | `guard-removal-null-user` |
| `empty-ratings` | `guard-removal-empty-ratings` |
| `short-title` | `guard-removal-short-title` |
| `search-sqli` | `qg-security-search-sqli` |
| `stock-race` | none: a race on shared state |
| `csv-handle-leak` | none: a resource leak on an error path |
| `price-cents` | none: a caller left on an old contract |
| `vacuous-slug-test` | none: a test that cannot fail |

## Prompt

Every arm's prompt body is one line: `/review:fanout run-everything No pull request is open for
this branch yet.`, then the Codex sentence, then `After the report is persisted, copy it byte for
byte to .work/eval/findings.md, then end your reply with the report's fanout_diversity: line and
its ## Surfaces section.` (with code spans around the path, the line name and the heading).

- Codex sentence for `l` and `m`: `Leave out the Codex surface even when it is installed.`
- Codex sentence for `mx` and `lx`: `Run the Codex surface, /codex:review --wait --base
  <review-base>, as one of the orchestrators, and list it in the ## Surfaces Ran entry.`

The copy gives the file graders one fixed path, since the persisted file's name carries a
timestamp. The reply's last lines give the arm check its input.

## Ground-truth file

`plugins/review/evals/fanout-diversity-<fixture>.ground-truth.yaml`, one per fixture, shared by
its four arm cases. The eval directory is hidden from the agent under test. Fields:

- `fixture`: the fixture name.
- `source_case`: the case whose scaffold the fixture reuses, or `none`.
- `defect`: the one planted defect, as `location` (`path:line` on the branch), `summary` (what the
  change does wrong) and `failure` (the input and what now fails). `none` for a decoy.
- `axis`: `spec` when the change fails its stated purpose (the commit message's own claim), else
  `standards`. `none` for a decoy.
- `not_defects`: claims the fixture's code refutes. The false-positive grader counts them.

## Severity

The report's `Tier` column rates each finding CRITICAL, IMPORTANT or SUGGESTION after
normalization (`plugins/review/context/severity.md`). Medium severity or higher is IMPORTANT or
CRITICAL; high or critical is CRITICAL. The graders read only the `Tier` column: the
`Confidence` column's `high`, `medium` and `low` are confidence, not severity.

## Graders

### `arm-check.md`

A `regex` grader on `last_message`, byte-identical across the fixtures of one arm. A fail means the
run did not use its arm (the repository layer was not read, `model` fell back to `lens`, or Codex
ran or did not run against the arm), so count the run as invalid rather than as a miss.

| Arm | `pattern` |
|---|---|
| `l` | `^(?=[\s\S]*fanout_diversity: lens \(docs/conventions/review\.yaml\))(?=[\s\S]*## Surfaces[\s\S]*Ran: \[[^\]]*code-reviewer)(?![\s\S]*Ran: \[[^\]]*[Cc]odex)` |
| `m` | `^(?=[\s\S]*fanout_diversity: model \(docs/conventions/review\.yaml\))(?=[\s\S]*## Surfaces[\s\S]*Ran: \[(?:(?:[^\]]*?model:(?![Cc]odex)){2}\|(?:[^\]]*?lane-verifier){2}))(?![\s\S]*Ran: \[[^\]]*[Cc]odex)` |
| `mx` | `^(?=[\s\S]*fanout_diversity: model \(docs/conventions/review\.yaml\))(?=[\s\S]*## Surfaces[\s\S]*Ran: \[(?:(?:[^\]]*?model:(?![Cc]odex)){2}\|(?:[^\]]*?lane-verifier){2}))(?=[\s\S]*## Surfaces[\s\S]*Ran: \[[^\]]*[Cc]odex)` |
| `lx` | `^(?=[\s\S]*fanout_diversity: lens \(docs/conventions/review\.yaml\))(?=[\s\S]*## Surfaces[\s\S]*Ran: \[[^\]]*code-reviewer)(?=[\s\S]*## Surfaces[\s\S]*Ran: \[[^\]]*[Cc]odex)` |

The `\|` in the `m` and `mx` rows is a table escape; the grader file holds a bare `|`. Under
`model`, the sweep labels its leaves `model:<tier>` (`plugins/review/workflows/fanout-sweep.js`)
and runs only with two or more tiers, so the `m` and `mx` checks need two non-Codex `model:`
leaves (or two `lane-verifier` leaves from the main-thread fallback). Codex listed as a tier does
not count toward the two.

### `recall.md` and `false-positive.md`

Two `type: llm` graders on the copied report. Only the defect sentence and the wrong-claims list
vary between fixtures. Both come from the ground-truth file:

- `<defect sentence>`: `plants one defect at <location>: <summary>. What now fails: <failure>.`,
  or `plants no defect.` for a decoy.
- `<not_defects>`: the `not_defects` entries joined with a semicolon and a space.

`recall.md`:

```markdown
---
type: llm
focus: { source: file, path: .work/eval/findings.md }
---

The file is a review findings report. The ground truth (`fanout-diversity-<fixture>.ground-truth.yaml`) <defect sentence>

PASS if a finding in the report's `## Findings` table names that defect, the input it now mishandles and what fails for it, with IMPORTANT or CRITICAL in its `Tier` column. The words need not match. Ignore the `Confidence` column. When the ground truth plants no defect, PASS if no finding has IMPORTANT or CRITICAL in its `Tier` column.

FAIL if the file is missing or empty, no finding names the defect, or every finding that names it has SUGGESTION in its `Tier` column. A finding that names the changed lines without the failing input and what fails for it does not count.
```

`false-positive.md`:

```markdown
---
type: llm
focus: { source: file, path: .work/eval/findings.md }
---

The file is a review findings report. The ground truth (`fanout-diversity-<fixture>.ground-truth.yaml`) <defect sentence> It marks these claims wrong for this fixture: <not_defects>.

Count the findings in the report's `## Findings` table with CRITICAL in their `Tier` column that make one of those wrong claims. Ignore the `Confidence` column. When the ground truth plants no defect, count every finding with CRITICAL in its `Tier` column. A finding about the planted defect never counts.

PASS if the count is 0. FAIL if the file is missing or empty, or the count is 1 or more.
```
