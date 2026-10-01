# Judge calibration

The task-end judge stays advisory until this set measures it (`plan.md` Phase 4, design DT1, DT9,
DT13). Everything lives in `plugins/testing/skills/audit/evals/judge-calibration/`: `cases/`,
`labels.tsv`, `sample.sh` (draws the set), `raters.sh` (the model raters) and `metrics.sh` (scores
the labels and runs the judge).

## Protocol

### Strata

| Stratum | Rows (files) | Holdout rows (files) | What it is |
|---|---|---|---|
| `seed` | 10 (10) | 4 (4) | The DT1 seeds: Pocock's S3, T3, M2, M3, M5, M6, M7-side-channel and S5, plus G7 and G10. S3 and G7 are in scope; the other eight are out of scope, and DT1 expects UNKNOWN on them. A FLAG on one scores as over-reach. |
| `adversarial` | 8 (8) | 3 (3) | Tautological tests from the scanner corpus, one each for js-jest, js-vitest, js-node-test, py-pytest, cs-xunit, go-testing, pwsh-pester and bash-harness, each carrying a misleading provenance comment ("expected value from the spec") or an instruction-shaped string. They measure whether the judge treats test text as data. |
| `in-use` | 60 (39) | 22 (12) | Test blocks drawn from the git histories of claude-code-plugins, medley and ci-runner, at natural prevalence. |

A case is a directory `cases/<id>/` holding the test file and the code it tests, each at its path
plus `.fixture`. The judge's question is where an expected value came from, which it cannot answer
without the code under test, so every case ships that code wherever any exists:

- In-use cases are verbatim. Each file sits at its repository path, and every file comes from the
  commit in the row's `source`. The row's `note` lists the code under test.
- The M6 and M7 seeds are verbatim from Pocock's `tests.md`, minus the upstream `// BAD: ...`
  comment, which states the answer. Upstream gives them no implementation, so they ship none.
- Adversarial cases are corpus files with the corpus header removed and one comment or string
  added. The corpus has no implementation for them, so the derivation the judge must see is in the
  test itself.
- Six seeds (S3, M2, M3, M5, S5, G10) are authored, because upstream gives no code for them. G7
  and T3 are authored around statements copied from the Release 1 research. All eight ship an
  authored implementation.

The one case file over 200 KB is `u03`'s 476 KB `test_hygiene.py`, the test's own file. It stays
whole because the judge reads whole files in use.

### In-use draw

`sample.sh` with seed `20260930`, over the three repositories at the commits pinned in the script.
The population is every test block a commit created or changed, in a file an adapter claims and
outside fixtures and testdata directories, scoped the way the hooks scope a write (`--blocks
--lines` over the commit's added lines). Two uniform phases keep every block's chance equal:

1. Shuffle the 6,138 (commit, test file) pairs and take the first 240. List every block each one
   changed. Drop pairs whose code under test cannot be resolved: 5 pairs, 5 blocks. That leaves
   586 blocks.
2. Shuffle those blocks and take 60: 60 blocks in 39 files.

`sample.sh` finds the code under test from the test's text, at the test's commit:

- the file the test's name points to (`foo.test.ts` to `foo.ts`, `test_foo.py` to `foo.py`,
  `Foo.Tests.ps1` to `Foo.ps1`);
- every path or relative import the test names, and the Python modules it imports;
- the package's other files for Go;
- the files declaring the C# types the test names.

Limits:

- It goes one level deep. The judge sees what the test names, not what that code imports.
- It reads text, so it misses a path built at run time.
- It keeps at most 20 files per case.
- It leaves other test files out.

A row's `note` names the lines the commit changed and the code under test.

Recorded before labeling: 60 in-use blocks drawn, and 5 in-use pairs dropped for unresolved code.

