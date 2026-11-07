---
bump: patch
---

### Changed

- The audit and check-visual-parity skills' legacy `evals.json` files are retired into native `claude plugin eval` cases ([#8635](https://github.com/melodic-software/claude-code-plugins/issues/8635)):
  - 29 new cases: audit 1 to 3 and 5 to 24 (`au-*`), check-visual-parity 1 to 6 (`cvp-*`).
  - Held: audit 4 (persist the findings), which needs the detector-findings contract fetched over the network.
  - Not graded, because the current skill contradicts them: audit 7's "does not claim to audit bash test files", and audit 11's and 14's "report-only, never gates --check" (the skill now gates inert-assertion and conditional-assertion).
  - Audit scaffolds copy the skill's existing fixtures through a new `evals/fixtures/audit-workspace.sh`, which drops each corpus file's leading header comments. `evals/fixtures/git-workspace.sh` is the testing-native branch's file, unchanged.
  - `cant-fail-scan.test.sh` check (e) reads the native audit cases instead of the deleted `evals.json`.
  - Five audit prompts now end "Use the `testing:audit` skill if you have it." On the unnamed prompt the skill fired in 0 of 1 runs for `au-boundary-routes-out`, `au-mock-only-advisory`, `au-conditional-assertion`, `au-relation-across-rows` and `au-snapshot-only`, and in 1 of 2 for `au-config-exemption-counted`.
  - Grader changes after the first smoke data. In each case the llm grader passed the reply, and every near-miss sample still fails:
    - `ran-scanner` (every scanning audit case): the script path may now be followed by `;`, `&`, `|`, `\` or `)`, not only by a space or a quote. The rejected reply was `bash "…/cant-fail-scan.sh"; echo "exit=$?"`.
    - `au-clean-suite-denominator`: "no can't-fail tests" now counts as a clean result. A new negative rejects a scan that examined 0 test files, with a new sample for it.
    - The rule-id regexes accept the unqualified `rule-<slug>`, except in `au-detect-happy-path`, whose legacy expectation asks for the qualified id. The rejected reply was `` `rule-flaky-passes-suite` at `playwright.config.ts:21` ``. The three weak-oracle cases also accept a bare `weak-oracle`. The rejected reply was "The audit's `weak-oracle` rule".
    - `au-snapshot-only`: "only oracle" now counts as well as "review it as code". The rejected reply was "The snapshot is its only oracle".
    - `cvp-repo-suite-first`: the prompt now names the README's `npm run test:visual` command and an available Playwright CLI, because the first run had no PNG driver to give the settings page and failed on both graders. Its grader now asks for that command plus `manifest` or `visual-compare.sh compare`. The rejected reply named only `visual-compare.sh compare`.
    - `au-repair-not-pruning` gains `no-write` and `no-edit`. A run rewrote the test file with Write and the old Bash-only check passed it.
