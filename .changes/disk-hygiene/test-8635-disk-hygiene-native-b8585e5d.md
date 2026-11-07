---
bump: patch
---

### Changed

- The audit and setup `evals.json` files are retired into the `evals/` case suite ([#8635](https://github.com/melodic-software/claude-code-plugins/issues/8635)). Nine new cases: `au-probe-then-scan-commands` (the kill-switch probe runs before a scan-only engine call whose snapshot goes under the data root), `au-null-data-root-not-run` (a null data root means the audit did not run, with no guessed root), `au-cleanup-request-routes-to-clean` (a removal request goes to the clean skill, not the audit), `su-bare-runs-check` and `su-apply-points-writes-nothing` (the bare and `apply` actions run the read-only check and write nothing), `su-exec-form-bash-registration-fails` (a bare `bash` registration fails step 1), `su-missing-git-bash-fails-probe` (no accepted bash fails the probe), `su-disabled-toggle-keeps-launch-fail` (a disabled toggle keeps the interpreter FAIL) and `su-python-below-floor-fails-closed` (an interpreter below `MIN_PYTHON` fails closed). Two halves of the legacy hints case are held because the existing `au-unwalked-child-is-coverage-gap` case does not grade them: truncated paths as coverage gaps (its fixture has none) and a plain path list proposed for removal (its graders catch only an engine `plan`, `preview` or `apply` call). The clean skill's `evals.json` stays for a later pull request.