The scanner finds 0 provenance-shaped findings in the 60 drawn blocks, and 0 in the 586-block
pool. That count covers the three rules shaped like provenance defects (`rule-recomputed-expectation`,
`rule-constant-restatement`, `rule-recomputed-derived`; design DT7). The count is not an estimate
of prevalence. Those rules match text shapes and cannot see where an expected value came from,
which is why the judge exists. In-use FLAG prevalence is unknown until the labels exist.

The FLAG count known before labeling is 2 in-scope seeds plus 8 adversarial cases, short of DT9's
30. Per the plan, the results state the achieved n with its interval, and the set is not padded.

### Split

Split by case file, so no file has rows on both sides. Within each stratum, case files are
shuffled with seed `20260930` and taken as `holdout` until holdout holds at least a third of the
stratum's rows; the rest is `tune`. The judge prompt (`plugins/testing/hooks/test-judge-prompt.md`)
stays frozen. A prompt change after the first commit to `labels.tsv` is measured on `holdout` only,
and calibration.md records it with a line `holdout-only: <commit sha>`, which `metrics.sh --check`
reads.

### Raters

Amended 2026-10-01 (user): the user, not a domain expert, delegated labeling to a blind panel of
three models, and the panel's consensus is `reference_label`; see Results, Reference labels. That
supersedes the user labeling below, and in metric names `user` means `reference_label`. The rest
of this section is the protocol as planned.

The user labels all 78 rows blind, and those labels (`reference_label`) are the ground truth. Labeling
every row instead of a random sample keeps every FLAG: a random 50 would hold about 6, since the
scanner found 0 provenance-shaped blocks in the 586-block in-use pool. No row needs adjudication,
because no rater label is used as ground truth.

The labeling page is a private claude.ai artifact. Per row it shows the test file and the code
under test with paths relative to the case root, the test name and the changed lines; never the
case id, `source`, `in_scope`, `note`, `stratum`, `split` or another label. The user wrote the seed
and adversarial cases, so those labels are not blind to authorship, and `metrics.sh` reports the
`in-use` stratum separately for that reason.

Two model raters label every row blind through `raters.sh`:

- `opus`: `claude -p --model opus` with the judge's isolation. Its only tools are Read, Grep and
  Glob, scoped to the case's repository, and it runs with no hooks, settings sources, MCP servers
  or slash commands.
- GPT through `codex exec -s read-only` when the Codex CLI is on PATH and logged in; otherwise
  `opus` rates alone.

Each row runs in an empty temporary git repository holding only its case's files at their
repository paths. The rater gets the judge's question, the FLAG, PASS and UNKNOWN definitions copied
from `test-judge-prompt.md`, the test file's path, the test's name and the changed lines. It answers
with one JSON object, `{"label", "reason"}`.

Codex's read-only sandbox does not refuse reads outside its directory, so:

- `raters.sh` refuses to run while `labels.tsv` holds any label;
- each rater's output goes to `raters/<rater>.tsv`, and `raters.sh --merge` copies it into the
  `opus_label` and `codex_label` columns only after both raters finish; the user's labels are
  merged after that;
- a row fails, with no label, when its transcript or answer names `labels.tsv`,
  `judge-calibration` or a case or row id.

Each rater's kappa against the user is reported with its coverage and raw agreement beside it.
Rater-versus-rater agreement is not reported as quality. A rater whose pooled kappa against the
user is under 0.6 is marked `failed` and dropped from use as a re-labeler. It does not block the
calibration, because the user's labels are the ground truth.

Why the user, not a model, is the independent rater: LLM judges show self-preference bias, scoring
output from their own model family higher. For that bias Haiku, Sonnet, Opus and Fable are one
family, so an Opus rater is not independent of a Sonnet or Opus judge. Independence comes from the
user. GPT is outside the family, which is why Codex is the second rater when it is available.
Since the 2026-10-01 delegation no human labels exist, so this independence is not achieved: two
of the three panel members are Opus (Results, Reference labels).

There is no separate pilot set. Run-to-run variance is measured on the chosen arm (see the sweep).

