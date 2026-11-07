---
bump: patch
---

### Changed

- The cleanup skill's legacy `evals.json` is retired into native `claude plugin eval` cases ([#8635](https://github.com/melodic-software/claude-code-plugins/issues/8635)):
  - 6 new cases (`cl-*`): `routing`, `refuses_default_branch`, `refuses_mixed_languages`, `refuses_without_mutation_setup`, `cannot_fail_only_accepted` and `cannot_fail_only_skeptic`. These legacy entries have no expectations list, so each llm grader quotes the expected output.
  - Already covered: `cannot_fail_only_offered` (`cl-no-mutation-gate`), which gains an llm grader quoting it.
  - Held, because each needs the mutation-testing plugin, which a testing-plugin eval run does not load: `cf_and_k_rewritten`, `trivial_getter_waits`, `registry_contract_kept`, `bash_harness_rewrite_only`, `expired_quarantine_reported_not_renewed`, `flaky_quarantined_gate_passes`, `red_baseline_stops`, `lost_kill_blocks`, `judge_diff_not_applied_unclassified`, `weaken_block_quarantine`, `findings_file_rows`, `answered_batch_commits`, `resumes_own_dirty_batch`, `cannot_fail_only_offered_on_empty_mapping`, `dotnet_gate_runs` and `dotnet_lost_kill_blocks`.
  - The skill's `evals/` directory is removed along with its `evals.json`. Its fixtures had no other consumer. The cases now seed the Python and C# shops through `evals/fixtures/cleanup-shop.sh` and `cleanup-dotnet.sh`. `evals/fixtures/git-workspace.sh` is the testing-native branch's file, unchanged.
  - A grader change after the first smoke data, in both cannot-fail-only cases: the reply-only `skeptic-verdicts` regex required the reply to say "throw is the only oracle". Both runs wrote that reason to `decisions.md` instead. It is now two graders: `records-keep-reason`, which checks the Bash write of `keep: throw is the only oracle`, and `proposes-two-deletions`, which checks the reply. The llm graders now read the trace, because the legacy text grades what `decisions.md` records. Every near-miss sample still fails.
