---
bump: patch
---

### Fixed

- fix-ci's fallback calls no longer start on the read runner's run-job outputs, which head code can forge. `fix-ci-handoff` and `fix-ci-rung-up-handoff`, base jobs with only `actions: read`, read this run's jobs through the Actions API, and the fallback call runs when the first call's report job posted no check ([#8890](https://github.com/melodic-software/claude-code-plugins/issues/8890)).
- A fix-ci round in which no call posted a check now posts `pr-unblock / fix-ci` failure on `fix-ci-context`'s head from the new `fix-ci-unreported` job when a call's broker-check job allowed the lane; as in the report job, a kill switch or a broker refusal posts nothing. fix-ci-dispatch counts that check toward `fix-ci-restarts`, so the loop stays capped whatever the run reports ([#8890](https://github.com/melodic-software/claude-code-plugins/issues/8890)).
- The read runner's report job no longer counts the PR head it reads at report time as a gated head. With no caller or event head, any run head is forged, and failure is posted on the head it read ([#8945](https://github.com/melodic-software/claude-code-plugins/issues/8945)).
- The read runner's run job fails before the head checkout when its trigger gate read a head other than the caller's non-empty `head-sha`. This is fix-ci's part of [#8954](https://github.com/melodic-software/claude-code-plugins/issues/8954).
- A fix-ci patch collection the collector refused (`collect-patch.sh` exit 3) now reaches a person. The collect step sets `state` `refused`, the scan job hands it on as the new `scan-collect-refused` output, and `apply-patch` runs on it and escalates `ci-fix-invalid` through `report-escalation`. `apply-patch` and `apply-patch-rung-up` now take every patch input from one leg's scan job, never from a run job ([#8912](https://github.com/melodic-software/claude-code-plugins/issues/8912)).