### Scoring

Labels are FLAG, PASS or UNKNOWN. The UNKNOWN rule was fixed before any label existed:

- A judge or rater UNKNOWN on a row the user labeled FLAG or PASS is an abstention. It is left out
  of kappa, precision and recall, and counted against coverage, whose denominator is the rows the
  user labeled FLAG or PASS.
- On a row the user labeled UNKNOWN, a judge UNKNOWN is correct and a judge FLAG or PASS is
  over-reach. A FLAG there counts against FLAG precision.
- Kappa is three-class Cohen's kappa over the rows where neither side abstained.

`metrics.sh` reports per stratum, then pooled as `all`:

- `kappa user-opus`, `kappa user-codex` and `kappa judge-user`, each with coverage and raw
  agreement;
- the judge's confusion matrix against the user's labels;
- FLAG precision and recall with Wilson 95% score intervals;
- FLAG prevalence and the achieved FLAG n (`flag-n`);
- on the rows the user labeled UNKNOWN, how often the judge said UNKNOWN and how often it
  over-reached.

The Wilson score interval keeps close to its nominal coverage at small n and near 0 or 1, where the
plain normal interval does not (Newcombe 1998, "Two-sided confidence intervals for the single
proportion"). System recall covers only tests the session created or changed (DT13).

### Judge runs and the model sweep

`metrics.sh --sweep` runs the frozen judge over every row for 7 arms: `sonnet` at `low`, `medium`,
`high` and `xhigh`, and `opus` at `low`, `medium` and `high`. Haiku waits on research gap G8. The
runs go through `judge::run` and `judge::validate`, the functions the hooks use, so the sweep
scores what a session would see relayed. Each row's verdict is kept in
`sweep/<model>-<effort>.tsv`, and each run's cost and wall time in `sweep/<model>-<effort>.runs.tsv`.
`metrics.sh --table` reprints the table from those files.

Each case runs in an empty temporary repository holding only its own files at their repository
paths: the test and the code under test, but no label, id or other case. The judge sees less of the
repository than in a real session, where it can follow imports past the first level.

The table reports, per arm: accuracy, FLAG precision and recall with Wilson intervals, coverage,
cost per row, wall time per run (median, and p95 by nearest rank), wall time for the arm, and the
exact McNemar p against the most accurate arm.

Selection uses paired accuracy over all rows. A verdict is correct when it equals the user's label,
so for selection an UNKNOWN on a FLAG or PASS row counts as wrong.

1. The most accurate arm is the reference.
2. An arm whose two-sided exact McNemar test against it (a binomial test on the rows where exactly
   one of the two is correct) is not significant at 0.05 ties with it.
3. Among tied arms `sonnet` wins, then the lower p95 wall time per run, then the lower cost per
   row. Accuracy comes first; the judge runs during normal development and must not stall it.
4. The fallback default is the best arm of the other class by the same rule, tested against that
   class's most accurate arm.

Both defaults go to `plugin.json` and the in-script defaults in the same commit, with the sweep
table below.

Power: at n = 50 the exact McNemar test has power 0.83 to separate accuracy 0.9 from 0.7. Separating
0.9 from 0.8 needs about 100 rows, so at 78 rows arms that close tie and the tie-breaks decide.

The prompt stays frozen, so selection runs on all rows. If the prompt changes after the first
commit to `labels.tsv`, every figure is re-measured on `holdout` rows only (29 rows), and this file
states that n.

Run-to-run variance: `metrics.sh --rerun <model> <effort>` runs the chosen arm twice more over every
row and reports the share of rows whose verdict changed across the three runs.

After the choice, R2-P13's Stop wait (18-28 s with `opus` `medium`) is re-measured with the chosen
arm and recorded in `probes.md`; a shorter debounce is considered if the wait stays long.

On every new model in a class, re-run `metrics.sh --sweep` and change the default only when the
sweep says so: the settings hold class aliases, so a new version needs no code change. Add Haiku
once G8 confirms its effort support.

## Results

### Reference labels

The labels in `reference_label` are not a human's. The user, who is not a domain expert in test
provenance, delegated labeling on 2026-10-01 to a blind panel of three models: Opus at `high`
effort, Opus at `xhigh`, and GPT through `codex exec` at reasoning effort `high`. Each member got
the raters' prompt and isolation (`raters.sh`): one case's files in an empty repository, the test
file's path, the test name and the changed lines, and nothing else. In round 1 the three labeled
every row independently. In round 2 each member of a row without a unanimous round-1 label saw the
other two labels and reasons, anonymized as Reviewer A and B, beside its own, re-read the code and
gave a final label. The consensus is the round-1 label where it was unanimous, else the round-2
majority. The Opus members' 368 calls cost $15.10, about 10 minutes wall time. The panel's script,
log and per-row results are kept untracked in `.work/tautological-tests-judge/panel/`.

Result: 6 FLAG, 56 PASS, 16 UNKNOWN. 42 rows were unanimous, 36 were decided by majority and none
split. In 35 of the 36 majority rows GPT was the lone dissenter. In 31 of them GPT said UNKNOWN
where both Opus members said PASS, on tests whose expected value is a hand-written literal with
no stated source. Those 31 rows are the first a human should spot-check: `seed-g10`, `u01-2`,
`u02-1`, `u03-2`, `u04-1`, `u05-3`, `u05-4`, `u05-5`, `u07-1`, `u09-1`, `u10-1`, `u12-1`, `u14-2`,
`u18-1`, `u21-1`, `u26-1`, `u27-1`, `u28-1`, `u28-2`, `u29-1`, `u30-1`, `u31-1`, `u32-1`, `u35-1`,
`u36-1`, `u37-1`, `u37-2`, `u37-4`, `u38-1`, `u38-3`, `u39-1`.

Limitations:

- Model-family bias. Two of three panel members are Opus, so on every split row the majority is
  Opus's view, and the judge is Sonnet or Opus. With GPT's round-2 label in place of the
  consensus on the 35 rows where GPT dissented (31 PASS to UNKNOWN, 2 FLAG to UNKNOWN, 2 UNKNOWN to
  PASS), every arm's accuracy falls to 0.44-0.54, `sonnet` `low` becomes significantly worse than
  the most accurate arm (`opus` `high`, McNemar p 0.0215), and the rule would choose `sonnet`
  `medium`, fallback `opus` `low`. The chosen default therefore depends on the Opus majority on
  those rows.
- The `in-use` stratum, the only one the user did not author, holds 0 reference FLAGs. The judge
  said PASS on all 60 of its rows, so its kappa there is 0.0000, and every FLAG precision and
  recall figure comes from user-authored seed and adversarial cases.
- 6 FLAGs cannot separate arms on FLAG precision or recall: every arm's recall interval has a lower
  bound of 0.61 or less.
- 78 rows cannot separate accuracy 0.9 from 0.8 (Power above), so close arms tie and the
  tie-breaks decide.
- Run-to-run churn: the chosen arm's verdict changed on 10% of rows across three runs (Model
  sweep), the same size as most accuracy gaps in the table.

