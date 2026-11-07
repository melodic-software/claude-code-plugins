---
bump: patch
---

### Changed

- The test-value, diagnose, plan and setup skills' legacy `evals.json` files are retired into native `claude plugin eval` cases ([#8635](https://github.com/melodic-software/claude-code-plugins/issues/8635)):
  - 13 new cases: test-value 1 and 3 to 7, diagnose 1 to 3, plan 2 and 3, setup 2 and 3.
  - Already covered by existing cases, each gaining an llm grader that quotes the legacy expectations: test-value 2 (`tv-gateway-charge-once`), plan 1 (`pl-branch-test-plan`), setup 1 (`setup-check-reports-missing-lint-rule`).
  - The setup cases invoke `/testing:setup` by slash command, since the skill is disable-model-invocation.
  - A shared sourced fixture, `evals/fixtures/git-workspace.sh`, holds the real-home guard and clears the inherited git environment before any git call.
