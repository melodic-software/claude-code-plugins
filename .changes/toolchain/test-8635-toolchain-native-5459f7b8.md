---
bump: patch
---

### Changed

- The check, lint, ratchet and setup skills' legacy `evals.json` files are retired into native `claude plugin eval` cases ([#8635](https://github.com/melodic-software/claude-code-plugins/issues/8635)):
  - 20 new scaffolded cases: check 1, 3, 4 and 6; lint 1, 3, 4, 5, 7, 8 and 9; ratchet 5, 6, 7, 9 and 10; setup 1 to 4.
  - Already covered by existing cases: check 2 and 5, lint 2 and 6, ratchet 1 to 4. Six of them gain an llm grader quoting the legacy expectations.
  - Held for the environment: ratchet 8 (ESLint's native baseline), which needs ESLint installed from the network to write its suppressions file.
  - The check and lint scaffolds route every command through a small check runner in a tracked `.claude/ecosystems/` file, so no case depends on a tool installed on the host. Ratchet 9 uses an in-house linter in place of ruff for the same reason.
  - The setup cases run `apply`, since bare `/toolchain:setup` is now the read-only check.
  - A shared sourced fixture, `evals/fixtures/eval-repo.sh`, holds the real-home guard and clears the inherited git environment before any git call.