### Rater agreement

From `metrics.sh`, per stratum and pooled. `user` here is `reference_label`, the panel consensus.

```text
kappa user-opus in seed 0.8039 (n=10) coverage 1.0000 (3/3) agreement 0.9000 (9/10)
kappa user-codex in seed 0.6429 (n=10) coverage 1.0000 (3/3) agreement 0.8000 (8/10)
kappa user-opus in adversarial 0.4839 (n=8) coverage 1.0000 (5/5) agreement 0.7500 (6/8)
kappa user-codex in adversarial 1.0000 (n=7) coverage 0.8000 (4/5) agreement 1.0000 (7/7)
kappa user-opus in in-use 0.7059 (n=60) coverage 1.0000 (54/54) agreement 0.9500 (57/60)
kappa user-codex in in-use 0.9046 (n=31) coverage 0.4630 (25/54) agreement 0.9677 (30/31)
kappa user-opus in all 0.8176 (n=78) coverage 1.0000 (62/62) agreement 0.9231 (72/78)
kappa user-codex in all 0.8887 (n=48) coverage 0.5161 (32/62) agreement 0.9375 (45/48)
```

Neither rater is under 0.6 pooled. The Opus rater's agreement is inflated: Opus is two of the
three panel members that made the reference. Codex's coverage is low because it abstains
(UNKNOWN) on hand-written literals with no stated source, the same pattern as GPT on the panel.

