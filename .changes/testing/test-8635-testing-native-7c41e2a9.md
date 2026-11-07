---
bump: patch
---

### Changed

- The test-value, diagnose, plan, setup and write skills' legacy `evals.json` files are retired into native `claude plugin eval` cases ([#8635](https://github.com/melodic-software/claude-code-plugins/issues/8635)):
  - 21 new cases: test-value 1 and 3 to 7, diagnose 1 to 3, plan 2 and 3, setup 2 and 3, write 1 to 8.
  - Already covered by existing cases, each gaining an llm grader that quotes the legacy expectations: test-value 2 (`tv-gateway-charge-once`), plan 1 (`pl-branch-test-plan`), setup 1 (`setup-check-reports-missing-lint-rule`).
  - Changes after the first smoke data, each disclosed:
    - Fifteen test-value, diagnose and write prompts now end "Use the `testing:<skill>` skill if you have it.", as `write-first-unit` already does. Natural phrasing alone loaded no skill in 15 of 19 runs, so that batch was invalid.
    - `tv-constant-restatement-detector` boundary-281: before, `281` with a reject or fail verb in the same clause; after, it also accepts `281` followed in code by `.toBe(false)`, `.toBeFalsy()` or `.toThrow(`. The rejected reply was `expect(validatePost('a'.repeat(281)).ok).toBe(false);`, which the llm grader passed 3 of 3. Every near-miss still fails, including a new `.toBe(true)` sample.
    - `wr-round-trip-property` round-trip: before, read `tests/test_durations.py`; after, it reads the trace, because the run put the property in a second test file. literal-example: before, an `==` comparison only; after, it also accepts a `(seconds, "text")` parametrize pair. The llm grader did not fail that run. Every near-miss still fails, including a new string-first parse-table sample.
  - The setup cases invoke `/testing:setup` by slash command, since the skill is disable-model-invocation.
  - A shared sourced fixture, `evals/fixtures/git-workspace.sh`, holds the real-home guard and clears the inherited git environment before any git call.
