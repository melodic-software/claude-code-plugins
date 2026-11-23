# Tests

- A test that feeds a parser another script's, service's or API's output takes its fixture from
  that producer's real output: a captured sample committed beside the test, or a run of the
  producer inside the test. Flag a hand-built fixture whose shape (column count, field set, a count
  field) nothing ties to the producer. Examples:
  - The test at `declare-test-scope.test.mjs:120`
    ([file](../../.github/scripts/pr-unblock/declare-test-scope.test.mjs)) runs
    [`scripts/selection-audit.sh`](../../scripts/selection-audit.sh) with only strace and the
    selector stubbed, and reads both rows the script writes to `$out/suites/$key` and puts together
    into `suites.tsv`: a traced suite's (`:124`) and, with `--budget 1`, a not-traced one's
    (`:127-128`).
  - In
    [`test_babysit_merge.py`](../../plugins/source-control/skills/babysit-prs/scripts/tests/test_babysit_merge.py),
    the force-push fixtures `NO_FORCE_PUSH` and `ONE_FORCE_PUSH` (`:2925`, `:2933`) replay recorded
    GitHub answers. A hand-built fixture with `totalCount` equal to its node count hides that
    GitHub's `totalCount` counts every timeline item, so a count check passes every test and fails
    on real pull requests
    ([7b9c622201](https://github.com/melodic-software/claude-code-plugins/commit/7b9c6222019abf4ba95dd1e0858ee29fb36e5a1d),
    [#15895](https://github.com/melodic-software/claude-code-plugins/pull/15895)).