### Judge against the labels

`metrics.sh` for the chosen arm, `sonnet` `low`, whose verdicts are `labels.tsv`'s
`judge_verdict` (copied from `sweep/sonnet-low.tsv`):

```text
stratum seed n=10
kappa judge-user in seed 0.6429 (n=10) coverage 1.0000 (3/3) agreement 0.8000 (8/10)
confusion seed judge=FLAG FLAG=1 PASS=0 UNKNOWN=0
confusion seed judge=PASS FLAG=0 PASS=2 UNKNOWN=2
confusion seed judge=UNKNOWN FLAG=0 PASS=0 UNKNOWN=5
flag-precision seed 1.0000 [0.2065, 1.0000] (1/1)
flag-recall seed 1.0000 [0.2065, 1.0000] (1/1)
prevalence seed 0.1000 (1/10)
flag-n seed 1
unknown seed user=7 correct=5 over-reach=2
stratum adversarial n=8
kappa judge-user in adversarial 0.4615 (n=7) coverage 0.8000 (4/5) agreement 0.7143 (5/7)
confusion adversarial judge=FLAG FLAG=4 PASS=0 UNKNOWN=1
confusion adversarial judge=PASS FLAG=0 PASS=0 UNKNOWN=1
confusion adversarial judge=UNKNOWN FLAG=1 PASS=0 UNKNOWN=1
flag-precision adversarial 0.8000 [0.3755, 0.9638] (4/5)
flag-recall adversarial 1.0000 [0.5101, 1.0000] (4/4)
prevalence adversarial 0.6250 (5/8)
flag-n adversarial 5
unknown adversarial user=3 correct=1 over-reach=2
stratum in-use n=60
kappa judge-user in in-use 0.0000 (n=60) coverage 1.0000 (54/54) agreement 0.9000 (54/60)
confusion in-use judge=FLAG FLAG=0 PASS=0 UNKNOWN=0
confusion in-use judge=PASS FLAG=0 PASS=54 UNKNOWN=6
confusion in-use judge=UNKNOWN FLAG=0 PASS=0 UNKNOWN=0
flag-precision in-use NA (0/0)
flag-recall in-use NA (0/0)
prevalence in-use 0.0000 (0/60)
flag-n in-use 0
unknown in-use user=6 correct=0 over-reach=6
stratum all n=78
kappa judge-user in all 0.6440 (n=77) coverage 0.9839 (61/62) agreement 0.8701 (67/77)
confusion all judge=FLAG FLAG=5 PASS=0 UNKNOWN=1
confusion all judge=PASS FLAG=0 PASS=56 UNKNOWN=9
confusion all judge=UNKNOWN FLAG=1 PASS=0 UNKNOWN=6
flag-precision all 0.8333 [0.4365, 0.9699] (5/6)
flag-recall all 1.0000 [0.5655, 1.0000] (5/5)
prevalence all 0.0769 (6/78)
flag-n all 6
unknown all user=16 correct=6 over-reach=10
```

The judge went beyond the reference on 10 of the 16 rows labeled UNKNOWN, 9 of them with PASS. It
abstained on 1 of the 6 FLAG rows and flagged one UNKNOWN row.

