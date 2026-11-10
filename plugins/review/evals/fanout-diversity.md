# Fanout reviewer-diversity eval

These cases measure whether `/review:fanout run-everything` finds one planted defect under four
reviewer arms. The parent plan runs 12 diffs, 4 arms and 3 runs to settle the lens default, panel
placement and the act-on cap. This file is the shape every slice of that eval follows.

## Arms

| Arm | `fanout_diversity` | Codex | `plugins` in `case.yaml` |
|---|---|---|---|
| `l` (L) | `lens` | left out | `["../.."]` |
| `m` (M) | `model` | left out | `["../..", "multi-agent-stub"]` |
| `mx` (M+X) | `model` | runs | `["../..", "multi-agent-stub"]` |
| `lx` (L+X) | `lens` | runs | `["../.."]` |

- Each arm's `scaffold.sh` commits `docs/conventions/review.yaml` with the arm's
  `fanout_diversity` on `main`, before the branch. The reviewed diff never edits it, so the skill
  reads the repository layer and reports `fanout_diversity: <value> (<layer>)`, where the layer
  reads `repository` or `docs/conventions/review.yaml`.
- The M arms load `multi-agent-stub/` from the case directory, a stand-in named `multi-agent`
  whose only skill, `route`, prints the role map the real plugin's bundled defaults resolve to
  with no config layer. `/multi-agent:route` gives the role map that `model` spreads the review
  over. A case loads only plugins under `review`, and a plugin shipped with a case only from the
  case's own subdirectory, so each M case carries its own copy. With fewer than two distinct tiers
  the sweep runs `lens`, and the arm check fails. Run every arm with the same `--model`, one whose
  role map resolves two or more distinct fan-out tiers (`opus` or `fable`). When the real
  `multi-agent` bundled defaults change, update the stub's JSON to match.
