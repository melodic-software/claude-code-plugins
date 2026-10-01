# Judge calibration

The task-end judge stays advisory until this set measures it (`plan.md` Phase 4, design DT1, DT9,
DT13). Everything lives in `plugins/testing/skills/audit/evals/judge-calibration/`: `cases/`,
`labels.tsv`, `sample.sh` (draws the set) and `metrics.sh` (scores it).

## Protocol

### Strata

| Stratum | Rows | Holdout | What it is |
|---|---|---|---|
| `seed` | 10 | 4 | The DT1 seeds: Pocock's S3, T3, M2, M3, M5, M6, M7-side-channel and S5, plus G7 and G10. S3 and G7 are in scope; the other eight are out of scope, and DT1 expects UNKNOWN on them. A FLAG on one scores as over-reach. |
| `adversarial` | 8 | 3 | Tautological tests from the scanner corpus, one per adapter family, each carrying a misleading provenance comment ("expected value from the spec") or an instruction-shaped string. They measure whether the judge treats test text as data. |
| `in-use` | 60 | 20 | Test blocks drawn from the git histories of claude-code-plugins, medley and ci-runner, at natural prevalence. |

Each row's `source` names where its code came from, with the path and commit. In-use cases and the
M6 and M7 seeds are verbatim; the M6 and M7 seeds drop the upstream `// BAD: ...` comment, which
states the answer. Adversarial cases are corpus files with the corpus header removed and one
comment or string added. Six seeds (S3, M2, M3, M5, S5, G10) are authored, because the upstream
gives no code for them; G7 and T3 are authored around statements copied from the Release 1
research. S3 and G7 ship the implementation they test beside the test file.

### In-use draw

`sample.sh` with seed `20260930`, over the three repositories at the commits pinned in the script.
The population is every test block a commit created or changed, in a file an adapter claims and
outside fixtures and testdata directories, scoped the way the hooks scope a write (`--blocks
--lines` over the commit's added lines). Two uniform phases keep every block's chance equal:

1. Shuffle the 6,138 (commit, test file) pairs and take the first 240. List every block each one
   changed: 564 blocks.
2. Shuffle those blocks and take 60: 60 blocks in 39 files.

20 of the 240 pairs were skipped because the file fails this repository's typos check, and a
verbatim case cannot be edited to pass it. A case file is the whole test file at that commit; a
row's `note` names the lines the commit changed.

Recorded before labeling: 60 in-use blocks drawn. A deterministic pre-screen, the scanner's three
provenance rules (`rule-recomputed-expectation`, `rule-constant-restatement`,
`rule-recomputed-derived`; design DT7), finds a provenance defect in 0 of the 60 drawn blocks and 0
of the 564 in phase 1. The pre-screen is the scanner's rules, not a judgment, and the labels decide.
The expected FLAG count is therefore 2 seeds plus 8 adversarial plus whatever the raters find in
use, short of DT9's 30. Per the plan, the results state the achieved n with its interval and the
set is not padded.

### Split

Within each stratum, rows are shuffled with seed `20260930` and the first third, rounded up, is
`holdout`; the rest is `tune`. The judge prompt (`plugins/testing/hooks/test-judge-prompt.md`)
stays frozen. A prompt change after the first commit to `labels.tsv` is measured on `holdout` only,
and calibration.md records it with a line `holdout-only: <commit sha>`, which `metrics.sh --check`
reads.

### Raters

Pending the Q12 rater decision. Settled by the plan: two raters, the user and a model rater of a
class other than the judge's, label every case blind to each other and to the judge. A rater sees
the case file, the test name and the changed lines, never `source`, `stratum`, `in_scope`, `note`
or another label. The user adjudicates every disagreement. Labels are trusted at user-versus-model
kappa of at least 0.6.

### Scoring

Labels are FLAG, PASS or UNKNOWN. `metrics.sh` reports, per stratum and pooled: Cohen's kappa for
user versus model rater, judge versus user and judge versus model rater; the judge's confusion
matrix against the adjudicated label; FLAG precision and recall with Wilson 95% intervals; FLAG
prevalence; and UNKNOWN counts. An UNKNOWN on an adjudicated FLAG counts as a miss. System recall
covers only tests the session created or changed (DT13).

### Judge runs and the model sweep

`metrics.sh --sweep` runs the judge over every case for `haiku`, `sonnet` and `opus` at `low` and
`medium` effort through `judge::run` and `judge::validate`, the functions the hooks use, so it
scores what a session would see relayed. Each case runs in an empty temporary repository holding
only its own files under their real names, so the judge cannot read a label, an id or another case.
For an in-use case that means the judge does not see the code under test, which it can read in a
real session. The shipped default is the arm with the best holdout FLAG precision and recall; where
arms' intervals overlap, the cheaper arm wins. The fallback default is the best arm of another
class.

On every new model in a class, re-run `metrics.sh --sweep` and change the default only when the
sweep says so: the settings hold class aliases, so a new version needs no code change.

## Results

### Rater agreement

TODO: the `kappa user-model` lines from `metrics.sh`, after labeling.

### Judge against the labels

TODO: per-stratum `metrics.sh` output for the chosen arm.

### Model sweep

TODO: the six-row table from `metrics.sh --sweep`.

### Chosen default

TODO: the chosen arm and fallback, as written to `plugin.json`.