### Model sweep

`metrics.sh --table`, from the kept `sweep/` files:

| model | effort | accuracy | FLAG precision [95% CI] | FLAG recall [95% CI] | coverage | cost per row | wall per run, median | wall per run, p95 | wall per arm | McNemar p vs most accurate |
|---|---|---|---|---|---|---|---|---|---|---|
| sonnet | low | 0.8590 (67/78) | 0.8333 [0.4365, 0.9699] (5/6) | 1.0000 [0.5655, 1.0000] (5/5) | 0.9839 (61/62) | $0.0155 | 6.7 s | 11.8 s | 428.5 s | 0.3438 |
| sonnet | medium | 0.8846 (69/78) | 0.8333 [0.4365, 0.9699] (5/6) | 1.0000 [0.5655, 1.0000] (5/5) | 0.9839 (61/62) | $0.0164 | 7.6 s | 12.6 s | 463.5 s | 0.7266 |
| sonnet | high | 0.8462 (66/78) | 0.8571 [0.4869, 0.9743] (6/7) | 1.0000 [0.6097, 1.0000] (6/6) | 0.9516 (59/62) | $0.0218 | 8.2 s | 17.3 s | 548.1 s | 0.1797 |
| sonnet | xhigh | 0.8590 (67/78) | 0.8571 [0.4869, 0.9743] (6/7) | 1.0000 [0.6097, 1.0000] (6/6) | 0.9677 (60/62) | $0.0336 | 10.9 s | 29.2 s | 776.6 s | 0.2891 |
| opus | low | 0.8846 (69/78) | 0.8333 [0.4365, 0.9699] (5/6) | 1.0000 [0.5655, 1.0000] (5/5) | 0.9677 (60/62) | $0.0249 | 7.7 s | 15.3 s | 495.1 s | 0.7266 |
| opus | medium | 0.9103 (71/78) | 0.8333 [0.4365, 0.9699] (5/6) | 1.0000 [0.5655, 1.0000] (5/5) | 0.9516 (59/62) | $0.0364 | 11.4 s | 26.0 s | 740.3 s | 1.0000 |
| opus | high | 0.9103 (71/78) | 0.8571 [0.4869, 0.9743] (6/7) | 1.0000 [0.6097, 1.0000] (6/6) | 0.9516 (59/62) | $0.0414 | 11.5 s | 23.8 s | 756.4 s | 1.0000 |

```text
chosen: sonnet low
fallback: opus low
```

Run-to-run variance, `metrics.sh --rerun sonnet low` (the first run and two more):

| run | model | effort | rows whose verdict changed |
|---|---|---|---|
| rerun | sonnet | low | 0.1026 (8/78) |

`sweep/sonnet-low.tsv` was emptied by an in-place edit and rebuilt from `labels.tsv`'s
`judge_verdict`, which had been copied from it in the same edit. Its verdicts are exact (they
reproduce every figure above and the re-run row) and its rows are in the order the sweep writes
them; its reason column is empty, losing the one reason it held ("the proposed diff does not
apply").

### Chosen default

`sonnet` at `low`, fallback `opus` at `low`, written to `plugin.json` (`test_judge_model`,
`test_judge_fallback_model`, `test_judge_effort`) and to `judge-lib.sh`'s in-script defaults.
The rule as applied: the most accurate arms are `opus` `medium` and `opus` `high` (71/78), and the
tie-breaks make `opus` `high` the reference (lower p95). No arm differs from it at 0.05 (lowest p
0.1797), so all seven tie. Among the tied arms `sonnet` wins, and among the four `sonnet` arms
`low` has the lowest p95 wall time per run (11.8 s). The fallback is the best `opus` arm by the
same rule: all three tie with `opus` `high`, and `low` has the lowest p95 (15.3 s). Both classes
run at the one `test_judge_effort`, `low`, which is the fallback arm's effort too.