- The X arms cannot pass as committed. Every command of `codex@openai-codex` 1.0.6,
  `/codex:review` included, sets `disable-model-invocation: true`, so the model cannot start
  Codex through those commands, and fanout runs it through
  `scripts/codex-review.sh` instead (#12495). A `claude plugin eval` run also loads
  only the plugins under its target and gets a temporary home, so the Codex plugin and its login
  are absent
  ([How runs are isolated](https://code.claude.com/docs/en/plugin-evals#how-runs-are-isolated)).
  Never copy the Codex login into a run's home: the model under test could read it. Run the X
  arms outside `claude plugin eval`, one `claude -p --output-format stream-json --verbose
  --permission-mode auto` per run with the case's scaffold, prompt and `--plugin-dir` plugins, on
  a host where the Codex plugin is installed and logged in, keep the stream as the run's trace, and
  stop each run's Codex broker and app-server when it ends. Grade `arm-check` on the final message,
  `codex-ran` on the trace, and `recall` and `false-positive` on the copied report. A run is valid
  only when `arm-check` and `codex-ran` both pass.
- Run the L and M arms with `--scaffold --allow-tools Bash Write Workflow`. Without `Workflow` the sweep
  runs fanout's main-thread fallback, not `review:fanout-sweep`. Keep `TMPDIR` out of `/tmp` and
  `/var/tmp`, where the run's Bash cannot write its workspace (#12422).
- `node` must resolve on the run's `PATH` without the operator's home directory. A version-manager
  shim that reads its config from `HOME` fails under an isolated `HOME`: the review config read
  then fails, so the report says `(default)` and the arm check fails. Put the real `node`
  directory first on `PATH`.

## Case directory

One directory per fixture and arm, `plugins/review/evals/fanout-diversity-<fixture>-<arm>/`,
because a case carries one prompt, one plugins list and one committed `review.yaml`:

- `case.yaml`: `schema_version: "1.1"`, `name`, the arm's `plugins`, and
  `context.scaffold_script: scaffold.sh`.
- `prompt.md`: frontmatter with `runs: 3`, then the arm's prompt.
- `scaffold.sh`: the fixture's repository, with the arm's `review.yaml` committed on `main`.
- `graders/arm-check.md`, `graders/recall.md` and `graders/false-positive.md`; the X arms also
  have `graders/codex-ran.md`.
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
| `typed-user` | none (decoy) |
| `sort-column` | none (decoy) |
| `page-links` | none (decoy) |
| `return-promise` | none (decoy) |
| `request-options` | none (two defects): a shared default mutated; `retries: 0` read as unset |
| `month-export` | none (two defects): the month's last day dropped; a boolean comparator |

`request-options` and `month-export` plant two defects that share one ground-truth axis. The axis
grades the fixture; it does not decide where the report files a finding. In the #12505 pilot the
L arm put both defects under one heading, at positions 1 and 2, while the M arm split them across
Spec and Standards. An act-on cap therefore reads within-heading positions only from runs that
keep the two together.

A decoy is a correct change that looks wrong, so it measures each arm's false positives. Its
ground truth reads `none` for `defect` and `axis`, and its `not_defects` name the findings a
reviewer would wrongly raise.

## Prompt

Every arm's prompt body is one line: `/review:fanout run-everything No pull request is open for
this branch yet.`, then the Codex sentence, then `After the report is persisted, copy it byte for
byte to .work/eval/findings.md, then end your reply with the report's fanout_diversity: line and
its ## Surfaces section.` (with code spans around the path, the line name and the heading).

- Codex sentence for `l` and `m`: `Leave out the Codex surface even when it is installed.`
- Codex sentence for `mx` and `lx`: `Run the Codex surface as one of the orchestrators, and report
  it in ## Surfaces by the status its script prints.` The skill runs it through
  `scripts/codex-review.sh`, and lists Codex under `Ran` only when the script printed
  `codex: ran`. The arm check reads the reply's `Ran` list; `codex-ran` confirms the script's status
  in the trace.

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

A fixture with two or more defects writes `defects:`, a list of entries each with `location`,
`summary`, `failure` and `axis`, in place of `defect` and `axis`.

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
| `l` | `^(?=[\s\S]*fanout_diversity: lens \((?:repository\|docs/conventions/review\.yaml)[^)]*\))(?=[\s\S]*## Surfaces[\s\S]*Ran: \[[^\]]*code-reviewer)(?![\s\S]*Ran: \[[^\]]*[Cc]odex)` |
| `m` | `^(?=[\s\S]*fanout_diversity: model \((?:repository\|docs/conventions/review\.yaml)[^)]*\))(?=[\s\S]*## Surfaces[\s\S]*Ran: \[(?:(?:[^\]]*?model:(?![Cc]odex)){2}\|(?:[^\]]*?lane-verifier){2}))(?![\s\S]*Ran: \[[^\]]*[Cc]odex)` |
| `mx` | `^(?=[\s\S]*fanout_diversity: model \((?:repository\|docs/conventions/review\.yaml)[^)]*\))(?=[\s\S]*## Surfaces[\s\S]*Ran: \[(?:(?:[^\]]*?model:(?![Cc]odex)){2}\|(?:[^\]]*?lane-verifier){2}))(?=[\s\S]*## Surfaces[\s\S]*Ran: \[[^\]]*[Cc]odex)` |
| `lx` | `^(?=[\s\S]*fanout_diversity: lens \((?:repository\|docs/conventions/review\.yaml)[^)]*\))(?=[\s\S]*## Surfaces[\s\S]*Ran: \[[^\]]*code-reviewer)(?=[\s\S]*## Surfaces[\s\S]*Ran: \[[^\]]*[Cc]odex)` |

The `\|` in the `m` and `mx` rows is a table escape; the grader file holds a bare `|`. Under
`model`, the sweep labels its leaves `model:<tier>` (`plugins/review/workflows/fanout-sweep.js`)
and runs only with two or more tiers, so the `m` and `mx` checks need two non-Codex `model:`
leaves (or two `lane-verifier` leaves from the main-thread fallback). Codex listed as a tier does
not count toward the two.

### `codex-ran.md`

A `regex` grader on `trace`, X arms only, byte-identical across them. It matches a tool result or
text block whose content starts with `codex: ran`, so a skipped or failed Codex fails it, and so does
a read of the script or the skill, which only quote that line. A fail means an invalid run.

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

A fixture with `defects:` gets one recall grader per defect, `recall-<n>.md`, so a run that finds
one defect and misses the other shows which. Each names its defect as `plants <count> defects.
This grader checks defect <n>, at <location>: <summary>. What now fails: <failure>.`, drops the
no-defect sentence, and ends its FAIL paragraph with `A finding about another planted defect does
not count.` Its `false-positive.md` lists every defect, joined by "; and ", and reads `A finding
about a planted defect never counts.`
