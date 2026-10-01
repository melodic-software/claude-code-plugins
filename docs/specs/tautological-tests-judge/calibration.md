# Judge calibration

The task-end judge stays advisory until this set measures it (`plan.md` Phase 4, design DT1, DT9,
DT13). Everything lives in `plugins/testing/skills/audit/evals/judge-calibration/`: `cases/`,
`labels.tsv`, `sample.sh` (draws the set) and `metrics.sh` (scores it).

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
only its own files at their repository paths: the test and the code under test, but no label, id
or other case. The judge sees less of the repository than in a real session, where it can follow
imports past the first level. The shipped default is the arm with the best holdout FLAG precision and recall; where
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
